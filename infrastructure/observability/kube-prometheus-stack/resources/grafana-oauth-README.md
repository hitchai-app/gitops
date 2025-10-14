# Grafana OAuth Secret

Grafana needs the Dex client secret to authenticate users.

## Create Sealed Secret

```bash
# Use the same client secret as defined in infrastructure/dex/secrets-sealed.yaml
# for key: grafana-client-secret

kubectl create secret generic grafana-oauth-secret \
  -n monitoring \
  --from-literal=client-secret='<DEX_CLIENT_SECRET_GRAFANA>' \
  --dry-run=client -o yaml | \
  kubeseal --cert pub.pem --format yaml > infrastructure/observability/kube-prometheus-stack/resources/grafana-oauth-secret-sealed.yaml
```

## Testing

1. Visit https://grafana.ops.last-try.org
2. Click "Sign in with Dex"
3. Login with GitHub (hitchai-app org members)
4. Should be logged in with Admin role

## Notes

- GitHub org members (`hitchai-app`) get Admin role
- Other authenticated users get Viewer role
- Local admin user still works as fallback
