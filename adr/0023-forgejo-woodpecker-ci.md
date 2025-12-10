# 0023. Forgejo + Woodpecker CI

**Status**: Partially Superseded (Woodpecker replaced by Forgejo Actions - see [ADR 0026](0026-forgejo-actions-ephemeral-runners.md))

**Date**: 2025-12-04

## Context

Need lightweight Git hosting + CI/CD. GitLab (ADR 0016) deployed ~30 pods, exceeding single-node capacity.

## Decision

Deploy **Forgejo** (Git) + **Woodpecker CI** (CI/CD).

### Forgejo

- [Gitea hard fork](https://forgejo.org/2024-02-forking-forward/) (Feb 2024), created Dec 2022 after [Gitea for-profit takeover](https://lwn.net/Articles/963095/)
- Under [Codeberg e.V.](https://codeberg.org/) non-profit
- License: [GPL v3+](https://codeberg.org/forgejo/forgejo) (since Aug 2024, MIT before)

### Woodpecker CI

- [Drone 0.8 fork](https://woodpecker-ci.org/about) (2019), after Harness acquisition changed Drone license
- License: [Apache 2.0](https://github.com/woodpecker-ci/woodpecker)
- Used by [Codeberg](https://codeberg.org/) as primary CI

## Alternatives Considered

| Option | Reason Not Chosen |
|--------|-------------------|
| GitLab | ~30 pods, 8-12GB RAM |
| Gitea | For-profit governance concerns |
| Drone | Harness acquisition, license change |

## Consequences

**Positive**: ~4 pods vs ~30, simple Go binaries

**Negative**: Two systems instead of one, smaller communities

## References

- [Forgejo Helm Chart](https://code.forgejo.org/forgejo-helm/forgejo-helm)
- [Woodpecker Helm Chart](https://github.com/woodpecker-ci/helm)
- [Forgejo vs Gitea comparison](https://forgejo.org/compare-to-gitea/)
- [Woodpecker about page](https://woodpecker-ci.org/about)
- ADR 0016: GitLab (Superseded)
