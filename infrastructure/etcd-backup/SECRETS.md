# etcd Backup R2 Credentials

## Required: etcd-backup-r2-credentials

After Crossplane creates the bucket, create R2 API token:

1. Cloudflare Dashboard → R2 → Manage R2 API Tokens
2. Create API Token → Object Read & Write → Bucket: etcd-backups

```bash
kubectl create secret generic etcd-backup-r2-credentials \
  --namespace=kube-system \
  --from-literal=access-key-id="ACCESS_KEY" \
  --from-literal=secret-access-key="SECRET_KEY" \
  --dry-run=client -o yaml | \
  kubeseal --cert .sealed-secrets-pub.pem --format yaml \
  > infrastructure/etcd-backup/r2-credentials-sealed.yaml
```

## Test

```bash
kubectl create job --from=cronjob/etcd-backup etcd-backup-test -n kube-system
kubectl logs -n kube-system -l job-name=etcd-backup-test -f
```
