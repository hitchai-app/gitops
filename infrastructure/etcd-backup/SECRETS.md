# etcd Backup R2 Credentials

## Required Secret: etcd-backup-r2-credentials

Create R2 API token for the etcd-backups bucket:
1. Wait for Crossplane to create the `etcd-backups` bucket
2. Cloudflare Dashboard → R2 → Manage R2 API Tokens
3. Create API Token
4. Permissions: Object Read & Write
5. Specify bucket: etcd-backups

## Create the Secret

```bash
.tmp/seal-etcd-backup-credentials.sh
```

Or manually:
```bash
kubectl create secret generic etcd-backup-r2-credentials \
  --namespace=kube-system \
  --from-literal=access-key-id="YOUR_ACCESS_KEY_ID" \
  --from-literal=secret-access-key="YOUR_SECRET_ACCESS_KEY" \
  --dry-run=client -o yaml | \
  kubeseal --cert .sealed-secrets-pub.pem --format yaml \
  > infrastructure/etcd-backup/r2-credentials-sealed.yaml
```

Note: R2 endpoint is hardcoded in cronjob.yaml (not sensitive).

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

```bash
# Download snapshot
aws s3 cp s3://etcd-backups/etcd-snapshot-YYYYMMDD-HHMMSS.db /tmp/snapshot.db \
  --endpoint-url=https://7c6222bba0337fbbad7876ad40c9ef59.r2.cloudflarestorage.com

# Restore (on new/rebuilt control plane)
ETCDCTL_API=3 etcdctl snapshot restore /tmp/snapshot.db \
  --data-dir=/var/lib/etcd-restore
```
