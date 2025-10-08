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

### Volume Binding Mode

**Use `volumeBindingMode: Immediate` (not WaitForFirstConsumer)**

**Observed Issue:** In our Longhorn v1.10.0 deployment, CSIStorageCapacity objects are not being created despite the feature being listed in release notes ([GitHub Issue #10685](https://github.com/longhorn/longhorn/issues/10685), [v1.10.0 Release Notes](https://github.com/longhorn/longhorn/releases/tag/v1.10.0)).

**Root Cause (Investigated 2025-10-07):**

After systematic investigation, we discovered TWO issues preventing CSIStorageCapacity object creation:

1. **Stale leader election lease**: External-provisioner pods couldn't acquire leadership, preventing the capacity controller from starting. The lease holder referenced a pod that no longer existed. Fixed by deleting the stale lease.

2. **Missing `dataEngine` parameter**: After fixing leader election, the capacity controller started but GetCapacity calls immediately failed with:
   ```
   CSI GetCapacity for {storageClassName:replicated}:
   rpc error: code = InvalidArgument desc = storage class parameters missing 'dataEngine' key
   ```
   This appears to be an undocumented requirement in Longhorn v1.10.0. Regular volume provisioning doesn't require explicit `dataEngine` (defaults to v1), but CSIStorageCapacity GetCapacity calls do. Fixed by adding `dataEngine: "v1"` to all StorageClass parameters.

**Problem with WaitForFirstConsumer:**
- Kubernetes scheduler needs CSIStorageCapacity objects to determine available storage per node
- Without them, scheduler assumes no storage available
- Results in: `0/1 nodes are available: 1 node(s) did not have enough free storage`
- Pods remain in Pending state indefinitely
- Verified: `kubectl get csistoragecapacities -A` returns no resources

**Why Immediate binding works:**
- PVC binds immediately to any available node with Longhorn storage
- Scheduler doesn't need capacity information upfront
- Pod scheduling happens after volume is already provisioned
- Tested successfully: PVC binds, pod runs, data persists

**When to reconsider WaitForFirstConsumer:**
- Now that `dataEngine` parameter is added, CSIStorageCapacity objects should be created
- Verify after merge: `kubectl get csistoragecapacities -A`
- If objects appear, can switch to WaitForFirstConsumer in follow-up PR when scaling to multi-node
- Benefit: Better pod/volume co-location across nodes (minimal benefit on single node)
- Single-node cluster: `Immediate` binding is sufficient (everything co-located anyway)

### Replica Configuration

- Single node: All classes use 1 replica (only 1 node available)
- Multi-node: Replicated class increases to 3 replicas for redundancy across nodes

### StorageClass Updates and Volume Migration

- Only metadata (labels/annotations, including default-class toggles) is mutable in-place. Kubernetes validation rejects spec edits to `parameters`, `provisioner`, `reclaimPolicy`, or `volumeBindingMode`, so changing the class configuration requires deleting and re-applying the `StorageClass` manifest ([Kubernetes storage validation](https://github.com/kubernetes/kubernetes/blob/v1.30.0/pkg/apis/storage/validation/validation.go#L66-L86)).
- Removing a `StorageClass` does not touch existing volumes: PersistentVolumes keep their lifecycle independent of the class object, so currently bound workloads stay online while the class is recreated, and new PVCs simply fail until the resource exists again ([Kubernetes PersistentVolume lifecycle](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#lifecycle-of-a-volume-and-claim)).
- Longhorn only reads `parameters` when provisioning a new volume. Updating a `StorageClass` later does not retrofit values onto existing Longhorn volumes, so plan follow-up actions for workloads that should inherit the new defaults ([Longhorn storage-class parameters](https://longhorn.io/docs/1.10.0/references/storage-class-parameters/)).
- Replication characteristics can be raised post-provisioning without recreating PVCs: adjust `spec.numberOfReplicas` (or related per-volume settings) through the Longhorn UI/CRD and Longhorn will create the additional replicas, re-balancing them as the cluster grows ([Longhorn replica auto-balance](https://longhorn.io/docs/1.10.0/high-availability/auto-balance-replicas/)).

## When to Reconsider

**Revisit if:**
- Managing > 5 different workload types (may need more classes)
- Developers consistently choose wrong class (naming/documentation issue)
- Storage cost becomes critical even with optimization

## References

- [CNCF PostgreSQL Recommendations](https://www.cncf.io/blog/2023/09/29/recommended-architectures-for-postgresql-in-kubernetes/)
- [CloudNativePG Best Practices](https://cloudnative-pg.io/documentation/current/architecture/)
- [Longhorn CSIStorageCapacity Issue #10685](https://github.com/longhorn/longhorn/issues/10685) - Feature request and implementation
- [Longhorn v1.10.0 Release Notes](https://github.com/longhorn/longhorn/releases/tag/v1.10.0) - CSIStorageCapacity mentioned
- [Kubernetes Storage Capacity Tracking](https://kubernetes-csi.github.io/docs/storage-capacity-tracking.html)
- [Kubernetes storage validation](https://github.com/kubernetes/kubernetes/blob/v1.30.0/pkg/apis/storage/validation/validation.go#L66-L86)
- [Kubernetes PersistentVolume lifecycle](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#lifecycle-of-a-volume-and-claim)
- [Longhorn storage-class parameters](https://longhorn.io/docs/1.10.0/references/storage-class-parameters/)
- [Longhorn replica auto-balance](https://longhorn.io/docs/1.10.0/high-availability/auto-balance-replicas/)
- ADR 0002: Longhorn Storage from Day One
- ADR 0004: CloudNativePG for PostgreSQL
