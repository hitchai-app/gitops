# 0027. Shared MinIO Tenant for Infrastructure

**Status**: Accepted

**Date**: 2025-12-10

## Context

Multiple infrastructure services need S3 storage (Forgejo cache, Longhorn backups, Velero). Options: dedicated tenant per service or single shared tenant.

Constraints: Single-node cluster, MinIO operator deployed, SNSD pattern (ADR 0006).

## Decision

Deploy **single shared MinIO tenant** (`minio-infra`) with multiple buckets. Consumers declare their buckets via MinIOJob in their own namespaces (per ADR 0010).

## Alternatives Considered

### Dedicated Tenant per Service
Rejected: Resource overhead not justified on single-node (each tenant = pod + PVC, all on same disk anyway).

### External S3 (R2/AWS)
Rejected: Cache requires low latency; egress costs scale with usage.

### Per-Pod Storage
Rejected: Ephemeral runners lose cache on restart.

## Consequences

**Positive:**
- Resource efficiency (single pod/PVC)
- Simplified operations (one tenant to manage)
- Easy bucket provisioning via MinIOJob

**Negative:**
- Shared fate (tenant failure affects all services)
- Single tenant capacity limits

## When to Reconsider

- Multi-node with tenant placement needs
- Compliance requires strict isolation
- Performance bottleneck
- Geographic DR needed (consider external S3)

## References

- ADR 0006: MinIO Operator Single-Drive Bootstrap
- ADR 0010: GitOps Repository Structure
