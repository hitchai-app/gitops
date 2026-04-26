# 0046. CNPG Tuning by Workload Class

**Status**: Proposed

**Date**: 2026-04-26

## Context

CNPG ships neutral PostgreSQL defaults. Our clusters serve different workload classes — typical
app DBs, write-heavy stores (sentry monitor check-ins, metrics, queues), mostly-read services.

A recent sentry-system cleanup failure made the gap concrete: factory autovacuum thresholds fired
8 times in 100 days on a 1.5 M-row hot table, and cleanup catch-up blew past its CronJob deadline.
The same defaults are in use across all our clusters.

## Decision

Classify each CNPG cluster by workload and tune the small set of parameters that matter for that
class. Don't set everything; set what moves the needle.

## Quick Guide

### Step 1 — pick the class

| Class | Signal | Examples |
|---|---|---|
| **Write-heavy / high churn** | constant inserts + scheduled or rolling deletes | sentry, metrics, audit, queues |
| **Mixed OLTP** | balanced reads/writes, transactional app | most product DBs |
| **Read-heavy** | mostly SELECT, infrequent writes | reporting, content, lookup |
| **Bulk-load** | sporadic large imports | ETL targets, dev/restore |

### Step 2 — set what matters

**Every cluster (cheap, broad payoff):**

- `maintenance_work_mem` ≈ 25 % of memory limit (default 64 MB starves vacuum / index builds)
- `effective_cache_size` ≈ 75 % of memory limit (planner uses this — default assumes 4 GB)
- `shared_buffers` ≈ 25 % of memory limit

**Write-heavy / high churn — add:**

- `autovacuum_vacuum_scale_factor: 0.05` (default 0.20 — fire at 5 % dead, not 20 %)
- `autovacuum_vacuum_insert_scale_factor: 0.05`
- `autovacuum_vacuum_cost_limit: 1000` (default 200 — un-throttle vacuum I/O)
- `autovacuum_naptime: 30s`

**Mixed OLTP — add:**

- `work_mem: 16 MB` (default 4 MB — joins / sorts spill to disk early)
- Autovacuum: same direction, less aggressive (`scale_factor: 0.10`)

**Read-heavy — add:**

- `random_page_cost: 1.1` (default 4.0 assumes spinning disk; we run SSDs)
- Bump `shared_buffers` if hot set exceeds 25 % of memory

**Bulk-load — add (during load window):**

- Larger `maintenance_work_mem` (≥ 1 GB) — raise memory limit accordingly
- `work_mem: 64 MB`
- Disable autovacuum on the target table during load, `VACUUM ANALYZE` after

### Step 3 — per-table overrides for hot spots

If one table dominates churn in an otherwise normal cluster, tune it at the table level instead of
cluster-wide:

```sql
ALTER TABLE foo SET (autovacuum_vacuum_scale_factor = 0.02);
```

Cleaner than over-vacuuming everything.

## Alternatives Considered

- **Keep CNPG defaults.** Proven inadequate for write-heavy workloads (sentry incident).
- **Per-cluster PGTune output.** Duplicates effort across similar clusters; ignores per-table
  heterogeneity.
- **External dynamic tuning (dbtune et al.).** Extra dependency, opaque to GitOps. Premature.

## Consequences

### Positive

- Concrete: classify → set 4–6 parameters → done.
- Hot tables can be tuned without changing cluster-wide defaults.

### Negative

- Workload class is a judgment call; misclassification of a cluster with one hot table is the main
  risk — the per-table override step exists to mitigate it.
- `shared_buffers` changes require a Postgres restart; other parameters reload only.

## When to Reconsider

- Cluster grows past ~50 GB or sustains > 1k TPS
- Workload class shifts (read-heavy app grows a metrics table)
- CNPG ships workload-class profiles upstream

## References

- ADR 0004: CloudNativePG for PostgreSQL
- ADR 0044: CNPG Backup and Recovery Strategy
- [Tembo: Optimizing Postgres Autovacuum for High-Churn Tables](https://www.tembo.io/blog/optimizing-postgres-auto-vacuum)
- [PGTune](https://pgtune.leopard.in.ua/)
