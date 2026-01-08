# Crossplane Cloudflare Credentials

## Required Secret: cloudflare-credentials

Create a Cloudflare API token with R2 permissions:
1. Cloudflare Dashboard → My Profile → API Tokens
2. Create Token → Custom Token
3. Permissions: Account → Workers R2 Storage → Edit
4. Account Resources: Include → Your Account

## Create the Secret

```bash
# Use the sealing script
.tmp/seal-cloudflare-credentials.sh
```

Or manually:
```bash
kubectl create secret generic cloudflare-credentials \
  --namespace=crossplane-system \
  --from-literal=api-token="YOUR_TOKEN" \
  --dry-run=client -o yaml | \
  kubeseal --cert .sealed-secrets-pub.pem --format yaml \
  > infrastructure/crossplane-providers/cloudflare-credentials-sealed.yaml
```

Note: Account ID is hardcoded in workspace YAMLs (not sensitive).

## Verify

After ArgoCD syncs:
```bash
kubectl get secret cloudflare-credentials -n crossplane-system
kubectl get workspace r2-etcd-backups
```
