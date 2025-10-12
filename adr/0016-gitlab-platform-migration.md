# 0016. GitLab Platform Migration

**Status**: Proposed

**Date**: 2025-10-12

## Context

We are considering migrating from GitHub to self-hosted GitLab as our primary development platform. This would replace:
- **GitHub** (source control)
- **GitHub Actions** (CI/CD)
- **Actions Runner Controller** (self-hosted runners, ADR 0014)
- **Potential Harbor deployment** (container registry, ADR 0015)

With a single unified platform:
- **GitLab** (SCM + CI/CD + Container Registry + Security Scanning)

Current infrastructure:
- Small team (developers handle ops)
- Single Hetzner node: 12 CPU / 128GB RAM / 280GB SSD
- CloudNativePG PostgreSQL cluster (shared)
- Valkey Redis (shared)
- Will scale to multi-node

## Decision

**This ADR evaluates whether to migrate to GitLab.** Decision pending answers to critical questions below.

If accepted, we will:
- Deploy self-hosted GitLab (Helm chart)
- Migrate all repositories from GitHub
- Rewrite all CI/CD workflows (GitHub Actions → GitLab CI)
- Decommission Actions Runner Controller
- Use GitLab's built-in container registry (Harbor becomes unnecessary)

## Motivation: Why Consider GitLab?

**Before analyzing alternatives, we must understand the motivation.** Different reasons lead to different conclusions.

### Possible Motivations

**A. Privacy / Self-Hosted Control**
- Don't trust GitHub with proprietary source code
- Compliance requires self-hosted SCM
- Want full control over infrastructure

**B. Cost Reduction**
- GitHub costs too high (private repos, Actions minutes, Enterprise features)
- Self-hosted GitLab cheaper long-term

**C. Feature Requirements**
- Need GitLab-specific features (advanced planning, built-in security scanning)
- GitHub Actions insufficient for CI/CD needs
- Want unified issue boards, wikis, planning tools

**D. Platform Consolidation**
- Frustrated with fragmented tools (GitHub + potential Harbor + separate scanning)
- Want single platform for everything

**E. Vendor Lock-in Avoidance**
- Prefer open-source, self-hostable platform
- Don't want dependency on GitHub's availability/pricing changes

**F. Team Preference**
- Team has GitLab experience
- Prefer GitLab workflows/UI

**⚠️ CRITICAL: The motivation determines whether GitLab is the right choice.**

## Alternatives Considered

### 1. Stay with GitHub + Add Harbor (ADR 0015)

**Approach:** Keep GitHub, add Harbor for registry improvements.

**Pros:**
- ✅ **Minimal migration** (1-2 days for Harbor vs 3-4 weeks for GitLab)
- ✅ **Leverage existing investment** (ARC, workflows, team knowledge)
- ✅ **Much lighter** (~1GB RAM vs 8-12GB)
- ✅ **Team productivity** (no learning curve, workflows stay)
- ✅ **Less risk** (incremental change, reversible)

**Cons:**
- ❌ **Doesn't solve GitHub pain points** (if cost, privacy, or feature gaps)
- ❌ **Fragmented platform** (GitHub + Harbor = two systems)
- ❌ **GitHub dependency remains** (still paying, still trusting GitHub)

