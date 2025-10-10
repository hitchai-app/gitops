# Steady Infrastructure Setup

## Required Secrets

Before deploying Steady infrastructure, create the following secrets:

### 1. Centrifugo Secrets

Generate random credentials and create secrets directly:

```bash
# Stage
kubectl create secret generic centrifugo-secrets \
  --namespace=steady-stage \
  --from-literal=admin-password=$(openssl rand -base64 32) \
  --from-literal=admin-secret=$(openssl rand -base64 32) \
  --from-literal=api-key=$(openssl rand -base64 32)

# Prod
kubectl create secret generic centrifugo-secrets \
  --namespace=steady-prod \
  --from-literal=admin-password=$(openssl rand -base64 32) \
  --from-literal=admin-secret=$(openssl rand -base64 32) \
  --from-literal=api-key=$(openssl rand -base64 32)
```

To retrieve credentials later:
```bash
kubectl get secret centrifugo-secrets -n steady-stage -o jsonpath='{.data.admin-password}' | base64 -d
```

### 2. LiteLLM Master Key (SealedSecret)

Generate and seal the master key:

```bash
# Stage
kubectl create secret generic litellm-secrets \
  --namespace=steady-stage \
  --from-literal=master-key=$(openssl rand -base64 32) \
  --dry-run=client -o yaml | \
  kubeseal \
    --controller-name=sealed-secrets-controller \
    --controller-namespace=sealed-secrets \
    --format=yaml > infrastructure/steady-litellm/overlays/stage/litellm-secrets-sealed.yaml

# Prod
kubectl create secret generic litellm-secrets \
  --namespace=steady-prod \
  --from-literal=master-key=$(openssl rand -base64 32) \
  --dry-run=client -o yaml | \
  kubeseal \
    --controller-name=sealed-secrets-controller \
    --controller-namespace=sealed-secrets \
    --format=yaml > infrastructure/steady-litellm/overlays/prod/litellm-secrets-sealed.yaml
```

Then add to kustomization:
```yaml
# infrastructure/steady-litellm/overlays/{stage,prod}/kustomization.yaml
resources:
- ../../base
- litellm-secrets-sealed.yaml
```

### 3. OpenAI API Keys (SealedSecret)

Create separate API keys for stage and prod in OpenAI dashboard, then seal:

```bash
# Stage
kubectl create secret generic ai-api-keys \
  --namespace=steady-stage \
  --from-literal=openai=sk-proj-YOUR-STAGE-KEY \
  --dry-run=client -o yaml | \
  kubeseal \
    --controller-name=sealed-secrets-controller \
    --controller-namespace=sealed-secrets \
    --format=yaml > infrastructure/steady-litellm/overlays/stage/ai-api-keys-sealed.yaml

# Prod
kubectl create secret generic ai-api-keys \
  --namespace=steady-prod \
  --from-literal=openai=sk-proj-YOUR-PROD-KEY \
  --dry-run=client -o yaml | \
  kubeseal \
    --controller-name=sealed-secrets-controller \
    --controller-namespace=sealed-secrets \
    --format=yaml > infrastructure/steady-litellm/overlays/prod/ai-api-keys-sealed.yaml
```

Then add to kustomization:
```yaml
# infrastructure/steady-litellm/overlays/{stage,prod}/kustomization.yaml
resources:
- ../../base
- ai-api-keys-sealed.yaml
- litellm-secrets-sealed.yaml
```

## Deployment Order

1. Create secrets (see above)
2. Commit SealedSecrets to Git
3. Merge PR → ArgoCD syncs infrastructure
4. Verify all pods running:
   ```bash
   kubectl get pods -n steady-stage
   kubectl get pods -n steady-prod
   ```

## S3 Backups

PostgreSQL backups use existing `backup-s3-credentials` Secret with paths:
- Stage: `s3://cloudnativepg-backups/steady-stage`
- Prod: `s3://cloudnativepg-backups/steady-prod`

No additional configuration needed.
