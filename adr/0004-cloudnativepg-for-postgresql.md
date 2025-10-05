# 0004. CloudNativePG for PostgreSQL

**Status**: Accepted

**Date**: 2025-10-05

## Context

We need a PostgreSQL operator for Kubernetes. The cluster starts on a single Hetzner node and will scale to multi-node. We require:
- Point-in-time recovery (PITR) backups to S3
- Automated failover when adding nodes
- Safe upgrade procedures
- Minimal operational complexity

Team context:
- Small development team (developers handle ops)
- Starting with single node, scaling to multi-node
- Target availability: 99% (two nines)
- Database size: Starting small, may grow to 100GB+

## Decision

We will use **CloudNativePG** as our PostgreSQL operator.

Configuration:
- PITR backups to S3 with 30-day retention
- Single replica on single node (no HA initially)
- When adding node 2: Enable multi-replica with automated failover
- Pin operator version, upgrade cautiously

## Alternatives Considered

### 1. Zalando Postgres Operator (with Patroni)
- **Pros**:
  - **Fastest failover**: ~27 seconds (vs CloudNativePG 40-80s)
  - Battle-tested: 5+ years in production at Zalando
  - Patroni is industry-standard HA solution
  - Simple setup, developer-friendly
  - 4k+ GitHub stars
