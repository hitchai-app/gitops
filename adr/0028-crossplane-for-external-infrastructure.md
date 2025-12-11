# 0028. Crossplane for External Infrastructure

**Status**: Proposed

**Date**: 2025-12-11

## Context

As infrastructure grows, we need to provision external cloud resources:
- Cloudflare R2 buckets for off-site backups
- AWS S3 for Longhorn backup targets
- DNS records
- External databases (if needed)

Current approach uses different tools for different scopes:
- ArgoCD/GitOps for in-cluster resources (MinIO, CNPG, operators)
- Manual or Terraform for external cloud resources

This creates split mental models and inconsistent provisioning patterns.

## Decision

**Proposed**: Adopt Crossplane for external infrastructure provisioning, keeping everything within GitOps paradigm.

Crossplane allows provisioning cloud resources via Kubernetes CRDs:
```yaml
apiVersion: s3.aws.upbound.io/v1beta1
kind: Bucket
metadata:
  name: longhorn-backups
spec:
  forProvider:
    region: eu-central-1
```

## Alternatives Considered

### 1. Terraform for External Resources
- **Pros**: Mature, wide provider coverage, well-documented
- **Cons**:
  - State file management
  - One-shot apply (no continuous reconciliation)
  - Different paradigm from GitOps
  - Two tools, two workflows
- **Why not preferred**: Breaks GitOps model, adds operational complexity

### 2. Manual Provisioning
- **Pros**: Simple, no tooling
- **Cons**: Not reproducible, no audit trail, drift undetected
- **Why not preferred**: Unacceptable for production infrastructure

### 3. Cloud-Specific Operators
- **Pros**: Native integration (AWS Controllers for K8s, etc.)
- **Cons**: Different operator per cloud, inconsistent APIs
- **Why not preferred**: Fragmented approach

### 4. Crossplane (Proposed)
- **Pros**:
  - Pure GitOps (declarative YAML, ArgoCD manages)
  - Continuous reconciliation (drift correction)
  - No state file (uses K8s etcd)
  - Unified model for all clouds
  - CNCF incubating project
- **Cons**:
  - Another operator to manage
  - Provider maturity varies
  - Learning curve for Compositions

## Architecture

```
gitops/
├── infrastructure/
│   ├── crossplane/
│   │   ├── controller/           # Crossplane operator
│   │   └── providers/
│   │       ├── cloudflare.yaml   # Provider + ProviderConfig
│   │       └── aws.yaml
│   │
│   ├── external-storage/         # External buckets
│   │   ├── r2-backups.yaml       # Cloudflare R2
│   │   └── s3-longhorn.yaml      # AWS S3
│   │
│   ├── minio-infra/              # Internal storage (unchanged)
│   └── forgejo-runner/
│       └── minio-bucket.yaml     # Internal bucket
```

**Flow:**
```
Git → ArgoCD → Crossplane CRD → Crossplane Controller → Cloud API
                                        ↓
                            Actual cloud resource created
                            Continuous reconciliation
```

## Scope Boundaries

| Resource Type | Tool | Rationale |
|---------------|------|-----------|
| K8s workloads | ArgoCD | Native |
| K8s operators/CRDs | ArgoCD | Native |
| Internal storage (MinIO) | ArgoCD + Operator | In-cluster |
| External storage (R2/S3) | ArgoCD + Crossplane | GitOps for cloud |
| DNS records | ArgoCD + Crossplane | GitOps for cloud |
| K8s cluster itself | Terraform | Bootstrap (chicken-egg) |

**Exception**: The Kubernetes cluster itself remains Terraform-managed (can't use K8s to create K8s).

## Implementation Plan

### Phase 1: Crossplane Foundation
1. Deploy Crossplane operator
2. Install Cloudflare provider
3. Configure ProviderConfig with credentials (sealed secret)

### Phase 2: R2 Backup Buckets
1. Create R2 bucket for Longhorn backups
2. Configure Longhorn to use R2 target
3. Validate backup/restore

### Phase 3: Expand Coverage
1. AWS provider (if needed)
2. DNS management
3. Other external resources

## Consequences

### Positive
- **Unified GitOps**: All infrastructure in Git, managed by ArgoCD
- **Continuous reconciliation**: Drift automatically corrected
- **No state file**: Eliminates Terraform state management
- **Consistent patterns**: Same YAML/CRD approach for internal and external
- **Audit trail**: Git history for all changes

### Negative
- **Another operator**: Crossplane controller adds complexity
- **Provider maturity**: Some providers less mature than Terraform
- **Credential management**: Cloud credentials in cluster
- **Learning curve**: Compositions and XRDs for advanced use

### Neutral
- **Migration effort**: Existing Terraform (if any) needs migration
- **Debugging**: Different debugging model than Terraform

## Prerequisites

Before adopting:
1. Evaluate Cloudflare provider maturity for R2
2. Assess credential management approach
3. Test backup/restore workflow with Crossplane-provisioned bucket
4. Document disaster recovery (Crossplane itself needs recovery)

## When to Implement

**Trigger**: When we need to provision first external cloud resource (R2 backup bucket).

**Not needed if**: All storage remains internal (MinIO only).

## References

- [Crossplane Documentation](https://docs.crossplane.io/)
- [Crossplane Providers](https://marketplace.upbound.io/providers)
- [Cloudflare Provider](https://marketplace.upbound.io/providers/upbound/provider-cloudflare)
- [AWS Provider](https://marketplace.upbound.io/providers/upbound/provider-aws)
- [CNCF Crossplane](https://www.cncf.io/projects/crossplane/)
- ADR 0027: Shared MinIO Tenant for Infrastructure
