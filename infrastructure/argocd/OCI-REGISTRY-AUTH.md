# ArgoCD OCI Registry Authentication

This document explains how ArgoCD matches credentials to OCI Helm repositories to prevent configuration mistakes.

Default posture (October 2025) is **anonymous access**: we no longer publish a `ghcr-helm-repo` Sealed Secret because the public `actions` organisation charts sync fine without credentials, while injecting an unrelated PAT breaks reconciliation.

## How ArgoCD Matches OCI Credentials

ArgoCD uses **PREFIX matching** to find credentials for OCI Helm charts:

1. Application declares: `repoURL: oci://ghcr.io/actions/actions-runner-controller-charts`
2. ArgoCD strips the `oci://` prefix: `ghcr.io/actions/actions-runner-controller-charts`
3. Searches for repository secrets where `url` is a **prefix** of the stripped URL
4. Uses the matching credentials

## When You Need Credentials

Most public charts (including ARC) can be pulled without authentication. Only add a repository secret when you actually need private access. The Application source always uses the full chart path:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  sources:
  - chart: gha-runner-scale-set-controller
    repoURL: oci://ghcr.io/actions/actions-runner-controller-charts  # ✅ FULL PATH
    targetRevision: 0.12.1
```

## Common Mistakes

### ❌ WRONG: Secret that Matches Too Much

```yaml
stringData:  # Secret exists at base domain
  url: ghcr.io
```

**Why it fails for public charts:** A PAT tied to another organisation (for example `hitchai-app`) becomes the default credential for **every** `ghcr.io/*` request. GHCR rejects that token when ArgoCD reaches into the `actions` org, so syncs fail with `response status code 403`.

### ❌ WRONG: Base Domain in Application

```yaml
spec:
  sources:
  - repoURL: oci://ghcr.io  # ❌ MISSING CHART PATH
```

**Why it fails:** Application needs the full chart path to know which OCI artifact to pull.

## Why This Matters

Credential scope is determined purely by prefix matching. If you need private charts for `ghcr.io/hitchai-app/*` **and** public charts for `ghcr.io/actions/*`, create narrowly scoped secrets:

```yaml
stringData:
  url: ghcr.io/hitchai-app         # applies only to our org
  username: hitchai-app
  password: <pat-with-read:packages>
```

No secret that matches `ghcr.io/actions/...` ⇒ ArgoCD talks anonymously to the public repo.

## Historical Context

**October 2025 Incident:** A base-domain secret (`url: ghcr.io`) bundled a PAT from the `hitchai-app` org. GHCR treated the token as unapproved for `actions/*` and returned 403, so ArgoCD couldn’t render ARC charts. The fix was to drop the secret entirely and rely on anonymous pulls; future private access must use tighter prefixes.

## References

- [ArgoCD OCI Documentation](https://argo-cd.readthedocs.io/en/latest/user-guide/oci/) (Official)
- [ArgoCD Private Repositories](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/) (Official)
- [How to configure ArgoCD to connect to a Private OCI Repository](https://blog.devops.dev/how-to-configure-argocd-to-connect-to-a-private-oci-repository-ft-dockerhub-b92fc0ead60d) (January 2025)

## Key Takeaways

- Add an OCI repository secret only when private access is required.
- Choose the narrowest `url` prefix that still covers the private charts you need.
- Public charts (such as ARC from the `actions` org) should sync without credentials, so deleting the secret is the safest default.