**When this wins:**
- Motivation is **only registry improvements** (Harbor solves it)
- Happy with GitHub otherwise
- Team capacity low (can't absorb GitLab)

### 2. GitHub Enterprise + GitHub Container Registry

**Approach:** Upgrade to GitHub Enterprise, use GHCR for images.

**Pros:**
- ✅ **No migration** (stay on GitHub)
- ✅ **Unified platform** (GitHub provides everything)
- ✅ **Managed service** (GitHub handles operations)
- ✅ **Team familiarity** (no learning curve)
- ✅ **GHCR integrated** (GitHub Packages for containers)

**Cons:**
- ❌ **High recurring cost** (GitHub Enterprise expensive)
- ❌ **Still hosted by GitHub** (if privacy is concern)
- ❌ **Vendor lock-in** (deeper GitHub dependency)
- ❌ **Limited self-hosting options** (GitHub Enterprise Server exists but complex)

**When this wins:**
- Motivation is **platform consolidation** (not privacy or cost)
- Budget allows Enterprise pricing
- Don't want operational burden

### 3. Gitea / Forgejo (Lightweight Self-Hosted)

**Approach:** Migrate to lightweight open-source Git forge.

**Pros:**
- ✅ **Much lighter than GitLab** (~500MB-1GB RAM)
- ✅ **Simple operations** (single binary, no Rails)
- ✅ **Self-hosted** (privacy, control)
- ✅ **Open source** (no vendor lock-in)
- ✅ **GitHub-compatible** (similar UI/API, easier migration)

**Cons:**
- ❌ **No built-in CI/CD** (need separate tool like Woodpecker CI, Drone)
- ❌ **No container registry** (need Harbor or separate registry)
- ❌ **Less mature** (smaller ecosystem than GitLab)
- ❌ **Fewer features** (basic issue tracking, no advanced planning)

**When this wins:**
- Motivation is **privacy + lightweight**
- Don't need advanced CI/CD features
- Can accept separate CI/CD tool

### 4. Stay with GitHub, Add Separate Tools

**Approach:** Keep GitHub, add specific tools for gaps (Harbor, external scanning, etc).

**Pros:**
- ✅ **Best-of-breed** (specialized tools for each need)
- ✅ **Incremental** (add tools as needed, not all-at-once)
- ✅ **Reversible** (can remove tools independently)
- ✅ **Minimal disruption** (team keeps familiar GitHub)

**Cons:**
- ❌ **Fragmented platform** (multiple tools to manage)
- ❌ **More integration work** (connect tools together)
- ❌ **GitHub dependency** (still paying, still trusting)
- ❌ **More operational complexity** (multiple systems)

**When this wins:**
- Motivation is **specific feature gaps** (not holistic platform problem)
- Team comfortable with tool sprawl
- Want flexibility to swap tools

## Consequences of Migrating to GitLab

### Positive

**Platform Unification:**
- ✅ **Single platform** - SCM, CI/CD, registry, issues, wikis all in one place
- ✅ **Unified permissions** - One RBAC system for everything
- ✅ **Integrated workflows** - Tight coupling between code, CI, and registry
- ✅ **Built-in security** - SAST, DAST, dependency scanning, container scanning

**Self-Hosted Control:**
- ✅ **Privacy** - Code never leaves your infrastructure
- ✅ **Compliance** - Full control for regulatory requirements
- ✅ **Customization** - Can modify GitLab if needed (open source)
- ✅ **No vendor lock-in** - Can export and migrate if needed

**Cost (if GitHub is expensive):**
- ✅ **No recurring GitHub fees** - Self-hosted = infrastructure cost only
- ✅ **Unlimited private repos** - No per-seat licensing
- ✅ **Unlimited CI/CD minutes** - Use your own runners

**Feature Set:**
- ✅ **Advanced planning** - Epic-level tracking, issue boards, roadmaps
- ✅ **Built-in registry** - No Harbor needed
- ✅ **Security dashboards** - Vulnerability reports per project/merge request
- ✅ **Auto DevOps** - Opinionated CI/CD templates

### Negative

**Migration Effort:**
- ❌ **3-4 weeks full-time work** - Migration complexity underestimated often
- ❌ **Rewrite all workflows** - GitHub Actions YAML ≠ GitLab CI YAML (syntax completely different)
- ❌ **Repository migration** - Must migrate all repos, branches, tags, releases
- ❌ **Team training** - New UI, CLI, concepts (merge requests vs pull requests)
- ❌ **URL changes** - Update all documentation, links, integrations
- ❌ **Secret migration** - Recreate all GitHub secrets in GitLab

**Resource Overhead:**
- ❌ **8-12GB RAM minimum** - Rails, Gitaly, PostgreSQL, Redis, Sidekiq, Registry
- ❌ **4-8 CPU cores recommended** - For responsive UI and CI
- ❌ **200-300GB storage** - Git repos + registry + artifacts + CI cache
- ❌ **Permanent cost** - Unlike Harbor evaluation, this is committed infrastructure

**Operational Complexity:**
- ❌ **Rails application** - Need Ruby/Rails debugging skills when things break
- ❌ **Multi-component architecture** - Puma, Sidekiq, Gitaly, Workhorse, Shell
- ❌ **Complex upgrades** - Database migrations, API changes, multi-step processes
- ❌ **Gitaly storage** - Manage Git repository storage separately
- ❌ **Background jobs** - Monitor Sidekiq queues, failed jobs
- ❌ **Performance tuning** - PostgreSQL, Redis, Puma worker pools

**Risk:**
- ❌ **Irreversible commitment** - Migrating back to GitHub is equally costly
- ❌ **Team productivity loss** - Learning curve during migration and after
- ❌ **Workflow disruption** - 3-4 weeks of reduced velocity
- ❌ **Potential bugs** - GitLab bugs affect entire dev workflow
- ❌ **GitLab dependency** - Now dependent on GitLab's release schedule, bugs

**Feature Gaps (compared to GitHub):**
- ⚠️ **Smaller ecosystem** - Fewer marketplace actions, integrations
- ⚠️ **GitHub Actions features** - Some Actions-specific features missing in GitLab CI
- ⚠️ **Community** - GitHub's community larger (more help, more examples)

### Neutral

**Long-term cost:**
- Infrastructure cost (RAM, CPU, storage) vs GitHub subscription fees
- Team time maintaining GitLab vs using managed GitHub
- Depends on team size, repo count, usage patterns

**Security:**
- Self-hosted = you control security, but also responsible for patches
- GitHub = trusted by default, but trust required

## Critical Questions

### For User to Answer

**1. What is the PRIMARY motivation for considering GitLab?**
   - Privacy/compliance (don't trust GitHub)?
   - Cost (GitHub too expensive)?
   - Features (need GitLab-specific capabilities)?
   - Consolidation (hate fragmented tools)?
   - Vendor lock-in avoidance?
   - Team preference?

**2. What specific GitHub pain points exist?**
   - Be concrete: What's broken? What's missing? What's too expensive?
   - If answer is "nothing specific, just exploring" → Stay with GitHub

**3. How committed is the team to this migration?**
   - A) **Definitely migrating** - Already decided, need execution plan
   - B) **Seriously evaluating** - Will migrate if compelling case
   - C) **Casually exploring** - Curious but not committed
   - If C, this is premature - defer until actual pain exists

