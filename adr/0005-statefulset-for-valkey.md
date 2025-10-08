# 0005. Valkey StatefulSet (Manual)

**Status**: Accepted  
**Date**: 2025-10-07

## Context

- Workloads: HTTP session cache and BullMQ job queues (via ioredis) with built-in retry logic.
- Data tolerates loss: cache entries rebuild automatically; BullMQ can replay jobs that were in-flight.
- Initial footprint: single-node Hetzner cluster using Longhorn for persistent volumes; may expand to multi-node later.
- Team: small, comfortable with GitOps but limited Kubernetes/operator expertise; willing to own simple manual operations.
- Non-goals (for now): automated failover, multi-primary clustering, TLS/auth hardening, scheduled backups, or multi-tenancy isolation.

## Decision

Run Valkey 8.x as a single-replica Kubernetes StatefulSet that we manage directly through GitOps manifests. We adopt Valkey instead of Redis to stay on a community-governed, BSD-licensed fork while keeping protocol compatibility with BullMQ. No operator or Helm chart is introduced; we accept the manual responsibilities that come with this.

### Guardrails We Commit To

- **Relative memory ceiling**: compute `maxmemory` at container start (target ~80 % of cgroup limit) so `maxmemory-policy noeviction` engages before the kernel OOM killer.
- **Persistence**: enable AOF with `everysec` fsync; accept the 1 s durability window.
- **Monitoring**: ship `redis_exporter` pinned to `v1.61.0` as a sidecar, expose a ServiceMonitor, and alert on `valkey_up`, `valkey_memory_used_bytes`, `valkey_connected_clients`, and BullMQ queue depth.
- **Security posture**: run inside the cluster network without AUTH/TLS initially; document that internal callers can reach the service and re-evaluate before exposing cross-namespace or external access.
- **Operational cadence**: review Valkey release notes monthly and upgrade deliberately; track toil hours spent on upgrades/incidents.

## Rationale

1. **Licensing & community**: Valkey keeps the permissive BSD license and is driven by the Linux Foundation. We avoid uncertainty stemming from Redis Ltd.’s license carve-outs while staying API-compatible with the Redis ecosystem (BullMQ, ioredis, redis-cli).
2. **Scope fit**: a single pod with acceptable RPO/RTO does not benefit from operator-driven automation. Manual manifests stay predictable and easy to debug.
3. **Operational simplicity**: omitting an operator or chart avoids additional CRDs, reconciliation logic, and release cycles—important for a team with limited capacity.

## Alternatives Considered

### Redis Helm Chart (Bitnami)
- **Pros**: packed defaults (Sentinel toggle, metrics sidecar, password generation), signed releases (`redis` chart 23.1.1, app 8.2.2), `helm upgrade` workflow.
- **Cons**: chart introduces a large values surface that we must learn and monitor; future changes to Bitnami images (Secure Images programme) may complicate reproducible builds; still relies on Redis Ltd.’s release cadence and licensing posture.
- **Why not now**: we value minimal YAML over chart indirection at single-node scale and prefer Valkey’s governance.

### Redis Operator (OT-CONTAINER-KIT)
- **Pros**: declarative replicas/Sentinel/cluster topologies, automated failover, built-in exporter wiring.
- **Cons**: open issues such as #1403 (failover leaves the cluster without a primary), #1164 (data loss during restart), #1513 (passwords logged via CLI), and slow turnaround on CVE-2025-49844 image rebuilds show ongoing maturity gaps; reconciler debugging overhead the team cannot absorb yet.
- **Why not now**: the automation does not offset the operational risk for a workload that already tolerates downtime.

### Valkey + Helm/Operator (future options)
- **Pros**: emerging charts (community-maintained) could reduce manual toil; consistent upgrades once ecosystems mature.
- **Cons**: as of Oct 2025 there is no widely trusted Valkey chart/operator; docs are still under review; examples are sparse.
- **Why not now**: we do not want to be early adopters of tooling that lacks a production track record.

### Managed Redis/Valkey Service
- **Pros**: offloads patching, backups, HA.
- **Cons**: adds cross-cloud networking complexity, recurring cost, and loss of data locality; overkill for the current scale.
- **Why not now**: budget and platform simplicity win while data is non-critical.

## Implementation Guidance

