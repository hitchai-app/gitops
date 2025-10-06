# Redis StatefulSet

Plain Kubernetes StatefulSet for Redis cache and BullMQ job queues (no operator).

## Architecture

**Deployment Pattern**: Plain StatefulSet (ADR 0005)
- **Operator Decision**: NO operator (all Redis operators have critical failover bugs)
- **Replicas**: 1 (single instance, no replication)
- **Storage**: longhorn-replicated StorageClass (Longhorn provides redundancy)
- **Monitoring**: redis-exporter sidecar for Prometheus metrics
- **Namespace**: redis

## Why No Operator?

All Kubernetes Redis operators have unresolved critical bugs (ADR 0005):

**OT-Container-Kit redis-operator:**
- Issue #1403: No master after failover
- Issue #1094: Sentinel can't find master (requires deleting ALL pods)
- Issue #1164: Complete data loss on cluster restart

**Spotahome redis-operator:**
- Effectively abandoned (last update July 2024)
- Issue #297: Cross-namespace sentinel contamination
- Issue #205: Total data loss during scaling (15GB lost)

**Plain StatefulSet provides:**
- Kubernetes auto-restart (usually sufficient)
- BullMQ ioredis handles reconnection automatically
- No operator bugs to manage
- Predictable behavior

## Configuration

### Persistence

```yaml
command:
  - redis-server
  - --appendonly yes           # AOF persistence enabled
  - --appendfsync everysec     # 1-second fsync (1s data loss window)
  - --maxmemory-policy noeviction  # CRITICAL for BullMQ
```

**AOF (Append-Only File):**
- Persists write operations to disk
- Fsync every second (balance between durability and performance)
- Data loss window: 1 second maximum

**noeviction Policy:**
- REQUIRED for BullMQ (job queues need atomic operations)
- Redis refuses writes when memory full (prevents eviction)
- Monitor memory usage to avoid write failures

### Storage Strategy (ADR 0007)

- **StorageClass**: longhorn-replicated (3 replicas)
- **Rationale**: Redis has NO built-in replication (single instance)
- **Redundancy**: Longhorn provides storage-level replication
- **Size**: 10Gi (base), 5Gi (stage), 20Gi (prod)

### Monitoring

**redis-exporter sidecar:**
- Image: oliver006/redis_exporter:latest
- Metrics port: 9121
- ServiceMonitor: 30-second scrape interval

**Key metrics:**
- `redis_up`: Instance health
- `redis_memory_used_bytes`: Memory usage
- `redis_commands_processed_total`: Throughput
- `redis_connected_clients`: Connection count

## BullMQ Integration

### Connection Configuration

```typescript
import { Queue, Worker } from 'bullmq';

const connection = {
  host: 'redis.redis.svc.cluster.local',
  port: 6379,
  maxRetriesPerRequest: null,  // Required for Workers
  // enableOfflineQueue: true (default, queues during disconnect)
};

const queue = new Queue('myqueue', { connection });
const worker = new Worker('myqueue', processor, { connection });
```

### Important Settings

- `maxRetriesPerRequest: null` - REQUIRED for BullMQ Workers
- `enableOfflineQueue: true` - Queues jobs during Redis disconnect (default)
- ioredis automatically reconnects on connection loss
- Jobs resume processing after reconnection

### Data Loss Tolerance

**Acceptable for:**
- Cache workload (rebuilds automatically)
- Job queues with retry logic (jobs reprocess on failure)

**Not acceptable for:**
- Critical transactional data (use PostgreSQL)
- Non-retryable operations

## Deployment

1. **Prerequisites:**
   - longhorn-replicated StorageClass exists

2. **Apply ArgoCD Application:**
   ```bash
   kubectl apply -f apps/infrastructure/redis.yaml
   ```

3. **Verify deployment:**
   ```bash
   kubectl get pods -n redis
   kubectl get pvc -n redis
   kubectl get svc -n redis
   ```

## Verification

### Test Connectivity

