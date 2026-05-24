# 0047. YouTrack for Task Tracking

**Status**: Accepted

**Date**: 2026-05-24

## Context

We need a task tracker for weekly sprint planning (personal) and shared projects with collaborators. GitLab is already the source of truth for code, and we want to keep using it — this is purely for issue/sprint management.

Constraints:
- UX matters more than feature breadth — daily-use tool
- Must integrate with self-hosted GitLab (`gitlab.ops.last-try.org`, CE edition)
- Authenticate via existing Dex OIDC (ADR 0018) — no separate identity store
- Sprint cadence support (we plan weekly)
- Reasonable footprint on a small cluster
- Self-hosted; data stays on our infrastructure

GitLab CE does not provide Iterations (sprint cadence) — only Milestones, which lack auto-rollover. Upgrading to GitLab Premium for Iterations alone (~$29/user/month) is not justified for personal use.

## Decision

Deploy **YouTrack Server** as a single-pod StatefulSet using the official `jetbrains/youtrack` Docker image, behind Traefik with cert-manager TLS, authenticating against Dex via OIDC.

Storage: four separate Longhorn PVCs (data, conf, logs, backups) on the `single-replica` StorageClass. Database: embedded (HSQL) — adequate for personal scale, externalization to CNPG deferred to a follow-up if needed.

Licensing: free tier for up to 10 users, perpetual. If we cross 10 users, a 15-user pack is ~$600 first year then $300/year renewal.

## Alternatives Considered

### Plane Enterprise (free tier) + Dex
- **Pros**: OIDC works natively, dashboards, epics, full feature parity with paid tiers
- **Cons**: ~25 pods (web, api, worker, beat-worker, live, space, admin, silo, outbox-poller, automation-consumer, runner, email, iframely, pi-* services, plus bundled postgres/redis/rabbitmq/minio/opensearch). Closed-source images. Free tier capped at 12 users.
- **Why not**: Infrastructure overhead unjustifiable for the user count. OpenSearch alone is 1-2 GB RAM baseline.

### Plane CE + GitLab OAuth
- **Pros**: OSS (AGPLv3), modern UX with cycles for sprints, ~7 pods
- **Cons**: No OIDC support (Pro/Business only) — would bypass Dex and use GitLab social login directly. No dashboards, epics, or templates. CE chart hasn't been updated since November 2024.
- **Why not**: Skipping Dex for a single app fragments auth strategy. Chart stagnation is a long-term concern.

### Huly
- **Pros**: Modern UX
- **Cons**: No GitLab integration as of mid-2026 (GitHub-only); feature request open since 2024.
- **Why not**: Disqualified by GitLab requirement.

### OpenProject Community Edition
- **Pros**: Unlimited free users, very mature, official GitLab integration, has Jira migrator
- **Cons**: UX is enterprise-dated — fails the primary criterion
- **Why not**: UX gap is the explicit deal-breaker.

### Taiga
- **Pros**: OSS, modern-ish UX, good Scrum support
- **Cons**: GitLab integration is webhook-only (one-way), no MCP
- **Why not**: Weak GitLab story.

### Redmine
- **Pros**: Boring-reliable, mature
- **Cons**: UX from 2010, sprint support via plugins only, weak GitLab integration
- **Why not**: UX disqualifies.

### Jetbrains "twenty20" community Helm chart for YouTrack
- **Pros**: Pre-built, JetBrains-endorsed partner
- **Cons**: Third-party chart, less control, adds dependency on the maintainer's release cadence
- **Why not**: Single-pod StatefulSet is six files we own; not worth the indirection.

## Consequences

### Positive
- ~2 pods (YouTrack + Dex client wiring) vs ~25 for Plane Enterprise
- Free up to 10 users; bounded cost above that ($300–600/yr — bounded by user packs, not per-user SaaS)
- Mature product (since 2008), stable APIs, JS workflow engine for automation
- Native OIDC with Dex
- GitLab integration is first-class (commit/MR linking via issue ID references in commits)
- Best-in-class UX for the category

### Negative
- Proprietary closed-source software
- 10-user free-tier cliff (paid user packs start at 15)
- OIDC config is UI-only (not GitOps-declarative) — same as most apps' first-time auth setup
- Single-node by design (no native HA), but our cluster has none for this tier anyway
- Embedded HSQL database — no PITR, backups are file-based via Longhorn S3 (ADR 0002)

### Neutral
- License is perpetual with 1 year of upgrades; renewal is 50% of new license price
- Data export via REST API enables migration to other trackers if needed (1-3 days of scripting effort for thousands of issues)

## Implementation Notes

- **Image**: pin to specific build tag (e.g., `jetbrains/youtrack:2026.1.12351`); do not use `latest`
- **Storage**: 4 PVCs on `single-replica` (ADR 0007) — data 20Gi, conf 1Gi, logs 5Gi, backups 30Gi
- **Resources**: JVM-based; request 1Gi/500m, limit 3Gi/2 CPU
- **Auth**: register YouTrack as a Dex static client; configure OIDC Auth Module in YouTrack UI after first deploy
- **First-run**: one-time setup token printed to pod logs — operator pastes it into setup wizard at first visit
- **Backups**: Longhorn snapshot to S3 (ADR 0002) covers all PVCs; YouTrack's own scheduled backup writes to the `backups` PVC

## When to Reconsider

- User count grows past ~15–25 and license cost becomes meaningful relative to alternatives
- JetBrains changes licensing terms unfavorably
- Plane CE or another OSS option becomes feature-competitive on sprints + UX + OIDC
- We need HA for the tracker (YouTrack Server is single-node by design)

## References

- [YouTrack Server documentation](https://www.jetbrains.com/help/youtrack/server/get-started-with-youtrack-server.html)
- [Deploy YouTrack with Kubernetes (official)](https://www.jetbrains.com/help/youtrack/server/deploy-youtrack-kubernetes.html)
- [OpenID Connect Auth Module](https://www.jetbrains.com/help/youtrack/server/openid-connect-authentication-module.html)
- [YouTrack Server pricing](https://www.jetbrains.com/youtrack/buy/)
- ADR 0007: Longhorn StorageClass Strategy
- ADR 0018: Dex Authentication Provider
