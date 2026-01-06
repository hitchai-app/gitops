# Crossplane Cloudflare Credentials

## Required Secret: cloudflare-credentials

Create a Cloudflare API token with R2 permissions:
1. Cloudflare Dashboard → My Profile → API Tokens
2. Create Token → Custom Token
3. Permissions: Account → R2 Storage → Edit
4. Account Resources: Include → Your Account

## Create the Secret

```bash
# Get your Account ID from Cloudflare Dashboard (right sidebar on any zone)
CLOUDFLARE_ACCOUNT_ID="your-account-id"
CLOUDFLARE_API_TOKEN="your-api-token"

# Create credentials.json
cat > /tmp/credentials.json << EOF
{
  "cloudflare_api_token": "${CLOUDFLARE_API_TOKEN}",
  "cloudflare_account_id": "${CLOUDFLARE_ACCOUNT_ID}"
}
EOF

# Create and seal the secret
kubectl create secret generic cloudflare-credentials \
  --namespace=crossplane-system \
  --from-file=credentials.json=/tmp/credentials.json \
  --dry-run=client -o yaml | \
  kubeseal --cert .sealed-secrets-pub.pem --format yaml \
  > infrastructure/crossplane-providers/cloudflare-credentials-sealed.yaml

# Clean up
rm /tmp/credentials.json
```

## Verify

After ArgoCD syncs:
```bash
kubectl get secret cloudflare-credentials -n crossplane-system
kubectl get workspace r2-etcd-backups
```
