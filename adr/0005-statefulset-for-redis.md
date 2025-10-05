# 0005. StatefulSet for Redis (No Operator)

**Status**: Accepted

**Date**: 2025-10-05

## Context

We need Redis for cache and BullMQ job queues. The cluster starts on a single Hetzner node and will scale to multi-node.

Key requirements:
- Cache: Session data, API responses (ephemeral)
- BullMQ: Job queues for async processing (jobs can retry)
- **Data loss is acceptable** (cache rebuilds, jobs retry)
- Need monitoring (Prometheus metrics)
- Will scale from single node to multi-node

Team context:
- Small development team
- Limited Kubernetes expertise
- Prefer simple, predictable solutions
- Can handle some manual operations

## Decision

We will use **plain Kubernetes StatefulSet for Redis** without an operator.

Configuration:
- Single-replica StatefulSet (single node phase)
- redis-exporter sidecar for monitoring
- AOF persistence enabled (1-second fsync)
- `maxmemory-policy: noeviction` (BullMQ requirement)
- When scaling: Add Sentinel manually or migrate to operator

## Alternatives Considered

### 1. OT-Container-Kit redis-operator
- **Pros**:
  - Most actively maintained Redis operator (Sep 2025 release)
  - Built-in redis-exporter integration
  - Supports multiple deployment modes (cluster, sentinel, replication)
  - Declarative configuration
  - Growing community (1.1k stars)
- **Cons**:
  - **CRITICAL UNRESOLVED BUGS**:
    - Issue #1403: No master after failover (replication left without master)
    - Issue #1094: Sentinel can't find master, requires deleting ALL pods
    - Issue #1164: Complete data loss on cluster restart
    - Issue #1314: Total data loss risk during master promotion
  - Cannot migrate standalone → cluster in-place (requires redeployment)
  - Scaling favors first pod (OOMKill risk)
  - Operator adds complexity we don't need for single node
- **Why not chosen**: Critical failover bugs unacceptable even for "acceptable loss" workload; complexity not justified for single node

### 2. Spotahome redis-operator
- **Pros**:
  - Simple Sentinel-based HA
  - 1.6k GitHub stars
  - Previously popular choice
