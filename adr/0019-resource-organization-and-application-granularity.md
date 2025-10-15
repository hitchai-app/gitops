# 0019. Resource Organization and Application Granularity

**Status**: Accepted

**Date**: 2025-10-15

## Context

When adding OAuth2 Proxy to infrastructure services (PR #113), we initially created 4 separate ArgoCD Applications, one for each OAuth2 Proxy instance. This approach:
- Cluttered the ArgoCD UI with supporting-resource Applications
- Obscured the ownership relationship (OAuth2 Proxy exists FOR services)
- Violated the principle that resources should be organized by what they serve

The fundamental question: **When adding a new resource, does it need its own Application?**

## Decision

Resources should be organized by **what they serve**, not **what they are**.

### The Ownership Principle

**Supporting resources belong to their consumer's directory and Application.**

```
✅ Correct:   infrastructure/<service>/<supporting-resource>/
❌ Incorrect: infrastructure/<supporting-resource>-<service>/
```

**Example:**
```
✅ infrastructure/observability/kube-prometheus-stack/resources/oauth2-proxy-prometheus/
❌ infrastructure/oauth2-proxy-prometheus/
```

### Application Granularity Rules

**1. Supporting resource for existing service** → Add to existing Application via multi-source
**2. Environment/configuration variant** → Kustomize overlays under existing Application
**3. Independent platform service** → New Application

### Decision Checklist

Before creating infrastructure resources, answer:

1. **What does this resource serve?** → Determines directory location
2. **Who manages it?** → Determines Application ownership
3. **What's the pattern?** → Determines implementation approach (multi-source, overlays, new App)

## Alternatives Considered

### 1. Separate Applications per Resource Type (Initially Implemented)

**What we did first:**
```
apps/infrastructure/
  oauth2-proxy-prometheus.yaml
  oauth2-proxy-alertmanager.yaml
  oauth2-proxy-longhorn.yaml
  oauth2-proxy-signoz.yaml

infrastructure/
  oauth2-proxy-prometheus/
  oauth2-proxy-alertmanager/
  oauth2-proxy-longhorn/
  oauth2-proxy-signoz/
```

**Pros:**
- Clear resource boundaries
- Each instance independently manageable
- Simple to understand at first glance

**Cons:**
- ArgoCD UI clutter (4 new Applications for supporting resources)
- Breaks ownership model (OAuth2 Proxy exists FOR services, not independently)
- Doesn't scale (what about backups, monitoring, logging for each service?)
- Violates "infrastructure exists FOR products" principle (ADR 0010)

**Why rejected:** Created 4 Applications for what is essentially configuration variance (same image, same pattern, different upstreams).

### 2. Flat Directory Structure

```
infrastructure/
  all-oauth2-proxies/
    longhorn-deployment.yaml
    prometheus-deployment.yaml
    ...
```

**Pros:**
- Simple navigation
- All similar resources grouped

**Cons:**
- No ownership hierarchy visible
- Doesn't communicate which service each proxy protects
- Hard to find related resources

**Why rejected:** Structure doesn't communicate intent or relationships.

## Consequences

### Positive

**Architectural Clarity:**
- ✅ Directory structure communicates ownership relationships
- ✅ Fewer Applications (0 new Applications vs 4)
- ✅ "Observability Application owns Prometheus AND its auth layer" is clear
- ✅ Reduced YAML (net -51 lines in refactor)

**Maintenance:**
- ✅ Related resources colocated (easier to find and modify)
- ✅ Service lifecycle matches auth layer lifecycle
- ✅ Follows established patterns (observability, observability-signoz already use multi-source)

**Scalability:**
- ✅ Framework for future decisions (backups, monitoring, etc.)
- ✅ Prevents Application proliferation
- ✅ Consistent with ADR 0010 principles

### Negative

**Flexibility:**
- ⚠️ Supporting resource can't be deployed/rolled back independently
- ⚠️ Harder to extract resource to separate Application later (but should be rare)

**Complexity:**
- ⚠️ Requires understanding ArgoCD multi-source pattern
- ⚠️ Multiple ReplicaSets under one Application (observability manages many resources)

### Neutral

- Supporting resources sync with parent service (trade-off: flexibility vs clarity)
- Kustomize required for services without existing multi-source setup

## Implementation Guidance

### When to Create New Application

✅ **Create Application when:**
- Independent lifecycle (deploy/rollback separately from other services)
- Different namespace AND unrelated functionality
- Platform-wide service (Dex, cert-manager, ArgoCD itself)

❌ **Don't create Application when:**
- Supporting resource for existing service (auth, backup, monitoring FOR service)
- Environmental variant (stage/prod)
- Multiple instances of same thing with different config

### Using ArgoCD Multi-Source

Services that already exist should incorporate supporting resources via additional sources:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  sources:
    # Existing Helm chart
    - repoURL: https://charts.example.com
      chart: my-service
      targetRevision: 1.0.0
      helm:
        valueFiles:
          - $values/infrastructure/my-service/values.yaml

    # Existing values file
    - repoURL: https://github.com/org/gitops
      targetRevision: master
      ref: values

    # Add supporting resources (NEW)
    - repoURL: https://github.com/org/gitops
      targetRevision: master
      path: infrastructure/my-service/resources  # Contains oauth2-proxy, secrets, etc.
```

**Example:** `apps/infrastructure/longhorn-operator.yaml` was updated to add 2nd source for `infrastructure/longhorn`.

### Directory Structure Pattern

**For services using Helm charts:**
```
infrastructure/
  <service>/
    values.yaml                    # Helm values
    <supporting-resource>/         # OAuth2 Proxy, backups, etc.
      deployment.yaml
      service.yaml
      secrets-sealed.yaml
```

**For services using plain manifests:**
```
infrastructure/
  <service>/
    kustomization.yaml
    service-deployment.yaml
    <supporting-resource>/
      ...
```

**For services with additional resources directory:**
```
infrastructure/
  <service>/
    helm-chart-config/
      values.yaml
    resources/                      # Synced as separate source
      sealed-secrets.yaml
      <supporting-resource>/
```

## When to Reconsider

**Revisit this ADR if:**

1. **Application bloat:** Single Application managing >50 distinct resources becomes unwieldy
2. **Independent lifecycle required:** Need to deploy/rollback supporting resources separately from parent service
3. **Multi-cluster scenarios:** Different ownership model required for resource distribution
4. **Team scale:** >20 people need more granular Application boundaries for access control

## References

- **PR #113:** Initial OAuth2 Proxy implementation (4 separate Applications)
- **Refactor commit:** `5a00d6a` - Consolidated OAuth2 Proxy into service Applications
- **ADR 0010:** GitOps Repository Structure (infrastructure exists FOR products)
- **ArgoCD Multi-Source:** https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/
