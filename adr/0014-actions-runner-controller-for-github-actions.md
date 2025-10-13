# 0014. Actions Runner Controller (ARC) for GitHub Actions

**Status**: Accepted

**Date**: 2025-10-11

## Context

We need self-hosted GitHub Actions runners for CI/CD pipelines with automatic scaling, ephemeral environments, Docker build support, and GitOps management.

Current constraint: Single Hetzner node (128GB RAM) scaling to multi-node.

## Decision

Use **GitHub Actions Runner Controller (ARC)** with ephemeral Docker-in-Docker runners managed via ArgoCD.

Initial deployment: Single heavy runner scale set (0-4 runners, Docker-in-Docker enabled)

## Alternatives Considered

### 1. GitHub-Hosted Runners
- **Why not**: $0.008/min expensive at scale, cannot access internal cluster services

### 2. Persistent Self-Hosted Runners
- **Why not**: No auto-scaling, state persists between jobs (security risk), manual maintenance

### 3. Jenkins Kubernetes Plugin
- **Why not**: Separate CI system to maintain, not GitHub Actions native

### 4. Legacy ARC (actions.summerwind.dev)
- **Why not**: Deprecated architecture, new `gha-runner-scale-set-controller` is official path

## Consequences

### Positive
- ✅ Auto-scaling (0-N based on queue, scale to zero when idle)
- ✅ Ephemeral runners (fresh pod per job, destroyed after)
- ✅ GitOps-managed via ArgoCD
- ✅ Private network access (can reach internal cluster services)

### Negative
- ❌ **Privileged containers required for Docker-in-Docker** (security risk)
  - ⚠️ **CRITICAL**: `privileged: true` grants access to **Kubernetes node resources** (not just pod)
  - Can mount node disk partitions (`/dev/sda1`), access other pods' data, escape to node
  - **Real risk**: ARC Issue #1288 demonstrates mounting node filesystem from DinD container
  - **Mitigation**: Ephemeral pods (destroyed after each job) + trusted users (GitHub org only)
  - **Risk accepted**: No viable alternative without breaking `services:` block or major infrastructure changes
  - **Alternatives evaluated**: Kata Containers (requires special nodes), Sysbox (requires CRI-O), Kaniko (breaks `services:`), Rootless DinD (high friction)
- ❌ Resource overhead per runner (memory + CPU allocation)
- ❌ Cold start time required to spin up new runner pods

### Neutral
- Node capacity planning required based on runner count and resource requests
- Controller restart delays new runner creation (acceptable downtime)

## Implementation Notes

**Architecture**: Controller in `arc-systems` watches GitHub queue → Listener polls for jobs → Runner pods spawn in `arc-runners`

**Authentication**: GitHub App (sealed secret) - more secure than PAT, fine-grained permissions

**Security**:
- ⚠️ **CRITICAL**: `privileged: true` on DinD container grants access to Kubernetes node
  - **What's accessible**: Node disk devices, other pods' storage, kernel capabilities
  - **Proof**: Docker docs state "can get a root shell on the host and take control"
  - **Example attack**: `mount /dev/sda1 /mnt` from DinD mounts node root filesystem
- **Why this risk is accepted**:
  - GitHub Actions `services:` block requires Docker daemon (very common in workflows)
  - Alternatives break functionality or require massive infrastructure changes
  - Ephemeral pods destroyed after each job (attacker must re-exploit every run)
  - Trusted users only (GitHub org members, not public runners)
- **When to revisit**:
  - Security incident involving runner compromise
  - Compliance requires VM-level isolation → Kata Containers
  - Team scales beyond trusted org members

## Future Enhancements

### 1. Increase Runner Capacity with Overcommit Strategy

**Current approach: Single DinD runner scale set with overcommit**

We use a single DinD runner type for all jobs (light and heavy) with an overcommit strategy:
- **Low resource requests**: Ensures many pods can schedule
- **High resource limits**: Allows bursting for heavy jobs (Docker builds)
- **ResourceQuota cap**: Prevents total namespace exhaustion

**Why not split into K8s-only and DinD runners:**
- GitHub Actions `services:` block is very common and requires Docker
- Operational simplicity: one scale set to maintain
- Overcommit handles both light jobs (use ~512Mi) and heavy jobs (burst to 4Gi)

**Scaling strategy:**
- Increase `maxRunners` as needed (currently 4)
- Monitor actual resource usage and adjust
- ResourceQuota prevents overcommit from causing node exhaustion

#### ResourceQuota Constraint Discovery (Oct 2025)

**Critical learning: ResourceQuota enforces at `limits.memory` specification level, NOT actual usage.**

**What we discovered:**
- Deployed 12 runners with 12Gi memory limits each
- Expected: Thin provisioning means only actual usage counts
- Reality: All 9 runners failed with quota exceeded errors
- Root cause: ResourceQuota admission control checks sum of limits, not actual memory consumption

**Current constraint:**
- Namespace quota: `50Gi limits.memory`
- Per-runner limit: `12Gi` (runner container) + overhead
- Math: `50Gi ÷ 12Gi = 4 runners maximum`
- Attempting 5+ runners triggers: `exceeded quota: arc-runners-quota, requested: limits.memory=12Gi, used: limits.memory=48Gi, limited: limits.memory=50Gi`

**Why thin provisioning doesn't help:**
- tmpfs volumes ARE thin-provisioned (sizeLimit is upper bound, only writes consume RAM)
- This helps with actual node memory pressure
- BUT: Kubernetes ResourceQuota checks `spec.containers.resources.limits.memory` at admission time
- Quota doesn't care if you only use 2Gi of your 12Gi limit—it blocks pod creation based on declared limits

