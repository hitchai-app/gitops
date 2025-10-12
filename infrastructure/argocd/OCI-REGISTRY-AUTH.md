# ArgoCD OCI Registry Authentication

This document explains how ArgoCD matches credentials to OCI Helm repositories to prevent configuration mistakes.

## How ArgoCD Matches OCI Credentials

ArgoCD uses **PREFIX matching** to find credentials for OCI Helm charts:

1. Application declares: `repoURL: oci://ghcr.io/actions/actions-runner-controller-charts`
2. ArgoCD strips the `oci://` prefix: `ghcr.io/actions/actions-runner-controller-charts`
3. Searches for repository secrets where `url` is a **prefix** of the stripped URL
4. Uses the matching credentials

## Correct Configuration

### ✅ Repository Secret (Base Domain)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ghcr-helm-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  name: github-container-registry
  url: ghcr.io                    # ✅ BASE DOMAIN ONLY
  type: helm
  enableOCI: "true"
  username: <github-username>
  password: <github-pat>
```

### ✅ Application (Full Path)

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

### ❌ WRONG: Full Path in Secret

```yaml
stringData:
  url: ghcr.io/actions/actions-runner-controller-charts  # ❌ TOO SPECIFIC
```

**Why it fails:** The secret URL is NOT a prefix of itself during matching - ArgoCD's prefix logic expects base domains.

### ❌ WRONG: Base Domain in Application

```yaml
spec:
  sources:
  - repoURL: oci://ghcr.io  # ❌ MISSING CHART PATH
```

**Why it fails:** Application needs the full chart path to know which OCI artifact to pull.

## Why This Matters

Using base domain (`ghcr.io`) in the secret allows **one credential to authenticate ALL charts** from that registry:

- ✅ `oci://ghcr.io/actions/actions-runner-controller-charts/...`
- ✅ `oci://ghcr.io/other-org/other-chart`
- ✅ Any chart from `ghcr.io`

Using full path in the secret would require **separate credentials for each chart** - defeating the purpose of registry credentials.

## Historical Context

**October 2025 Incident:**

1. ✅ Original secret correctly used `url: ghcr.io`
2. ❌ PR #54 "fixed" it to `url: ghcr.io/actions/actions-runner-controller-charts` (WRONG)
3. ❌ PR #55 propagated the wrong format to the correct location
4. 🔄 This PR reverts to the correct base domain format

**Root cause of confusion:** Misinterpreted "full path" examples that applied to Application manifests, not secret configuration.

## References

- [ArgoCD OCI Documentation](https://argo-cd.readthedocs.io/en/latest/user-guide/oci/) (Official)
- [ArgoCD Private Repositories](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/) (Official)
- [How to configure ArgoCD to connect to a Private OCI Repository](https://blog.devops.dev/how-to-configure-argocd-to-connect-to-a-private-oci-repository-ft-dockerhub-b92fc0ead60d) (January 2025)

## Testing Credentials

To verify credentials work:

```bash
# 1. Check secret exists with correct label
kubectl get secret ghcr-helm-repo -n argocd -o jsonpath='{.metadata.labels}'

# 2. Test with helm CLI (validates credentials are correct)
helm registry login ghcr.io -u <username> --password-stdin <<< "<password>"
helm pull oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller --version 0.12.1

# 3. Refresh ArgoCD Application
kubectl patch application arc-controller -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

## Key Takeaway

**Repository secret `url` = Registry base domain (e.g., `ghcr.io`)**
**Application `repoURL` = Full OCI chart path (e.g., `oci://ghcr.io/org/chart`)**

This is the official ArgoCD pattern for OCI registry authentication.
