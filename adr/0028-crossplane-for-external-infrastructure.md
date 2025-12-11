# 0028. Crossplane for External Infrastructure

**Status**: Proposed

**Date**: 2025-12-11

## Context

Future need for external cloud resources (R2 backups, AWS S3, DNS). Current GitOps approach doesn't cover external provisioning, leading to split tooling (ArgoCD + Terraform/manual).

## Decision

**Proposed**: Adopt Crossplane for external infrastructure, keeping everything in GitOps.

Crossplane provisions cloud resources via K8s CRDs:
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

### Terraform
Rejected: State file management, no continuous reconciliation, breaks GitOps model.

### Manual Provisioning
Rejected: Not reproducible, no audit trail.

### Cloud-Specific Operators (ACK, etc.)
Rejected: Different operator per cloud, inconsistent APIs.

## Scope Boundaries

| Resource Type | Tool |
|---------------|------|
| K8s workloads/operators | ArgoCD |
| Internal storage (MinIO) | ArgoCD + Operator |
| External storage (R2/S3) | ArgoCD + Crossplane |
| K8s cluster itself | Terraform (bootstrap) |

## Consequences

**Positive:**
- Unified GitOps (all infra in Git)
- Continuous reconciliation
- No state file

**Negative:**
- Another operator
- Provider maturity varies

## When to Implement

**Trigger**: First external cloud resource needed (R2 backup bucket).

## References

- [Crossplane Docs](https://docs.crossplane.io/)
- [Upbound Providers](https://marketplace.upbound.io/providers)
- ADR 0027: Shared MinIO Tenant
