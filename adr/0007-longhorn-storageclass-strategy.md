# 0007. Longhorn StorageClass Strategy

**Status**: Accepted

**Date**: 2025-10-05

## Context

We use Longhorn for persistent storage across different workload types with different redundancy characteristics:

- **PostgreSQL** - CloudNativePG provides 3 DB replicas (application-level replication)
- **Redis** - Single instance, no replication (data loss acceptable)
- **MinIO** - Distributed with erasure coding EC:2 (application-level redundancy)

Question: Should redundancy live at the storage layer (Longhorn replication) or application layer?

## Decision

**Create multiple Longhorn StorageClasses with different replication strategies:**

- **Single-replica class**: For apps with built-in replication (avoids double replication overhead)
- **Replicated class**: For apps without replication (Longhorn provides redundancy)
- **Optional ephemeral class**: For non-critical data with automatic cleanup

**Key principle:** Applications with built-in replication should use single-replica storage to avoid wasting disk space and degrading performance.

## Alternatives Considered

### 1. Single StorageClass with High Replication (All Workloads)
- **Pros**: Simple, safe default
- **Cons**: 9× data copies for apps with built-in replication (3 DB replicas × 3 storage replicas), massive storage waste
- **Why not chosen**: Extreme storage overhead

### 2. Application-Level Only (All Single Replica)
- **Pros**: Maximum efficiency
- **Cons**: No redundancy for simple apps without built-in HA
- **Why not chosen**: Need safe default for workloads without built-in HA

## Consequences

### Positive
- ✅ **3× storage savings** for replicated applications
- ✅ Lower write latency (less replication overhead)
- ✅ Application-aware failover (e.g., PostgreSQL automatic promotion)
- ✅ Follows CNCF best practices for stateful workloads

### Negative
- ⚠️ Developers must choose correct StorageClass
- ⚠️ Misconfiguration risk (wrong class = no redundancy or double redundancy)

### Neutral
- Multi-node behavior differs from single-node (replicas spread vs colocated)

## Best Practice: Application vs Storage Replication

**CNCF recommendation for databases:**
> "Choose application-level replication (PostgreSQL) instead of storage-level replication."

**Why application replication wins:**
- Transaction-aware (understands commits, rollbacks, consistency)
- Automatic failover (database promotes replica, storage doesn't)
- Point-in-time recovery (WAL-based)
- Better performance (streaming replication faster than block replication)

**Storage replication is dumb:** Just copies blocks without understanding data consistency or providing automatic failover.

## Implementation Notes

- Use `volumeBindingMode: WaitForFirstConsumer` for proper pod/volume placement
- Single node: All classes use 1 replica (only 1 node available)
- Multi-node: Replicated class increases to 3 replicas for redundancy across nodes

## When to Reconsider

**Revisit if:**
- Managing > 5 different workload types (may need more classes)
- Developers consistently choose wrong class (naming/documentation issue)
- Storage cost becomes critical even with optimization

## References

- [CNCF PostgreSQL Recommendations](https://www.cncf.io/blog/2023/09/29/recommended-architectures-for-postgresql-in-kubernetes/)
- [CloudNativePG Best Practices](https://cloudnative-pg.io/documentation/current/architecture/)
- ADR 0002: Longhorn Storage from Day One
- ADR 0004: CloudNativePG for PostgreSQL
