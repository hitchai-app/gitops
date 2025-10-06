# Bootstrap

Manual installation steps for cluster bootstrap.

**NOT managed by ArgoCD** - these are prerequisites.

## Install ArgoCD

Official installation method:

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD (official manifests)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd
```

## Access ArgoCD UI

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open: https://localhost:8080
# Username: admin
# Password: (from command above)
```

## Configure Repository

In ArgoCD UI:
1. Settings → Repositories → Connect Repo
2. Method: HTTPS
3. Repository URL: `https://github.com/hitchai-app/gitops`
4. Leave credentials empty (public repo)

## Apply Root Applications

```bash
kubectl apply -f apps/infrastructure.yaml
# kubectl apply -f apps/workloads-stage.yaml  # when ready
# kubectl apply -f apps/workloads-prod.yaml   # when ready
```

From this point, all changes via Git → ArgoCD auto-syncs.

## Upgrading ArgoCD

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
