# 0002. Longhorn Storage from Day One

**Status**: Accepted

**Date**: 2025-10-05

## Context

We need persistent storage for our Kubernetes cluster that will start on a single Hetzner node (280GB SSD) but scale to multiple nodes in the future. The cluster hosts stateful services (PostgreSQL, Redis, MinIO) and requires reliable storage with backup capabilities.

Key requirements:
- Persistent volumes for stateful workloads
- Backup to S3 (cost-effective off-site backups)
- Future scalability to multi-node with replication
- Avoid painful migration when scaling

Current setup:
- Single Hetzner node: 12 CPU / 128GB RAM / 280GB SSD
- Will add nodes as customer base grows
- Target availability: 99% (two nines)

## Decision

We will deploy **Longhorn distributed storage from day one**, even on a single node.

Configuration:
- Replica count: 1 (single node, no replication yet)
- S3 backups: Automated snapshots to AWS S3
- When adding node 2: Increase replica count to 2-3
- Snapshot retention: 30 days

## Alternatives Considered

### 1. local-path-provisioner (then migrate to Longhorn later)
- **Pros**:
  - Simpler on single node
  - Lower resource overhead
  - Minimal complexity
  - No distributed storage overhead
- **Cons**:
  - **Migration requires 1-2 days downtime** (major blocker)
    - Must create new PVCs with Longhorn storage class
    - Copy data via migration pod (hours for large DBs)
    - Update StatefulSet manifests
    - Test and verify
  - Migration happens when scaling (under pressure)
  - No built-in S3 backup (must build CronJob solution)
  - Tied to single node (if node fails, data doesn't follow pod)

### 2. Cloud provider storage (Hetzner volumes)
- **Pros**:
  - Managed by provider
  - Simple integration
  - Reliable backups
- **Cons**:
  - Vendor lock-in
  - Additional cost per GB
  - Less control over replication strategy
  - Not portable to other providers

## Consequences

### Positive
- **No migration downtime**: When adding nodes, just increase replica count (Longhorn handles data distribution)
- **S3 backups built-in**: Automated snapshots to S3, no custom CronJob scripts
- **Snapshot functionality**: Point-in-time volume snapshots ready from day one
- **Multi-node ready**: Architecture supports scaling without redesign
- **Disaster recovery**: Can restore volumes from S3 if node dies
- **Portability**: Can move to different cloud providers without storage re-architecture

### Negative
- **Overhead on single node**:
  - Longhorn manager daemonset
  - Longhorn CSI driver
  - Longhorn UI
  - ~500MB-1GB extra RAM usage (acceptable given 128GB total)
- **Complexity on day one**: More components to monitor and debug
- **Single point of failure remains**: Until node 2 is added, still no HA (but at least have S3 backups)
- **More things to learn**: Team needs to understand Longhorn concepts

### Neutral
- **Must test disaster recovery**: Need runbook for restoring from S3 (would need this regardless)
- **Monitoring required**: Longhorn disk usage, replica health, engine health (would monitor storage anyway)

## Implementation Notes

### Single Node Configuration
```yaml
replica-count: 1  # No replication on single node
backup-target: s3://our-backups/longhorn
retention: 30d
```

### Multi-Node Migration (when adding node 2)
```yaml
replica-count: 2  # Longhorn automatically replicates existing volumes
```

### Disaster Recovery Testing
- **CRITICAL**: Must test full restore from S3 backup before production
- Document restore procedure in runbook
- Time how long restoration takes (sets RTO expectations)

### Monitoring
- Alert on disk usage >80%
- Alert on replica health issues
- Alert on backup failures

## Migration Path from local-path (for reference)

If we had chosen local-path-provisioner, the migration would require:

1. Create new Longhorn-backed PVC
2. Scale down StatefulSet to 0
3. Create migration pod mounting both old and new PVCs
4. Copy data: `cp -rp /old-data/* /new-data/`
5. Update StatefulSet volumeClaimTemplates
6. Scale up StatefulSet
7. Verify data integrity
8. Delete old PVC

**Estimated downtime**: 2-4 hours for 100GB Postgres, longer for larger datasets.

This migration pain justifies the overhead of running Longhorn from day one.

## References

- [Longhorn Documentation](https://longhorn.io/docs/)
- [Longhorn S3 Backup Configuration](https://longhorn.io/docs/1.10.0/snapshots-and-backups/backup-and-restore/set-backup-target/)
- [Kubernetes PVC Migration Challenges](https://justyn.io/til/migrate-kubernetes-pvc-to-another-pvc/)
