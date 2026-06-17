# 0048. GitLab Container Registry Retention Strategy

**Status**: Accepted

**Date**: 2026-06-17

## Context

The GitLab container registry (CE 18.7.0 via chart 9.7.0, GitLab Operator;
blobs stored in the external MinIO SNSD tenant, 50 GiB Longhorn single-replica)
reached 89% capacity (43/44 GiB). An offline GC dry-run reclaimed only ~4 GiB;
~39 GiB was *referenced* and dominated by kaniko build-cache repositories pushed
as siblings of app-image repos inside each source project.

Key facts established during investigation:

- **kaniko `--cache-ttl=24h` never deletes registry blobs** — it only makes
  kaniko *ignore* stale cache. Cache layers accumulate indefinitely.
- **App images are deployed by immutable 8-hex commit SHA** (kustomize
  `images[].newTag` in envs overlays; CI bumps the SHA). There is no semver or
  `release-*` convention, so a deployed SHA is indistinguishable by name from a
  throwaway build.
- **GitLab cleanup policies are per-project, applied per container-repository,
  with a single `keep_n` and match tag *names* only** (`keep_n ∈ {1,5,10,…}`,
  `latest` always kept, expiry by tag **push-age**, not last-pull). They cannot
  express "keep N of main, keep 1 of feature" in one policy, and a `keep_n`
  policy on a bare-SHA image repo can evict a still-deployed SHA.
- The registry **metadata database** (online GC, zero-downtime) and **protected
  container tags** are GA on 18.7.
- The MinIO operator is archived *upstream* but **still running in-cluster**
  (v5.0.17); its storage backend and its own continued maintenance are a
  separate risk (see Consequences).

## Decision

Treat images and build cache **asymmetrically**, separated at the GitLab
data-model level, and reclaim disk via **online GC** rather than recurring
manual offline GC.

1. **Build cache → dedicated `ci/kaniko-cache` project.** Repoint kaniko
   `--cache-repo` there; authenticate cross-project with a single group deploy
   token (read/write registry) inherited by all source repos. Cleanup policy on
   that project (keep newest few, expire ~7d). Because the project holds only
   cache, a match-all policy is safe. Push-age 7d ≈ "unused 7d" given kaniko's
   24h TTL re-pushes live cache.

2. **Images persist as immutable SHA tags and rotate to a bounded rollback
   set.** App projects carry no count/age policy that could evict a live SHA.
   The current + recent releases are guaranteed by **protected container tags**
   (on the SHA pattern) plus rotating `release-1/2/3` anchors re-tagged on prod
   deploy; older unprotected SHAs rotate out. Feature/preview images keep only
   the latest (separate preview project or on-stop registry deletion at MR
   close). `:latest` is **not** used to pin or protect prod — deploys already
   pin immutable SHAs, and `:latest` would protect only one image while
   reintroducing mutability.

3. **Reclamation = registry metadata database + online GC.** Online GC reclaims
   unreferenced blobs continuously with no read-only window. Offline GC is
   retired (and becomes unsafe — data loss — once the metadata DB is enabled).

4. **Capacity buffer expanded the GitOps way.** Grow the MinIO data PVC
   50→100 GiB via a Git-managed PVC manifest applied with Server-Side Apply
   (Longhorn online resize). The Tenant `volumeClaimTemplate` is left untouched
   because the operator treats a template size change as pool expansion
   (StatefulSet delete+recreate → downtime + data-loss risk).

## Alternatives Considered

1. **Per-project cleanup policy on app projects** — rejected: one `keep_n` per
   repo + bare-SHA tags means it cannot separate cache from images or protect a
   deployed SHA from eviction.
2. **`:latest`-tag prod images for protection** — rejected: protects only one
   image (not the rollback set), and adds mutability the SHA-pinned deploys do
   not currently have.
3. **Direct `kubectl patch` of the PVC** — rejected: not GitOps; intent lives
   outside Git.
4. **Bump the Tenant `volumeClaimTemplate`** — rejected: triggers operator pool
   expansion (StatefulSet recreate, downtime, data-loss risk).
5. **Tier-1 (no metadata DB) with scheduled offline GC** — viable and meets the
   requirements, but keeps a recurring read-only GC window; superseded by the
   metadata-DB end state, which the operator wants automated.

## Consequences

### Positive
- Deployed image SHAs are never at risk: no policy touches app projects; the
  rollback set is guaranteed by protected tags, not by fragile push-age rules.
- Cache cleanup is safe and uniform in a cache-only project; the dominant
  consumer (build cache) is reclaimed and stops accumulating.
- Online GC removes the manual read-only GC chore entirely.
- Drive expansion is declarative and zero-downtime.

### Negative
- Cache expiry keys on push-age, not last-pull (accepted; bounded by kaniko's
  24h TTL).
- Enabling the metadata DB is effectively irreversible after activation
  (mitigated by the three-step import with read-only only in step two and a
  CNPG snapshot taken immediately before the flip). Offline GC must never run
  afterward.
- Per-project policies and protected tags live in GitLab (API/UI), not this
  repo — they are configuration outside GitOps reconciliation.

### Neutral
- Existing stale sibling cache (~35 GiB) is reclaimed automatically by online GC
  once the cache tags are unlinked.
- The registry's object store runs on an archived MinIO operator (v5.0.17) with
  a pre-archival server image. This is a latent security/maintenance risk now
  that the cluster is client-facing and fires ADR 0006's "revisit when MinIO
  operator maintenance becomes untenable" trigger. Migrating object storage
  (e.g. to SeaweedFS) is tracked as a separate workstream/ADR.

## Implementation Phasing

- **Phase 0 (this ADR):** expand the MinIO data PVC to 100 GiB via SSA
  (`workloads/gitlab/minio/pvc-data.yaml`).
- **Phase 1:** enable the registry metadata database + online GC (pre-create a
  CNPG `registry` database and role; three-step import; `parallelwalk: false`).
- **Phase 2:** create `ci/kaniko-cache` + group deploy token + cleanup policy;
  repoint kaniko `--cache-repo` in each source repo's `.gitlab-ci.yml`; add
  protected container tags and `release-N` rotation to prod-deploy CI; wire
  preview-image cleanup.

## References
- ADR 0004 (CloudNativePG), ADR 0006 (MinIO Operator Single-Drive), ADR 0009
  (Secrets Management)
- [GitLab cleanup policies](https://docs.gitlab.com/user/packages/container_registry/reduce_container_registry_storage/)
- [GitLab protected container tags](https://docs.gitlab.com/user/packages/container_registry/protected_container_tags/)
- [GitLab registry metadata database](https://docs.gitlab.com/charts/charts/registry/metadata_database/)
- [MinIO operator expansion](https://github.com/minio/operator/blob/master/docs/expansion.md)
- [Kubernetes PVC expansion](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#expanding-persistent-volumes-claims)
- gitlab-org/gitlab#196118 (no per-repository cleanup policy)
