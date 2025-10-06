# GitOps Infrastructure

GitOps repository for Kubernetes cluster infrastructure using ArgoCD.

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
- **Cache**: Redis StatefulSet (@adr/0005-statefulset-for-redis.md)
- **Object Storage**: MinIO Operator (@adr/0006-minio-operator-with-4-drives.md)
- **Certificates**: cert-manager + Let's Encrypt DNS-01 (@adr/0008-cert-manager-for-tls.md)
- **Secrets**: Sealed Secrets BYOK (@adr/0009-secrets-management-strategy.md)
- **Ingress**: Traefik (@adr/0011-traefik-ingress-controller.md)

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
- @adr/0005-statefulset-for-redis.md
- @adr/0006-minio-operator-with-4-drives.md
- @adr/0007-longhorn-storageclass-strategy.md
- @adr/0008-cert-manager-for-tls.md
- @adr/0009-secrets-management-strategy.md
- @adr/0010-gitops-repository-structure.md
- @adr/0011-traefik-ingress-controller.md

See @adr/README.md for ADR format guidelines.

## Related Repositories

- **Product Environment**: ../hi-env (development environment with Tilt)
- **Services**: Managed as git submodules in hi-env repository

## Cluster Specifications

- Provider: Hetzner
- Resources: 12 CPU / 128GB RAM / 280GB SSD
- Nodes: 1 (single node) → scaling to multi-node
- Target availability: 99%

See individual ADRs for infrastructure and workload details.

## Development Workflow

**IMPORTANT: All changes MUST go through pull requests. Never commit directly to master.**

1. Create feature branch from master
2. Make changes in feature branch
3. Submit PR for review
4. Merge to master → ArgoCD auto-syncs to cluster

## Disaster Recovery

- **Storage**: Longhorn S3 backups (@adr/0002-longhorn-storage-from-day-one.md)
- **Database**: CloudNativePG PITR (@adr/0004-cloudnativepg-for-postgresql.md)
- **Secrets**: Sealed Secrets key backup (@adr/0009-secrets-management-strategy.md)

See individual ADRs for RTO/RPO targets.
