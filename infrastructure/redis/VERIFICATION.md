# Redis Verification Guide

Complete verification procedures for Redis StatefulSet deployment.

## Quick Verification Checklist

```bash
# 1. Pod running
kubectl get pods -n redis
# Expected: redis-0  2/2  Running

# 2. PVC bound
kubectl get pvc -n redis
# Expected: data-redis-0  Bound  longhorn-replicated

# 3. Service exists
kubectl get svc -n redis
# Expected: redis  ClusterIP  None  6379/TCP,9121/TCP

# 4. Redis responsive
kubectl exec -n redis redis-0 -c redis -- redis-cli ping
# Expected: PONG

# 5. AOF enabled
kubectl exec -n redis redis-0 -c redis -- redis-cli CONFIG GET appendonly
# Expected: appendonly yes

# 6. noeviction policy
kubectl exec -n redis redis-0 -c redis -- redis-cli CONFIG GET maxmemory-policy
# Expected: maxmemory-policy noeviction

# 7. Metrics endpoint
kubectl exec -n redis redis-0 -c redis-exporter -- wget -qO- http://localhost:9121/metrics | grep redis_up
# Expected: redis_up 1
```

## Detailed Verification Steps

### 1. ArgoCD Application Status

```bash
# Check Application sync status
kubectl get application -n argocd redis

# Expected output:
# NAME    SYNC STATUS   HEALTH STATUS
# redis   Synced        Healthy

# Detailed status
argocd app get redis
```

### 2. StatefulSet Status

```bash
# Check StatefulSet
kubectl get statefulset -n redis

# Expected output:
# NAME    READY   AGE
# redis   1/1     Xm

# Describe StatefulSet
kubectl describe statefulset -n redis redis

# Check for:
# - Replicas: 1 desired, 1 current, 1 ready
# - Pod Management Policy: OrderedReady
# - Update Strategy: RollingUpdate
```

### 3. Pod Health

```bash
# Check pod status
kubectl get pods -n redis

# Expected output:
# NAME      READY   STATUS    RESTARTS   AGE
# redis-0   2/2     Running   0          Xm

# Check container readiness
kubectl get pods -n redis redis-0 -o jsonpath='{.status.containerStatuses[*].ready}'
# Expected: true true

# Pod details
kubectl describe pod -n redis redis-0

# Check for:
# - Both containers (redis, redis-exporter) Running
# - Liveness probes passing
# - Readiness probes passing
```

### 4. Storage Verification

```bash
# Check PVC
kubectl get pvc -n redis

# Expected output:
# NAME            STATUS   VOLUME     CAPACITY   STORAGECLASS          AGE
# data-redis-0    Bound    pvc-xxx    10Gi       longhorn-replicated   Xm

# PVC details
kubectl describe pvc -n redis data-redis-0

# Verify:
# - Status: Bound
# - StorageClass: longhorn-replicated
# - Capacity: 10Gi (base), 5Gi (stage), 20Gi (prod)

# Longhorn volume
kubectl get volumes.longhorn.io -n longhorn-system | grep redis

# Check Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# Open http://localhost:8080
# Volumes tab: Should show redis PVC with 3 replicas
```

### 5. Service and DNS

```bash
# Check Service
kubectl get svc -n redis

# Expected output:
# NAME    TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)              AGE
# redis   ClusterIP   None         <none>        6379/TCP,9121/TCP    Xm

# Verify headless service (ClusterIP: None)
kubectl describe svc -n redis redis

# DNS resolution test
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup redis.redis.svc.cluster.local

# Expected:
# Name: redis.redis.svc.cluster.local
# Address: <pod-ip>
```

### 6. Redis Configuration Verification

```bash
# AOF persistence
kubectl exec -n redis redis-0 -c redis -- redis-cli CONFIG GET appendonly
# Expected: 1) "appendonly" 2) "yes"

kubectl exec -n redis redis-0 -c redis -- redis-cli CONFIG GET appendfsync
# Expected: 1) "appendfsync" 2) "everysec"

# Maxmemory policy
kubectl exec -n redis redis-0 -c redis -- redis-cli CONFIG GET maxmemory-policy
# Expected: 1) "maxmemory-policy" 2) "noeviction"

# All config
kubectl exec -n redis redis-0 -c redis -- redis-cli CONFIG GET '*' | grep -E '(appendonly|appendfsync|maxmemory-policy)'
```

