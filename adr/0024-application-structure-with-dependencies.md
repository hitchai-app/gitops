# 0024. Application Structure with Infrastructure Dependencies

**Status**: Accepted

**Date**: 2025-12-06

## Decision

For apps that own infrastructure (e.g., database, cache), use an **app-of-apps**: one parent Application as the entrypoint, children per component, ordered by **sync-wave**.

```
apps/infrastructure/
├─ glitchtip.yaml          # parent entrypoint
└─ glitchtip/
   ├─ postgres.yaml        # sync-wave: -2
   ├─ valkey.yaml          # sync-wave: -1
   └─ app.yaml             # sync-wave: 0
```

- Benefits: single deploy/delete switch; independent sync/rollback per component; deterministic order.
- Costs: extra Application CRDs; deleting the parent removes children.

Use app-of-apps when an application ships dedicated infra and needs ordered rollout. Use a single Application for stateless apps on shared infra.

## References

- [ArgoCD App-of-Apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ADR 0010: GitOps Repository Structure](0010-gitops-repository-structure.md)
