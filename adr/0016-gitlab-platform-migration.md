# 0016. GitLab Platform Migration

**Status**: Deferred

**Date**: 2025-10-12

## Context

We currently use GitHub for source control and GitHub Actions for CI/CD. Self-hosted GitLab would provide a unified platform (SCM + CI/CD + Container Registry + Security Scanning) with self-hosted control and vendor lock-in avoidance.

However, migration would require:
- Rewriting all GitHub Actions workflows to GitLab CI (completely different YAML syntax)
- 3-4 weeks full-time migration effort
- ~8-12GB RAM permanent overhead
- Team learning curve (Rails operations, new UI/workflows)

Current infrastructure: Single Hetzner node (12 CPU / 128GB RAM), small team (developers handle ops).

## Decision

**Deferred** - Not pursuing GitLab migration at this time.

**Primary blocker:** Don't want to rewrite all GitHub Actions workflows to GitLab CI YAML.

**Current assessment:** Currently satisfied with GitHub. May reconsider strategically in future when vendor lock-in or privacy concerns outweigh migration costs.

## Rationale

**Why GitLab could make sense:**
- ✅ Vendor lock-in avoidance (open-source, self-hostable)
- ✅ Platform consolidation (single system for SCM + CI/CD + registry + scanning)
- ✅ Privacy/control (code never leaves infrastructure)
- ✅ No recurring GitHub fees (self-hosted = infrastructure cost only)

**Why deferring:**
- ❌ GitHub Actions migration is dealbreaker (rewrite all workflows)
- ❌ No urgent pain with current GitHub setup
- ❌ 3-4 weeks migration effort not justified by current problems
- ❌ 8-12GB RAM overhead significant on single node

## Alternatives Considered

### Stay with GitHub + Add Harbor (ADR 0015)
- **Chosen approach** - Addresses registry improvements (~1GB RAM, 1-2 days) without platform migration
- Solves multi-registry caching, vulnerability scanning, RBAC
- Keeps familiar GitHub workflows and team productivity

### GitHub Enterprise
- Deeper GitHub lock-in, high recurring cost
- Doesn't address self-hosting or vendor lock-in concerns

### Gitea/Forgejo
- Lighter than GitLab (~500MB-1GB RAM)
- But no built-in CI/CD (need separate tool like Woodpecker CI)
- Smaller ecosystem, less mature

## Relationship to Harbor (ADR 0015)

Harbor and GitLab can coexist - these ADRs are NOT mutually exclusive.

**If later migrating to GitLab:**
- Option A: GitLab + Harbor (Harbor provides multi-registry proxy that GitLab registry lacks)
- Option B: GitLab registry only (simpler, but no external registry caching)

Harbor makes sense **regardless of GitHub vs GitLab** if you need multi-registry proxy caching and advanced scanning/RBAC.

## When to Reconsider

**Revisit GitLab if:**
- Willing to rewrite GitHub Actions workflows to GitLab CI
- GitHub costs become prohibitive
- Privacy/compliance requires self-hosted SCM
- Vendor lock-in concerns outweigh migration effort
- Team gains capacity to absorb 3-4 week migration + ongoing GitLab ops

**For now:** Focus on Harbor (ADR 0015) for registry improvements without platform migration.

## Related ADRs

- ADR 0014: Actions Runner Controller (would be decommissioned if GitLab chosen)
- ADR 0015: Harbor Container Registry (can coexist with GitLab, or use GitLab registry alone)
- ADR 0004: CloudNativePG (would provide GitLab's database if deployed)
- ADR 0005: Valkey StatefulSet (would provide GitLab's Redis if deployed)

## References

- [GitLab Documentation](https://docs.gitlab.com/)
- [GitLab Helm Chart](https://docs.gitlab.com/charts/)
- [GitLab CI/CD vs GitHub Actions](https://docs.gitlab.com/ee/ci/migration/github_actions.html)
