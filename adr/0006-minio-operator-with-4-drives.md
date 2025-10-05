# 0006. MinIO Operator with 4-Drive Configuration

**Status**: Accepted

**Date**: 2025-10-05

## Context

We need S3-compatible object storage for application file uploads, Velero cluster backups, and general object storage needs. The cluster starts on a single Hetzner node and will scale to multi-node.

Key requirements:
- S3 API compatibility
- Ability to scale from single node to distributed
- Declarative GitOps configuration
- Multi-tenancy support (stage/prod isolation)

**Note**: Longhorn will backup to external S3 (AWS or similar), not to MinIO, to avoid circular dependencies.

## Decision

We will use **MinIO Operator with 4-drive configuration** (SNMD - Single-Node Multi-Drive).

Configuration:
- Single server with 4 PVCs (volumesPerServer: 4)
- Small drives initially (5Gi per drive for testing)
- Erasure coding EC:2 (2 data + 2 parity drives)
- TLS via cert-manager (disable operator auto-cert)
- Longhorn single-replica StorageClass (see ADR 0007)

## Alternatives Considered

### 1. Ceph (Unified Storage)
- **Pros**: Battle-tested, unified block+file+object, LGPL license, enterprise-grade
- **Cons**:
  - **Steep learning curve** - requires distributed systems expertise
  - **High operational burden** - MONs, OSDs, MGRs configuration
  - **Resource overhead** - 2-4GB RAM per OSD, minimum 3 nodes
  - Setup time: weeks vs hours for MinIO
- **Why not chosen**: Massive complexity for small team; overkill for our scale

### 2. MinIO with 1 Drive (SNSD)
- **Pros**: Simplest setup, 100% capacity efficiency, minimal overhead
- **Cons**:
  - **CRITICAL: Cannot expand** - SNSD uses EC:0 (no parity), cannot add pools
  - **No migration path** - Must backup → rebuild to scale
  - **No bitrot protection** - Missing erasure coding data integrity
- **Why not chosen**: Dead end architecture; migration pain unacceptable

### 3. MinIO StatefulSet (no operator)
- **Pros**: Full control, no operator bugs, simpler troubleshooting
- **Cons**: Manual TLS management, no tenant automation, higher operational burden
- **Why not chosen**: Operator automation (TLS, tenants, expansion) worth the complexity

## Consequences

### Positive

**Scalability:**
- ✅ Can add server pools without data migration
- ✅ 4-drive topology enables distributed expansion
- ✅ Ready for multi-node growth

**Data Integrity:**
- ✅ Erasure coding EC:2 (tolerates 2 drive failures)
- ✅ Bitrot protection (silent corruption detection)
- ✅ 50% capacity efficiency (10Gi usable from 20Gi raw)

**Operations:**
- ✅ TLS automation via cert-manager
- ✅ Multi-tenancy (namespace isolation)
- ✅ GitOps compatible (tenant, buckets, certificates all declarative)
- ✅ Active maintenance (MinIO Inc backing, v5.0.18 May 2025)

### Negative

**Capacity & Complexity:**
- ❌ 50% capacity loss (need 2× storage for usable space)
- ❌ Operator bugs exist (TLS issues, tenant upgrade downtime)
- ❌ Two-phase upgrades (operator separate from tenant)
- ❌ Breaking changes (v6.0 removed console, v5.0 CRD changes)

**Single-Node Limitations:**
- ⚠️ No HA on single node (all drives on same pod)
- ⚠️ Erasure coding provides integrity, not availability (until multi-node)
- ⚠️ Redundancy is theoretical (pod failure takes all drives)

**Known Issues:**
- ⚠️ Auto-cert frequently broken (mitigated: use cert-manager)
- ⚠️ Tiering feature has data loss bug (don't use tiering)
- ⚠️ Velero PVC restore broken (use MinIO replication instead)

### Neutral
- AGPL licensing safe for internal use (S3 API over network)
- More stable than Redis operators (no critical failover bugs)
- Less mature than CloudNativePG (more operational issues)

## Why 4 Drives Instead of 1?

**Technical reason:**

**1-drive (SNSD):**
- Uses EC:0 (no erasure coding)
- Cannot add pools (no parity level to match)
- Dead end architecture

**4-drive (SNMD):**
- Uses EC:2 (2 data + 2 parity)
- Can add pools (new pool needs ≥ 2 × EC:2 = 4 drives)
- MinIO rule: "New pool must support minimum 2 × EC:N drives"

**Capacity with 4 × 5Gi drives:**
- Raw: 20Gi
- Usable: 10Gi (50% due to EC:2 parity)
- Can lose: 2 drives and recover

## Critical Mitigations

**Avoid:**
- ❌ Tiering feature (data loss bug in MinIO core)
- ❌ Auto-cert (use cert-manager)
- ❌ Object locking (config loss on restart)

**Required:**
- ✅ Pin MinIO version (test before upgrading)
- ✅ Monitor GitHub issues for critical bugs
- ✅ Use MinIO replication for backups (not Velero)
- ✅ Test tenant upgrades in staging
- ✅ Set up external backup strategy

## When to Reconsider

**Revisit if:**
1. Storage cost becomes critical (50% overhead unacceptable)
2. Operator becomes unmaintained (6+ months no releases)
3. Critical data loss bugs in production
4. Team can't handle operational complexity
5. Need unified storage (consider Ceph with dedicated ops)

## Licensing

**MinIO AGPL v3:**
- ✅ Internal use compliant (S3 API over network)
- ✅ No commercial license needed
- ⚠️ Would need commercial if: modifying code, linking into app, or offering as SaaS

## References

- [MinIO Operator](https://github.com/minio/operator)
- [Erasure Coding Guide](https://min.io/docs/minio/linux/operations/concepts/erasure-coding.html)
- [MinIO AGPL License](https://blog.min.io/from-open-source-to-free-and-open-source-minio-is-now-fully-licensed-under-gnu-agplv3/)
- ADR 0007: Longhorn StorageClass Strategy
