# 0014. Actions Runner Controller (ARC) for GitHub Actions

**Status**: Accepted

**Date**: 2025-10-11

## Context

We need self-hosted GitHub Actions runners for our CI/CD pipelines. Requirements include:
- Automatic scaling based on workflow demand
- Ephemeral runners (fresh environment per job)
- Docker-in-Docker support for containerized builds
- GitOps-compatible management
- Cost efficiency (scale to zero when idle)

Current constraint: Single Hetzner node cluster (will scale to multi-node)

## Decision

We will use **GitHub Actions Runner Controller (ARC)** with the `gha-runner-scale-set-controller` architecture.

Configuration:
- ARC controller in `arc-systems` namespace
- Runner scale sets per GitHub organization
- Ephemeral Docker-in-Docker runners
- Scale range: 0-5 runners (auto-scale based on queue)
- Helm-based deployment via ArgoCD

## Alternatives Considered

### 1. Persistent Self-Hosted Runners (Traditional)
- **Pros**: Simple setup, no Kubernetes required
- **Cons**:
  - Manual scaling
  - State persists between jobs (security risk)
  - Manual maintenance and updates
  - No automatic cleanup
  - Resource waste when idle
- **Why not chosen**: No auto-scaling, security concerns with persistent state

### 2. GitHub-Hosted Runners
- **Pros**: Zero maintenance, unlimited scaling, always updated
- **Cons**:
  - Cost: $0.008/minute (expensive at scale)
  - Cannot access private cluster resources
  - Limited customization
  - Bandwidth costs for large artifacts
- **Why not chosen**: Cost prohibitive for frequent builds, cannot access internal services

### 3. Jenkins Kubernetes Plugin
- **Pros**: Mature, ephemeral agents, wide ecosystem
- **Cons**:
  - Separate CI system to maintain
  - Not native GitHub Actions
  - Different workflow syntax
  - Additional infrastructure overhead
- **Why not chosen**: Prefer GitHub-native solution, avoid maintaining separate CI system

### 4. Self-Hosted Runner Scale Set (Legacy ARC)
- **Pros**: Auto-scaling, Kubernetes-native
- **Cons**:
  - Old architecture (`actions.summerwind.dev` CRDs)
  - Less actively maintained
  - Complex setup
  - Migration path unclear
- **Why not chosen**: New ARC architecture is the official path forward

## Consequences

### Positive
- ✅ **Auto-scaling**: 0-5 runners based on queue depth (cost efficient)
- ✅ **Ephemeral**: Fresh runner per job (security benefit)
- ✅ **GitOps-native**: Declarative Helm charts via ArgoCD
- ✅ **Official GitHub solution**: Actively maintained by GitHub
- ✅ **Private network access**: Runners can access internal cluster services
- ✅ **Docker-in-Docker**: Full container build support
- ✅ **Multi-organization support**: Easy to add more runner scale sets

### Negative
- ❌ **Privileged containers**: Docker-in-Docker requires `securityContext.privileged: true`
- ❌ **Resource overhead**: Each runner uses 1-4Gi memory + 500m-2 CPU
- ❌ **Complexity**: More moving parts than simple runners
- ⚠️ **Single point of failure**: Controller restart delays new runner creation
- ⚠️ **GitHub token management**: Must secure and rotate PAT/GitHub App credentials

### Neutral
- **Cold start delay**: ~30-60s to spin up new runner (acceptable)
- **Node capacity**: 5 runners × 4Gi = 20Gi max (acceptable on 128GB node)
- **Maintenance**: Helm chart updates via ArgoCD (consistent with other infrastructure)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ arc-systems namespace                                   │
│                                                         │
│  ┌──────────────────────┐                              │
│  │ arc-gha-rs-controller│  ← Watches GitHub queue      │
│  │  (Deployment)        │                              │
│  └──────────────────────┘                              │
│                                                         │
│  ┌────────────────────────────────────────┐            │
│  │ hitchai-app-runners-listener (Pod)     │            │
│  │  - Polls GitHub for workflow jobs      │            │
│  │  - Creates EphemeralRunner CRDs        │            │
│  └────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ arc-runners namespace                                   │
│                                                         │
│  ┌─────────────────────┐  ┌─────────────────────┐     │
│  │ runner-xxx (Pod)    │  │ runner-yyy (Pod)    │     │
│  │  - runner container │  │  - runner container │     │
│  │  - dind container   │  │  - dind container   │     │
│  └─────────────────────┘  └─────────────────────┘     │
│                                                         │
│  (Scales 0-5 based on GitHub Actions queue)            │
└─────────────────────────────────────────────────────────┘
```

## Implementation Notes

### Two-Component Architecture

**1. Controller** (`gha-runner-scale-set-controller`):
- Watches AutoscalingRunnerSet CRDs
- Manages lifecycle of runner scale sets
- Single instance in `arc-systems`

**2. Runner Scale Sets** (`gha-runner-scale-set`):
- One per GitHub organization or repository
- Creates listener pod (polls GitHub) in `arc-systems`
- Creates runner pods (execute jobs) in `arc-runners`

### GitHub Authentication

Use Sealed Secrets for GitHub PAT:
```bash
# Create sealed secret with GitHub PAT
kubectl create secret generic hitchai-app-github-token \
  --namespace=arc-runners \
  --from-literal=github_token=YOUR_PAT \
  --dry-run=client -o yaml | \
