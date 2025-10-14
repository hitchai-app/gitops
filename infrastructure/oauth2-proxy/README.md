# OAuth2 Proxy for Services Without Native OIDC

OAuth2 Proxy provides authentication for services that don't have built-in OIDC support.

## Manual Setup Required

### Generate Secrets for dev-ui (Stage)

```bash
# Generate cookie secret (32 bytes base64)
openssl rand -base64 32

# Create sealed secret
kubectl create secret generic oauth2-proxy-dev-ui-secrets \
  -n steady-stage \
  --from-literal=client-secret='<DEX_CLIENT_SECRET_DEV_UI_STAGE>' \
  --from-literal=cookie-secret='<GENERATED_COOKIE_SECRET>' \
  --dry-run=client -o yaml | \
  kubeseal --cert pub.pem --format yaml > infrastructure/oauth2-proxy/dev-ui-stage-secrets-sealed.yaml
```

**Note:** The `client-secret` value must match the one used in `infrastructure/dex/secrets-sealed.yaml` for key `dev-ui-stage-client-secret`.

### Update Ingress

The dev-ui ingress needs to be updated to route through oauth2-proxy instead of directly to dev-ui.

See example in: `infrastructure/oauth2-proxy/dev-ui-stage-ingress-example.yaml`

## Testing

```bash
# Check oauth2-proxy pods
kubectl get pods -n steady-stage -l app=oauth2-proxy-dev-ui

# Test authentication flow
# 1. Visit https://app-stage.steady.ops.last-try.org
# 2. Should redirect to https://auth.ops.last-try.org
# 3. Login with GitHub
# 4. Redirect back with session cookie
```

## Deployment Pattern

OAuth2 Proxy runs as a separate deployment that:
1. Receives unauthenticated requests via ingress
2. Redirects to Dex for authentication
3. Validates OIDC token from Dex
4. Proxies authenticated requests to upstream service (dev-ui)
5. Sets session cookie for subsequent requests
