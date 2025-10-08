# CloudNativePG production cluster

This directory contains the manifests for the production PostgreSQL cluster managed by the CloudNativePG operator.

## Manual steps before ArgoCD sync

1. Create an S3 bucket (e.g. `cloudnativepg-backups`) and IAM credentials with `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`, and `s3:ListBucket` permissions.
2. Seal the credentials for the `postgres-prod` namespace:
   ```bash
   kubectl create secret generic backup-s3-credentials \
     --from-literal=ACCESS_KEY_ID=<access> \
     --from-literal=ACCESS_SECRET_KEY=<secret> \
     --namespace=postgres-prod \
     --dry-run=client -o yaml > /tmp/backup-s3-credentials.yaml

   kubeseal --format=yaml \
     < /tmp/backup-s3-credentials.yaml \
     > infrastructure/postgres/backup-s3-credentials-sealed.yaml

   rm /tmp/backup-s3-credentials.yaml
   ```
3. Commit the sealed secret alongside `cluster.yaml` so ArgoCD can apply both. An
   example template (`backup-s3-credentials-sealed.yaml.example`) is included
   for reference.

## What gets deployed

- Single instance PostgreSQL 17.2 (`postgres-prod` in namespace `postgres-prod`).
- Longhorn-backed 50 GiB volume (`longhorn-single-replica`).
- Continuous WAL/base backups to `s3://cloudnativepg-backups/postgres-prod` with gzip compression and 30‑day retention.
- PodMonitor for Prometheus.

## Verification cheatsheet

```bash
kubectl get pods -n cnpg-system
kubectl get cluster postgres-prod -n postgres-prod
kubectl get pods -n postgres-prod
kubectl get pvc -n postgres-prod
kubectl get podmonitor -n postgres-prod
```

After the first backup completes, `kubectl get cluster postgres-prod -n postgres-prod -o jsonpath='{.status.firstRecoverabilityPoint}'` should print a timestamp. Check the S3 bucket to confirm WAL/base backups are written.
