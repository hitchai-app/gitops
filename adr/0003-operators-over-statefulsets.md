# 0003. Operators over StatefulSets (General Principle)

**Status**: Accepted

**Date**: 2025-10-05

## Context

We need a general principle for when to use Kubernetes operators versus plain StatefulSets for stateful infrastructure services.

Team context:
- Small development team (developers wear ops hats)
- Limited deep Kubernetes expertise
- Need reliable operations (backups, upgrades, monitoring)
- Resources available (128GB RAM, overhead acceptable)

## Decision

**Default to operators for stateful infrastructure** when all conditions are met:

1. ✅ Operator is actively maintained (commits in last 3 months)
2. ✅ Operator provides operational value (backups, upgrades, monitoring)
3. ✅ Operator supports our requirements
4. ✅ Resource overhead is acceptable

**Fall back to StatefulSets when:**

1. ❌ Operator is unmaintained (no commits 6+ months, unresolved critical bugs)
2. ❌ Operator lacks critical features we need
3. ❌ Operator abstracts too much (debugging becomes impossible)
4. ❌ Compliance forbids operators/CRDs
5. ❌ Resource constraints make overhead unacceptable

## Rationale

**Operators provide higher-level abstraction:**
- Encode best practices (don't need to be expert)
- Declarative configuration (express intent, not implementation)
- Built-in lifecycle management (backups, upgrades, monitoring)

**StatefulSets require manual implementation:**
- Write backup scripts (CronJobs, pg_dump, WAL archiving)
- Handle upgrades manually (compatibility checks, rollback plans)
- Deploy monitoring separately (exporters, dashboards)

**For a small team: abstraction > control**

## Alternatives Considered

### 1. Always use StatefulSets
- **Pros**: Maximum control, no dependencies, simple
- **Cons**: Massive operational burden, manual everything

### 2. Always use operators
- **Pros**: Consistent approach, minimal operations
- **Cons**: Not all operators are good, some add complexity without value

### 3. Case-by-case evaluation (our choice)
- **Pros**: Pragmatic, choose right tool per service
- **Cons**: Requires research per service

## Consequences

### Positive
- **Reduced operational burden**: Operators handle complex operations
- **Faster time to production**: Don't reinvent backup/monitoring
- **Better reliability**: Battle-tested operator code vs custom scripts

### Negative
- **Dependency on maintainers**: Must trust operator quality
- **Learning curve**: Each operator has own concepts
- **Debugging complexity**: More layers to understand

### Neutral
- **Specific operator choices**: Documented in separate ADRs (0004, 0005, 0006...)
- **Migration possible**: Can move from operator to StatefulSet if needed

## Implementation Notes

Each infrastructure service gets its own ADR evaluating:
- Available operators vs StatefulSet
- Operator maintenance status
- Features vs complexity trade-off
- Specific choice rationale

## References

- ADR 0004: PostgreSQL operator selection
- ADR 0005: Redis operator selection
- ADR 0006: MinIO operator selection
