# 0024. Application Structure with Infrastructure Dependencies

**Status**: Accepted

**Date**: 2025-12-06

## Context

Applications like GlitchTip need infrastructure dependencies (PostgreSQL, Valkey). Need a pattern for organizing these within ArgoCD with guaranteed deployment order.

## Decision

Use **app-of-apps pattern with sync waves** for applications with infrastructure dependencies.

**Structure:**
```
apps/infrastructure/
├── glitchtip.yaml              # Parent app → points to glitchtip/
└── glitchtip/                  # Child Application CRDs
    ├── postgres.yaml           # sync-wave: "-2"
    ├── valkey.yaml             # sync-wave: "-1"
    └── app.yaml                # sync-wave: "0"
```

**Sync order guaranteed by waves:**
1. Wave -2: postgres (CloudNativePG cluster)
2. Wave -1: valkey (SAP Valkey instance)
3. Wave 0: app (deployments, services, migration job)

**When to use this pattern:**
- Applications with database dependencies
- Applications with cache/queue dependencies
- Any app needing ordered infrastructure provisioning

**When NOT to use (single app sufficient):**
- Stateless applications
- Applications using shared infrastructure (e.g., shared postgres cluster)

## Consequences

### Positive
- Guaranteed deployment order via sync waves
- Independent health status per component in ArgoCD UI
- Parent app shows overall health of all children
- Can sync individual components without affecting others

### Negative
- More Application CRDs to manage
- Nested app structure adds complexity
- Must understand sync-wave semantics

## References

- ArgoCD Sync Waves: https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/
- ArgoCD App-of-Apps: https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/
- ADR 0010: GitOps Repository Structure
