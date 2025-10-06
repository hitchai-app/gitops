# Longhorn Distributed Storage

Longhorn provides distributed block storage for Kubernetes with S3 backup capabilities.

## StorageClasses

Three StorageClasses for different use cases:

### `single-replica` (1 replica, Retain)
**Use for apps with built-in replication:**
- CloudNativePG PostgreSQL (3 DB replicas)
- MinIO distributed (erasure coding EC:2)
- Any stateful app with built-in HA

**Why:** Avoids double replication overhead - app handles redundancy.

### `replicated` (3 replicas, Retain, default)
**Use for apps without replication:**
- Redis (single instance)
- Single-instance databases
- General stateful workloads

**Why:** Longhorn provides redundancy across nodes.

### `ephemeral` (1 replica, Delete)
**Use for non-critical data:**
- Temporary files
- Build caches
- Testing/development workloads

**Why:** Automatic cleanup on PVC deletion - prevents orphaned volumes.

**Note:** On single node, replica counts behave identically (only 1 node available).

## S3 Backup Configuration (Optional)

**WARNING:** Do NOT use MinIO for Longhorn backups (circular dependency). Use external S3 provider.

### Setup Steps

1. **Create SealedSecret** with S3 credentials:
   ```bash
   kubectl create secret generic longhorn-backup-secret \
     --from-literal=AWS_ACCESS_KEY_ID=xxx \
     --from-literal=AWS_SECRET_ACCESS_KEY=xxx \
     --from-literal=AWS_ENDPOINTS=https://s3.amazonaws.com \
     --namespace=longhorn-system --dry-run=client -o yaml | \
     kubeseal --format=yaml > infrastructure/longhorn/backup-secret-sealed.yaml
   ```

2. **Update Longhorn config** in `apps/infrastructure/longhorn-operator.yaml`:
   ```yaml
   backupTarget: "s3://bucket-name@region/"
   backupTargetCredentialSecret: "longhorn-backup-secret"
   ```

3. **Commit and push** - ArgoCD syncs automatically.

See [Longhorn Backup Docs](https://longhorn.io/docs/latest/snapshots-and-backups/backup-and-restore/set-backup-target/) for details.

## Multi-Node Scaling

When adding nodes, Longhorn automatically distributes replicas. No configuration changes needed.

## Access Longhorn UI

```bash
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80
```

Open http://localhost:8080

## References

- ADR 0002: Longhorn Storage from Day One
- ADR 0007: Longhorn StorageClass Strategy
- [Longhorn Documentation](https://longhorn.io/docs/)
