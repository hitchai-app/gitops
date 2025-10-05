# 0007. Longhorn StorageClass Strategy

**Status**: Accepted

**Date**: 2025-10-05

## Context

We use Longhorn for persistent storage across different workload types. These workloads have different redundancy characteristics:

- **PostgreSQL** - CloudNativePG provides 3 DB replicas (application-level replication)
- **Redis** - Single instance, no replication (data loss acceptable)
- **MinIO** - Distributed with erasure coding EC:2 (application-level redundancy)

The question: Should redundancy live at the storage layer (Longhorn replication) or application layer?

## Decision

We will create **two Longhorn StorageClasses** with different replica strategies:

1. **longhorn-single-replica** (1 replica)
   - For apps with built-in replication (PostgreSQL, MinIO)
   - Avoids double replication overhead

2. **longhorn-replicated** (3 replicas)
   - For apps without replication (Redis, general workloads)
   - Longhorn provides redundancy

Both use `volumeBindingMode: WaitForFirstConsumer` for proper pod scheduling.

## Alternatives Considered

### 1. Single StorageClass with 3 Replicas (All Workloads)
- **Pros**: Simple, one storage class, safe default
- **Cons**:
  - **9× data copies** for PostgreSQL (3 DB replicas × 3 storage replicas)
  - **Massive storage waste**: 300GB DB = 900GB disk usage
  - Slower performance (replication overhead)
- **Why not chosen**: Extreme storage overhead when apps have built-in replication

### 2. Storage-Level Replication Only (No App Replication)
- **Pros**: Simple, consistent approach, all redundancy in one place
- **Cons**:
  - **Dumb replication**: Storage copies blocks, doesn't understand transactions
  - **No application failover**: DB replica provides automatic failover, storage doesn't
  - **Slower recovery**: Storage replication slower than DB streaming replication
- **Why not chosen**: Application-level replication is superior for databases

### 3. Application-Level Only (All Single Replica)
- **Pros**: Maximum efficiency, no storage overhead
- **Cons**:
  - **No redundancy for simple apps**: Redis, single-instance workloads unprotected
  - **Risky default**: Developers might forget to add replication
- **Why not chosen**: Need safe default for workloads without built-in HA

## Consequences

### Positive

**Storage Efficiency:**
- ✅ PostgreSQL: 3 DB replicas × 1 storage = 300GB for 100GB database (vs 900GB)
- ✅ MinIO: 4 drives EC:2 × 1 storage = 20GB raw (vs 60GB with 3× replication)
- ✅ **3× storage savings** for replicated applications

**Performance:**
- ✅ Lower write latency (less replication overhead)
- ✅ Faster recovery (app replication > storage replication)
- ✅ Application-aware failover (PostgreSQL automatic promotion)

**Architectural Clarity:**
- ✅ Clear separation: Apps manage data redundancy, storage provides volumes
- ✅ Follows best practices (CNCF recommendation for PostgreSQL)
- ✅ Explicit choice per workload (not hidden in storage layer)

### Negative

**Complexity:**
- ⚠️ Two StorageClasses to manage (vs one)
- ⚠️ Developers must choose correct class
- ⚠️ Misconfiguration risk (wrong class = no redundancy or double redundancy)

**Operational:**
- ⚠️ Need documentation on which class to use when
- ⚠️ On single node, both behave identically (only 1 replica possible)
- ⚠️ Difference only matters on multi-node (can be confusing)

### Neutral
- On single node: Both classes result in 1 replica (only 1 node exists)
- Naming can be improved (current names are descriptive but verbose)
- Migration between classes requires PVC recreation (not in-place)

## Best Practice: Application vs Storage Replication

**Recommendation from CloudNativePG and CNCF:**
> "Choose application-level replication (PostgreSQL) instead of storage-level replication."

**Why application replication wins:**
1. **Transaction-aware** - Understands commits, rollbacks, consistency
2. **Automatic failover** - PostgreSQL promotes replica, storage doesn't
3. **Point-in-time recovery** - WAL-based recovery (CloudNativePG)
4. **Better performance** - Streaming replication faster than block replication