**4. Can the team realistically absorb GitLab operations?**
   - Dedicate 3-4 weeks to migration (repo migration, workflow rewrites, testing)?
   - Spare 8-12GB RAM permanently?
   - Learn Rails debugging for when GitLab breaks?
   - Maintain complex multi-component system long-term?
   - If "no" to any → GitLab is wrong choice regardless of motivation

**5. What's the budget reality?**
   - How much does GitHub cost currently?
   - What's the GitLab infrastructure cost (RAM/CPU you're buying)?
   - What's the opportunity cost of 3-4 weeks migration?
   - Is GitHub actually the expensive part, or is team time more expensive?

## Decision Framework

### Choose GitLab if ALL of these are true:

1. ✅ **Strong motivation exists** - Clear, specific pain with GitHub (not just curiosity)
2. ✅ **Team committed** - Actively planning migration, not just exploring
3. ✅ **Capacity exists** - Can dedicate 3-4 weeks + absorb 8-12GB RAM
4. ✅ **Operational capability** - Team can handle Rails app operations
5. ✅ **Long-term commitment** - Willing to own GitLab maintenance for years
6. ✅ **ROI positive** - Benefits (privacy, cost, features) outweigh migration effort

**If even ONE is false, GitLab is probably wrong choice.**

### Stay with GitHub if ANY of these are true:

