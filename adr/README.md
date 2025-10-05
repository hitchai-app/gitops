# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) documenting significant architectural choices made for this GitOps infrastructure.

## What is an ADR?

An ADR captures an important architectural decision along with its context and consequences. ADRs help teams understand:
- Why decisions were made
- What alternatives were considered
- What trade-offs were accepted
- When the decision can be revisited

## ADR Format

Each ADR follows this structure:

```markdown
# [Number]. [Title]

**Status**: [Proposed | Accepted | Deprecated | Superseded]

**Date**: YYYY-MM-DD

## Context

What is the issue we're addressing? What constraints exist?

## Decision

What decision did we make? Be specific and actionable.

## Alternatives Considered

What other options did we evaluate?

1. **Option A**: Brief description
   - Pros: ...
   - Cons: ...

2. **Option B**: Brief description
   - Pros: ...
   - Cons: ...

## Consequences

What are the implications of this decision?

### Positive
- Benefit 1
- Benefit 2

### Negative
- Trade-off 1
- Trade-off 2

### Neutral
- Consideration 1
- Consideration 2

## References

- Links to relevant documentation
- Related ADRs
- External resources
```

## Naming Convention

ADRs are numbered sequentially with zero-padding:

```
0001-gitops-with-argocd.md
0002-longhorn-storage-from-day-one.md
0003-operators-over-statefulsets.md
```

## Current ADRs

| Number | Title | Status | Date |
|--------|-------|--------|------|
| [0001](0001-gitops-with-argocd.md) | GitOps with ArgoCD | Accepted | 2025-10-05 |
| [0002](0002-longhorn-storage-from-day-one.md) | Longhorn Storage from Day One | Accepted | 2025-10-05 |
| [0003](0003-operators-over-statefulsets.md) | Operators over StatefulSets | Accepted | 2025-10-05 |

## When to Create an ADR

Create an ADR when making decisions about:
- Infrastructure architecture
- Technology selection
- Deployment strategies
- Security patterns
- Operational procedures
- Significant trade-offs

## When NOT to Create an ADR

Don't create ADRs for:
- Implementation details (these go in code comments)
- Temporary workarounds
- Obvious/standard practices
- Decisions that can be easily reversed

## Updating ADRs

ADRs are immutable historical records. To change a decision:
1. Create a new ADR
2. Reference the old ADR
3. Mark the old ADR as "Superseded by ADR-XXXX"
