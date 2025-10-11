# hitchai-app Runner Scale Set

Heavy runners with Docker-in-Docker for containerized builds.

## Overview

- **Scale**: 0-5 runners (auto-scale based on GitHub Actions queue)
- **Container mode**: Docker-in-Docker (privileged)
- **Resources**: 500m-2 CPU, 1-4Gi memory per runner
- **Authentication**: GitHub App (sealed secret)
- **Workflow usage**: `runs-on: hitchai-app-runners`

## Prerequisites

1. ARC Controller installed (`infrastructure/arc-controller/`)
2. Sealed Secrets controller running
3. GitHub App configured with Actions (read/write), Metadata (read) permissions

Setup instructions: See `github-app-sealed.yaml.example`

## Workflow Example

```yaml
jobs:
  build:
    runs-on: hitchai-app-runners
    steps:
      - uses: actions/checkout@v4
      - run: docker build -t myapp .
```

## Common Operations

**Check runner status:**
```bash
kubectl get pods -n arc-runners
kubectl get pods -n arc-systems -l app.kubernetes.io/name=hitchai-app-runners
```

**View logs:**
```bash
# Listener (polls GitHub queue)
kubectl logs -n arc-systems -l app.kubernetes.io/name=hitchai-app-runners

# Controller
kubectl logs -n arc-systems deployment/arc-gha-rs-controller

# Runner (if pod exists)
kubectl logs -n arc-runners <pod-name> -c runner
kubectl logs -n arc-runners <pod-name> -c dind
```

**Adjust scaling:**
Edit `values.yaml` → commit → ArgoCD syncs automatically

**Troubleshooting:**
1. Verify secret exists: `kubectl get secret hitchai-app-github-app -n arc-runners`
2. Check GitHub App has Actions (read/write) permission
3. Ensure `githubConfigUrl` matches organization URL

## References

- [ARC Documentation](https://github.com/actions/actions-runner-controller)
- ADR 0014: Actions Runner Controller for GitHub Actions
