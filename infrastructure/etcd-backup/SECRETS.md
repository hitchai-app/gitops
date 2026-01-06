# etcd Backup R2 Credentials

## Required Secret: etcd-backup-r2-credentials

Create R2 API token for the etcd-backups bucket:
1. Cloudflare Dashboard → R2 → Manage R2 API Tokens
2. Create API Token
3. Permissions: Object Read & Write
4. Specify bucket: etcd-backups (after Crossplane creates it)

## Create the Secret

```bash
# Get from Cloudflare R2 API Tokens page
R2_ACCESS_KEY_ID="your-access-key-id"
R2_SECRET_ACCESS_KEY="your-secret-access-key"
# Format: https://<account-id>.r2.cloudflarestorage.com
R2_ENDPOINT="https://your-account-id.r2.cloudflarestorage.com"

# Create and seal the secret
kubectl create secret generic etcd-backup-r2-credentials \
  --namespace=kube-system \
  --from-literal=access-key-id="${R2_ACCESS_KEY_ID}" \
  --from-literal=secret-access-key="${R2_SECRET_ACCESS_KEY}" \
  --from-literal=endpoint-url="${R2_ENDPOINT}" \
  --dry-run=client -o yaml | \
  kubeseal --cert .sealed-secrets-pub.pem --format yaml \
  > infrastructure/etcd-backup/r2-credentials-sealed.yaml

# Clean up (unset variables)
unset R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_ENDPOINT
```

## Verify

After ArgoCD syncs:
```bash
# Check secret exists
kubectl get secret etcd-backup-r2-credentials -n kube-system

# Trigger manual backup to test
kubectl create job --from=cronjob/etcd-backup etcd-backup-manual -n kube-system

# Check logs
kubectl logs -n kube-system -l job-name=etcd-backup-manual -f
```

## Recovery

To restore from backup:
```bash
# Download snapshot
aws s3 cp s3://etcd-backups/etcd-snapshot-YYYYMMDD-HHMMSS.db /tmp/snapshot.db \
  --endpoint-url=https://your-account-id.r2.cloudflarestorage.com

# Restore (on new/rebuilt control plane)
ETCDCTL_API=3 etcdctl snapshot restore /tmp/snapshot.db \
  --data-dir=/var/lib/etcd-restore
```
