# 0006. MinIO Operator (Single-Drive Bootstrap)

**Status**: Accepted

**Date**: 2025-10-05

## Context

We need an S3-compatible object store for application uploads, Velero backups, and general file storage. The Kubernetes cluster starts on a single Hetzner node (Longhorn-backed volumes) with plans to grow to multiple nodes later.

Key constraints:
- Minimal operational overhead for a small team
- Declarative GitOps management
- Stage/prod tenant isolation
- The platform already depends on Longhorn single-replica volumes (ADR 0007)

Non-goals right now:
- Surviving node or disk failure (no second node exists yet)
- Achieving parity-based durability
- Multi-site replication beyond copying to external object storage

## Decision

Operate a **Single-Node Single-Drive (SNSD) MinIO tenant** via the MinIO Operator. We accept zero in-cluster durability in exchange for the simplest possible footprint—this is the easiest way to get S3 storage running on day one while the cluster is single-node. TLS is issued by cert-manager (operator auto-cert disabled). When additional nodes arrive, we will provision a new distributed MinIO tenant and migrate data rather than stretching the single-node deployment.

## Alternatives Considered

### Ceph / Rook
- **Pros**: true HA across nodes, unified block/object, rich ecosystem.
- **Cons**: significant operational load (MON/OSD tuning, capacity planning), high resource requirements, steep learning curve.
- **Reason rejected**: disproportionate complexity for a single-node starter cluster.

### MinIO SNMD (4 drives, EC:2)
- **Pros**: enables erasure coding, matches the layout required for future multi-node pools.
- **Cons**: still collapses with a node/disk failure (Longhorn places all PVCs on the same host), wastes 50% capacity on parity, adds operational knobs we cannot leverage yet.
- **Reason rejected**: parity without hardware redundancy is illusory; we are better served by keeping things simple and planning an explicit migration later.

### MinIO without the operator (plain StatefulSet)
- **Pros**: minimal components, no operator bugs, full control of TLS and lifecycle.
- **Cons**: additional manual work (TLS, tenants, upgrades), harder GitOps reconciliation.
- **Reason rejected**: the operator still provides enough automation (tenant lifecycle, cert propagation) to be worthwhile even in single-node mode.

## Consequences

### Positive
- **Small blast radius**: one PVC and one pod are easy to reason about and debug.
- **Operationally easiest**: no parity tuning, pool math, or additional PVCs to juggle; provisioning stays straightforward in GitOps.
- **Zero parity overhead**: all allocated storage is usable; no silent assumption of resilience.
- **Clear migration plan**: we explicitly plan to move to a distributed tenant once multi-node hardware is available.
- **Operator ergonomics**: declarative tenants, TLS integration with cert-manager, namespace-scoped isolation per environment.

### Negative
- **No in-cluster durability**: disk or node loss wipes the tenant; external replication is mandatory.
- **Migration debt**: future multi-node rollout requires provisioning a new distributed tenant and mirroring buckets.
- **Operator quirks remain**: two-step upgrades (operator + tenant), auto-cert bugs, and tiering issues still need monitoring.
- **Velero limitations**: PVC restores targeting MinIO remain unreliable; replication to another S3-compatible store is required instead.

### Neutral
- AGPLv3 licensing is fine for internal S3 API usage; revisit if we expose MinIO as a service.
- Compared to Redis/Valkey operators, MinIO’s operator is mature but still opinionated; we accept the trade-offs.

## Implementation Notes

- **Storage**: provision a single PVC via Longhorn’s single-replica class; size for near-term needs and monitor usage.
- **TLS**: supply cert-manager-issued secrets via `externalCertSecret`; keep operator auto-cert disabled due to instability.
- **Replication**: configure bucket replication (or `mc mirror`) to an external S3 target to cover catastrophic loss of the cluster.
- **Monitoring**: scrape MinIO metrics and alert on capacity thresholds, replication lag, and pod restarts.
- **Upgrades**: pin operator and tenant image versions; rehearse upgrades in staging before applying to production.

## Future Migration (Multi-Node)

When the cluster gains additional nodes:
1. Deploy a new MinIO tenant with an MNMD topology (e.g., multiple nodes × drives) in parallel.
2. Configure bucket replication from the single-drive tenant to the new distributed tenant.
3. Cut over applications, validate data integrity, then decommission the bootstrap tenant.

This approach avoids trying to reshape an SNSD pool—which MinIO does not support—while providing a controlled migration path.

## When to Revisit

- Additional Kubernetes nodes or direct-attached storage become available.
- Durability requirements tighten beyond acceptable downtime/data loss.
- MinIO Operator maintenance becomes untenable.
- Storage footprint or performance pushes past the single-drive envelope.

## References

- [MinIO Kubernetes Documentation](https://min.io/docs/minio/kubernetes/upstream/index.html)
- [MinIO Concepts – SNSD vs SNMD vs MNMD](https://min.io/docs/minio/linux/operations/concepts.html#what-system-topologies-does-minio-support)
- [MinIO Operator GitHub](https://github.com/minio/operator)
- ADR 0007: Longhorn StorageClass Strategy