### StatefulSet Skeleton

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: valkey
spec:
  serviceName: valkey
  replicas: 1
  selector:
    matchLabels:
      app: valkey
  template:
    metadata:
      labels:
        app: valkey
    spec:
      containers:
      - name: valkey
        image: valkeyio/valkey:8.1.4-alpine
        command:
        - /bin/sh
        - -c
        - |
          mem_file=/sys/fs/cgroup/memory.max
          if [ -f "$mem_file" ]; then
            raw=$(cat "$mem_file")
            if [ "$raw" = "max" ]; then
              maxmemory=512mb
            else
              maxmemory_bytes=$((raw * 80 / 100))
              maxmemory="${maxmemory_bytes}B"
            fi
          else
            maxmemory=512mb
          fi
          exec valkey-server \
            --appendonly yes \
            --appendfsync everysec \
            --maxmemory "$maxmemory" \
            --maxmemory-policy noeviction
        ports:
        - containerPort: 6379
          name: valkey
        volumeMounts:
        - name: data
          mountPath: /data
        resources:
          requests:
            cpu: 100m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          exec:
            command: ["valkey-cli", "ping"]
          initialDelaySeconds: 10
          periodSeconds: 15
        readinessProbe:
          exec:
            command: ["valkey-cli", "ping"]
          initialDelaySeconds: 5
          periodSeconds: 5
      - name: redis-exporter
        image: oliver006/redis_exporter:v1.61.0
        args:
        - --redis.addr=redis://localhost:6379
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
      storageClassName: longhorn
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

**Notes**
- Adjust the fallback value (`512mb`) to stay under the pod limit if the kernel reports `max`. Update resources as we collect usage data.
- Longhorn will bind the PVC to the node hosting the pod; no failover occurs until the cluster adds additional nodes.
- Probes keep the pod cycling if the process wedges; BullMQ workers must handle reconnects (they already do).

### Monitoring

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: valkey
  labels:
    app: valkey
spec:
  selector:
    matchLabels:
      app: valkey
  endpoints:
  - port: metrics
    interval: 30s
```

Alerting expectations:
- Warn when `valkey_memory_used_bytes / container_memory_limit_bytes > 0.75` for 10 m.
- Critical when `valkey_up == 0` for 2 scrape intervals.
- Track BullMQ queue depth (from app metrics) to spot backlog after restarts.

### Security Posture

- No AUTH/TLS initially. Document that only workloads in the same namespace should connect; revisit before cross-namespace access or external exposure.
- If we later need credentials: configure `requirepass`, mount a Kubernetes Secret, update exporter CLI flags, and add Namespace-scoped NetworkPolicies.

### Features Deferred

- **Backups**: not implemented; if requirements change, options include Longhorn snapshots or CronJobs that coordinate pod downtime.
- **High availability**: a manual Sentinel build-out or migration to a Valkey/Redis operator is the future path once downtime becomes unacceptable.
- **Modules**: we currently rely only on core data structures; Valkey modules (JSON, search) remain optional.

## Operational Checklist

- **Upgrades**: monthly review of Valkey release notes and CVEs; pin new image tags/digests deliberately; run staging smoke tests before promoting.
- **Capacity review**: quarterly check of memory usage vs limit; if steady-state >65 %, plan for vertical scaling or additional instances.
- **Incident playbook**:
  - Pod crash → Kubernetes restarts; verify AOF replay, watch BullMQ backlog, ensure metrics recover.
  - Node failure (single-node cluster) → manual intervention needed; reattach Longhorn volume once node is back or cluster scales out.
- **Toil tracking**: monitor manual hours spent on upgrades/incident response; when >8 h per quarter, reassess adoption of a maintained chart or operator.

## Triggers to Revisit This ADR

1. **Availability expectations tighten** (downtime for pod restart no longer acceptable).
2. **Scale**: sustained memory >50 GiB or job throughput >10k ops/sec.
3. **Security**: requirement for TLS, ACLs, or tenant isolation.
4. **Ecosystem maturity**: stable Valkey Helm chart/operator with production references, or Redis operator issues resolved with proven uptime.
5. **Team capacity**: ability to manage Sentinel/operator increases or toil from manual processes becomes burdensome.

## References

- Valkey releases: [github.com/valkey-io/valkey/releases](https://github.com/valkey-io/valkey/releases)
- Valkey blog (feature cadence): [valkey.io/blog](https://valkey.io/blog/)
- OT-CONTAINER-KIT issue tracker (redis-operator): [github.com/OT-CONTAINER-KIT/redis-operator/issues](https://github.com/OT-CONTAINER-KIT/redis-operator/issues)
- Bitnami Redis Helm chart: [artifacthub.io/packages/helm/bitnami/redis](https://artifacthub.io/packages/helm/bitnami/redis)
- BullMQ production guidance: [docs.bullmq.io](https://docs.bullmq.io/guide/going-to-production)