### 7. Redis Functionality Tests

```bash
# Test write operations
kubectl exec -n redis redis-0 -c redis -- redis-cli SET test:key1 "value1"
# Expected: OK

kubectl exec -n redis redis-0 -c redis -- redis-cli GET test:key1
# Expected: "value1"

# Test lists (BullMQ uses lists)
kubectl exec -n redis redis-0 -c redis -- redis-cli LPUSH test:list "item1" "item2"
# Expected: (integer) 2

kubectl exec -n redis redis-0 -c redis -- redis-cli LRANGE test:list 0 -1
# Expected: 1) "item2" 2) "item1"

# Test sets
kubectl exec -n redis redis-0 -c redis -- redis-cli SADD test:set "member1" "member2"
# Expected: (integer) 2

kubectl exec -n redis redis-0 -c redis -- redis-cli SMEMBERS test:set
# Expected: 1) "member1" 2) "member2"

# Cleanup test keys
kubectl exec -n redis redis-0 -c redis -- redis-cli DEL test:key1 test:list test:set
```

### 8. Data Persistence Test

```bash
# Step 1: Write test data
kubectl exec -n redis redis-0 -c redis -- redis-cli SET persist:test "data before restart"
kubectl exec -n redis redis-0 -c redis -- redis-cli GET persist:test
# Expected: "data before restart"

# Step 2: Delete pod (triggers restart)
kubectl delete pod -n redis redis-0

# Step 3: Wait for pod to be ready
kubectl wait --for=condition=ready pod -n redis redis-0 --timeout=60s

# Step 4: Verify data persisted
kubectl exec -n redis redis-0 -c redis -- redis-cli GET persist:test
# Expected: "data before restart"

# Success: AOF persistence working correctly

# Cleanup
kubectl exec -n redis redis-0 -c redis -- redis-cli DEL persist:test
```

### 9. Monitoring and Metrics

```bash
# Check redis-exporter container
kubectl logs -n redis redis-0 -c redis-exporter --tail=20

# Metrics endpoint
kubectl exec -n redis redis-0 -c redis-exporter -- wget -qO- http://localhost:9121/metrics | head -50

# Key metrics to verify:
kubectl exec -n redis redis-0 -c redis-exporter -- wget -qO- http://localhost:9121/metrics | grep -E '(redis_up|redis_memory_used_bytes|redis_connected_clients)'

# Expected output includes:
# redis_up 1
# redis_memory_used_bytes{...} <value>
# redis_connected_clients{...} <value>

# ServiceMonitor (if Prometheus Operator installed)
kubectl get servicemonitor -n redis
# Expected: redis

kubectl describe servicemonitor -n redis redis
```

### 10. Performance Baseline

```bash
# Redis INFO command
kubectl exec -n redis redis-0 -c redis -- redis-cli INFO > /tmp/redis-info.txt
cat /tmp/redis-info.txt

# Key sections:
# - Server: Redis version, uptime
# - Memory: used_memory, used_memory_rss, maxmemory_policy
# - Persistence: aof_enabled, aof_last_write_status
# - Stats: total_connections_received, total_commands_processed

# Memory usage
kubectl exec -n redis redis-0 -c redis -- redis-cli INFO memory | grep used_memory_human
# Note baseline memory usage

# Connected clients
kubectl exec -n redis redis-0 -c redis -- redis-cli INFO clients | grep connected_clients
# Should be 1 (redis-cli connection itself)

# Operations per second
kubectl exec -n redis redis-0 -c redis -- redis-cli INFO stats | grep instantaneous_ops_per_sec
# Note baseline ops/sec
```

### 11. BullMQ Compatibility Test

