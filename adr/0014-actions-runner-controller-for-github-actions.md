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
  - ⚠️ **WARNING**: Docker-in-Docker mode (`containerMode: dind`) requires privileged containers, which have elevated security risks:
    - Can access host resources
    - Bypass container isolation
    - Potential for container escape
  - **Mitigation**: Ephemeral pods (destroyed after each job) limit exposure window
  - **Alternative**: Kaniko for privileged-free builds (requires workflow changes)
- ❌ Resource overhead per runner (memory + CPU allocation)
- ❌ Cold start time required to spin up new runner pods

### Neutral
- Node capacity planning required based on runner resource requests
- Controller restart delays new runner creation (acceptable downtime)

## Implementation Notes

**Architecture**: Controller in `arc-systems` watches GitHub queue → Listener polls for jobs → Runner pods spawn in `arc-runners`

**Authentication**: GitHub App (sealed secret) - more secure than PAT, fine-grained permissions

**Security**:
- ⚠️ **CRITICAL**: Docker-in-Docker mode requires privileged containers with elevated security risks
- Privileged containers can access host resources and bypass container isolation
- **Mitigation**: Ephemeral pods are destroyed after each job, limiting exposure window
- **Alternative**: Kaniko for privileged-free builds (requires workflow changes, see Future Enhancements)

## Future Enhancements

### 1. Light + Heavy Runner Architecture (High Priority)

**Problem**: Most CI jobs don't need Docker (linting, tests, npm scripts), but current setup wastes resources with Docker-in-Docker for everything.

**Solution**: Two-tier runner architecture

#### Light Runners (New)
- **Use case**: Linting, tests, scripts, non-Docker jobs (~80% of workflows)
- **Container mode**: Kubernetes (no Docker, no privileged)
- **Resources**: Lower memory/CPU footprint than heavy runners
- **Scaling**: Higher max count (more concurrent jobs possible)
- **Workflow**: `runs-on: hitchai-app-light`

#### Heavy Runners (Current, Rename)
- **Use case**: Docker builds, complex containerized workflows (~20% of workflows)
- **Container mode**: Docker-in-Docker (privileged)
- **Resources**: Higher memory/CPU allocation for Docker daemon
- **Scaling**: Lower max count (resource-intensive)
- **Workflow**: `runs-on: hitchai-app-heavy`

**Capacity planning**: Allocate based on actual workflow mix and resource availability. Light runners can handle higher concurrency due to lower per-pod resource requirements.

**Benefits**:
- ✅ Significant resource reduction for non-Docker jobs
- ✅ No privileged containers for majority of jobs
- ✅ Faster startup for Kubernetes-mode runners
- ✅ Higher concurrent job capacity on same hardware

**Implementation**: Copy existing runner scale set, change 5 lines in values.yaml

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

### 3. Other Considerations

**Kaniko for privileged-free builds**:
- Alternative to Docker-in-Docker (no privileged mode)
- Requires workflow changes (`kaniko` instead of `docker build`)
- Consider if security audit flags privileged containers

**When to reconsider ARC**:
- Scale significantly beyond current capacity (evaluate GitHub-hosted or multi-cluster)
- Maintenance burden becomes unsustainable (consider managed solutions)

## References

- [ARC Documentation](https://github.com/actions/actions-runner-controller)
- [GitHub Actions Runner Controller Quickstart](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/quickstart-for-actions-runner-controller)
- [Authenticating to GitHub API](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/authenticating-to-the-github-api)
- [Kaniko - Daemonless Docker Builds](https://github.com/GoogleContainerTools/kaniko)
- ADR 0001: GitOps with ArgoCD
- ADR 0009: Secrets Management Strategy