1. ❌ **No specific pain** - Exploring without concrete GitHub problems
2. ❌ **Capacity constrained** - Team maxed out, can't absorb migration effort
3. ❌ **Resource constrained** - 8-12GB RAM unaffordable on single node
4. ❌ **Ops inexperienced** - Team uncomfortable with Rails/multi-component systems
5. ❌ **Uncertainty** - Not confident GitLab solves actual problems

**If ANY true, defer GitLab until conditions change.**

## Implementation Notes (If GitLab Chosen)

### Phase 1: GitLab Deployment (Week 1)

**Infrastructure:**
- Deploy GitLab Helm chart
- Configure external PostgreSQL (CloudNativePG shared cluster)
- Configure external Redis (Valkey shared)
- Set up TLS certificates (cert-manager, ADR 0008)
- Configure SMTP for notifications
- Set up OAuth/SAML if needed
- Configure object storage (MinIO for artifacts, registry, uploads)

**Resource Allocation:**
```yaml
# Minimum production configuration
postgresql:
  type: external  # Use CloudNativePG

redis:
  type: external  # Use Valkey

resources:
  # Total: ~8-12GB RAM
  gitlab-webservice:
    requests: { cpu: 1000m, memory: 2Gi }
    limits: { cpu: 2000m, memory: 3Gi }

  gitlab-sidekiq:
    requests: { cpu: 500m, memory: 1Gi }
    limits: { cpu: 1000m, memory: 2Gi }

  gitlab-gitaly:
    requests: { cpu: 500m, memory: 1Gi }
    limits: { cpu: 1000m, memory: 2Gi }

  registry:
    requests: { cpu: 100m, memory: 256Mi }
    limits: { cpu: 500m, memory: 512Mi }
```

**Testing:**
- Create test repository
- Test Git clone/push
- Test CI pipeline (simple test)
- Test container registry push/pull
- Verify UI responsiveness

### Phase 2: Migration (Week 2-3)

**Repository Migration:**
- Use GitLab's GitHub importer (preserves issues, PRs, comments)
- Migrate repos in batches (test → dev → prod)
- Verify all branches, tags, releases migrated
- Update repository URLs in documentation

**CI/CD Migration:**
- Rewrite GitHub Actions workflows → GitLab CI YAML
  - Syntax completely different (not 1:1 mapping)
  - Test each workflow thoroughly
  - Some Actions features may need workarounds
- Migrate secrets and variables
- Configure GitLab Runners (not ARC, different system)
- Test all pipelines end-to-end

**Container Registry:**
- Configure GitLab registry
- Migrate cached images from Docker Registry
- Update runner configs to use GitLab registry
- Test image push/pull in CI

**Team Migration:**
- Create GitLab accounts
- Set up SSH keys
- Configure personal access tokens
- Train team on new UI/CLI

### Phase 3: Decommission (Week 4)

**GitHub Cleanup:**
- Archive GitHub repositories (read-only)
- Redirect from GitHub to GitLab (README updates)
- Cancel GitHub subscriptions (if applicable)

**ARC Cleanup:**
- Decommission Actions Runner Controller (ADR 0014)
- Remove arc-systems, arc-runners namespaces
- Reclaim ~2-4GB RAM from runner pods

**Registry Cleanup:**
- Decommission old Docker Registry
- Reclaim ~100MB RAM + storage

### Monitoring

**Critical metrics:**
- GitLab web response time (< 500ms)
- Gitaly RPC latency (< 100ms)
- Sidekiq queue depth (< 1000)
- PostgreSQL connection pool usage (< 80%)
- Redis memory usage (< 80%)
- CI pipeline success rate (> 95%)
- Registry push/pull performance

