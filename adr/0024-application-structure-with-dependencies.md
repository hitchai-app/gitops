# 0024. Application Structure with Infrastructure Dependencies

**Status**: Accepted

**Date**: 2025-12-06

## Context

Applications like GlitchTip need infrastructure dependencies (PostgreSQL, Valkey). Need a pattern for:
- Single entrypoint for the entire application stack
- Independent control of each component
- Guaranteed deployment order

## Decision

Use **app-of-apps pattern** for applications with infrastructure dependencies.

**Key concepts:**
1. **Single entrypoint**: One parent Application that manages the entire stack
2. **Independent children**: Each component is a separate ArgoCD Application
3. **Sync waves**: Control deployment order between children

**Structure:**
```
apps/infrastructure/
├── glitchtip.yaml              # Parent app (single entrypoint)
└── glitchtip/                  # Child Application CRDs
    ├── postgres.yaml           # sync-wave: "-2" → glitchtip-postgres app
    ├── valkey.yaml             # sync-wave: "-1" → glitchtip-valkey app
    └── app.yaml                # sync-wave: "0"  → glitchtip-app app
```

**How it works:**
1. Parent `glitchtip` app syncs → creates child Application CRDs
2. ArgoCD reconciles children as independent apps
3. Sync waves ensure postgres → valkey → app order

**ArgoCD UI shows:**
```
glitchtip (parent - single entrypoint)
├── glitchtip-postgres (independent app)
├── glitchtip-valkey (independent app)
└── glitchtip-app (independent app)
```

**Each child can be:**
- Synced independently
- Rolled back individually
- Health-checked separately

## Consequences

### Positive
- Single entrypoint to deploy/delete entire stack
- Independent control of each component
- Guaranteed deployment order via sync waves
- Clear visibility in ArgoCD UI

### Negative
- More Application CRDs to manage
- Nested structure adds complexity
- Deleting parent deletes all children

## When to Use

**Use app-of-apps when:**
- Application has dedicated infrastructure (database, cache)
- Need independent sync/rollback per component
- Want single entrypoint for entire stack

**Use single app when:**
- Stateless application
- Using shared infrastructure
- Simple deployment without dependencies

## References

- ArgoCD App-of-Apps: https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/
- ArgoCD Sync Waves: https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/
- ADR 0010: GitOps Repository Structure
