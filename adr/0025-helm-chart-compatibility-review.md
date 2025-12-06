# 0025. Helm Chart Compatibility Review Process

**Status**: Accepted

**Date**: 2025-12-06

## Context

Helm charts may have compatibility issues with ArgoCD, particularly around hooks and resource ordering. Discovered while deploying GlitchTip.

## Decision

Before adopting any Helm chart, review for:
1. Hook annotations (`helm.sh/hook`) and their dependencies
2. Resource ordering assumptions
3. Compatibility with our infrastructure (CloudNativePG, SAP Valkey)

## Known Caveat: Helm Hooks with ArgoCD

**The Problem:**

ArgoCD converts Helm hooks to ArgoCD sync phases:
- `helm.sh/hook: pre-install,pre-upgrade` → `PreSync` (runs BEFORE resources)
- `helm.sh/hook: post-install,post-upgrade` → `PostSync`

If a hook Job depends on a ConfigMap (via `envFrom`), and the ConfigMap is NOT a hook, the Job runs before ConfigMap exists.

**Root Cause:**

ArgoCD uses `helm template` (templating only), then applies with kubectl. Cannot distinguish install vs upgrade - all are "syncs". PreSync hooks run before ANY non-hook resources.

**Evidence:**
- [ArgoCD #6456](https://github.com/argoproj/argo-cd/issues/6456) - Hook ordering problems
- [ArgoCD #355](https://github.com/argoproj/argo-cd/issues/355) - Hook mapping discussion
- [Longhorn #6415](https://github.com/longhorn/longhorn/issues/6415) - Same PreSync issue

**GlitchTip Example:**

Chart's migration Job (`glitchtip-migrate`):
- Has: `helm.sh/hook: pre-install,pre-upgrade`
- Depends on: ConfigMap `glitchtip` (via `envFrom`)
- ConfigMap has: `helm.sh/hook-weight: "-1"` but NO `helm.sh/hook`

Result: ConfigMap is NOT a hook → created during main sync. Job IS a hook → runs as PreSync BEFORE ConfigMap exists. **Job fails.**

## Workarounds

1. **Replace chart's hook with ArgoCD Sync hook** (our choice for GlitchTip)
   - Disable chart's migration Job
   - Create custom Job with `argocd.argoproj.io/hook: Sync` and `sync-wave: "1"`
   - Job runs DURING sync, AFTER wave 0 resources

2. **Make dependencies hooks too**
   - Requires chart modification or patching
   - May conflict with chart's design

3. **Use plain manifests instead of Helm**
   - Full control over resource ordering
   - More maintenance overhead

## Consequences

### Positive
- Prevents deployment failures from hook timing issues
- Documents known patterns for future charts
- Clear workaround path when issues arise

### Negative
- Adds review overhead before adopting charts
- May need custom manifests for some charts

## References

- [ArgoCD Sync Phases](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ArgoCD Resource Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/)
- [Helm Hooks Documentation](https://helm.sh/docs/topics/charts_hooks/)
