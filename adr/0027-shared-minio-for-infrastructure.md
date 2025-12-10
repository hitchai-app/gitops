# 0027. Shared MinIO Tenant for Infrastructure

**Status**: Accepted

**Date**: 2025-12-10

## Context

Multiple infrastructure services require S3-compatible storage:
- Forgejo Actions cache (runner cache persistence)
- Longhorn backups (volume snapshots)
- Future: Velero backups, monitoring data, logs

Two approaches exist:
1. **Dedicated tenants**: Each service gets its own MinIO tenant
2. **Shared tenant**: Single MinIO tenant with multiple buckets

Current constraints:
- Single-node cluster (Hetzner, 128GB RAM)
- MinIO operator already deployed
- ADR 0006 established SNSD (Single-Node Single-Drive) pattern

## Decision

Deploy a **single shared MinIO tenant** (`minio-infra`) for all infrastructure services. Services access dedicated buckets within this tenant.

**Bucket strategy:**
- `actions-cache` - Forgejo Actions runner cache
- `longhorn-backups` - Longhorn volume backups (future)
- `velero` - Cluster backups (future)

**Access control:**
- Root credentials for setup jobs
- Per-service credentials can be added via MinIO IAM policies when needed

## Alternatives Considered

### 1. Dedicated MinIO Tenant per Service
- **Pros**:
  - Complete isolation
  - Independent scaling
  - Service-specific configurations
- **Cons**:
  - Resource overhead (each tenant = separate pod + PVC)
  - Operational complexity (multiple tenants to manage)
  - Wasted storage (minimum allocation per tenant)
  - Single-node: All tenants on same disk anyway
- **Why not chosen**: Overhead not justified for infrastructure services on single-node

### 2. External S3 (AWS/Cloudflare R2)
- **Pros**:
  - No operational overhead
  - Built-in durability
  - Geographic distribution
- **Cons**:
  - Egress costs
  - Latency for cache operations
  - External dependency for CI
- **Why not chosen**: Cache requires low latency; cost scales with usage

### 3. No Shared Storage (Per-Pod Storage)
- **Pros**: Simplest, no dependencies
- **Cons**: Cache lost on pod restart (defeats purpose for ephemeral runners)
- **Why not chosen**: Ephemeral runners require persistent cache

## Consequences

### Positive
- **Resource efficiency**: Single pod, single PVC serves all infrastructure
- **Simplified operations**: One tenant to monitor, backup, upgrade
- **Consistent patterns**: All services use same S3 endpoint
- **Easy bucket provisioning**: Setup job creates buckets declaratively

### Negative
- **Shared fate**: Tenant failure affects all services
- **No isolation**: Services share resources (acceptable for infrastructure)
- **Scaling limits**: Single tenant capacity limits apply to all

### Neutral
- **Security**: Bucket-level policies provide sufficient isolation for infrastructure
- **Migration path**: Can split to dedicated tenants if needed later

## Implementation

```
minio-infra namespace
├── Tenant: infra (SNSD, 50Gi)
│   ├── Bucket: actions-cache
│   ├── Bucket: longhorn-backups (future)
│   └── Bucket: velero (future)
└── Setup Job: Creates buckets on deploy
```

**Service endpoints:**
```
http://infra-hl.minio-infra.svc.cluster.local:9000
```

**Adding new buckets:**
1. Update setup job with new `mc mb` command
2. Create service credentials if isolation needed
3. Configure service to use new bucket

## When to Reconsider

**Split to dedicated tenants if:**
- Multi-node cluster with need for tenant placement control
- Compliance requires strict service isolation
- Single tenant performance becomes bottleneck
- Different durability requirements per service

**Move to external S3 if:**
- Disaster recovery requires geographic distribution
- Egress costs become acceptable
- Managed service reduces operational burden

## References

- ADR 0006: MinIO Operator Single-Drive Bootstrap
- ADR 0026: Forgejo Actions Ephemeral Runners
- [MinIO Multi-Tenancy](https://min.io/docs/minio/kubernetes/upstream/operations/concepts/multi-tenancy.html)
- [falcondev cache server](https://github.com/falcondev-oss/github-actions-cache-server)