- **Cons**:
  - **Declining maintenance**: Fewer updates, slower feature development
  - **Outdated Postgres versions**: Lagging on latest releases
  - **Failover issues**: Stuck states with 2-node + sync mode (Issue #2276)
  - **No failover on node crash** (Issue #556)
  - **Connection pooler problems** after failover (Issue #1928)
  - **Patroni slowness reports** (Issue #1145)
- **Why not chosen**: Declining maintenance is a long-term risk that outweighs faster failover

### 2. Crunchy PGO (Postgres Operator)
- **Pros**:
  - **Most mature**: Since 2017, 3.7k stars
  - **pgBackRest integration**: Incremental backups, delta restore, block-level efficiency
  - **Best reliability testing results**: Minimal downtime in benchmarks
  - **Fast failover**: ~30s (Patroni-based)
  - **Major upgrade support**: PGUpgrade API for version upgrades
  - Active maintenance, production-proven
- **Cons**:
  - **Complexity**: pgBackRest setup, repository configuration, retention policies
  - **More components**: pgBackRest, pgBouncer, Patroni layer
  - **Heavier footprint**: Additional infrastructure overhead
  - **Awkward upgrades**: Multi-stage process with special CRDs
  - **Random crashes reported** (Issue #2138)
  - **Pods stuck on node failure**
- **Why not chosen**: pgBackRest complexity not justified for our scale; CloudNativePG simplicity better fits small team

### 3. Plain StatefulSet
- **Pros**:
  - Full control, no operator dependency
  - Minimal resource overhead
  - Simple mental model
- **Cons**:
  - Manual everything: backups, WAL archiving, PITR, monitoring
  - No automated failover
  - Must be PostgreSQL expert
  - Write and maintain all scripts
- **Why not chosen**: See ADR 0003 (operators provide better abstraction)

## Consequences

### Positive

#### Operational Simplicity
- **15 lines of YAML → production PITR**: Continuous WAL archiving to S3, declarative restore
- **No external HA dependencies**: Instance Manager built into operator (vs Patroni/etcd)
- **Single control plane**: Operator directly manages Postgres (not Operator → Patroni → Postgres)
- **Kubernetes-native**: Uses K8s API primitives, no external tools

#### Development & Community
- **Very active maintenance**: v1.27.0 (Aug 2025), CNCF project, 6.9k stars
- **Rapid feature development**: Community growing fast, active issue resolution
- **Modern architecture**: Built for Kubernetes from ground up (not adapted)
- **Long-term viability**: CNCF backing suggests sustained development

#### Features
- **Multi-cluster support**: Manage multiple PostgreSQL clusters
- **Built-in monitoring**: Prometheus metrics ready
- **S3 backups**: Automated with retention policies
- **Declarative recovery**: Restore to specific timestamp via YAML

### Negative

#### Failover Performance & Reliability
- **Slowest failover**: 40-80 seconds (vs Zalando 27s, Crunchy ~30s)
  - 30-37s delay before failover starts
  - Chaos testing showed 3 minutes total recovery time
- **Stuck failover states**:
  - Issue #7393: Cluster stuck in "Failing over" for days
  - Issue #1593: Forever stuck after node termination (requires manual fix)
- **Data loss scenarios**:
  - Aggressive `switchoverDelay` settings can cause data loss
  - Fast shutdown failure → immediate shutdown → WAL not written
- **Storage exhaustion death spiral**:
  - Disk full → failover → replica disk full → infinite loop
  - On single node, this is catastrophic

#### Maturity & Stability
- **Younger project**: Less battle-tested than Zalando/Crunchy
- **Major version upgrades**: Still requires manual steps (improving)
- **Breaking changes**: Barman Cloud deprecation (v1.28.0) poorly communicated
- **Operator downtime = no self-healing**: If operator pod dies, failover doesn't work

#### Infrastructure Gotchas
- **Network policy issues**: Operator needs pod connectivity, GKE blocks ports by default
- **Kubernetes expertise required**: CNCF recommends CKA certification
- **No self-healing during operator downtime**: Clusters run fine but no failover

### Neutral

- **Failover speed acceptable for our use case**:
  - Single node: Failover irrelevant (no replica)
  - Multi-node: 40-80s acceptable for 99% uptime target
- **ALL operators have failover issues**: Zalando, Crunchy, CloudNativePG all have stuck states
- **Manual intervention required sometimes**: True for all Postgres K8s operators
- **Migration path exists**: Can move to Crunchy PGO if needed (export data, redeploy)

## Critical Understanding: All Postgres Operators Have Limitations

**Research shows ALL Kubernetes Postgres operators suffer from:**
1. Failover delays (30s-3min best case)
2. Stuck states requiring manual recovery
3. Edge cases with 2-node clusters
4. Data loss risks with aggressive settings

**Root causes (affect ALL operators):**
- Kubernetes node detection is slow (30-40s)
- Split-brain prevention requires caution (adds delay)
- Consensus mechanisms need time (Patroni DCS / K8s API)
- WAL replay before promotion (can't skip)

**This is a fundamental Kubernetes + Postgres challenge, not CloudNativePG-specific.**

## Implementation Notes

### Deployment Strategy
- **Single node phase**: 1 replica, no HA, S3 backups only
- **Multi-node phase**: 2-3 replicas, automated failover enabled
- **Backup configuration**: 30-day retention, continuous WAL archiving
- **Version pinning**: Pin operator version, read release notes before upgrading

### Operational Requirements
- ✅ **Runbook for manual failover recovery**: Test and document stuck state recovery
- ✅ **Monthly disaster recovery testing**: Restore from S3 backup, verify procedures
- ✅ **Aggressive monitoring**:
  - Disk usage alerts at 70% (prevent death spiral)
  - Operator health monitoring (failover depends on it)
  - Failover detection and alerting
- ✅ **Safe defaults**: Don't optimize for speed, keep conservative `switchoverDelay`
- ✅ **Backup verification**: Test restore process before production

### Mitigation Strategies
- **Storage exhaustion**: Alert at 70% disk, automated cleanup, volume expansion
- **Stuck failover**: Documented manual recovery procedure, tested monthly
- **Operator downtime**: Monitor operator pod health, auto-restart, redundancy when possible
- **Breaking changes**: Subscribe to release notes, test upgrades in stage first

### Configuration Example
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres
spec:
  instances: 1  # Start with 1, increase when adding nodes
  backup:
    barmanObjectStore:
      destinationPath: s3://backups/postgres
      s3Credentials:
        accessKeyId: ...
        secretAccessKey: ...
      wal:
        compression: gzip
      retention: "30d"
  # Conservative failover settings (favor safety over speed)
  failoverDelay: 0  # Default, don't optimize prematurely
```

## When to Reconsider

**Revisit this decision if:**

1. **Failover becomes critical**: Need sub-30s RTO (consider Zalando)
2. **Database grows large**: 500GB+ needing fast restores (consider Crunchy pgBackRest)
3. **CloudNativePG maintenance declines**: Fewer commits, unresolved critical bugs
4. **Stuck failover becomes frequent**: Manual intervention unacceptable (consider managed DB)
5. **Team can't handle complexity**: Need simpler solution (consider managed RDS/CloudSQL)

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/)
- [CloudNativePG GitHub](https://github.com/cloudnative-pg/cloudnative-pg)
- [Failover Performance Analysis](https://github.com/cloudnative-pg/cloudnative-pg/issues/6154)
- [Chaos Testing CloudNativePG](https://coroot.com/blog/engineering/chaos-testing-a-postgres-cluster-managed-by-cloudnativepg/)
- [Chaos Testing Zalando](https://coroot.com/blog/engineering/chaos-testing-of-a-postgres-cluster-managed-by-the-zalando-postgres-operator/)
- [Operator Comparison - Palark](https://blog.palark.com/comparing-kubernetes-operators-for-postgresql/)
