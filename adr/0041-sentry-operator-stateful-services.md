# 0041. Sentry Operator-Managed Stateful Services

**Status**: Accepted

**Date**: 2026-01-17

## Context

We switched Sentry to bundled Kafka/ClickHouse to reduce operational overhead, but encountered version skew and lifecycle issues that blocked upgrades and migrations. These failures show that Sentry’s analytics stack needs independent versioning and lifecycle control beyond what the bundled chart can reliably provide.

## Decision

Return to operator-managed stateful services for Sentry:
- **ClickHouse** via Altinity operator
- **Kafka** via Strimzi operator (KRaft)

Keep PostgreSQL on CloudNativePG.

This supersedes ADR 0040 and re-aligns with ADR 0003 (operators over StatefulSets) for Sentry’s stateful dependencies.

## Alternatives Considered

1. **Stay bundled (Kafka/ClickHouse)**
   - Pros: fewer components, simpler manifests
   - Cons: version lag, blocked migrations, coupled upgrades

2. **Managed Sentry (sentry.io)**
   - Pros: no in-cluster ops
   - Cons: data leaves cluster, ongoing cost

## Consequences

### Positive
- Independent versioning and upgrades for Kafka/ClickHouse
- Reduced risk of chart-driven incompatibilities
- Better alignment with operator-first platform strategy

### Negative
- Additional operators/CRDs to manage
- More moving parts for Sentry’s dependency stack

### Neutral
- PostgreSQL remains unchanged (CNPG)

## References

- ADR 0003: Operators over StatefulSets
- ADR 0036: Altinity ClickHouse Operator
- ADR 0037: Strimzi Kafka Operator
- ADR 0040: Sentry Bundled Stateful Services
