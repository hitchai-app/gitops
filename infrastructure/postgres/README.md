# PostgreSQL with CloudNativePG

This component provisions a shared PostgreSQL cluster using the CloudNativePG operator. It is intended for production workloads and runs in the `postgres-prod` namespace.

## What ships here

- CloudNativePG operator (deployed cluster-wide via ArgoCD)
- A single `postgres-shared` cluster (PostgreSQL 17.2)
- Continuous WAL/data backups to S3 with 30-day retention (Barman)
- Prometheus PodMonitor for metrics scraping

## Manual prerequisites

1. **Create an S3 bucket** – for example `cloudnativepg-backups`.
2. **Provision IAM credentials** with `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`, and `s3:ListBucket` permissions on that bucket.
3. **Seal the credentials** for ArgoCD:

   ```bash
   kubectl create secret generic backup-s3-credentials \
     --from-literal=ACCESS_KEY_ID=<access-key> \
     --from-literal=ACCESS_SECRET_KEY=<secret-key> \
     --namespace=postgres-prod \
     --dry-run=client -o yaml > /tmp/backup-s3-credentials.yaml

   kubeseal --format=yaml \
     < /tmp/backup-s3-credentials.yaml \
     > infrastructure/postgres/overlays/prod/backup-s3-credentials-sealed.yaml

   rm /tmp/backup-s3-credentials.yaml
   ```

4. **Add the sealed secret to Kustomize** – uncomment the line in
   `infrastructure/postgres/overlays/prod/kustomization.yaml` that references
   `backup-s3-credentials-sealed.yaml`, then commit it.

Once the credentials are sealed and committed, ArgoCD will be able to sync the cluster successfully.

## Storage & backups

- StorageClass: `longhorn-single-replica`
- PVC size: 50 GiB
- Backups: gzip-compressed WAL and base backups to `s3://cloudnativepg-backups/postgres-prod`
- Retention: 30 days
- Point-in-time recovery supported via Barman

## Related ADRs

- [ADR 0004](../../adr/0004-cloudnativepg-for-postgresql.md) – operator rationale
- [ADR 0007](../../adr/0007-longhorn-storageclass-strategy.md) – Longhorn usage
- [ADR 0009](../../adr/0009-secrets-management-strategy.md) – handling secrets