**Path forward:**
- Short-term: Limited to 4 runners with current 50Gi quota
- To increase runners: Must increase ResourceQuota first (e.g., 120Gi allows 10 runners)
- Overcommit still valuable: 4 runners × 12Gi limits = 48Gi quota used, but actual RAM usage typically 8-16Gi total

---

### 2. Docker Registry Cache (High Priority)

**Problem**: Pulling same base images repeatedly wastes bandwidth, hits Docker Hub rate limits (100-200 pulls/6h), slows builds.

**Solution**: In-cluster registry cache

#### Option A: Simple Docker Registry (Pull-Through Cache)

**Best for**: Quick start, minimal maintenance, simple use case

**Pros**:
- ✅ Extremely simple (single StatefulSet, minimal memory footprint)
- ✅ Transparent (change image URLs or configure Docker daemon)
- ✅ Works with Docker Hub, ghcr.io, gcr.io
- ✅ Zero-config caching

**Cons**:
- ❌ No UI (debugging cache misses harder)
- ❌ No garbage collection (manual disk cleanup)
- ❌ No authentication/RBAC (anyone in cluster can pull)
- ❌ No vulnerability scanning

**Setup**:
```yaml
env:
- name: REGISTRY_PROXY_REMOTEURL
  value: https://registry-1.docker.io
- name: REGISTRY_PROXY_USERNAME
  valueFrom:
    secretKeyRef:
      name: dockerhub-creds
      key: username
```

**Usage**: `FROM registry-cache.arc-runners.svc:5000/node:20` (proxies to `docker.io/node:20`)

**When to use**: Start here. Run for 2-4 weeks, measure cache hit rates. If simple registry becomes painful (debugging, cleanup), upgrade to Harbor.

---

#### Option B: Harbor (Full-Featured Registry)

**Best for**: Long-term, if simple registry proves insufficient

**Pros**:
- ✅ Built-in pull-through cache (proxy projects)
- ✅ Web UI for cache monitoring, hit rates
- ✅ Vulnerability scanning (Trivy integration)
- ✅ Image signing (Cosign/Notary)
- ✅ RBAC and authentication
- ✅ Garbage collection (automated cleanup)
- ✅ Replication to S3 backups
- ✅ CNCF graduated (production-proven)

**Cons**:
- ❌ Heavier footprint (multiple components with higher memory requirements)
- ❌ More complex setup (PostgreSQL, Redis dependencies)
- ❌ Longer initial setup time

**Why Harbor fits your stack**:
- You already have CloudNativePG (Harbor uses PostgreSQL)
- You already have Valkey (Harbor can use Redis-compatible)
- Aligns with operator-first approach (ADR 0003)

**When to use**: If simple registry cache becomes painful (no UI for debugging, manual cleanup needed, want vulnerability scanning).

---

### Caching Strategy Decision Tree

```
Start with simple Docker registry cache
    ↓
Run for 2-4 weeks
    ↓
Measure: Cache hit rate, disk usage, bandwidth savings
    ↓
Pain points?
    ├─ No → Keep simple registry
    └─ Yes → Evaluate pain
        ├─ Debugging cache misses → Harbor (UI)
        ├─ Disk cleanup painful → Harbor (GC)
        ├─ Need vuln scanning → Harbor (Trivy)
        └─ Working fine → Keep simple registry
```

**Don't over-engineer**: Start simple, upgrade only if needed.

---

### 3. Alternative Container Runtimes (If Security Requirements Change)

**If privileged containers become unacceptable**, evaluated alternatives:

#### Kata Containers (Recommended if must eliminate privileged)
- Runs pods in lightweight VMs (microVMs)
- Privileged escape contained within VM boundary
- **Requires**: Dedicated nodes with nested virtualization
- **Works with `services:` block**: Yes ✅
- **Trade-off**: Higher cost, slower startup, more complexity

#### Sysbox Runtime
- Rootless nested containerization without privileged mode
- **Blocker**: Requires cluster-wide CRI-O runtime (incompatible with containerd)
- **Works with `services:` block**: Yes ✅

#### Kaniko (Build-only)
- **DOES NOT solve the problem**: Only handles `docker build`, not `services:` block
- GitHub Discussion #46300: `services:` do not work in Kubernetes mode
- **Archived**: No longer maintained
- **Would break**: All workflows using `services: redis/postgres/etc`

#### Rootless DinD
- Docker daemon runs as non-root user
- **High friction**: No sudo access, must pre-bake all tools in runner image
- **Works with `services:` block**: Yes ✅

**Decision**: Privileged DinD risk accepted as lower cost than alternatives for current threat model.

**When to reconsider ARC**:
- Scale beyond 20 concurrent runners (evaluate GitHub-hosted)
- Maintenance burden becomes unsustainable (consider managed solutions)

## References

- [ARC Documentation](https://github.com/actions/actions-runner-controller)
- [GitHub Actions Runner Controller Quickstart](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/quickstart-for-actions-runner-controller)
- [Authenticating to GitHub API](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/authenticating-to-the-github-api)
- [ARC Security Issue #1288](https://github.com/actions/actions-runner-controller/issues/1288) - Privileged container node access
- [Docker Privileged Mode](https://docs.docker.com/reference/cli/docker/container/run/#privileged) - Official security warning
- [CNCF: Privileged Pods](https://www.cncf.io/blog/2020/10/16/hack-my-mis-configured-kubernetes-privileged-pods/) - Attack demonstration
- [GitHub Discussion #46300](https://github.com/orgs/community/discussions/46300) - Services block limitation in Kubernetes mode
- [Sysbox Runtime](https://github.com/nestybox/sysbox) - Rootless nested containers
- [Kata Containers](https://katacontainers.io/) - VM-level isolation
- ADR 0001: GitOps with ArgoCD
- ADR 0009: Secrets Management Strategy
