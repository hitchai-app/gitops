# Shared PostgreSQL Cluster

Shared PostgreSQL clusters managed by CloudNativePG operator for stage and production environments.

## Architecture

- **Operator**: CloudNativePG (cnpg-system namespace)
- **Clusters**: postgres-shared (stage and prod namespaces)
- **Storage**: Longhorn single-replica (CloudNativePG handles replication)
- **Backups**: S3 with 30-day retention, gzip compression

## Configuration

### Base Configuration

- **Instances**: 1 (single node initially, scale to 3 on multi-node)
- **PostgreSQL**: 17.2 (explicit version, no tags)
- **Storage**: 10Gi (stage), 50Gi (prod)
- **StorageClass**: longhorn-single-replica
- **Monitoring**: PodMonitor enabled

### Backup Strategy

- **Retention**: 30 days
- **Compression**: gzip (WAL and data)
- **Destination**: S3 bucket `cloudnativepg-backups`
  - Stage: `s3://cloudnativepg-backups/postgres-stage`
  - Prod: `s3://cloudnativepg-backups/postgres-prod`

## Required Manual Steps

### 1. Create S3 Backup Credentials

Before deploying, create SealedSecret for S3 credentials in each environment:

```bash
# Stage environment
kubectl create secret generic postgres-backup-s3-credentials \
  --namespace postgres-stage \
  --from-literal=ACCESS_KEY_ID=<your-access-key> \
  --from-literal=ACCESS_SECRET_KEY=<your-secret-key> \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > infrastructure/postgres/overlays/stage/backup-s3-credentials-sealed.yaml

# Production environment
kubectl create secret generic postgres-backup-s3-credentials \
  --namespace postgres-prod \
  --from-literal=ACCESS_KEY_ID=<your-access-key> \
  --from-literal=ACCESS_SECRET_KEY=<your-secret-key> \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > infrastructure/postgres/overlays/prod/backup-s3-credentials-sealed.yaml
```

Add sealed secrets to kustomization.yaml:
```yaml
resources:
  - ../../base
  - backup-s3-credentials-sealed.yaml
```

### 2. S3 Bucket Setup

Create S3 bucket with the following structure:
```
cloudnativepg-backups/
├── postgres-stage/
└── postgres-prod/
```

IAM permissions required:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::cloudnativepg-backups/*",
        "arn:aws:s3:::cloudnativepg-backups"
      ]
    }
  ]
}
```

## Verification

### Check Cluster Status

```bash
# Stage environment
kubectl get cluster -n postgres-stage
kubectl describe cluster postgres-shared -n postgres-stage

# Production environment
kubectl get cluster -n postgres-prod
kubectl describe cluster postgres-shared -n postgres-prod
```

### Check Backup Status

```bash
# View backup list
kubectl get backup -n postgres-stage
kubectl get backup -n postgres-prod

# Check scheduled backups
kubectl get scheduledbackup -n postgres-stage
kubectl get scheduledbackup -n postgres-prod
```

### Check Pods

```bash
# Stage
kubectl get pods -n postgres-stage
kubectl logs -n postgres-stage postgres-shared-1 -c postgres

# Production
kubectl get pods -n postgres-prod
kubectl logs -n postgres-prod postgres-shared-1 -c postgres
```

### Database Connection

```bash
# Get credentials (operator generates these)
kubectl get secret -n postgres-stage postgres-shared-app -o jsonpath='{.data.password}' | base64 -d

# Connect to database
kubectl exec -it -n postgres-stage postgres-shared-1 -- psql -U app -d app
```

## Database Management

CloudNativePG supports declarative database and user management. Products declare their database needs using Database CRDs:

```yaml
# Example: Product declares database in workloads/product-a/databases/
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: product-a-api-stage
  namespace: postgres-stage
spec:
  cluster:
    name: postgres-shared
  name: api_db
  owner: app
```

See ADR 0010 for full GitOps repository structure guidance.

## Scaling to Multi-Node

When adding second node, update base configuration:

```yaml
spec:
  instances: 3  # Change from 1 to 3
```

CloudNativePG will automatically:
- Create 2 additional replicas
- Configure streaming replication
- Enable automated failover
- Distribute replicas across nodes

## Disaster Recovery

### Point-in-Time Recovery (PITR)

Restore cluster to specific timestamp:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-restored
spec:
  instances: 1
  storage:
    size: 10Gi
  bootstrap:
    recovery:
      source: postgres-shared
      recoveryTarget:
        targetTime: "2025-10-06 12:00:00"
  externalClusters:
  - name: postgres-shared
    barmanObjectStore:
      destinationPath: s3://cloudnativepg-backups/postgres-stage
      s3Credentials:
        # Same credentials as original cluster
```

### Full Cluster Recovery

```bash
# 1. Delete failed cluster
kubectl delete cluster postgres-shared -n postgres-stage

# 2. Update cluster.yaml bootstrap section
spec:
  bootstrap:
    recovery:
      source: backup
  externalClusters:
  - name: backup
    barmanObjectStore:
      destinationPath: s3://cloudnativepg-backups/postgres-stage
      # ... S3 credentials

# 3. Apply configuration (ArgoCD will sync)
```

RTO: ~15-30 minutes (depends on database size)
RPO: Up to 5 minutes (archive_timeout setting)

## Monitoring

Prometheus metrics available via PodMonitor:
- `cnpg_pg_stat_database_*` - Database statistics
- `cnpg_pg_replication_*` - Replication lag
- `cnpg_backends_*` - Connection counts
- `cnpg_wal_*` - WAL statistics

Alert on:
- Replication lag > 10s
- Backup failures
- Disk usage > 80%
- Connection count approaching max_connections

## Troubleshooting

### Backup Failures

```bash
# Check backup logs
kubectl logs -n postgres-stage postgres-shared-1 -c postgres | grep barman

# Test S3 connectivity
kubectl exec -it -n postgres-stage postgres-shared-1 -- barman-cloud-backup-list s3://cloudnativepg-backups/postgres-stage
```

### Replication Issues

```bash
# Check replication status
kubectl exec -it -n postgres-stage postgres-shared-1 -- psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

### Storage Issues

```bash
# Check PVC status
kubectl get pvc -n postgres-stage
kubectl describe pvc postgres-shared-1 -n postgres-stage

# Check Longhorn volume
kubectl get volume -n longhorn-system
```

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/current/)
- [ADR 0004: CloudNativePG for PostgreSQL](../../adr/0004-cloudnativepg-for-postgresql.md)
- [ADR 0007: Longhorn StorageClass Strategy](../../adr/0007-longhorn-storageclass-strategy.md)
- [ADR 0010: GitOps Repository Structure](../../adr/0010-gitops-repository-structure.md)
