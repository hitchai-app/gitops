# 0028. Crossplane for External Infrastructure

**Status**: Accepted

**Date**: 2025-12-11

**Updated**: 2026-01-08

## Context

Need for external cloud resources (R2 backups, AWS S3, DNS). Current GitOps approach doesn't cover external provisioning, leading to split tooling (ArgoCD + Terraform/manual).

## Decision

Adopt Crossplane with provider-terraform for external infrastructure, keeping everything in GitOps.

### Provider Choice: provider-terraform

Use `provider-terraform` (Upbound) instead of native Cloudflare provider:
- Leverages existing Terraform modules and providers
- Better documentation and community support
- `cloudflare_api_token` resource for programmatic R2 credentials

### Auto-Provisioning Secrets

**Key pattern**: Use `writeConnectionSecretToRef` to automatically create Kubernetes secrets from Terraform outputs.

```yaml
apiVersion: tf.upbound.io/v1beta1
kind: Workspace
metadata:
  name: r2-etcd-backups
spec:
  # Terraform outputs automatically become secret data
  writeConnectionSecretToRef:
    namespace: kube-system
    name: etcd-backup-r2-credentials

  forProvider:
    source: Inline
    module: |
      # Create R2 bucket
      resource "cloudflare_r2_bucket" "backups" { ... }

      # Create scoped API token
      resource "cloudflare_api_token" "backup" { ... }

      # Outputs become secret keys
      output "access-key-id" {
        value     = cloudflare_api_token.backup.id
        sensitive = true
      }
      output "secret-access-key" {
        value     = sha256(cloudflare_api_token.backup.value)
        sensitive = true
      }
```

This eliminates manual secret sealing - Crossplane handles the entire flow:
1. Creates external resource (R2 bucket)
2. Creates credentials (API token)
3. Provisions Kubernetes secret automatically

### R2 S3-Compatible Credentials

Cloudflare R2 uses derived S3 credentials:
- **Access Key ID** = API token ID
- **Secret Access Key** = SHA-256 hash of API token value

The `cloudflare_api_token` resource can be scoped to specific buckets:
```hcl
data "cloudflare_api_token_permission_groups" "all" {}

resource "cloudflare_api_token" "backup" {
  name = "etcd-backup-r2"
  policies = [{
    permission_groups = [
      { id = data.cloudflare_api_token_permission_groups.all.r2["Workers R2 Storage Bucket Item Write"] }
    ]
    resources = {
      "com.cloudflare.edge.r2.bucket.${account_id}_default_${bucket_name}" = "*"
    }
  }]
}
```

## Alternatives Considered

### Terraform (standalone)
Rejected: State file management, no continuous reconciliation, breaks GitOps model.

### Manual Provisioning + Sealed Secrets
Rejected: Requires manual steps after resource creation.

### Crossplane Kubernetes Provider for Secrets
Considered: Would require additional provider and RBAC. `writeConnectionSecretToRef` is native to provider-terraform.

### Cloud-Specific Operators (ACK, etc.)
Rejected: Different operator per cloud, inconsistent APIs.

## Scope Boundaries

| Resource Type | Tool |
|---------------|------|
| K8s workloads/operators | ArgoCD |
| Internal storage (MinIO) | ArgoCD + Operator |
| External storage (R2/S3) | ArgoCD + Crossplane |
| External credentials | Crossplane (auto-provisioned) |
| K8s cluster itself | Terraform (bootstrap) |

## Consequences

**Positive:**
- Unified GitOps (all infra in Git)
- Continuous reconciliation
- No state file concerns (managed by Crossplane)
- Zero manual steps for credentials
- Scoped permissions (principle of least privilege)

**Negative:**
- Another operator to maintain
- Terraform state stored in K8s secrets
- Provider-terraform timeout limits (20m default)

## Implementation Notes

- Crossplane credentials (master token) sealed via ADR 0009
- Child tokens created automatically with minimal scope
- Use `data.cloudflare_api_token_permission_groups` to look up permission IDs dynamically

## References

- [Crossplane Docs](https://docs.crossplane.io/)
- [provider-terraform](https://github.com/crossplane-contrib/provider-terraform)
- [Cloudflare R2 API Tokens](https://developers.cloudflare.com/r2/api/tokens/)
- ADR 0009: Secrets Management Strategy
- ADR 0027: Shared MinIO Tenant
