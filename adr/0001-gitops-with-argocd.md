# 0001. GitOps with ArgoCD

**Status**: Accepted

**Date**: 2025-10-05

## Context

We need a declarative infrastructure management approach for our Kubernetes cluster. The cluster hosts microservices with stage and prod environments, and will be managed by a small development team without dedicated ops specialists.

Key requirements:
- Declarative infrastructure as code
- Git as single source of truth
- Automated sync from repository to cluster
- Rollback capabilities
- Audit trail of changes

Constraints:
- Small team (developers wear ops hats)
- Single node currently (128GB RAM available)
- Will scale to multi-node in future
- Need visibility into sync status

## Decision

We will use **ArgoCD** as our GitOps continuous delivery tool for Kubernetes.

ArgoCD will:
- Monitor this Git repository for changes
- Automatically sync Kubernetes manifests to the cluster
- Provide UI for deployment visibility
- Handle rollbacks declaratively
- Manage both infrastructure and application deployments

## Alternatives Considered

### 1. Flux
- **Pros**:
  - Lighter weight (~500MB RAM vs 1-2GB for ArgoCD)
  - GitOps-native design
  - CLI-driven workflow
  - More minimal architecture
- **Cons**:
  - No built-in UI (requires separate dashboard)
  - Less batteries-included
  - Steeper learning curve for developers

### 2. Manual kubectl/Helm
- **Pros**:
  - No additional dependencies
  - Maximum control
  - Simple to understand
- **Cons**:
  - No GitOps workflow
  - Manual sync process
  - No automated rollback
  - No audit trail
  - Human error prone

## Consequences

### Positive
- **UI visibility**: Developers can see deployment status without kubectl
- **Batteries-included**: Less configuration needed, more features out-of-box
- **Strong community**: Large user base, active development (CNCF graduated project)
- **Declarative rollback**: Can rollback by reverting Git commits
- **Git as source of truth**: All changes tracked in version control
- **App-of-Apps pattern**: Can manage ArgoCD Applications declaratively

### Negative
- **Resource overhead**: ~1-2GB RAM for ArgoCD components (acceptable given 128GB total)
- **Additional complexity**: One more system to learn and maintain
- **Sync delays**: Changes aren't instant (polling interval or webhook required)
- **ArgoCD itself needs management**: Must maintain ArgoCD upgrades, backups

### Neutral
- **Philosophy choice**: ArgoCD is more feature-rich, Flux is more minimal (we chose features)
- **UI dependency**: Team will rely on UI (could be pro or con depending on perspective)
- **RBAC complexity**: ArgoCD RBAC is powerful but has learning curve

## Implementation Notes

- ArgoCD will be bootstrapped manually (chicken-and-egg problem)
- After bootstrap, ArgoCD manages itself via App-of-Apps pattern
- Will use ArgoCD ApplicationSets for environment-specific deployments
- Webhooks will be configured for faster sync (vs polling)

### Notifications

ArgoCD Notifications sends deployment events to Discord:

**Events tracked:**
- Successful deployments (sync succeeded + healthy)
- Sync failures (error/failed)
- Health degraded

**Configuration:**
- Discord webhook service in `argocd-notifications-cm` ConfigMap
- Default subscriptions for all applications
- Rich embed format with app name, environment, revision, status, ArgoCD UI link

**Location:** `infrastructure/argocd-notifications/`

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Flux vs ArgoCD Comparison](https://www.cncf.io/blog/2024/12/17/managing-large-scale-redis-clusters-on-kubernetes-with-an-operator-kuaishous-approach/)
- [App-of-Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
