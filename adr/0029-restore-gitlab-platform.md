# 0029. Restore GitLab Platform

**Status**: Accepted

**Date**: 2025-12-20

## Context

Forgejo + Actions covers lightweight Git hosting and CI, but several workflows require GitLab-specific features (integrated registry, security scans, advanced CI templates, and tighter integration with existing GitLab tooling). We need to restore a full GitLab deployment while retaining the lightweight stack where it is sufficient.

Operator experience also surfaced gaps that add friction in day-to-day use:

- **Actions compatibility is limited**: Forgejo Actions is designed for *familiarity*, not full GitHub Actions compatibility, and some workflow keys and behaviors differ or are unsupported. This increases migration and maintenance effort for existing workflows.  
  - See: Forgejo Actions “familiarity instead of compatibility” and known differences.  
- **Runner performance tuning is non-trivial**: Forgejo runner caching can *slow down* builds on slower disks; community users report slow builds and caching issues that are hard to resolve quickly.  
  - See: Forgejo runner cache guidance and user reports of slow builds.  
- **CLI ergonomics are limited**: Forgejo’s documented CLI focuses on server/admin operations, while the main end‑user CLI is Gitea’s `tea`, not Forgejo‑specific. This leaves a tooling gap compared to GitLab’s mature user CLI and API ecosystem.  
  - See: Forgejo CLI docs and Gitea Tea CLI overview.

## Decision

Reintroduce **GitLab** using the GitLab Operator and externalized dependencies:

- GitLab Operator manages the GitLab custom resource
- CloudNativePG provides PostgreSQL
- Valkey (SAP operator) provides Redis-compatible cache/session storage
- MinIO provides S3-compatible object storage

Forgejo remains available for lightweight use cases; GitLab is the system of record for workflows that require its feature set.

## Alternatives Considered

| Option | Reason Not Chosen |
| --- | --- |
| Keep Forgejo only | Missing GitLab-specific features and existing workflow compatibility |
| Hosted GitLab | Reduces control and increases recurring cost |
| GitHub-only | Continued vendor lock-in and no self-hosted registry/security stack |

## Consequences

**Positive**: Full GitLab feature set restored; better compatibility with existing workflows.

**Negative**: Increased resource footprint and operational overhead compared to Forgejo-only.

## References

- [GitLab Operator](https://docs.gitlab.com/charts/installation/gitlab_operator.html)
- [GitLab Helm Chart](https://docs.gitlab.com/charts/)
- ADR 0023: Forgejo + Woodpecker CI
- [Forgejo Actions: GitHub Actions differences](https://forgejo.org/docs/v12.0/user/actions/github-actions/)
- [Forgejo Actions overview](https://forgejo.org/docs/latest/user/actions/overview/)
- [Forgejo Runner installation guide (cache notes)](https://forgejo.org/docs/v11.0/admin/actions/runner-installation/)
- [Forgejo CLI (admin/server focus)](https://forgejo.org/docs/latest/admin/command-line/)
- [Gitea Tea CLI (official end‑user CLI for Gitea)](https://about.gitea.com/products/tea/)
- [Community report: slow Forgejo/Gitea Actions builds](https://www.reddit.com/r/NixOS/comments/1bpaml5/how_to_speed_up_slow_builds_using_forgejo_gitea_actions/)
