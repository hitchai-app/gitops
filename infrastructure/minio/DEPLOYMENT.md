# MinIO Deployment Guide

Complete deployment and verification guide for MinIO shared tenant.

## Prerequisites

Before deploying MinIO, ensure:

1. **cert-manager deployed** with `letsencrypt-prod` ClusterIssuer
2. **longhorn-single-replica** StorageClass exists
3. **Cloudflare DNS-01** configured for DNS challenges
4. **Sealed Secrets** controller installed

Verify:
```bash
kubectl get clusterissuer letsencrypt-prod
kubectl get storageclass longhorn-single-replica
kubectl get pods -n sealed-secrets
```

## Step 1: Create Root Credentials

```bash
# Generate credentials
MINIO_ROOT_USER="admin"
MINIO_ROOT_PASSWORD="$(openssl rand -base64 32)"

# Save to password manager
echo "MinIO Root: ${MINIO_ROOT_USER} / ${MINIO_ROOT_PASSWORD}" | pass insert -m gitops/minio-root

# Create Sealed Secret
kubectl create secret generic minio-shared-root \
  --from-literal=config.env="export MINIO_ROOT_USER=${MINIO_ROOT_USER}
export MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}" \
  --namespace=minio \
  --dry-run=client -o yaml | \
  kubeseal --format=yaml > infrastructure/minio/base/root-credentials-sealed.yaml

# Add to kustomization
echo "- root-credentials-sealed.yaml" >> infrastructure/minio/base/kustomization.yaml

# Commit
git add infrastructure/minio/base/root-credentials-sealed.yaml
git add infrastructure/minio/base/kustomization.yaml
git commit -m "feat: add MinIO root credentials"
git push
```

## Step 2: Deploy via ArgoCD

```bash
# Apply operator
kubectl apply -f apps/infrastructure/minio-operator.yaml

# Wait for operator ready
kubectl wait --for=condition=available deployment/minio-operator -n minio-operator --timeout=300s

# Apply tenant
kubectl apply -f apps/infrastructure/minio.yaml

# Monitor deployment
kubectl get application -n argocd minio-operator minio-shared
argocd app get minio-operator
argocd app get minio-shared
```

## Step 3: Verify Operator

```bash
# Operator deployment
kubectl get deployment -n minio-operator

# Expected output:
# NAME             READY   UP-TO-DATE   AVAILABLE   AGE
# minio-operator   1/1     1            1           Xm

# Operator pods
kubectl get pods -n minio-operator

# Operator logs
kubectl logs -n minio-operator deployment/minio-operator
```

## Step 4: Verify Tenant

```bash
# Tenant status
kubectl get tenant -n minio minio-shared

# Expected output:
# NAME           STATE         AGE
# minio-shared   Initialized   Xm

# Tenant pods (expect 1 pod for 1-server SNMD)
kubectl get pods -n minio -l v1.min.io/tenant=minio-shared

# Expected:
# NAME                  READY   STATUS    RESTARTS   AGE
# minio-shared-pool-0-0 2/2     Running   0          Xm

# Pod details
kubectl describe pod -n minio minio-shared-pool-0-0
```

## Step 5: Verify Storage

```bash
# PVCs (expect 4 for 4-drive SNMD)
kubectl get pvc -n minio

# Expected output:
# NAME                                STATUS   VOLUME   CAPACITY   STORAGECLASS
# data-0-minio-shared-pool-0-0        Bound    pvc-xxx  5Gi        longhorn-single-replica
# data-1-minio-shared-pool-0-0        Bound    pvc-xxx  5Gi        longhorn-single-replica
# data-2-minio-shared-pool-0-0        Bound    pvc-xxx  5Gi        longhorn-single-replica
# data-3-minio-shared-pool-0-0        Bound    pvc-xxx  5Gi        longhorn-single-replica

# Longhorn volumes
kubectl get volumes.longhorn.io -n longhorn-system | grep minio
```

## Step 6: Verify TLS Certificate

```bash
# Certificate status
kubectl get certificate -n minio minio-shared-tls

# Expected:
# NAME               READY   SECRET             AGE
# minio-shared-tls   True    minio-shared-tls   Xm

# Certificate secret
kubectl get secret -n minio minio-shared-tls

# Certificate details
kubectl describe certificate -n minio minio-shared-tls

# Check DNS-01 challenge
kubectl get challenges -n minio
# Should be empty (challenges resolved)
```

## Step 7: Test S3 API

### Setup MinIO Client

```bash
# Port-forward to MinIO service
kubectl port-forward -n minio svc/minio-shared-hl 9000:9000 &

# Install mc client (if not installed)
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# Get root password
MINIO_ROOT_PASSWORD=$(pass show gitops/minio-root | grep -oP 'MinIO Root: admin / \K.*')

# Configure alias
mc alias set minio-local https://localhost:9000 admin "${MINIO_ROOT_PASSWORD}" --insecure

# Test connection
mc admin info minio-local
```

