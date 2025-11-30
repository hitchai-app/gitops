# 0020. SAP Valkey Operator

**Status**: Accepted

**Date**: 2025-11-30

**Supersedes**: ADR 0005 (Valkey StatefulSet)

## Context

ADR 0005 chose manual StatefulSet for Valkey, citing ecosystem immaturity. After deployment, persistent ArgoCD OutOfSync issues emerged from Kubernetes injecting default field values (~20 fields). Options were bloating manifests or maintaining extensive `ignoreDifferences` - both create maintenance burden.

## Decision

Adopt **SAP valkey-operator** to manage Valkey instances.

**Why SAP:**
- Uses Bitnami Valkey chart (battle-tested)
- SAP backing suggests maintenance continuity
- Operator owns StatefulSet complexity
- Supports our use case (single instance, persistence, metrics)

## Alternatives Reconsidered

| Operator | Decision | Reason |
|----------|----------|--------|
| OT-CONTAINER-KIT/redis-operator | Avoid | Critical bugs: #1403 (failover), #1164 (data loss) |
| Spotahome/redis-operator | Skip | Redis-only, Valkey unverified |
| Hyperspike/valkey-operator | Too early | Pre-1.0 (v0.0.x) |
| SAP/valkey-operator | **Chosen** | SAP-backed, no critical bugs |

## Consequences

### Positive
- No OutOfSync noise - operator manages StatefulSet details
- Cleaner manifests - Valkey CR vs StatefulSet+Service+ServiceMonitor
- Built-in metrics exporter and ServiceMonitor
- Future HA via Sentinel mode if needed

### Negative
- New operator dependency
- Early version (v0.1.x)
- Some fields immutable after creation (sentinel.enabled, persistence.size)

## When to Reconsider

- SAP abandons operator
- Need sharding (not supported)
- Critical operator bugs emerge

## References

- [SAP valkey-operator](https://github.com/SAP/valkey-operator)
- Superseded: ADR 0005
