# 0033. Crossplane for External Infrastructure

**Status**: Accepted

**Date**: 2026-01-06

## Context

We need to manage external cloud resources (Cloudflare R2, Load Balancers, DNS) declaratively through GitOps. Currently, all infrastructure is Kubernetes-native and managed via ArgoCD, but external cloud resources require manual provisioning or separate tooling.

Requirements:
- Declarative management of external cloud resources
- GitOps workflow (same as Kubernetes resources)
- Continuous reconciliation (drift detection)
- Start with Cloudflare R2 for etcd backups, expand to other resources

First use case: R2 bucket for automated etcd backups (disaster recovery).

## Decision

**Use Crossplane with Terraform provider for external infrastructure, starting with R2 bucket for etcd backups.**

Components:
- **Crossplane v2.1.3**: Kubernetes-native infrastructure provisioning
- **Terraform provider v1.0.5**: Manages Cloudflare R2 (no native Crossplane provider)
- **CronJob**: Runs `etcdctl snapshot save` every 6 hours, uploads to R2

Why Crossplane over plain Terraform:
- Kubernetes-native (CRDs, ArgoCD syncs it)
- No separate state file to manage
- Continuous reconciliation (drift detection)
- Same GitOps workflow as everything else

Why Terraform provider (not native Cloudflare):
- No Crossplane Cloudflare provider supports R2 yet
- Terraform Cloudflare provider is mature and well-tested
- Can migrate to native provider when available

## Alternatives Considered

### 1. Plain Terraform (no Crossplane)
- **Pros**: Simpler, no operator overhead, familiar tooling
- **Cons**: Separate state management, needs CI pipeline for apply, not Kubernetes-native
- **Why not chosen**: Want everything in ArgoCD, continuous reconciliation

### 2. Velero with etcd plugin
- **Pros**: Battle-tested backup solution, handles restores too
- **Cons**: Another operator, more complex, overkill for just etcd
- **Why not chosen**: CronJob + R2 is simpler for our needs

### 3. Manual backups
- **Pros**: No infrastructure needed
- **Cons**: Human error, no automation, will be forgotten
- **Why not chosen**: Automation is essential for DR

### 4. etcd-backup-operator
- **Pros**: Purpose-built for etcd backups
- **Cons**: Another operator, less flexible storage options
- **Why not chosen**: CronJob approach is simpler and uses existing R2

## Consequences

### Positive
- ✅ Automated etcd backups every 6 hours
- ✅ Off-cluster storage (survives node failure)
- ✅ GitOps-managed (R2 bucket defined in Git)
- ✅ Foundation for more external resources (LB, DNS)
- ✅ 30-day retention with automatic cleanup

### Negative
- ⚠️ Crossplane operator overhead (~256MB RAM)
- ⚠️ Terraform provider adds complexity layer
- ⚠️ Two secrets to manage (Cloudflare API, R2 access keys)

### Neutral
- Can switch Terraform → OpenTofu later (same syntax, same state)
- Can add native Cloudflare provider when R2 support lands

## Implementation Notes

### Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Crossplane      │────▶│ Terraform        │────▶│ R2 Bucket       │
│ (operator)      │     │ Provider         │     │ etcd-backups    │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                         ▲
┌─────────────────┐                                      │
│ etcd-backup     │──────────────────────────────────────┘
│ CronJob (6h)    │  (uploads snapshots via aws-cli)
└─────────────────┘
```

### etcd Backup Details

- **Schedule**: Every 6 hours (`0 */6 * * *`)
- **Certificates**: Uses `healthcheck-client.crt/key` (clientAuth)
- **Retention**: 30 snapshots (~7.5 days at 6h intervals)
- **Upload**: aws-cli to R2 (S3-compatible)

### Recovery Process

```bash
# Download snapshot
aws s3 cp s3://etcd-backups/etcd-snapshot-YYYYMMDD-HHMMSS.db /tmp/snapshot.db \
  --endpoint-url=https://<account-id>.r2.cloudflarestorage.com

# Restore on new control plane
ETCDCTL_API=3 etcdctl snapshot restore /tmp/snapshot.db \
  --data-dir=/var/lib/etcd-restore
```

### Future Expansion

Crossplane can manage more Cloudflare resources:
- Load Balancers (native provider support exists)
- DNS records
- Tunnels
- Workers

## When to Reconsider

**Revisit if:**
1. Native Crossplane Cloudflare provider adds R2 support (drop Terraform provider)
2. Crossplane overhead becomes problematic (switch to plain Terraform)
3. Need more sophisticated backup/restore (consider Velero)
4. Managing 50+ external resources (evaluate dedicated IaC approach)

## References

- [Crossplane Documentation](https://docs.crossplane.io/latest/)
- [Crossplane Terraform Provider](https://github.com/crossplane-contrib/provider-terraform)
- [Cloudflare R2 Terraform](https://developers.cloudflare.com/r2/examples/terraform/)
- [etcd Disaster Recovery](https://etcd.io/docs/v3.5/op-guide/recovery/)
- PR #299: Implementation
