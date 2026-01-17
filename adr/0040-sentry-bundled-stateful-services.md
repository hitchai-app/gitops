# 0040. Sentry Bundled Stateful Services

**Status**: Superseded by ADR 0041

**Date**: 2026-01-15

## Context

Sentry was deployed with external operators for Kafka, ClickHouse, and Redis/Valkey. This added operational overhead (multiple operators, TLS management, and bespoke secrets) for a single workload. We want to simplify the Sentry footprint while keeping Postgres managed by CloudNativePG.

## Decision

Use the Sentry Helm chart bundled services for:
- Kafka
- Redis
- ClickHouse

Continue using CloudNativePG for PostgreSQL.

This creates a deliberate exception to ADR 0003 (operators over StatefulSets) for Sentry's non-Postgres dependencies, trading operational complexity for simplicity and tighter chart-managed upgrades.

## Alternatives Considered

1. **External operators for Kafka/ClickHouse/Valkey** (current)
   - Pros: Operator-level lifecycle features, TLS/mTLS patterns, reuse across workloads
   - Cons: Higher operational overhead, more components to manage for a single app

2. **Managed Sentry (sentry.io)**
   - Pros: No in-cluster ops
   - Cons: Data outside cluster, ongoing cost

## Consequences

### Positive
- Fewer operators and CRDs to manage
- Sentry dependency versions upgrade in lockstep with the chart
- Reduced TLS/certificate sprawl for internal services

### Negative
- Less granular control over Kafka/Redis/ClickHouse lifecycle
- Bundled components scale less independently
- Harder to reuse for other workloads

### Neutral
- PostgreSQL remains external (CNPG) and unchanged

## References

- ADR 0003: Operators over StatefulSets
- ADR 0039: CNPG-Managed TLS and Password Auth for Sentry Postgres
- Sentry Helm chart documentation
