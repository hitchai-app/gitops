# Repository Guidelines

For architectural context and onboarding narrative, read [`CLAUDE.md`](CLAUDE.md).

## Project Structure & Module Organization
- `bootstrap/` holds one-time manifests you run manually to prime a new cluster (ArgoCD install, Sealed Secrets key). Keep this directory immutable by ArgoCD.
- `apps/` defines the ArgoCD app-of-apps entry points. `apps/infrastructure.yaml` must always reflect the canonical list of platform services before workloads.
- `infrastructure/` contains the Kustomize bases that ArgoCD syncs. Group resources by service (`longhorn/`, `argocd/`, `metallb/`) and keep overlays self-contained with `kustomization.yaml`.
- `adr/` captures architectural decisions. Open a new ADR when a change alters operational posture or contradicts an accepted record.

## Build, Test, and Development Commands
- `kubectl apply -f apps/infrastructure.yaml` bootstraps or updates the platform app-of-apps. Run from a context with admin privileges.
- `kubectl diff -k infrastructure/longhorn` previews rendered changes against the cluster; swap the path for any service directory.
- `kustomize build infrastructure/argocd` renders manifests locally for linting or PR review.
- `kubectl apply --dry-run=server -k <path>` validates API compatibility without mutating the cluster; use before every PR.

## Coding Style & Naming Conventions
- Indent YAML with two spaces and keep document order consistent: `apiVersion`, `kind`, `metadata`, then `spec`.
- File names and resource identifiers use lower-hyphen case (e.g., `longhorn-storageclasses.yaml`, `secrets-management-strategy`).
- Prefer declarative patches (Kustomize `patchesStrategicMerge` or `patchesJson6902`) over imperative edits; document rationale in inline comments only when the manifest is non-obvious.
- Secrets land in Sealed Secrets (`*-sealed.yaml`); never commit plaintext credentials.

## Testing Guidelines
- Treat every change as production-impacting: run the relevant `kubectl diff` and `--dry-run=server` commands locally.
- When introducing new CRDs or operators, confirm CRD availability by referencing ADR updates or linking the upstream Helm/app source in the PR.
- If a manifest changes scheduling, security contexts, or service types, note the expected cluster impact and verify resource quotas in the PR description.

## Commit & Pull Request Guidelines
- Follow Conventional Commits observed in history (`feat:`, `fix:`, `docs:`, `refactor:`). Scope optional but helpful (`feat(longhorn): ...`).
- Open PRs from feature branches off `master`, describe the change, affected services, and rollback plan. Link related ADRs or issues explicitly.
- Attach validation evidence: command outputs (`kubectl diff`, screenshots of ArgoCD health) as PR comments when relevant.
- The `Claude Code Review` workflow will auto-review every PR; respond to its findings or re-run checks after updates before requesting human review.
