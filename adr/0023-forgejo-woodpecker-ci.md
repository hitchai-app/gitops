# 0023. Forgejo + Woodpecker CI

**Status**: Accepted

**Date**: 2025-12-04

## Context

We need self-hosted Git hosting and CI/CD for:
- Code mirroring from GitHub (backup, vendor lock-in mitigation)
- Self-hosted CI/CD runners with cluster access
- Container registry (optional)

Previous attempt: GitLab (ADR 0016) deployed ~30 pods requiring 8-12GB RAM. Combined with Sentry's 57 pods, exceeded single-node capacity (110 pod limit).

Team context:
- Small development team
- Primary code on GitHub (continue using GitHub Actions)
- Single Hetzner node (12 CPU / 128GB RAM / 110 pod limit)
- Need lightweight self-hosted option

## Decision

Deploy **Forgejo** (Git hosting) + **Woodpecker CI** as lightweight alternatives to GitLab.

**Forgejo** (community-governed Gitea fork):
- ~2 pods (web + optional runner)
- ~500MB-1GB RAM
- Git hosting, issue tracking, wiki, container registry

**Woodpecker CI** (container-native CI):
- ~2 pods (server + agent)
- ~256MB RAM
- YAML-based pipelines, native Docker/Kubernetes support

### Comparison

| Aspect | GitLab | Forgejo + Woodpecker |
|--------|--------|---------------------|
| Pods | ~30 | ~4 |
| RAM | 8-12GB | ~1.5GB |
| Features | Full platform | Essential features |
| Complexity | High | Low |

## Alternatives Considered

### 1. GitLab (ADR 0016)
- **Pros**: Full-featured platform, unified UI, mature
- **Cons**: ~30 pods, 8-12GB RAM, complex operations
- **Why not chosen**: Too heavy for single-node cluster

### 2. Gitea (without Forgejo)
- **Pros**: Lightweight, Go binary, active development
- **Cons**: For-profit governance concerns, less community-driven
- **Why not chosen**: Forgejo offers community governance and same features

### 3. GitHub Actions Only (no self-hosted Git)
- **Pros**: Zero overhead, familiar workflow
- **Cons**: No self-hosted backup, vendor lock-in
- **Why not chosen**: Want self-hosted option for independence

### 4. Drone CI
- **Pros**: Similar to Woodpecker, more mature
- **Cons**: Harness acquisition, licensing concerns
- **Why not chosen**: Woodpecker is community-governed fork with same architecture

## Consequences

### Positive
- ~4 pods vs ~30 pods (87% reduction from GitLab)
- ~1.5GB RAM vs 8-12GB RAM
- Simple operations (Go binaries, minimal dependencies)
- Community-governed (Forgejo = Gitea fork, Woodpecker = Drone fork)
- Kubernetes-native CI (Woodpecker agent runs pipelines as pods)
- Container registry included in Forgejo
- GitHub mirroring supported

### Negative
- Two systems instead of one (Git + CI separate)
- Smaller communities than GitLab
- Fewer features (no built-in security scanning, project management)
- Less enterprise polish

### Neutral
- Continue using GitHub as primary (Forgejo for backup/mirror)
- Can use Woodpecker OR GitHub Actions (not mutually exclusive)
- MIT licensed (both projects)

## Implementation

### Architecture

```
Internet -> Traefik -> Forgejo Web
                           |
                           v
                      PostgreSQL (CloudNativePG)

Internet -> Traefik -> Woodpecker Server -> Woodpecker Agent
                           |                    |
                           v                    v
                      PostgreSQL           Kubernetes API
                                          (runs CI pods)
```

### Namespaces

- `forgejo-system` - Git hosting
- `woodpecker-system` - CI/CD

### Components

**Forgejo:**
- Forgejo Web (UI + Git server)
- PostgreSQL (CloudNativePG)
- Optional: Redis/Valkey for caching

**Woodpecker:**
- Woodpecker Server (UI + API)
- Woodpecker Agent (runs pipelines)
- PostgreSQL (CloudNativePG, can share with Forgejo)

### Resource Allocation

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Forgejo | 200m | 512Mi | 10Gi |
| Forgejo PostgreSQL | 250m | 512Mi | 10Gi |
| Woodpecker Server | 100m | 256Mi | - |
| Woodpecker Agent | 100m | 256Mi | - |
| **Total** | ~650m | ~1.5Gi | ~20Gi |

### OAuth Integration

Both Forgejo and Woodpecker support OAuth2/OIDC:
- Forgejo: Native OAuth2 provider + Dex consumer
- Woodpecker: OAuth via Forgejo or GitHub

### GitHub Mirroring

Forgejo supports repository mirroring:
- Pull mirrors: Sync from GitHub to Forgejo (backup)
- Push mirrors: Sync from Forgejo to GitHub (primary)

## When to Reconsider

**Upgrade to GitLab if:**
1. Multi-node cluster with sufficient capacity (>10 nodes)
2. Need advanced features (security scanning, project management)
3. Team grows beyond 20 developers
4. Compliance requires unified audit trail

**Stay with GitHub only if:**
1. Self-hosting becomes burdensome
2. Team satisfied with vendor lock-in trade-off

## References

- [Forgejo Documentation](https://forgejo.org/docs/)
- [Forgejo Helm Chart](https://code.forgejo.org/forgejo-helm/forgejo-helm)
- [Woodpecker CI Documentation](https://woodpecker-ci.org/docs/)
- [Woodpecker Helm Chart](https://github.com/woodpecker-ci/helm)
- ADR 0004: CloudNativePG for PostgreSQL
- ADR 0014: Actions Runner Controller (remains for GitHub Actions)
- ADR 0016: GitLab Platform Migration (Superseded)