kubeseal --format=yaml > github-token-sealed.yaml
```

**PAT requirements**:
- Organization: `repo` + `admin:org` (or `read:org`)
- Repository: `repo` scope only

**Alternative**: GitHub App (more secure, fine-grained permissions)

### Resource Planning

Single node capacity (128GB RAM):
- Max 5 concurrent runners × 4Gi = 20Gi
- Buffer for system pods: ~8-12Gi
- Remaining: ~96-100Gi for workloads

Multi-node: Spread runners across nodes via affinity/anti-affinity

### Workflow Usage

Reference runner scale set by its installation name:

```yaml
name: CI
on: push

jobs:
  build:
    runs-on: hitchai-app-runners  # ← Runner scale set name
    steps:
      - uses: actions/checkout@v4
      - run: docker build -t myapp .
```

### Monitoring

**Key metrics**:
- Runner pod count (current/min/max)
- Queue depth (pending workflows)
- Runner startup time
- Docker-in-Docker failures

**Alerts**:
- Controller down > 5 minutes
- Runners failing to start
- Persistent runner scaling lag
- GitHub authentication failures

### Security Considerations

**Privileged containers**: Docker-in-Docker requires `privileged: true`
- Risk: Container breakout could compromise node
- Mitigation: Runners use ephemeral pods (destroyed after job)
- Alternative: Use Kaniko for Docker builds (no privileged mode)

**GitHub token**: PAT has broad access
- Risk: Compromised token = org access
- Mitigation: Use GitHub App with fine-grained permissions
- Rotation: Rotate token quarterly

**Network isolation**: Runners can access cluster services
- Risk: Malicious workflow could probe internal services
- Mitigation: NetworkPolicies to restrict runner egress

## Migration from Manual Setup

Current manual setup:
- Controller installed via `helm install`
- Runner scale set installed via `helm install`

Migration to GitOps:
1. Create sealed secret for GitHub token
2. Apply ArgoCD Applications (will adopt existing resources)
3. Verify no disruption to running jobs
4. Delete manual Helm releases (ArgoCD owns them now)

**Note**: Helm label changes may cause recreation. Plan maintenance window.

## Future Considerations

**When to add more runner scale sets**:
- Per repository (finer-grained control)
- Different runner sizes (small/medium/large)
- Specialized runners (GPU, ARM)

**When to reconsider**:
- Scale beyond 20 concurrent runners (evaluate GitHub-hosted)
- Security audit flags privileged containers (consider Kaniko)
- Maintenance burden > 4 hours/month (consider managed solutions)

**Kaniko for privileged-free builds**:
```yaml
# Alternative to Docker-in-Docker (no privileged mode)
containerMode:
  type: "kubernetes"
  kubernetesModeWorkVolumeClaim:
    accessModes: ["ReadWriteOnce"]
    storageClassName: "longhorn-single-replica"
    resources:
      requests:
        storage: 10Gi
```

## References

- [ARC Documentation](https://github.com/actions/actions-runner-controller)
- [GitHub Actions Runner Controller Quickstart](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/quickstart-for-actions-runner-controller)
- [Authenticating to GitHub API](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/authenticating-to-the-github-api)
- [Kaniko - Daemonless Docker Builds](https://github.com/GoogleContainerTools/kaniko)
- ADR 0001: GitOps with ArgoCD
- ADR 0009: Secrets Management Strategy
