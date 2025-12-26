# 0031. GitLab Runner Image Pull Policy

**Status:** Accepted

**Date:** 2025-12-26

## Context

GitLab CI jobs with Kubernetes executor were timing out after 180s waiting for pods to start. Root cause: Containerd has no registry mirror, default `pull_policy="always"` attempts to pull from Docker Hub on every job (slow/rate-limited).

Images are already cached on node (rust:latest, postgres:18-alpine, alpine:latest).

## Decision

Set GitLab Runner's `pull_policy` to "**if-not-present**" to use cached images.

```toml
[runners.kubernetes]
  pull_policy = "if-not-present"
```

## Alternatives Considered

### 1. Containerd Registry Mirror
Not chosen: Requires manual node-level configuration (Ubuntu, no NixOS automation). Would be proper fix but adds operational complexity for single-node cluster.

### 2. Docker Executor with DinD
Not chosen: Heavier resource footprint, privileged mode required, more complex than Kubernetes executor.

### 3. Pre-pull Images with DaemonSet
Not chosen: Same outcome as `if-not-present` with additional infrastructure.

## Consequences

### Positive
- ✅ Fixes CI timeout blocker immediately
- ✅ Faster job startup (uses cache)
- ✅ No infrastructure changes needed

### Negative (Accepted Trade-offs)

**Multi-tenant image access** - Any pod can access cached images without authentication
**Reality**: Single-project private runner, no multi-tenant isolation to bypass

**Stale image vulnerabilities** - Cached images may miss security patches
**Reality**: Images already cached; same security posture. Mitigate by manual re-pull when needed.

**Node variance** - Different nodes may have different cached images
**Reality**: Single-node cluster (N/A)

## When to Reconsider

- Multi-tenant CI with strong isolation requirements
- Compliance requires automated image freshness scanning
- Cluster scales to multiple nodes
- Automation available for containerd configuration (e.g., NixOS module)

## References

- GitLab Issue: https://gitlab.ops.last-try.org/green/green/-/issues/1
- PR #267: https://github.com/hitchai-app/gitops/pull/267
- ADR 0009: Secrets Management (single-tenant context)
