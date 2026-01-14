# 0036. Altinity ClickHouse Operator

**Status**: Proposed

**Date**: 2026-01-14

## Context

Need production-ready OLAP database for analytics workloads (logs, metrics, events). ClickHouse is columnar database for real-time analytics, requiring operator for backups and management.

## Decision

Deploy **Altinity Kubernetes Operator for ClickHouse**.

- Single replica initially (single-node cluster)
- ClickHouse Keeper (no ZooKeeper)
- Longhorn single-replica storage

## Alternatives Considered

| Option | Decision | Reason |
|--------|----------|--------|
| Bitnami operator | Avoid | Too new (2025), untested |
| Bundled (StatefulSet) | Avoid | Manual ops, no backups |
| Altinity operator | **Chosen** | Production-mature since 2019 |

## Consequences

**Positive**:
- CHI resources for declarative management
- Built-in backups (clickhouse-backup)
- Prometheus metrics ready
- Reusable across multiple workloads

**Negative**:
- New operator dependency
- Resource overhead (~500Mi RAM)

## When to Reconsider

- Altinity abandoned (no commits 6+ months)
- Need multi-master ClickHouse
- ClickHouse schema propagation bug fixed in future operator versions

## Implementation Notes

**ClickHouse version pin:** Use 25.8.9 or earlier due to schema propagation regression in 25.8.10+ (Altinity issue #898).

**TLS Authentication:** ClickHouse has NO default authentication and requires TLS for production use. Implementation:
- Self-signed CA via cert-manager (ClusterIssuer)
- Server certificate for ClickHouse pods
- Client certificates for applications
- ConfigMap for TLS XML configuration (operator lacks native TLS support)
- Certificates auto-rotate via cert-manager (30 days before expiry)

## References

- [Altinity operator](https://github.com/Altinity/clickhouse-operator)
- [Altinity issue #898 - schema propagation bug](https://github.com/Altinity/clickhouse-operator/issues/898)
- ADR 0003: Operators over StatefulSets
