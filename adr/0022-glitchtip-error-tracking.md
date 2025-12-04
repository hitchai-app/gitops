# 0022. GlitchTip Error Tracking

**Status**: Accepted

**Date**: 2025-12-04

## Context

We need error tracking for applications running in the cluster. Requirements:

- Capture and aggregate application errors
- Provide stack traces and context for debugging
- Support multiple projects/applications
- Self-hosted (data stays in cluster)
- Lightweight footprint for single-node cluster

Previous attempt: Sentry (ADR 0021) deployed 57 pods requiring Kafka, ClickHouse, RabbitMQ. This exceeded our single-node pod capacity (110 pods) and consumed excessive resources (~6.5GB RAM).

Team context:
- Small development team
- Low volume initially (<10k events/day)
- Single Hetzner node (12 CPU / 128GB RAM / 110 pod limit)

## Decision

Deploy **GlitchTip** via the official Helm chart as a lightweight Sentry-compatible alternative.

**Key benefits:**
- ~3 pods total (web, worker, beat)
- Sentry SDK compatible (same client libraries)
- Only requires PostgreSQL + optional Redis/Valkey
- No Kafka, ClickHouse, or complex event pipeline

### Service Integration

| Service | External? | Rationale |
|---------|-----------|-----------|
| PostgreSQL | Yes | CloudNativePG (PITR backups, proven pattern) |
| Valkey | Yes | SAP Valkey Operator (session/cache, follows existing pattern) |

## Alternatives Considered

### 1. Sentry Self-Hosted (ADR 0021)
- **Pros**: Full-featured, large ecosystem, mature
- **Cons**: 57 pods, ~6.5GB RAM, requires Kafka + ClickHouse + RabbitMQ
- **Why not chosen**: Resource footprint exceeded single-node capacity

### 2. Managed Sentry (sentry.io)
- **Pros**: Zero ops, always up-to-date
- **Cons**: Data outside cluster, ongoing cost
- **Why not chosen**: Prefer self-hosted for data locality and cost

### 3. No Error Tracking
- **Pros**: Zero overhead
- **Cons**: Blind to production errors, slower debugging
- **Why not chosen**: Error tracking is essential for production quality

## Consequences

### Positive
- ~3 pods vs 57 pods (95% reduction)
- ~1GB RAM vs ~6.5GB RAM
- Sentry SDK compatible (existing client libraries work)
- Simple architecture (Django app + Celery workers)
- PostgreSQL-only storage (no specialized databases)
- GitOps-native deployment via ArgoCD

### Negative
- Fewer features than full Sentry (no performance monitoring, session replay)
- Smaller community and ecosystem
- Less frequent releases
- No ClickHouse means less efficient at high event volumes

### Neutral
- MIT licensed
- Active development (v5.2.0 as of Dec 2025)
- Suitable for small-medium workloads (<100k events/day)

## Implementation

### Architecture

```
Internet -> Traefik -> GlitchTip Web -> Workers
                           |
                           v
                      PostgreSQL (CloudNativePG)
                           |
                           v
                      Valkey (SAP Operator)
```

### Namespace

`glitchtip-system` - platform infrastructure service

### Components

- GlitchTip Web (UI + API, Django)
- GlitchTip Worker (background processing, Celery)
- GlitchTip Beat (scheduled tasks, Celery Beat)

### Resource Allocation

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| PostgreSQL | 250m | 512Mi | 10Gi |
| Valkey | 100m | 128Mi | 1Gi |
| GlitchTip (web+worker+beat) | ~500m | ~1Gi | - |
| **Total** | ~850m | ~1.6Gi | ~11Gi |

### Migration from Sentry SDKs

GlitchTip uses Sentry SDK protocol. To migrate:
1. Change DSN from Sentry to GlitchTip
2. No code changes required in application

## When to Reconsider

**Upgrade to Sentry if:**
1. Event volume exceeds 100k/day consistently
2. Need performance monitoring (APM)
3. Need session replay or advanced features
4. Multi-node cluster with sufficient capacity

**Consider managed service if:**
1. Team can't maintain self-hosted infrastructure
2. Need 24/7 support and SLA

## References

- [GlitchTip Documentation](https://glitchtip.com/documentation/)
- [GlitchTip Helm Chart](https://gitlab.com/glitchtip/glitchtip-helm-chart)
- [GlitchTip GitLab](https://gitlab.com/glitchtip)
- ADR 0004: CloudNativePG for PostgreSQL
- ADR 0020: SAP Valkey Operator
- ADR 0021: Sentry Error Tracking (Superseded)
