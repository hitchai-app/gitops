# 0029. Restore GitLab Platform

**Status**: Accepted

**Date**: 2025-12-20

## Context

Forgejo + Actions covers lightweight Git hosting and CI, but several workflows require GitLab-specific features (integrated registry, security scans, advanced CI templates, and tighter integration with existing GitLab tooling). We need to restore a full GitLab deployment while retaining the lightweight stack where it is sufficient.

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
