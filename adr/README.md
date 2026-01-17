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
| [0005](0005-statefulset-for-valkey.md) | Valkey StatefulSet | Superseded | 2025-10-07 |
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
| [0016](0016-gitlab-platform-migration.md) | GitLab Platform Migration | Superseded | 2025-10-12 |
| [0017](0017-observability-stack-evaluation.md) | Observability Stack Evaluation | Superseded | 2025-10-14 |
| [0018](0018-dex-authentication-provider.md) | Dex Authentication Provider | Proposed | 2025-10-14 |
| [0019](0019-resource-organization-and-application-granularity.md) | Resource Organization and Application Granularity | Accepted | 2025-10-15 |
| [0020](0020-sap-valkey-operator.md) | SAP Valkey Operator | Accepted | 2025-11-30 |
| [0021](0021-sentry-error-tracking.md) | Sentry Error Tracking Platform | Superseded | 2025-12-04 |
| [0022](0022-glitchtip-error-tracking.md) | GlitchTip Error Tracking | Accepted | 2025-12-04 |
| [0023](0023-forgejo-woodpecker-ci.md) | Forgejo + Woodpecker CI | Partially Superseded | 2025-12-04 |
| [0024](0024-application-structure-with-dependencies.md) | Application Structure with Dependencies | Accepted | 2025-12-06 |
| [0025](0025-helm-chart-compatibility-review.md) | Helm Chart Compatibility Review | Accepted | 2025-12-06 |
| [0026](0026-forgejo-actions-ephemeral-runners.md) | Forgejo Actions with Ephemeral Runners | Accepted | 2025-12-10 |
| [0027](0027-shared-minio-for-infrastructure.md) | Shared MinIO Tenant for Infrastructure | Accepted | 2025-12-10 |
| [0028](0028-crossplane-for-external-infrastructure.md) | Crossplane for External Infrastructure | Accepted | 2025-12-11 |
| [0029](0029-restore-gitlab-platform.md) | Restore GitLab Platform | Accepted | 2025-12-20 |
| [0030](0030-remove-signoz-evaluation.md) | Remove SigNoz Evaluation Stack | Accepted | 2025-12-20 |
| [0031](0031-gitlab-runner-pull-policy.md) | GitLab Runner Pull Policy | Accepted | 2025-12-26 |
| [0032](0032-gitlab-ci-path-variable-service-container-fix.md) | GitLab CI Path Variable Fix | Accepted | 2025-12-26 |
| [0033](0033-crossplane-external-infrastructure.md) | Crossplane External Infrastructure | Accepted | 2026-01-08 |
| [0034](0034-node-naming-convention.md) | Node Naming Convention | Accepted | 2026-01-09 |
| [0035](0035-cluster-target-architecture.md) | Cluster Target Architecture | Accepted | 2026-01-09 |
| [0036](0036-altinity-clickhouse-operator.md) | Altinity ClickHouse Operator | Accepted | 2026-01-14 |
| [0037](0037-strimzi-kafka-operator.md) | Strimzi Kafka Operator | Accepted | 2026-01-14 |
| [0039](0039-cnpg-managed-tls-for-sentry-postgres.md) | CNPG-Managed TLS and Password Auth for Sentry Postgres | Accepted | 2026-01-15 |
| [0040](0040-sentry-bundled-stateful-services.md) | Sentry Bundled Stateful Services | Superseded | 2026-01-15 |
| [0041](0041-sentry-operator-stateful-services.md) | Sentry Operator-Managed Stateful Services | Accepted | 2026-01-17 |

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
