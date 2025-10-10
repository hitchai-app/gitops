#!/bin/bash
# Generate Centrifugo secrets for stage environment
# Run once before deploying

kubectl create secret generic centrifugo-secrets \
  --namespace=steady-stage \
  --from-literal=admin-password=$(openssl rand -base64 32) \
  --from-literal=admin-secret=$(openssl rand -base64 32) \
  --from-literal=api-key=$(openssl rand -base64 32) \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Centrifugo secrets created. To view:"
echo "kubectl get secret centrifugo-secrets -n steady-stage -o json"
