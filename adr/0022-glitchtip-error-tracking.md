# 0022. GlitchTip Error Tracking

**Status**: Accepted

**Date**: 2025-12-04

## Context

Need lightweight error tracking. Sentry (ADR 0021) deployed 57 pods, exceeding single-node capacity.

## Decision

Deploy **GlitchTip** - Sentry SDK compatible, MIT licensed.

- Components: web, worker, beat (3 pods)
- Storage: PostgreSQL only (Redis optional)
- SDK: Drop-in replacement for Sentry client libraries

## Alternatives Considered

| Option | Reason Not Chosen |
|--------|-------------------|
| Sentry self-hosted | 57 pods, Kafka/ClickHouse/RabbitMQ required |
| Managed Sentry | Data outside cluster, ongoing cost |

## Consequences

**Positive**: ~95% pod reduction, simple PostgreSQL-only storage

**Negative**: Fewer features (no APM, session replay), smaller community

## References

- [GlitchTip GitLab](https://gitlab.com/glitchtip) - MIT License
- [GlitchTip Sentry SDK docs](https://glitchtip.com/documentation/sentry-client-integration)
- [GlitchTip Helm Chart](https://gitlab.com/glitchtip/glitchtip-helm-chart)
- ADR 0021: Sentry (Superseded)
