# 0044. Backup and Recovery Strategy

**Status**: Accepted

**Date**: 2026-02-03

## Context

After an incident where a PR preview PostgreSQL cluster became unrecoverable due to cascading infrastructure failures, we need clear guidelines for:

1. When to configure backups and what type
2. Where backups should be stored (internal vs external)
3. Retention policies and cost implications
4. Recovery procedures for various failure scenarios

**Key insight:** Internal backups (to MinIO on the same cluster) don't protect against cluster-wide failures. External backups are required for disaster recovery.

## Decision

### Backup Destination

**All production backups go to Backblaze B2** (external S3-compatible storage):
- Survives cluster failure
- No egress fees for downloads under 3x storage
- $0.006/GB/month (3x cheaper than alternatives)
- Provisioned via Crossplane

**Internal MinIO is runtime storage, NOT a backup target.**

### Backup Strategy by Workload Type

| Workload Type | External Backup | Method | Retention | RPO |
|---------------|-----------------|--------|-----------|-----|
| **Production DB** (sentry, green-prod, fire-prod) | ✅ Required | CNPG WAL + weekly base | 7d WAL, 4 base | ~5 min |
| **Critical non-DB** (gitlab-gitaly) | ✅ Required | Longhorn weekly | 4 weekly | ~1 week |
| **Infrastructure DB** (gitlab, glitchtip, standalock) | ✅ Required | CNPG weekly base | 4 weekly | ~1 week |
| **Staging DB** | ❌ Optional | - | - | Accept loss |
| **PR Preview** | ❌ No | - | - | Recreate |
| **Metrics/Logs** (prometheus, loki) | ❌ No | - | - | Start fresh |
| **Caches/Queues** (valkey, kafka) | ❌ No | - | - | Ephemeral |

### Storage and Cost Estimate

| Backup Type | Data Size | Retention | Est. Storage |
|-------------|-----------|-----------|--------------|
| CNPG WAL (prod DBs) | ~1GB/day | 7 days | ~7GB |
| CNPG base backups | ~80GB total | 4 copies | ~320GB |
| Longhorn snapshots (gitaly) | 50GB | 4 copies | ~200GB |
| **Total** | | | **~530GB** |

**Estimated B2 cost:** ~$3/month (530GB × $0.006)

### HA Replication (Complements Backup)

In-cluster replication for fast failover (NOT a replacement for external backup):

| Service | Replicas | Purpose |
|---------|----------|---------|
| sentry-postgres | 2+ | HA, fast failover |
| green-prod postgres | 2 | HA, fast failover |
| fire-prod postgres | 2 | HA, fast failover |
| Longhorn volumes | 2 replicas | Node failure survival |

## Backup Methods

### 1. CNPG WAL Archiving (Minutes RPO)

Continuous shipping of Write-Ahead Logs to B2. Enables point-in-time recovery.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
spec:
  backup:
    barmanObjectStore:
      destinationPath: s3://cnpg-backups/cluster-name
      endpointURL: https://s3.us-west-002.backblazeb2.com
      s3Credentials:
        accessKeyId:
          name: cnpg-backup-b2-credentials
          key: AWS_ACCESS_KEY_ID
        secretAccessKey:
          name: cnpg-backup-b2-credentials
          key: AWS_SECRET_ACCESS_KEY
      wal:
        compression: gzip
    retentionPolicy: "7d"
```

**Use for:** Production databases requiring point-in-time recovery.

### 2. CNPG Scheduled Base Backups (Weekly RPO)

Full database snapshots for faster recovery.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: cluster-weekly-backup
spec:
  schedule: "0 3 * * 0"  # Sunday 3 AM
  cluster:
    name: cluster-name
  backupOwnerReference: cluster
```

**Use for:** Infrastructure databases where weekly RPO is acceptable.

### 3. Longhorn Volume Backups (Weekly)

Storage-level snapshots of entire volumes to B2.

```yaml
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: backup-weekly
spec:
  cron: "0 3 * * 0"
  task: backup
  retain: 4
  groups:
    - default
```

**Use for:** Non-database critical data (git repositories).

### 4. On-Demand Backups

Manual backups before/after significant changes.

```bash
# CNPG on-demand backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: manual-$(date +%Y%m%d)
spec:
  cluster:
    name: <cluster-name>
EOF
```

**Use for:** Before config changes, after new service setup.

## Recovery Procedures

### Scenario 1: Pod Crash (PVC Healthy)

```bash
# 1. Verify data exists
kubectl run debug --rm -it --image=busybox \
  --overrides='...' -n <namespace>
ls -la /data/pgdata/

# 2. Delete pod, let operator recreate
kubectl delete pod -n <namespace> <pod-name>
```

### Scenario 2: PVC Data Lost (Backup Restore)

**CNPG Database:**
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
spec:
  bootstrap:
    recovery:
      source: cluster-backup
      recoveryTarget:
        targetTime: "2026-02-03 04:30:00+00"  # Optional PITR
  externalClusters:
    - name: cluster-backup
      barmanObjectStore:
        destinationPath: s3://cnpg-backups/cluster-name
        endpointURL: https://s3.us-west-002.backblazeb2.com
        # ... credentials
```

**Longhorn Volume:**
```bash
# Restore from B2 backup
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restored-pvc
spec:
  dataSource:
    name: <backup-name>
    kind: Backup
    apiGroup: longhorn.io
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 50Gi
EOF
```

### Pre-Recovery Checklist

1. **Verify backup exists and is recent**
2. **Check if data still exists on volume** (mount debug pod)
3. **Determine acceptable data loss** (production vs ephemeral)

## Implementation Phases

### Phase 1: External Backup Foundation
- Crossplane provisions B2 bucket for Longhorn
- Longhorn configured to backup to B2
- Weekly recurring backup job

### Phase 2: CNPG WAL Archiving
- B2 bucket for CNPG
- Production clusters with WAL archiving
- Scheduled base backups

### Phase 3: HA Replication
- Increase CNPG replicas for production
- Verify Longhorn replica count

## Consequences

### Positive
- External backups survive cluster failure
- Clear decision matrix reduces confusion
- Cost-effective (~$3/month with B2)

### Negative
- B2 dependency for disaster recovery
- Recovery procedures need regular testing

## References

- [Longhorn Backup to S3](https://longhorn.io/docs/1.7.2/snapshots-and-backups/backup-and-restore/set-backup-target/)
- [CloudNativePG Backup](https://cloudnative-pg.io/documentation/current/backup/)
- [Backblaze B2 S3 Compatibility](https://www.backblaze.com/docs/cloud-storage-s3-compatible-api)
- ADR 0004: CloudNativePG for PostgreSQL
