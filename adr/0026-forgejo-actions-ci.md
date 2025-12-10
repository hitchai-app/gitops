# 0026. Forgejo Actions (Native CI/CD)

**Status**: Accepted

**Date**: 2025-12-10

**Supersedes**: ADR 0023 (Forgejo + Woodpecker CI)

## Context

ADR 0023 deployed Forgejo for Git hosting with Woodpecker CI as a separate CI/CD system. While functional, this architecture required:
- Two separate systems to maintain (Forgejo + Woodpecker)
- OAuth integration between systems
- Separate webhook configuration
- Two different configuration syntaxes (`.woodpecker.yml` vs GitHub Actions)

Forgejo now includes **Forgejo Actions** - a native, GitHub Actions-compatible CI/CD system built into Forgejo itself.

## Decision

Replace Woodpecker CI with **Forgejo Actions**.

### Why Forgejo Actions

- **Native integration**: CI/CD built into Forgejo, no separate system
- **GitHub Actions compatible**: Uses `.github/workflows/*.yml` syntax
- **Single system**: One deployment, one set of credentials, one OAuth config
- **Familiar syntax**: Team already knows GitHub Actions workflow format
- **Growing ecosystem**: Can use existing GitHub Actions from marketplace

### Runner Architecture

Deploy Forgejo Runner with DinD (Docker-in-Docker) sidecar, matching existing ARC pattern:
- Native K8s sidecar using `restartPolicy: Always`
- Privileged DinD container for container builds
- Runner auto-registers with Forgejo instance

## Alternatives Considered

| Option | Reason Not Chosen |
|--------|-------------------|
| Keep Woodpecker | Two systems to maintain, different syntax |
| Drone | Harness acquisition, license concerns (same as ADR 0023) |
| GitHub Actions | External dependency, not self-hosted |

## Consequences

**Positive**:
- Single system (Forgejo handles Git + CI/CD)
- GitHub Actions compatible syntax
- No OAuth app configuration between services
- Fewer pods (~2 vs ~4 with Woodpecker)

**Negative**:
- Forgejo Actions newer than Woodpecker (less battle-tested)
- Runner ecosystem smaller than GitHub Actions

## Implementation

- Enable Actions in Forgejo config
- Deploy Forgejo Runner with DinD sidecar
- Workflows use `.github/workflows/*.yml` (standard GitHub Actions format)

## References

- [Forgejo Actions Documentation](https://forgejo.org/docs/latest/admin/actions/)
- [Forgejo Runner Installation](https://forgejo.org/docs/latest/admin/actions/runner-installation/)
- ADR 0023: Forgejo + Woodpecker CI (Superseded)
