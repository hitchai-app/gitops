# 0025. Helm Chart Compatibility Review Process

**Status**: Accepted

**Date**: 2025-12-06

## Decision

Before adopting a chart, check three things:
- Hook annotations (`helm.sh/hook`) and whether dependent resources are also hooks
- Assumed resource order
- Fit with our infra (CloudNativePG, SAP Valkey)

### Hook Caveat

ArgoCD maps Helm hooks to sync phases (`pre-install/upgrade` → `PreSync`, `post-*` → `PostSync`). A PreSync Job runs **before** non-hook resources, so if it depends on a ConfigMap/Secret that lacks `helm.sh/hook`, it will fail. This surfaced in GlitchTip: migration Job was a hook; its ConfigMap was not.

### Preferred Mitigation

Preferred: replace chart hooks with an ArgoCD Sync hook job—disable the chart's hook job, add a custom Job with `argocd.argoproj.io/hook: Sync` and a positive `sync-wave` so dependencies are present. Alternatives: make dependencies hooks too, or render manifests instead of Helm when ordering is unfixable.

## References

- [ArgoCD Sync Phases](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ArgoCD Resource Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/)
- [Helm Hooks](https://helm.sh/docs/topics/charts_hooks/)
