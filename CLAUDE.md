# GitOps Infrastructure

GitOps repository for Kubernetes cluster infrastructure using ArgoCD.

## Project Overview

This repository manages infrastructure for an in-house Kubernetes cluster running on Hetzner (12 CPU / 128GB RAM / 280GB SSD). The cluster hosts microservices architecture with stage and prod environments, following GitOps practices with ArgoCD.

## Repository Structure

```
gitops/
├── bootstrap/          # Initial cluster setup (ArgoCD, Longhorn, sealed-secrets)
├── infrastructure/     # Shared services (Postgres, Redis, Minio, monitoring)
├── platform/          # Product services (stage/prod environments)
├── apps/              # ArgoCD Applications
├── adr/               # Architecture Decision Records
└── docs/              # Additional documentation
```

## Key Technologies

- **GitOps**: ArgoCD (declarative infrastructure management)
- **Storage**: Longhorn (distributed storage with S3 backups)
- **Databases**: CloudNativePG (PostgreSQL operator), OT-Redis-Operator (Redis operator)
- **Object Storage**: MinIO Operator
- **Monitoring**: [TBD - will be defined in ADR]
- **Secrets**: [TBD - will be defined in ADR]

## Environments

- **Stage**: Namespace `stage` with ResourceQuota (prevent resource starvation)
- **Prod**: Namespace `prod` with ResourceQuota (isolated resource allocation)

Current deployment: Single-node Hetzner server
Future: Multi-node cluster with Longhorn replication

## Getting Started

### Prerequisites
- Kubernetes cluster (v1.30+)
- kubectl configured
- Access to cluster

### Bootstrap Process
1. Install ArgoCD: See `bootstrap/argocd/`
2. Install Longhorn: See `bootstrap/longhorn/`
3. Configure secrets: See `bootstrap/sealed-secrets/`
4. Deploy infrastructure: ArgoCD syncs from `apps/`

## Architecture Decisions

All major architectural decisions are documented in ADRs:

- [ADR 0001: GitOps with ArgoCD](adr/0001-gitops-with-argocd.md)
- [ADR 0002: Longhorn Storage from Day One](adr/0002-longhorn-storage-from-day-one.md)
- [ADR 0003: Operators over StatefulSets](adr/0003-operators-over-statefulsets.md)

See [adr/README.md](adr/README.md) for the complete list and ADR format guidelines.

## Related Repositories

- **Product Environment**: ../hi-env (development environment with Tilt)
- **Services**: Managed as git submodules in hi-env repository

## Cluster Specifications

**Current Setup:**
- Provider: Hetzner
- Resources: 12 CPU / 128GB RAM / 280GB SSD
- Nodes: 1 (single node, will scale to multi-node)
- Target availability: 99% (two nines)

**Planned Services:**
- Longhorn (distributed storage)
- PostgreSQL (via CloudNativePG operator)
- Redis (via OT-Redis-Operator)
- MinIO (via MinIO operator)
- Monitoring stack (Prometheus, Grafana)
- LiteLLM proxy
- Langfuse (LLM observability)
- GitHub Actions self-hosted runners

## Development Workflow

1. Make changes in feature branch
2. Submit PR for review
3. ArgoCD detects changes on merge to master
4. ArgoCD syncs to cluster (stage first, then prod)

## Disaster Recovery

- **Storage**: Longhorn S3 backups (automated)
- **Postgres**: PITR via CloudNativePG (point-in-time recovery)
- **Cluster State**: [TBD - Velero or similar]
- **RTO/RPO**: Defined per service in operational runbooks

## Support

For questions or issues:
- Check ADRs for architectural context
- Review bootstrap READMEs for setup guidance
- Check ArgoCD UI for sync status