- **Cons**:
  - **EFFECTIVELY ABANDONED**: Last meaningful update July 2024
  - **CRITICAL BUG** (Issue #297): Cross-namespace sentinel contamination (sentinels join wrong clusters)
  - **DATA LOSS** (Issue #205): Total data loss during scaling (15GB dataset lost)
  - Users actively migrating to OT-Container-Kit
  - No cluster mode support (Sentinel only)
- **Why not chosen**: Abandoned project with unresolved critical bugs

### 3. Redis Enterprise Operator
- **Pros**:
  - Production-grade features
  - Official Redis operator
  - Active development
  - Comprehensive monitoring
- **Cons**:
  - **Requires commercial license** for Redis Enterprise cluster
  - Operator is free, but Redis Enterprise cluster is not
  - Cost prohibitive for small teams
- **Why not chosen**: Commercial licensing incompatible with budget

### 4. Dragonfly with Official Operator
- **Pros**:
  - 25x better throughput than Redis
  - 80% less resources
  - Official operator in GA
  - BullMQ compatible
  - Drop-in Redis replacement
- **Cons**:
  - Newer project, less battle-tested
  - Smaller community than Redis
  - Requires queue naming pattern changes for optimal performance
  - Unknown long-term viability
- **Why not chosen**: Too experimental; prefer battle-tested Redis for initial deployment

## Consequences

### Positive

#### Simplicity & Reliability
- **No operator bugs**: Avoid OT-Container-Kit failover issues, Spotahome data loss
- **Predictable behavior**: Standard Kubernetes primitives, no "magic"
- **Easy to debug**: All configuration explicit in manifests
- **Battle-tested**: Redis + StatefulSet is well-understood pattern

#### Operational
- **Kubernetes auto-restart**: Pod failures handled by Kubernetes (usually sufficient)
- **BullMQ handles reconnection**: ioredis automatically reconnects, jobs resume
- **Acceptable data loss**: Cache rebuilds, jobs retry on failure
- **No external dependencies**: Just Redis + Kubernetes, no operator lifecycle

#### Development
- **Fast iteration**: No operator to learn, deploy, upgrade
- **Clear migration path**: Can add Sentinel or migrate to operator later
- **Learning opportunity**: Team understands Redis internals, not abstracted away

### Negative

#### Manual Operations Required
- **No automated failover**: When scaling to multi-node, must add Sentinel manually
- **Manual scaling**: Cluster mode setup requires manual slot distribution
- **No declarative HA**: Multi-node HA needs custom configuration
- **Monitoring setup**: Must deploy redis-exporter manually as sidecar

#### Scaling Complexity
- **Single → Multi-node migration**:
  - Option A: Add Sentinel manually (complex ConfigMaps, init containers)
  - Option B: Migrate to operator (redeploy, data migration)
  - Option C: Stay single node until breaking point
- **No automatic rebalancing**: Cluster mode requires manual slot redistribution
- **Connection handling**: Clients need manual reconfiguration for Sentinel

#### Missing Operator Features
- **No backup automation**: Must implement backup CronJobs if needed
- **No health management**: Must write custom health checks for multi-node
- **No automatic repair**: Stuck states require manual intervention
- **Limited observability**: No operator-level metrics (just Redis metrics)

### Neutral

- **Data loss acceptable for our use case**: Cache and job queues can tolerate loss
- **Single node sufficient initially**: Don't need HA features yet
- **Manual operations manageable**: Small team can handle operational overhead
- **Migration path exists**: Not locked into this decision

## Critical Understanding: Why Operators Aren't Worth It

**Research findings:**
- **ALL Redis operators have critical failover bugs**
- OT-Container-Kit: Clusters lose masters, require manual pod deletion
- Spotahome: Data loss during scaling, namespace contamination
- **Failover "improvements" don't work reliably in practice**

**For our use case:**
- Operators add complexity without solving real problems
- BullMQ handles reconnection automatically (ioredis)
- Data loss is acceptable (cache, job retries)
- **Simplicity > theoretical HA that doesn't work**

## Implementation Notes

### Single Node Configuration

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
spec:
  serviceName: redis
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
          name: redis
        command:
        - redis-server
        - --appendonly yes
        - --appendfsync everysec
        - --maxmemory-policy noeviction  # BullMQ requirement
        volumeMounts:
        - name: data
          mountPath: /data
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi

      # Monitoring sidecar
      - name: redis-exporter
        image: oliver006/redis_exporter:latest
        ports:
        - containerPort: 9121
          name: metrics
        resources:
          requests:
            cpu: 10m
            memory: 32Mi
          limits:
            cpu: 50m
            memory: 64Mi

  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: longhorn
      resources:
        requests:
          storage: 10Gi
```

### BullMQ Configuration

**Critical settings (must be configured):**
```javascript
// BullMQ connection
const connection = {
  host: 'redis.default.svc.cluster.local',
  port: 6379,
  maxRetriesPerRequest: null,  // Required for Workers
  // enableOfflineQueue: true,  // Queue jobs during disconnection (default)
};

// Queue configuration
const queue = new Queue('myqueue', { connection });
const worker = new Worker('myqueue', processor, { connection });
```

**Redis config verification:**
- `maxmemory-policy: noeviction` (jobs require atomic operations)
- AOF persistence enabled (prevent job loss on restart)
- Sufficient memory for queue depth

### Monitoring Setup

**ServiceMonitor for Prometheus:**
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: redis
spec:
  selector:
    matchLabels:
      app: redis
  endpoints:
  - port: metrics
    interval: 30s
```

**Key metrics to alert on:**
- `redis_up` (instance health)
- `redis_memory_used_bytes` (memory usage)
- `redis_commands_processed_total` (throughput)
- `redis_connected_clients` (connection count)
- BullMQ queue depth (from application metrics)

### Backup Strategy (Optional)

**For job queues (if needed):**
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: redis-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: redis:7-alpine
            command:
            - /bin/sh
            - -c
            - |
              redis-cli -h redis BGSAVE
              sleep 10
              cp /data/dump.rdb /backup/dump-$(date +%Y%m%d).rdb
              find /backup -mtime +7 -delete
            volumeMounts:
            - name: data
              mountPath: /data
            - name: backup
              mountPath: /backup
```

**Note:** For cache workload, backups likely unnecessary.

## Migration Paths (Future)

### When Single Node Becomes Insufficient

**Option A: Add Sentinel Manually (Most Control)**
1. Deploy 3 Redis replicas (1 master + 2 replicas)
2. Deploy 3 Sentinel instances
3. Configure Sentinel for automatic failover
4. Update BullMQ connection to use Sentinel
5. **Complexity**: High (ConfigMaps, init containers, service routing)

**Option B: Migrate to OT-Container-Kit Operator (Automated)**
1. Deploy RedisReplication CRD (1 master + N replicas)
2. Use `SLAVEOF` to replicate data from old instance
3. Cutover BullMQ connections
4. Decommission StatefulSet
5. **Complexity**: Medium (operator bugs, but simpler config)

**Option C: Migrate to Dragonfly (Performance)**
1. Deploy Dragonfly with official operator
2. Migrate data (Redis protocol compatible)
3. Update queue naming for optimal performance
4. **Complexity**: Medium (new technology, testing required)

**Option D: Stay Single Node Longer**
1. Vertical scaling (increase pod resources)
2. Optimize BullMQ (concurrency, rate limiting)
3. Only migrate when truly necessary
4. **Complexity**: Low (simplest option)

**Recommendation:** Stay single node as long as possible (Option D), then evaluate based on actual needs.

## When to Reconsider

**Revisit this decision if:**

1. **Single node becomes bottleneck**: >10k jobs/sec, >50GB memory
2. **HA becomes critical**: Business can't tolerate pod restart downtime
3. **Operator bugs are fixed**: OT-Container-Kit resolves Issues #1403, #1094, #1164
4. **Dragonfly matures**: Official operator proven in production at scale
5. **Team expertise grows**: Comfortable managing Sentinel or operators

**Don't migrate prematurely.** Operators solve problems you might never have.

## Operational Runbook

### Pod Restart (Kubernetes Handles)
- Kubernetes detects pod failure
- Restarts pod automatically
- BullMQ reconnects via ioredis
- Jobs resume processing
- **Action required:** None (monitor recovery)

### Node Failure (Single Node)
- Pod stuck until node returns or is evicted
- Kubernetes reschedules pod to healthy node (if multi-node cluster)
- PersistentVolume reattaches
- **Downtime:** Until pod restarts (minutes)
- **Action required:** None (Kubernetes handles)

### Data Corruption (Rare)
- AOF corruption detected on startup
- Redis refuses to start
- **Recovery**: Restore from backup or accept data loss
- **Action required**: Investigate logs, restore if needed

### Memory Pressure
- Redis hits maxmemory limit
- With `noeviction`: Writes fail (jobs queue in BullMQ)
- **Action required**: Increase pod memory or clear old data

### Scaling to Multi-Node (Manual)
- See "Migration Paths" section above
- **Action required**: Evaluate options, plan migration

## References

- [BullMQ Production Guide](https://docs.bullmq.io/guide/going-to-production)
- [Redis Persistence](https://redis.io/docs/management/persistence/)
- [OT-Container-Kit Issues](https://github.com/OT-CONTAINER-KIT/redis-operator/issues)
- [Spotahome Data Loss Analysis](https://blog.palark.com/failure-with-redis-operator-and-redis-data-analysis-tools/)
- [Redis Exporter](https://github.com/oliver006/redis_exporter)
- ADR 0003: Operators over StatefulSets (general principle - exception made here due to operator immaturity)
