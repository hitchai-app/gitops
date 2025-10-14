# Dex Authentication Provider

OIDC/OAuth2 authentication provider for infrastructure services.

## Manual Setup Required

### 1. Create GitHub OAuth Application

Visit: https://github.com/organizations/hitchai-app/settings/applications

**Create New OAuth App:**
- Name: `Dex Authentication (ops cluster)`
- Homepage URL: `https://auth.ops.last-try.org`
- Authorization callback URL: `https://auth.ops.last-try.org/callback`

Save the Client ID and Client Secret.

### 2. Generate Client Secrets

```bash
# Generate random secrets for each service
openssl rand -hex 32  # dev-ui stage
openssl rand -hex 32  # dev-ui prod
openssl rand -hex 32  # grafana
```

### 3. Create Sealed Secret

```bash
kubectl create secret generic dex-secrets \
  -n dex \
  --from-literal=github-client-id='<GITHUB_CLIENT_ID>' \
  --from-literal=github-client-secret='<GITHUB_CLIENT_SECRET>' \
  --from-literal=dev-ui-stage-client-secret='<GENERATED_SECRET_1>' \
  --from-literal=dev-ui-prod-client-secret='<GENERATED_SECRET_2>' \
  --from-literal=grafana-client-secret='<GENERATED_SECRET_3>' \
  --dry-run=client -o yaml | \
  kubeseal --cert pub.pem --format yaml > infrastructure/dex/secrets-sealed.yaml
```

### 4. Commit and Deploy

```bash
git add infrastructure/dex/secrets-sealed.yaml
git commit -m "feat(dex): add sealed secrets for Dex clients"
git push
# ArgoCD will deploy
```

## Verification

```bash
# Check Dex pods
kubectl get pods -n dex

# Check OIDC discovery
curl https://auth.ops.last-try.org/.well-known/openid-configuration
```

## Services Using Dex

- **dev-ui (stage/prod)**: OAuth2 Proxy
- **Grafana**: Native OIDC
- **Future**: ArgoCD, SigNoz, MinIO Console
