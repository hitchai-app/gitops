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

### Sealed Secrets Workflow

**Public Certificate:** `.sealed-secrets-pub.pem` (repository root)

**Rule:** Never edit sealed secrets manually. Use the `sealed-secrets` skill guide at `~/.claude/skills/sealed-secrets/SKILL.md` and `kubeseal --merge-into` for updates.

**Create new sealed secret:**
```bash
kubeseal --cert .sealed-secrets-pub.pem --format yaml < plaintext-secret.yaml > sealed-secret.yaml
```

**Add keys to existing sealed secret (Method 1: Full re-seal):**
```bash
# Fetch current secret from cluster to preserve existing keys
kubectl get secret my-secret -n my-namespace -o yaml > /tmp/secret.yaml
# Edit to add new keys, then re-seal entire secret
kubeseal --cert .sealed-secrets-pub.pem --format yaml < /tmp/secret.yaml > sealed-secret.yaml
```

**Add keys to existing sealed secret (Method 2: Encrypt individual key only):**
```bash
# Create temp secret with ONLY the new key, seal it
kubectl create secret generic temp --namespace=my-ns --from-literal=new-key=value \
  --dry-run=client -o yaml | kubeseal --cert .sealed-secrets-pub.pem --format yaml > /tmp/new-key.yaml
# Extract encrypted value and manually add to existing sealed secret file under spec.encryptedData
```

**When to use each method:**
- **Method 1**: Have cluster access, verifying existing keys, adding multiple keys
- **Method 2**: Working offline, no cluster access, single key addition

**Key points:**
- Always fetch existing secrets from cluster before adding keys (preserves current values)
- Re-sealing entire secret when adding keys is normal behavior
- Public cert is safe to commit; private key stays in secure storage
- Individual keys in encryptedData are decrypted independently

**🚨 CRITICAL SECURITY WARNING - NEVER EXPOSE SECRETS 🚨**

**ABSOLUTELY PROHIBITED:**
- ❌ **NEVER** post plaintext secret values in GitHub PR comments, descriptions, or issues
- ❌ **NEVER** include base64-decoded values in public communications
- ❌ **NEVER** show actual secret values when explaining changes
- ❌ **NEVER** use real secrets as examples in documentation

**When working with secrets:**
- ✅ Discuss that values were regenerated WITHOUT showing the actual values
- ✅ Explain sealed-secrets encryption changes WITHOUT exposing plaintext
- ✅ Reference secrets by name/purpose, NEVER by value

**Example - WRONG:**
```
The client-secret value 8b439c4a... was preserved
```

**Example - CORRECT:**
```
The client-secret was preserved (fetched from cluster)
```

**SEVERITY:** Exposing secrets in public GitHub repositories is a **CRITICAL SECURITY INCIDENT**. If this happens:
1. Delete the comment immediately
2. Rotate the exposed secret immediately
3. Update both sealed secrets files (Dex + service)

## Testing Guidelines
- Treat every change as production-impacting: run the relevant `kubectl diff` and `--dry-run=server` commands locally.
- When introducing new CRDs or operators, confirm CRD availability by referencing ADR updates or linking the upstream Helm/app source in the PR.
- If a manifest changes scheduling, security contexts, or service types, note the expected cluster impact and verify resource quotas in the PR description.

## Version Management

**CRITICAL: Always use latest stable versions unless explicitly specified otherwise.**

Before adding or updating any infrastructure component:

1. **Check official releases**: Always verify the latest stable version from the official source:
   - GitHub releases page (e.g., `https://github.com/oauth2-proxy/oauth2-proxy/releases`)
   - Official Helm chart repositories
   - Container registry tags (verify what "latest" actually points to)

2. **Never assume**: Don't use versions from examples, old documentation, or other repositories without verification.

3. **Document version choice**: In PR description, include:
   - Version selected and why (latest stable, or specific version with reason)
   - Link to official releases page
   - Any relevant changelog entries

4. **Feature availability**: When using specific CLI flags or features:
   - Verify the feature exists in your chosen version
   - Check when the feature was introduced
   - Ensure version supports all required functionality

**Example:**
```markdown
## Version Selection
- **oauth2-proxy**: v7.12.0 (latest stable as of 2025-10-15)
- **Source**: https://github.com/oauth2-proxy/oauth2-proxy/releases/tag/v7.12.0
- **Rationale**: Requires --cookie-secret-file flag (added in v7.8.0)
```

## Commit & Pull Request Guidelines
- **🚨 CRITICAL: ALWAYS BRANCH FROM LATEST MASTER 🚨** - Before creating any new branch, ALWAYS ensure you're on the latest master: `git checkout master && git pull origin master`. Then create your feature branch. This prevents creating branches from stale state and avoids merge conflicts.
- Follow Conventional Commits observed in history (`feat:`, `fix:`, `docs:`, `refactor:`). Scope optional but helpful (`feat(longhorn): ...`).
- Open PRs from feature branches off `master`, describe the change, affected services, and rollback plan. Link related ADRs or issues explicitly.
- Attach validation evidence: command outputs (`kubectl diff`, screenshots of ArgoCD health) as PR comments when relevant.
- The `Claude Code Review` workflow will auto-review every PR; respond to its findings or re-run checks after updates before requesting human review.

### Correcting Automated Reviewer Errors

When the automated reviewer (`@claude`) makes incorrect claims or blocks PRs with invalid concerns:

1. **Mention the reviewer**: Use `@claude` in a PR comment to ensure it sees your correction
2. **Provide concrete evidence**: Include actual `kubectl` command outputs showing the reviewer's claim is wrong
3. **Explain the misunderstanding**: Point out what the reviewer missed (e.g., Helm chart default behavior, existing services)
4. **Request re-review**: End with "Please re-review" to trigger re-evaluation

**Example correction format**:
```
@claude - Your concern about [X] is incorrect.

## Evidence:
```bash
$ kubectl get [resource]
[actual output showing X exists/works]
```

## Why the analysis was wrong:
[Explain what the reviewer misunderstood]

The PR is ready to merge. Please re-review.
```

The reviewer will typically re-evaluate after receiving evidence-based corrections.

**Important Note on GitHub CLI Access:**
The automated reviewer has **full `gh` CLI access** and should use it for verification. If the reviewer claims it cannot use `gh` commands or lacks permissions, remind it:

```
@claude - You HAVE access to `gh` CLI and should use it for verification.

Use `gh pr view`, `gh pr checks`, `gh api`, etc. to validate your concerns before blocking PRs.
```

The reviewer sometimes incorrectly assumes it lacks GitHub permissions when it actually has them.