```bash
# Port-forward Redis
kubectl port-forward -n redis redis-0 6379:6379 &

# Create test script (requires Node.js and bullmq installed)
cat > /tmp/test-bullmq.js <<'EOF'
const { Queue, Worker } = require('bullmq');

const connection = {
  host: 'localhost',
  port: 6379,
  maxRetriesPerRequest: null,
};

const queue = new Queue('test-queue', { connection });

async function test() {
  // Add job
  const job = await queue.add('test-job', { data: 'test' });
  console.log('Job added:', job.id);

  // Process job
  const worker = new Worker('test-queue', async job => {
    console.log('Processing job:', job.id, job.data);
    return { result: 'success' };
  }, { connection });

  // Wait for completion
  await new Promise(resolve => setTimeout(resolve, 2000));

  // Cleanup
  await worker.close();
  await queue.close();
  console.log('BullMQ test successful');
  process.exit(0);
}

test().catch(err => {
  console.error('BullMQ test failed:', err);
  process.exit(1);
});
EOF

# Run test (requires bullmq package)
node /tmp/test-bullmq.js

# Stop port-forward
pkill -f "kubectl port-forward.*redis"
```

## Troubleshooting

### Pod Not Starting

**Check logs:**
```bash
kubectl logs -n redis redis-0 -c redis
kubectl logs -n redis redis-0 -c redis-exporter
```

**Common issues:**
- PVC not binding → Check StorageClass exists
- AOF corruption → Check logs for "Bad file format"
- Memory limits → Check OOMKilled status

### PVC Not Binding

**Check StorageClass:**
```bash
kubectl get storageclass longhorn-replicated
# If missing: Deploy Longhorn first
```

**Check Longhorn:**
```bash
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system deployment/longhorn-driver-deployer
```

**Check PVC events:**
```bash
kubectl describe pvc -n redis data-redis-0
# Look for "ProvisioningFailed" events
```

### AOF Corruption

**Symptoms:**
- Pod crash loop
- Logs show "Bad file format reading the append only file"

**Recovery:**
```bash
# Exec into pod (if running)
kubectl exec -it -n redis redis-0 -c redis -- sh

# Check AOF
redis-check-aof /data/appendonly.aof

# Fix corruption
redis-check-aof --fix /data/appendonly.aof

# Restart pod
kubectl delete pod -n redis redis-0
```

### High Memory Usage

**Check memory:**
```bash
kubectl exec -n redis redis-0 -c redis -- redis-cli INFO memory | grep used_memory_human
```

**Flush data (CAUTION: deletes all data):**
```bash
kubectl exec -n redis redis-0 -c redis -- redis-cli FLUSHALL
```

**Increase memory limit:**
Edit overlay kustomization.yaml, increase memory limits, commit and push.

### Connection Refused

**Check service:**
```bash
kubectl get svc -n redis
kubectl describe svc -n redis redis
```

**Test connectivity:**
```bash
kubectl run -it --rm debug --image=redis:7-alpine --restart=Never -- \
  redis-cli -h redis.redis.svc.cluster.local ping
# Expected: PONG
```

## Success Criteria

All checks must pass:

- [x] Pod redis-0 Running with 2/2 containers ready
- [x] PVC data-redis-0 Bound with longhorn-replicated
- [x] Service redis exists (headless ClusterIP)
- [x] Redis responds to PING
- [x] AOF persistence enabled (appendonly yes, appendfsync everysec)
- [x] maxmemory-policy noeviction
- [x] Data persists across pod restart
- [x] redis-exporter metrics accessible
- [x] ServiceMonitor created (if Prometheus Operator installed)
- [x] BullMQ compatibility (if tested)

## Post-Deployment Tasks

1. **Set up monitoring alerts** (if Prometheus installed)
2. **Document baseline metrics** (memory, ops/sec)
3. **Test application connectivity** (BullMQ queues)
4. **Schedule periodic backups** (if needed, though data loss acceptable)

## Regular Maintenance

**Weekly:**
- Check memory usage trends
- Review connection counts
- Monitor AOF file growth

**Monthly:**
- Test data persistence (pod restart)
- Review logs for errors
- Verify monitoring alerts working

**Quarterly:**
- Evaluate scaling needs (single instance sufficient?)
- Review ADR 0005 for operator maturity updates
