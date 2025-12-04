# 0021. Sentry Error Tracking Platform

**Status**: Accepted

**Date**: 2025-12-04

## Context

We need error tracking for applications running in the cluster. Requirements:

- Capture and aggregate application errors
- Provide stack traces and context for debugging
- Support multiple projects/applications
- Integrate with existing authentication (Dex SSO)
- Self-hosted (data stays in cluster)

Team context:
- Small development team
- Low volume initially (<10k events/day)
- Single Hetzner node (12 CPU / 128GB RAM)

## Decision

Deploy **Sentry self-hosted** via the community Helm chart (`sentry-kubernetes/charts`) with:

1. **External PostgreSQL** via CloudNativePG (dedicated cluster)
2. **External Valkey** via SAP Valkey Operator (dedicated instance)
3. **Bundled ClickHouse, Kafka, RabbitMQ** (Sentry-managed)
4. **Dex OIDC integration** via `sentry-auth-oidc` plugin

### Service Integration Strategy

| Service | External? | Rationale |
|---------|-----------|-----------|
| PostgreSQL | Yes | Benefits from CloudNativePG (PITR backups, declarative management, proven pattern) |
| Valkey | Yes | Simple cache, follows existing SAP Valkey Operator pattern |
| ClickHouse | No | Tight Sentry/Snuba coupling, schema migrations managed by chart, version lock-in |
| Kafka | No | Sentry-specific Kraft config, topic/consumer coupling, low-volume doesn't justify Strimzi |
| RabbitMQ | No | Internal task queue only, minimal operational benefit from operator |

## Alternatives Considered

### 1. Managed Sentry (sentry.io)
- **Pros**: Zero ops, always up-to-date, professional support
- **Cons**: Data outside cluster, ongoing cost, less control
- **Why not chosen**: Prefer self-hosted for data locality and cost

### 2. External ClickHouse Operator (Altinity)
- **Pros**: Better backup/restore, monitoring, rolling updates
- **Cons**: Tight version coupling with Sentry/Snuba, risk of schema mismatch
- **Why not chosen**: Sentry chart manages schema migrations atomically

### 3. External Kafka Operator (Strimzi)
- **Pros**: Mature CNCF project, could share Kafka for other workloads
- **Cons**: Sentry requires specific Kraft configuration, topic coupling
- **Why not chosen**: Low-volume use case doesn't justify complexity

### 4. GlitchTip (Sentry-compatible alternative)
- **Pros**: Lighter weight, simpler deployment
- **Cons**: Fewer features, smaller community, less mature
- **Why not chosen**: Sentry has better ecosystem and features

## Consequences

### Positive
- GitOps-native deployment via ArgoCD
- SSO via existing Dex infrastructure (no separate user management)
- External PostgreSQL benefits from CloudNativePG (PITR, backups)
- External Valkey follows established pattern
- Atomic Sentry upgrades (chart manages all bundled service versions)
- Dedicated database/cache isolation (Sentry issues don't affect other workloads)

### Negative
- Bundled services (ClickHouse, Kafka, RabbitMQ) upgrade only with Sentry chart
- Resource overhead (~6.5GB RAM, ~92GB storage)
- Operational complexity of bundled stateful services
- sentry-auth-oidc plugin requires custom image or init container

### Neutral
- 30-day event retention (configurable)
- Community-maintained chart (not official Sentry)
- Breaking changes between chart versions require careful upgrade path

## Implementation

### Architecture

```
Internet → Traefik → Sentry Web → Workers
                         ↓
                      Relay → Kafka → ClickHouse
                         ↓           (bundled)
                      Snuba

External:
├── CloudNativePG (sentry-postgres)
└── SAP Valkey (sentry-valkey)
```

### Namespace

`sentry-system` - platform infrastructure service

### Components

- Sentry Web (UI + API)
- Sentry Workers (background processing)
- Sentry Relay (event preprocessing)
- Snuba (ClickHouse query layer)
- ClickHouse (analytics storage, bundled)
- Kafka (event streaming, bundled)
- RabbitMQ (task queue, bundled)

### Resource Allocation

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| PostgreSQL | 250m | 512Mi | 20Gi |
| Valkey | 100m | 128Mi | 2Gi |
| ClickHouse | 500m | 2Gi | 50Gi |
| Kafka | 500m | 1Gi | 20Gi |
| Sentry Services | ~1.4 CPU | ~3Gi | - |
| **Total** | ~2.7 CPU | ~6.5Gi | ~92Gi |

### Authentication

Dex OIDC integration via `sentry-auth-oidc` plugin:
- Users login via Dex (GitHub or static password)
- JIT provisioning creates Sentry accounts on first login
- Single Sign-On with other platform services

## When to Reconsider

**Migrate to external ClickHouse/Kafka operators if:**
1. Want to share Kafka for other event streaming workloads
2. ClickHouse storage exceeds 100GB requiring sophisticated backup
3. Scale increases beyond 100k events/day
4. Need independent upgrade cycles for data services

**Consider managed Sentry if:**
1. Team can't maintain self-hosted infrastructure
2. Need 24/7 support and SLA
3. Cost savings from reduced ops outweigh hosting cost

## References

- [Sentry Self-Hosted Documentation](https://develop.sentry.dev/self-hosted/)
- [sentry-kubernetes/charts](https://github.com/sentry-kubernetes/charts)
- [sentry-auth-oidc plugin](https://github.com/siemens/sentry-auth-oidc)
- ADR 0004: CloudNativePG for PostgreSQL
- ADR 0018: Dex Authentication Provider
- ADR 0020: SAP Valkey Operator
