# 0021. Sentry Error Tracking Platform

**Status**: Proposed

**Date**: 2025-12-04

**Updated**: 2026-01-14 - Operator-based approach for all stateful services

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

Deploy **Sentry self-hosted** via community Helm chart (`sentry-kubernetes/charts`) with **external operators for all stateful services**:

1. **PostgreSQL** via CloudNativePG (dedicated cluster)
2. **Valkey** via SAP Valkey Operator (dedicated instance)
3. **ClickHouse** via Altinity operator (dedicated cluster)
4. **Kafka** via Strimzi operator (KRaft mode, dedicated cluster)
5. **Dex OIDC integration** via `sentry-auth-oidc` plugin

**Rationale**: ADR 0003 - operators for stateful services. Avoid painful migration later.

## Alternatives Considered

| Option | Decision | Reason |
|--------|----------|--------|
| Managed Sentry (sentry.io) | Avoid | Data outside cluster, ongoing cost |
| GlitchTip | Current | Lighter, but fewer features |
| Sentry + bundled services | Avoid | Painful migration to operators later |

## Why Operators Over Bundled?

Bundled services (ClickHouse, Kafka in Helm chart) seem simpler initially, but:
- No independent backups/monitoring
- Can't share services with other workloads
- Migrating to operators later = days of downtime
- Violates ADR 0003 principle

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

### TLS Architecture

**Decision**: Use namespace-local CA certificate for Sentry services

**Certificate chain:**
```
selfsigned-root (ClusterIssuer)
    ↓
internal-ca (cluster-wide CA in cert-manager ns)
    ↓
sentry-ca (namespace CA in sentry-system, isCA: true)
    ↓
Server certificates (postgres, clickhouse, kafka, valkey, client)
```

**Rationale:**
- **Native cert-manager pattern**: Certificate resources create secrets in their namespace
- **No cross-namespace dependencies**: All certificates and CA in sentry-system
- **GitOps-friendly**: Managed by ArgoCD like other certificates
- **Simple debugging**: Single namespace for all TLS resources

**Alternatives considered:**
- **kubernetes-replicator**: Copy cluster CA to sentry-system
  - Rejected: Adds external dependency, less native to cert-manager
- **Direct cluster CA reference**: Services mount cert-manager namespace secret
  - Rejected: Cross-namespace secret access not allowed by Kubernetes

**Implementation:**
- `sentry-ca` Certificate creates `sentry-ca-tls` secret
- Server certificates issued by `internal-ca-issuer` (ClusterIssuer)
- Services mount `sentry-ca-tls` for CA trust
- mTLS between Sentry and databases (client + server certificates)

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
