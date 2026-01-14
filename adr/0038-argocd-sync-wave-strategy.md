# 0038. ArgoCD Sync Wave Strategy

**Status**: Proposed

**Date**: 2026-01-14

## Context

ArgoCD sync waves control resource deployment order. Without clear conventions, dependencies deploy in wrong order causing failures (app before database, resources before operator).

**Note:** The ×10 gap convention (-30, -20, -10, 0, +10) is a team-specific pattern for flexibility. ArgoCD only requires numeric values; the spacing strategy is our own.

## Decision

Establish numeric sync wave convention with ×10 gaps for flexibility.

### Sync Wave Convention

```
-30: Operators (CRDs, must exist first)
-20: Databases/Clusters (require operators)
-10: Cache/Instances (require operators)
   0: Applications (require data/cache)
 +10: Ingress, jobs, dependent resources
 +20: Post-deployment hooks
```

### Examples

**Operators (wave -30):**
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-30"
```

**Databases (wave -20):**
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-20"
```

**Applications (wave 0):**
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"
```

## When to Use Sync Waves

**Use when:**
- Explicit dependency exists (operator before resources)
- Database must exist before application
- Migration jobs run after deployment
- Certificates required before ingress

**Skip when:**
- No dependencies (independent services)
- Order doesn't matter
- Single-service deployments
- Resources can start in any order (Kubernetes handles initialization)
- Services use retry logic and tolerate missing dependencies

## Consequences

**Positive**:
- Clear dependency ordering
- ×10 gaps allow flexibility
- Prevents deployment failures

**Negative**:
- Extra annotation complexity
- Must remember convention

## When to Reconsider

- ArgoCD introduces better dependency mechanism
- Convention causes more confusion than clarity

## References

- [ArgoCD Sync Waves Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [Understanding ArgoCD Sync Waves (Codefresh)](https://codefresh.io/learn/argo-cd/understanding-argo-cd-sync-waves/)