**Alerts:**
- GitLab web unhealthy > 5 minutes
- Sidekiq queue growth > 1000/minute
- Gitaly storage > 80% full
- PostgreSQL connections exhausted
- Redis memory OOM risk

## Relationship to ADR 0015 (Harbor)

**If GitLab is accepted:**
- ❌ **Harbor ADR 0015 should be rejected** - GitLab's built-in registry is sufficient
- ❌ **No need for separate container registry** - GitLab includes Trivy scanning, retention policies, RBAC
- ✅ **Simpler architecture** - One less system to manage

**If GitLab is rejected:**
- ✅ **Harbor ADR 0015 remains relevant** - Provides registry improvements without platform migration
- ✅ **Incremental approach** - Solve registry problem without rewriting everything

**These ADRs are mutually exclusive.**

## When to Reconsider

**Revisit GitLab if:**

1. **Migration is failing** - Took > 6 weeks, team exhausted, consider aborting
2. **Performance unacceptable** - GitLab too slow, can't scale vertically
3. **Operational burden too high** - Frequent incidents, team can't keep up with maintenance
4. **Feature gaps discovered** - GitLab missing critical features team needs
5. **Cost exceeds GitHub** - Infrastructure + team time > GitHub subscription

**If reconsidering, options:**
- Scale back to GitHub (painful but possible)
- Evaluate Gitea/Forgejo (lighter alternative)
- Accept pain, invest in GitLab expertise

**Revert cost: ~2-3 weeks migration back** (same pain as forward migration)

## Open Questions

### For Team Discussion

1. **What is the actual ROI?**
   - GitHub annual cost: $____
   - GitLab infrastructure cost: $____ (RAM, CPU, storage)
   - Migration opportunity cost: 3-4 weeks × team cost = $____
   - Break-even timeline?

2. **What's the rollback plan?**
   - If migration fails at week 3, can we rollback?
   - How long can we run GitLab + GitHub in parallel?
   - What's the "abort criteria" (conditions to stop migration)?

3. **Who owns GitLab operations?**
   - Who debugs when GitLab breaks?
   - Who handles upgrades?
   - Who monitors performance?
   - Is there on-call for GitLab?

4. **What about ecosystem integrations?**
   - Which GitHub integrations do you rely on?
   - Do GitLab equivalents exist?
   - What breaks during migration (Dependabot, code scanning, etc)?

## Related ADRs

- ADR 0014: Actions Runner Controller (will be decommissioned if GitLab chosen)
- ADR 0015: Harbor Container Registry (will be rejected if GitLab chosen)
- ADR 0004: CloudNativePG (provides GitLab's database)
- ADR 0005: Valkey StatefulSet (provides GitLab's Redis)
- ADR 0008: cert-manager for TLS (provides GitLab's certificates)
- ADR 0010: GitOps Repository Structure (workflows will change if GitLab CI used)

## References

- [GitLab Documentation](https://docs.gitlab.com/)
- [GitLab Helm Chart](https://docs.gitlab.com/charts/)
- [GitLab vs GitHub Comparison](https://about.gitlab.com/devops-tools/github-vs-gitlab/)
- [GitLab Architecture](https://docs.gitlab.com/ee/development/architecture.html)
- [GitLab CI/CD vs GitHub Actions](https://docs.gitlab.com/ee/ci/migration/github_actions.html)
- [GitLab Installation Requirements](https://docs.gitlab.com/ee/install/requirements.html)

## Status Decision Criteria

**This ADR will be:**
- **Accepted** - If team answers questions, motivation is strong, capacity exists, and team commits
- **Rejected** - If no clear motivation, insufficient capacity, or team prefers incremental approach
- **Deferred** - If exploring but not ready to commit, revisit when pain is concrete

**DO NOT accept this ADR without answering the Critical Questions section.**
