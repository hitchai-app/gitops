# Migration Guide: ARC Runners to GitOps

This guide covers migrating the existing manually-installed ARC runners to GitOps management.

## Current State

- **Controller**: Installed manually via Helm (`arc` release in `arc-systems`)
- **Runner Scale Set**: Installed manually via Helm (`hitchai-app-runners` in `arc-runners`)
- **Authentication**: GitHub token stored as Kubernetes secret

## Target State

- **Controller**: Managed by ArgoCD via `apps/infrastructure/arc-controller.yaml`
- **Runner Scale Set**: Managed by ArgoCD via `apps/infrastructure/arc-runners.yaml`
- **Authentication**: Sealed Secret in Git

## Prerequisites

Before starting:
1. Fetch sealed-secrets public certificate:
   ```bash
   kubeseal --fetch-cert > sealed-secrets-pub.pem
   ```

2. Extract current GitHub token (if you don't have it):
   ```bash
   # This requires cluster admin access
   kubectl get secret hitchai-app-github-token -n arc-runners -o jsonpath='{.data.github_token}' | base64 -d
   ```

## Migration Steps

### Step 1: Create Sealed Secret

```bash
# 1. Create plain secret (use your actual GitHub PAT)
kubectl create secret generic hitchai-app-github-token \
  --namespace=arc-runners \
  --from-literal=github_token=YOUR_GITHUB_PAT_HERE \
  --dry-run=client -o yaml > /tmp/github-token.yaml

# 2. Seal it
kubeseal --format=yaml --cert=sealed-secrets-pub.pem \
  < /tmp/github-token.yaml > infrastructure/arc-runners/hitchai-app/github-token-sealed.yaml

# 3. Clean up plain secret
rm /tmp/github-token.yaml

# 4. Verify sealed secret was created
cat infrastructure/arc-runners/hitchai-app/github-token-sealed.yaml
```

### Step 2: Commit and Push GitOps Manifests

```bash
# Stage all new files
git add apps/infrastructure/arc-controller.yaml
git add apps/infrastructure/arc-runners.yaml
git add infrastructure/arc-controller/
git add infrastructure/arc-runners/
git add adr/0014-actions-runner-controller-for-github-actions.md

# Commit
git commit -m "feat(ci): migrate ARC runners to GitOps management

- Add ARC controller GitOps manifests
- Add hitchai-app runner scale set configuration
- Add sealed secret for GitHub authentication
- Document decision in ADR 0014

Refs: ADR 0014"

# Push
git push origin feat/arc-runners-gitops
```

### Step 3: Create Pull Request

Create a PR with the changes. The PR should:
- Show all new files
- Include ADR 0014 for review
- Pass any CI checks

### Step 4: Apply ArgoCD Applications (After PR Merge)

**Option A: Smooth Adoption (Recommended)**

This approach adopts existing resources without recreation:

```bash
# 1. Apply ArgoCD Applications
kubectl apply -f apps/infrastructure/arc-controller.yaml
kubectl apply -f apps/infrastructure/arc-runners.yaml

# 2. Wait for ArgoCD to sync
kubectl get application -n argocd arc-controller -w
kubectl get application -n argocd arc-runners -w

# 3. Verify ArgoCD adopted existing resources (check for "Healthy")
argocd app get arc-controller
argocd app get arc-runners
```

**Option B: Clean Reinstall (If Issues)**

If adoption fails, you can do a clean reinstall during a maintenance window:

```bash
# 1. Delete existing manual installations
helm uninstall arc -n arc-systems
helm uninstall hitchai-app-runners -n arc-runners

# 2. Wait for cleanup
kubectl get pods -n arc-systems -w
kubectl get pods -n arc-runners -w

# 3. Apply ArgoCD Applications
kubectl apply -f apps/infrastructure/arc-controller.yaml
kubectl apply -f apps/infrastructure/arc-runners.yaml

# 4. Wait for sync
argocd app sync arc-controller
argocd app sync arc-runners
```

### Step 5: Verify Migration

```bash
# 1. Check ArgoCD application status
argocd app list | grep arc

# 2. Check controller is running
kubectl get deployment -n arc-systems arc-gha-rs-controller

# 3. Check listener is running
kubectl get pods -n arc-systems -l app.kubernetes.io/name=hitchai-app-runners

# 4. Trigger a test workflow
# Go to GitHub Actions and run a workflow that uses 'hitchai-app-runners'

# 5. Watch runner pods scale up
kubectl get pods -n arc-runners -w

# 6. Check runner logs
kubectl logs -n arc-runners <runner-pod-name> -c runner
```

### Step 6: Cleanup (After Verification)

If everything works:

```bash
# Remove Helm releases (ArgoCD now owns the resources)
# Note: Only if you used Option A (adoption)
# If resources were deleted in Option B, skip this

# The resources are now managed by ArgoCD, not Helm
# You can verify:
kubectl get deployment arc-gha-rs-controller -n arc-systems -o yaml | grep "app.kubernetes.io/managed-by"
# Should show: Helm (initially) or may not appear (after ArgoCD takeover)
```

## Rollback Plan

If migration causes issues:

```bash
# 1. Delete ArgoCD Applications
kubectl delete application arc-controller -n argocd
kubectl delete application arc-runners -n argocd

# 2. Reinstall manually via Helm
helm install arc \
  --namespace arc-systems \
  --create-namespace \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version 0.12.1

helm install hitchai-app-runners \
  --namespace arc-runners \
  --create-namespace \
  --set githubConfigUrl="https://github.com/hitchai-app" \
  --set githubConfigSecret.github_token="${GITHUB_PAT}" \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version 0.12.1
```

## Common Issues

### Issue: ArgoCD Can't Adopt Helm Resources

**Symptom**: ArgoCD shows "OutOfSync" and tries to recreate resources

**Solution**: Add Helm annotations to ArgoCD Application:
```yaml
spec:
  source:
    helm:
      skipCrds: true  # Don't recreate CRDs
```

### Issue: Sealed Secret Not Decrypting

**Symptom**: Runner scale set can't authenticate to GitHub

**Solution**:
1. Verify sealed-secrets controller is running:
   ```bash
   kubectl get pods -n sealed-secrets
   ```
2. Check SealedSecret was created:
   ```bash
   kubectl get sealedsecret hitchai-app-github-token -n arc-runners
   ```
3. Check plain Secret was created:
   ```bash
   kubectl get secret hitchai-app-github-token -n arc-runners
   ```

### Issue: Runners Not Scaling Up

**Symptom**: GitHub workflows queue but no runner pods appear

**Solution**:
1. Check listener logs:
   ```bash
   kubectl logs -n arc-systems -l app.kubernetes.io/name=hitchai-app-runners
   ```
2. Check controller logs:
   ```bash
   kubectl logs -n arc-systems deployment/arc-gha-rs-controller
   ```
3. Verify GitHub token has correct permissions (repo + admin:org)

## Post-Migration

After successful migration:

1. **Update documentation**: Ensure team knows runners are now GitOps-managed
2. **Monitor**: Watch for any issues in the first few days
3. **Update workflows**: No changes needed (runner name stays `hitchai-app-runners`)
4. **Plan maintenance**: Schedule regular updates via ArgoCD

## References

- ADR 0014: Actions Runner Controller for GitHub Actions
- [ARC Documentation](https://github.com/actions/actions-runner-controller)
- [ArgoCD App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
