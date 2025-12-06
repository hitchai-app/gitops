# 0024. Application Structure with Infrastructure Dependencies

**Status**: Accepted

**Date**: 2025-12-06

## Context

Applications like GlitchTip need infrastructure dependencies (PostgreSQL, Valkey). Need a pattern for organizing these within ArgoCD.

Options:
1. Single ArgoCD Application with multi-source (tightly coupled)
2. Sub-applications for each dependency (independent lifecycle)

## Decision

Use **sub-applications for infrastructure dependencies** when they have independent lifecycles.

**Structure:**
```
apps/infrastructure/
├── glitchtip.yaml           # Main app (deployments, services)
├── glitchtip-postgres.yaml  # Sub-app (CloudNativePG cluster)
└── glitchtip-valkey.yaml    # Sub-app (SAP Valkey instance)
```

**When to use sub-apps:**
- Databases (PostgreSQL, MySQL) - separate backup/restore lifecycle
- Caches (Redis, Valkey) - can restart without affecting main app
- Message queues - independent scaling

**When to use multi-source (single app):**
- Tightly coupled resources (ConfigMaps, Secrets, Ingress)
- Resources that must sync atomically

## Consequences

### Positive
- Independent health status per component in ArgoCD UI
- Isolated sync/rollback per dependency
- Clear dependency visibility
- Can sync database without touching application

### Negative
- More ArgoCD Applications to manage
- Must coordinate sync order manually if needed
- Slightly more complex initial setup

## References

- ArgoCD App-of-Apps: https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/
- ADR 0010: GitOps Repository Structure
- ADR 0019: Resource Organization and Application Granularity
