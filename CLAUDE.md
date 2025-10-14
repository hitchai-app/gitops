# GitOps Infrastructure

GitOps repository for Kubernetes cluster infrastructure using ArgoCD.

For contributor expectations and workflow checklists, see [`AGENTS.md`](AGENTS.md).

## Project Overview

This repository manages infrastructure for an in-house Kubernetes cluster running on Hetzner (12 CPU / 128GB RAM / 280GB SSD). The cluster hosts microservices architecture with stage and prod environments, following GitOps practices with ArgoCD.

## Repository Structure

```
gitops/
├── bootstrap/          # Manual installation (ArgoCD, Sealed Secrets key)
├── apps/              # ArgoCD Application CRDs (app-of-apps pattern)
├── infrastructure/    # Platform services (shared PostgreSQL, MinIO, monitoring)
├── workloads/         # Your products and applications
└── adr/               # Architecture Decision Records
```

**Key principle:** Infrastructure exists FOR products, workloads ARE products.

See @adr/0010-gitops-repository-structure.md for details.

## Key Technologies

- **GitOps**: ArgoCD (@adr/0001-gitops-with-argocd.md)
- **Storage**: Longhorn (@adr/0002-longhorn-storage-from-day-one.md, @adr/0007-longhorn-storageclass-strategy.md)
- **Databases**: CloudNativePG (@adr/0004-cloudnativepg-for-postgresql.md)
- **Cache**: Valkey StatefulSet (@adr/0005-statefulset-for-valkey.md)
- **Object Storage**: MinIO Operator (@adr/0006-minio-operator-single-drive-bootstrap.md)
- **Certificates**: cert-manager + Let's Encrypt DNS-01 (@adr/0008-cert-manager-for-tls.md)
- **Secrets**: Sealed Secrets BYOK (@adr/0009-secrets-management-strategy.md)
- **Ingress**: Traefik (@adr/0011-traefik-ingress-controller.md)
- **LoadBalancer**: MetalLB Layer 2 (@adr/0012-metallb-load-balancer.md)

## Environments

- **Stage**: Testing environment with lower resource quotas
- **Prod**: Production environment with higher resource quotas

Current: Single-node Hetzner server → Future: Multi-node cluster

## Getting Started

### Prerequisites
- Kubernetes cluster (v1.30+)
- kubectl configured
- Access to cluster

### Bootstrap Process
1. Install ArgoCD: `helm install argocd ...` (see @adr/0010-gitops-repository-structure.md)
2. Generate and inject Sealed Secrets key (see @adr/0009-secrets-management-strategy.md)
3. Apply root apps: `kubectl apply -f apps/infrastructure.yaml`
4. Everything else automated via ArgoCD

See @adr/0010-gitops-repository-structure.md for detailed bootstrap workflow.

## Architecture Decisions

All major architectural decisions are documented in `adr/`:

- @adr/0001-gitops-with-argocd.md
- @adr/0002-longhorn-storage-from-day-one.md
- @adr/0003-operators-over-statefulsets.md
- @adr/0004-cloudnativepg-for-postgresql.md
- @adr/0005-statefulset-for-valkey.md
- @adr/0006-minio-operator-single-drive-bootstrap.md
- @adr/0007-longhorn-storageclass-strategy.md
- @adr/0008-cert-manager-for-tls.md
- @adr/0009-secrets-management-strategy.md
- @adr/0010-gitops-repository-structure.md
- @adr/0011-traefik-ingress-controller.md
- @adr/0012-metallb-load-balancer.md

See @adr/README.md for ADR format guidelines.

## Related Repositories

- **Product Environment**: ../hi-env (development environment with Tilt)
- **Services**: Managed as git submodules in hi-env repository

## Cluster Specifications

- Provider: Hetzner
- Resources: 12 CPU / 128GB RAM / 280GB SSD
- Nodes: 1 (single node) → scaling to multi-node
- Target availability: 99%
- Domain: `*.ops.last-try.org` (internal infrastructure services)

See individual ADRs for infrastructure and workload details.

## Development Workflow

**IMPORTANT: All changes MUST go through pull requests. Never commit directly to master.**

1. Create feature branch from master
2. Make changes in feature branch
3. Submit PR for review
4. Merge to master → ArgoCD auto-syncs to cluster

### Working with Automated Reviews

This repository uses automated code review via GitHub Actions. See [`AGENTS.md`](AGENTS.md) for detailed guidance on:
- Correcting reviewer errors with evidence-based comments
- Reminding the reviewer it has **full `gh` CLI access** (it often assumes it lacks permissions)
- Using `@claude` mentions to trigger re-evaluation

**Key reminder:** The automated reviewer has kubectl and gh CLI access. If it claims it cannot verify something, remind it to use these tools.

## Best Practices

### ArgoCD Applications with Helm Charts

**We use ArgoCD's native multi-source Helm** (not kustomize helmCharts):

```yaml
spec:
  project: default
  sources:
    # 1. Helm chart from OCI/HTTP registry
    - repoURL: oci://ghcr.io/org/charts
      chart: my-chart
      targetRevision: 1.0.0
      helm:
        releaseName: my-release
        valueFiles:
          - $values/infrastructure/my-app/values.yaml
    # 2. Git repo with values file
    - repoURL: https://github.com/org/gitops.git
      targetRevision: HEAD
      ref: values
    # 3. (Optional) Git repo with additional manifests (sealed secrets, etc.)
    - repoURL: https://github.com/org/gitops.git
      targetRevision: HEAD
      path: infrastructure/my-app
```

**Why this approach:**
- ✅ Works perfectly with app-of-apps pattern (no field stripping)
- ✅ Simpler - no kustomization files needed
- ✅ ArgoCD handles Helm natively
- ✅ Can combine Helm charts with plain manifests (sealed secrets, configmaps)
- ✅ No `--enable-helm` flags or middleware complexity

**Why NOT kustomize helmCharts:**
- ❌ In app-of-apps pattern, `kustomize.buildOptions` field gets stripped during Server-Side Apply
- ❌ Requires kustomization.yaml files that add unnecessary complexity
- ❌ Needs `--enable-helm` flag that may not survive parent→child Application sync

**Examples:** `apps/infrastructure/arc-controller.yaml`, `apps/infrastructure/arc-runners.yaml`, `apps/infrastructure/observability.yaml`

### Kubernetes Manifests

**Labels**: Do NOT add labels manually to Kubernetes resources. ArgoCD automatically adds tracking labels to all resources it manages. Manual labels are redundant and create maintenance overhead.

```yaml
# ❌ Don't do this
metadata:
  labels:
    app.kubernetes.io/managed-by: argocd
    app.kubernetes.io/name: my-app

# ✅ Do this instead - minimal, let ArgoCD handle tracking
metadata:
  name: my-resource
```

ArgoCD automatically adds:
- `app.kubernetes.io/instance: <app-name>`
- `argocd.argoproj.io/instance: <namespace>_<app-name>`

These are sufficient for resource tracking and querying.

## Disaster Recovery

- **Storage**: Longhorn S3 backups (@adr/0002-longhorn-storage-from-day-one.md)
- **Database**: CloudNativePG PITR (@adr/0004-cloudnativepg-for-postgresql.md)
- **Secrets**: Sealed Secrets key backup (@adr/0009-secrets-management-strategy.md)

See individual ADRs for RTO/RPO targets.