**Storage replication is dumb:**
- Just copies blocks
- No understanding of data consistency
- No automatic failover
- Slower than app-level replication

## StorageClass Configurations

### longhorn-single-replica
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-single-replica
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "1"
  dataLocality: "best-effort"  # Keep replica on same node as pod
  staleReplicaTimeout: "30"
  fsType: "ext4"
volumeBindingMode: WaitForFirstConsumer  # Critical for scheduling
```

**Use for:**
- PostgreSQL (CloudNativePG manages replication)
- MinIO distributed (erasure coding handles redundancy)
- Any stateful app with built-in HA (Kafka, MongoDB replica sets, etc.)

### longhorn-replicated
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-replicated
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "3"
  dataLocality: "disabled"  # Spread replicas across nodes
  staleReplicaTimeout: "30"
  fsType: "ext4"
volumeBindingMode: WaitForFirstConsumer
```

**Use for:**
- Redis (single instance, no replication)
- Single-instance databases (if no app replication)
- General stateful workloads (safe default)

## volumeBindingMode: WaitForFirstConsumer

**Why this is critical:**

**With WaitForFirstConsumer:**
1. Pod scheduled to Node A
2. Kubernetes tells Longhorn: "Create volume on Node A"
3. Longhorn creates volume on Node A
4. Pod and volume on same node ✅

**Without it (Immediate):**
1. Longhorn creates volume on random node (Node B)
2. Pod scheduled to Node A
3. Pod can't access volume (wrong node) ❌

**For dataLocality: "best-effort"** - Volume replica placed on same node as pod (lower latency)

## Usage Examples

### PostgreSQL (CloudNativePG)
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
spec:
  instances: 3  # App handles replication
  storage:
    storageClass: longhorn-single-replica  # 1 replica per instance
    size: 10Gi
```

**Result:** 3 DB replicas × 10Gi × 1 storage replica = 30Gi total

### MinIO
```yaml
apiVersion: minio.min.io/v2
kind: Tenant
spec:
  pools:
  - servers: 1
    volumesPerServer: 4
    volumeClaimTemplate:
      spec:
        storageClassName: longhorn-single-replica  # 1 replica
        resources:
          requests:
            storage: 5Gi
```

**Result:** 4 drives × 5Gi × 1 replica = 20Gi total (10Gi usable with EC:2)

### Redis
```yaml
apiVersion: apps/v1
kind: StatefulSet
spec:
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      storageClassName: longhorn-replicated  # 3 replicas
      resources:
        requests:
          storage: 10Gi
```

**Result:** 1 instance × 10Gi × 3 replicas = 30Gi total (on multi-node)

## Single Node vs Multi-Node Behavior

### Single Node (Current)
- Both StorageClasses result in 1 replica (only 1 node available)
- No actual difference in behavior
- **Create both now for future readiness**

### Multi-Node (Future)
- **longhorn-single-replica**: 1 copy of data (app handles redundancy)
- **longhorn-replicated**: 3 copies spread across nodes (Longhorn handles redundancy)
- **Significant storage difference** (3× for replicated class)

## When to Reconsider

**Revisit if:**
1. **Naming confusion** - Developers consistently choose wrong class (rename for clarity)
2. **Single class sufficient** - All workloads have built-in replication (remove replicated class)
3. **Storage cost critical** - Even 3× replication too expensive (rethink entire strategy)
4. **Hybrid approach needed** - Some workloads need 2 replicas (add third class)

## References

- [CloudNativePG Best Practices](https://cloudnative-pg.io/documentation/current/architecture/)
- [CNCF PostgreSQL Recommendations](https://www.cncf.io/blog/2023/09/29/recommended-architectures-for-postgresql-in-kubernetes/)
- [Longhorn StorageClass Parameters](https://longhorn.io/docs/latest/references/storage-class-parameters/)
- [CloudNativePG with Longhorn](https://medium.com/@camphul/cloudnative-pg-in-the-homelab-with-longhorn-b08c40b85384)
- ADR 0004: CloudNativePG for PostgreSQL
- ADR 0005: StatefulSet for Redis
- ADR 0006: MinIO Operator with 4-Drive Configuration
