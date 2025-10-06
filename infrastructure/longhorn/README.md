# Longhorn Distributed Storage

Longhorn provides distributed block storage for Kubernetes with S3 backup capabilities.

## Components

- **Longhorn Operator**: Deployed via Helm chart (managed by ArgoCD)
- **StorageClasses**: Two classes for different replication strategies
  - `longhorn-single-replica`: For apps with built-in replication (PostgreSQL, MinIO)
  - `longhorn-replicated`: For apps without replication (Redis, general workloads)

## Configuration

### Current State: Single Node
- Replica count: 1 (only one node available)
- Both StorageClasses behave identically on single node
- S3 backups: Not yet configured (manual step required)

### S3 Backup Configuration (Optional)

**WARNING: Do NOT configure S3 backup to MinIO cluster - creates circular dependency**
Use external S3 provider (AWS S3, Backblaze B2, etc.) for backups.

#### Step 1: Create Backup Credentials Secret

Create a SealedSecret for S3 credentials:

```bash
# Create plain secret (do NOT commit this)
kubectl create secret generic longhorn-backup-secret \
  --from-literal=AWS_ACCESS_KEY_ID=your-access-key \
  --from-literal=AWS_SECRET_ACCESS_KEY=your-secret-key \
  --from-literal=AWS_ENDPOINTS=https://s3.amazonaws.com \
  --namespace=longhorn-system \
  --dry-run=client -o yaml > /tmp/backup-secret.yaml

# Seal the secret
kubeseal --format=yaml < /tmp/backup-secret.yaml > infrastructure/longhorn/backup-secret-sealed.yaml

# Clean up plain secret
rm /tmp/backup-secret.yaml

# Commit sealed secret to Git
git add infrastructure/longhorn/backup-secret-sealed.yaml
git commit -m "feat(longhorn): add S3 backup credentials"
```

#### Step 2: Update Longhorn Configuration

Edit `apps/infrastructure/longhorn.yaml`:

```yaml
helm:
  valuesObject:
    defaultSettings:
      backupTarget: "s3://your-bucket-name@us-east-1/"
      backupTargetCredentialSecret: "longhorn-backup-secret"
```

Commit and push - ArgoCD will sync automatically.

#### Step 3: Verify Backup Configuration

```bash
# Check Longhorn settings
kubectl -n longhorn-system get settings.longhorn.io backup-target -o yaml

# Test backup manually via Longhorn UI
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80
# Open http://localhost:8080 and test backup
```

## StorageClass Selection Guide

### Use `longhorn-single-replica` for:
- CloudNativePG PostgreSQL (3 DB replicas)
- MinIO distributed (erasure coding EC:2)
- Any stateful app with built-in HA

**Why:** Avoids double replication (app handles redundancy)

### Use `longhorn-replicated` for:
- Redis (single instance, no replication)
- Single-instance databases
- General stateful workloads (safe default)

**Why:** Longhorn provides redundancy (3 replicas across nodes)

## Multi-Node Scaling

When adding second node, Longhorn automatically:
- Distributes replicas across nodes
- `longhorn-replicated` StorageClass creates 3 replicas
- `longhorn-single-replica` remains at 1 replica

No configuration changes needed - just add nodes to cluster.

## Monitoring

Longhorn exposes Prometheus metrics automatically:

```bash
# Check metrics endpoint
kubectl -n longhorn-system get svc longhorn-backend -o yaml
```

Add ServiceMonitor for Prometheus scraping (future task).

## Disaster Recovery

### Backup Strategy
1. **S3 backups**: Automated snapshots to external S3 (configured above)
2. **Snapshot retention**: 30 days (configurable in Longhorn settings)
3. **PITR**: Point-in-time recovery from S3 snapshots

### Recovery Procedure
1. Deploy Longhorn via ArgoCD (this manifest)
2. Restore backup credentials secret
3. Configure backup target (same S3 location)
4. Restore volumes via Longhorn UI or kubectl

## Troubleshooting

### Check Longhorn System Health
```bash
kubectl -n longhorn-system get pods
kubectl -n longhorn-system get daemonsets
```

### View Longhorn UI
```bash
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80
# Open http://localhost:8080
```

### Check StorageClass Status
```bash
kubectl get storageclass
kubectl describe storageclass longhorn-single-replica
kubectl describe storageclass longhorn-replicated
```

### Volume Issues
```bash
# List all Longhorn volumes
kubectl -n longhorn-system get volumes.longhorn.io

# Check specific volume
kubectl -n longhorn-system describe volume.longhorn.io <volume-name>
```

## References

- ADR 0002: Longhorn Storage from Day One
- ADR 0007: Longhorn StorageClass Strategy
- [Longhorn Documentation](https://longhorn.io/docs/)
- [Longhorn Backup Configuration](https://longhorn.io/docs/latest/snapshots-and-backups/backup-and-restore/set-backup-target/)