### Create Test Bucket

```bash
# Create bucket
mc mb minio-local/test-bucket

# Upload file
echo "Hello MinIO" | mc pipe minio-local/test-bucket/hello.txt

# List objects
mc ls minio-local/test-bucket/

# Download file
mc cat minio-local/test-bucket/hello.txt

# Expected output: Hello MinIO
```

### Cleanup Test

```bash
# Remove test objects
mc rm --recursive --force minio-local/test-bucket/

# Remove bucket
mc rb minio-local/test-bucket

# Stop port-forward
pkill -f "kubectl port-forward.*minio"
```

## Step 8: Verify Erasure Coding

```bash
# Exec into MinIO pod
kubectl exec -it -n minio minio-shared-pool-0-0 -c minio -- sh

# Check erasure set configuration
mc admin info local

# Expected: 4 drives, EC:2 (2 data + 2 parity)

# Exit pod
exit
```

## Troubleshooting

### Tenant Not Starting

**Symptom**: Tenant stuck in "Provisioning" or "WaitingForReadiness"

**Check root credentials:**
```bash
kubectl get secret -n minio minio-shared-root
kubectl describe secret -n minio minio-shared-root

# If missing:
# Follow Step 1 to create Sealed Secret
```

**Check certificate:**
```bash
kubectl get certificate -n minio minio-shared-tls
kubectl describe certificate -n minio minio-shared-tls

# If not ready:
kubectl get challenges -n minio
kubectl describe challenge -n minio <challenge-name>
```

### PVC Stuck Pending

**Symptom**: PVCs not binding

**Check StorageClass:**
```bash
kubectl get storageclass longhorn-single-replica

# If missing:
# Deploy Longhorn first (prerequisite)
```

**Check Longhorn:**
```bash
kubectl get pods -n longhorn-system
kubectl logs -n longhorn-system deployment/longhorn-driver-deployer
```

### Certificate Not Ready

**Symptom**: Certificate stuck in "Issuing" or "False"

**Check ClusterIssuer:**
```bash
kubectl get clusterissuer letsencrypt-prod
kubectl describe clusterissuer letsencrypt-prod
```

**Check cert-manager:**
```bash
kubectl get pods -n cert-manager
kubectl logs -n cert-manager deployment/cert-manager
```

**Check DNS-01 challenge:**
```bash
kubectl get challenges -n minio
kubectl describe challenge -n minio <challenge-name>

# Verify Cloudflare API token
kubectl get secret -n cert-manager cloudflare-api-token
```

### S3 API Connection Failed

**Symptom**: mc alias fails with connection error

**Check service:**
```bash
kubectl get svc -n minio

# Expected: minio-shared-hl (headless service)
```

**Check pod readiness:**
```bash
kubectl get pods -n minio
kubectl logs -n minio minio-shared-pool-0-0 -c minio
```

**Test internal connectivity:**
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -k https://minio-shared-hl.minio.svc.cluster.local:9000/minio/health/live
```

## Monitoring

### Pod Resources

```bash
kubectl top pods -n minio
```

### Longhorn Volume Usage

```bash
kubectl exec -it -n longhorn-system deployment/longhorn-manager -- \
  curl http://localhost:9500/v1/volumes | jq '.data[] | select(.name | contains("minio"))'
```

### MinIO Metrics

```bash
kubectl port-forward -n minio svc/minio-shared-hl 9000:9000
curl -k https://localhost:9000/minio/v2/metrics/cluster
```

## Scaling Considerations

**Current (Single Node):**
- 1 server × 4 drives = 4 drives total
- EC:2 provides integrity, not availability (all drives on same pod)
- Pod restart = brief downtime

**Future (Multi-Node):**
- Add server pool: minimum 4 drives (EC:2 requirement)
- Cannot modify existing pool-0, must add pool-1
- MinIO distributes new objects across pools
- Existing data stays in pool-0

**Example: Adding pool-1 (2 servers × 4 drives = 8 drives)**
```yaml
pools:
  - servers: 1
    name: pool-0
    volumesPerServer: 4
    # ... existing config

  - servers: 2
    name: pool-1
    volumesPerServer: 4
    # ... new pool config
```

## References

- ADR 0006: MinIO Operator with 4-Drive Configuration
- ADR 0008: cert-manager for TLS
- [MinIO Operator Documentation](https://min.io/docs/minio/kubernetes/upstream/)
- [MinIO Erasure Coding](https://min.io/docs/minio/linux/operations/concepts/erasure-coding.html)
