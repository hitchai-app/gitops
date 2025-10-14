# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) documenting significant architectural choices made for this GitOps infrastructure.

## What is an ADR?

An ADR captures an important architectural decision along with its context and consequences. ADRs help teams understand:
- Why decisions were made
- What alternatives were considered
- What trade-offs were accepted
- When the decision can be revisited

## ADR Format

Each ADR follows this structure:

```markdown
# [Number]. [Title]

**Status**: [Proposed | Accepted | Deprecated | Superseded]

**Date**: YYYY-MM-DD

## Context

What is the issue we're addressing? What constraints exist?

## Decision

What decision did we make? Be specific and actionable.

## Alternatives Considered

What other options did we evaluate?

1. **Option A**: Brief description
   - Pros: ...
   - Cons: ...

2. **Option B**: Brief description
   - Pros: ...
   - Cons: ...

## Consequences

What are the implications of this decision?

### Positive
- Benefit 1
- Benefit 2

### Negative
- Trade-off 1
- Trade-off 2

### Neutral
- Consideration 1
- Consideration 2

## References

- Links to relevant documentation
- Related ADRs
- External resources
```

## Naming Convention

ADRs are numbered sequentially with zero-padding:

```
0001-gitops-with-argocd.md
0002-longhorn-storage-from-day-one.md
0003-operators-over-statefulsets.md
```

## Current ADRs

| Number | Title | Status | Date |
|--------|-------|--------|------|
| [0001](0001-gitops-with-argocd.md) | GitOps with ArgoCD | Accepted | 2025-10-05 |
| [0002](0002-longhorn-storage-from-day-one.md) | Longhorn Storage from Day One | Accepted | 2025-10-05 |
| [0003](0003-operators-over-statefulsets.md) | Operators over StatefulSets | Accepted | 2025-10-05 |
| [0004](0004-cloudnativepg-for-postgresql.md) | CloudNativePG for PostgreSQL | Accepted | 2025-10-05 |
| [0005](0005-statefulset-for-valkey.md) | Valkey StatefulSet | Accepted | 2025-10-07 |
| [0006](0006-minio-operator-single-drive-bootstrap.md) | MinIO Operator Single-Drive Bootstrap | Accepted | 2025-10-05 |
| [0007](0007-longhorn-storageclass-strategy.md) | Longhorn StorageClass Strategy | Accepted | 2025-10-05 |
| [0008](0008-cert-manager-for-tls.md) | cert-manager for TLS Certificates | Accepted | 2025-10-05 |
| [0009](0009-secrets-management-strategy.md) | Secrets Management Strategy | Accepted | 2025-10-05 |
| [0010](0010-gitops-repository-structure.md) | GitOps Repository Structure | Accepted | 2025-10-05 |
| [0011](0011-traefik-ingress-controller.md) | Traefik Ingress Controller | Accepted | 2025-10-06 |
| [0012](0012-metallb-load-balancer.md) | MetalLB for LoadBalancer | Accepted | 2025-10-06 |
| [0013](0013-observability-foundation.md) | Observability Foundation | Accepted | 2025-10-08 |
| [0014](0014-actions-runner-controller-for-github-actions.md) | Actions Runner Controller for GitHub Actions | Accepted | 2025-10-11 |
| [0015](0015-harbor-container-registry.md) | Harbor Container Registry | Deferred | 2025-10-12 |
| [0016](0016-gitlab-platform-migration.md) | GitLab Platform Migration | Deferred | 2025-10-12 |
| [0017](0017-observability-stack-evaluation.md) | Observability Stack Evaluation | Proposed | 2025-10-14 |

## When to Create an ADR

Create an ADR when making decisions about:
- Infrastructure architecture
- Technology selection
- Deployment strategies
- Security patterns
- Operational procedures
- Significant trade-offs

## When NOT to Create an ADR

Don't create ADRs for:
- Implementation details (these go in code comments)
- Temporary workarounds
- Obvious/standard practices
- Decisions that can be easily reversed

## Writing Good ADRs

**Document decisions, not implementations.**

❌ Bad: "Use StorageClass named `longhorn-single-replica` with `numberOfReplicas: "1"`"
✅ Good: "Use single-replica class for apps with built-in replication"

**Why:** Implementation details (exact names, parameters, configs) belong in manifests. ADRs explain *why* decisions were made, not *how* to implement them.

**Lesson learned:** ADR 0007 included exact names and configurations, causing automated reviews to flag reasonable implementation choices as "violations." Simplified from 200 to 85 lines by removing specs while keeping the decision intact.

## Updating ADRs

ADRs are immutable historical records. To change a decision:
1. Create a new ADR
2. Reference the old ADR
3. Mark the old ADR as "Superseded by ADR-XXXX"

To refine (remove unnecessary detail):
- Keep core decision and rationale
- Remove implementation specifications
- Note refinement in commit message