```bash
# Redis CLI
kubectl exec -n redis redis-0 -c redis -- redis-cli ping
# Expected: PONG

# Test write/read
kubectl exec -n redis redis-0 -c redis -- redis-cli SET test hello
kubectl exec -n redis redis-0 -c redis -- redis-cli GET test
# Expected: "hello"
```

### Verify Configuration

```bash
# AOF enabled
kubectl exec -n redis redis-0 -c redis -- redis-cli CONFIG GET appendonly
# Expected: 1) "appendonly" 2) "yes"

# noeviction policy
kubectl exec -n redis redis-0 -c redis -- redis-cli CONFIG GET maxmemory-policy
# Expected: 1) "maxmemory-policy" 2) "noeviction"

# Metrics endpoint
kubectl exec -n redis redis-0 -c redis-exporter -- wget -qO- http://localhost:9121/metrics | grep redis_up
# Expected: redis_up 1
```

### Test Data Persistence

```bash
# Write data
kubectl exec -n redis redis-0 -c redis -- redis-cli SET persist "test data"

# Restart pod
kubectl delete pod -n redis redis-0

# Wait for pod ready
kubectl wait --for=condition=ready pod -n redis redis-0 --timeout=60s

# Verify data persisted
kubectl exec -n redis redis-0 -c redis -- redis-cli GET persist
# Expected: "test data"
```

## Scaling (Future)

**Current (Single Instance):**
- 1 replica, no HA
- Kubernetes auto-restart on pod failure
- Data loss acceptable (cache, job retries)

**Future Options:**

### Option A: Add Sentinel Manually (Most Control)
1. Deploy 3 Redis replicas (1 master + 2 replicas)
2. Deploy 3 Sentinel instances
3. Configure automatic failover
4. Update BullMQ to use Sentinel
5. **Complexity**: High (ConfigMaps, init containers, service routing)

### Option B: Migrate to Operator (When Mature)
1. Wait for operators to fix critical bugs
2. Deploy RedisReplication CRD
3. Cutover connections
4. **Complexity**: Medium (operator bugs, simpler config)

### Option C: Migrate to Dragonfly (Performance)
1. Deploy Dragonfly operator (official GA)
2. 25× better throughput, 80% less resources
3. BullMQ compatible (Redis protocol)
4. **Complexity**: Medium (new technology, testing required)

### Option D: Stay Single Instance (Recommended)
1. Vertical scaling (increase pod resources)
2. Optimize BullMQ (concurrency, rate limiting)
3. Only migrate when truly necessary
4. **Complexity**: Low (simplest option)

**Recommendation**: Stay single instance as long as possible (Option D), then evaluate based on actual needs.

## Monitoring Alerts

**Recommended alerts:**

```yaml
- alert: RedisDown
  expr: redis_up == 0
  for: 5m

- alert: RedisMemoryHigh
  expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.8
  for: 5m

- alert: RedisConnectionsHigh
  expr: redis_connected_clients > 100
  for: 5m
```

## Operational Notes

### Pod Restart (Kubernetes Handles)
- Kubernetes detects failure → restarts pod automatically
- AOF loads previous state → data restored
- BullMQ reconnects via ioredis → jobs resume
- **Action**: Monitor recovery, no manual intervention

### Node Failure (Single Node)
- Pod stuck until node returns or is evicted
- Kubernetes reschedules to healthy node (if multi-node)
- PVC reattaches → AOF restores data
- **Downtime**: Minutes (until pod reschedules)

### Data Corruption (Rare)
- AOF corruption detected on startup
- Redis refuses to start
- **Recovery**: `redis-check-aof --fix /data/appendonly.aof`
- **Last resort**: Accept data loss (cache, job retries)

### Memory Pressure
- Redis hits maxmemory limit
- With noeviction: Writes fail
- BullMQ jobs queue in memory (ioredis enableOfflineQueue)
- **Action**: Increase pod memory or clear old data

## References

- ADR 0005: StatefulSet for Redis (No Operator)
- ADR 0007: Longhorn StorageClass Strategy
- [BullMQ Production Guide](https://docs.bullmq.io/guide/going-to-production)
- [Redis Persistence](https://redis.io/docs/management/persistence/)
