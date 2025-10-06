# MinIO Shared Tenant

Shared MinIO S3-compatible object storage for application file uploads, backups, and general storage needs.

## Architecture

**Deployment Pattern**: SNMD (Single-Node Multi-Drive)
- **Topology**: 1 server × 4 volumes = 4 drives total
- **Erasure Coding**: EC:2 (2 data + 2 parity drives)
- **Capacity**: 5Gi per drive = 20Gi raw, ~10Gi usable (50% EC:2 overhead)
- **Storage Class**: longhorn-single-replica (MinIO provides data redundancy)
- **Namespace**: minio

## Why 4 Drives (SNMD)?

**1-drive (SNSD):**
- Uses EC:0 (no erasure coding)
- Cannot add pools (dead-end architecture)
- No bitrot protection

**4-drive (SNMD):**
- Uses EC:2 (2 data + 2 parity)
- Can add pools when scaling (MinIO requires ≥ 4 drives per pool)
- Bitrot protection via erasure coding checksums
- Tolerates 2 drive failures

## Configuration

### Root Credentials (Sealed Secret Required)

**CRITICAL**: Before ArgoCD can deploy, create Sealed Secret:

```bash
# Generate strong credentials
MINIO_ROOT_USER="admin"
MINIO_ROOT_PASSWORD="$(openssl rand -base64 32)"

# Save password securely
echo "MinIO Root Password: ${MINIO_ROOT_PASSWORD}" | pass insert -m gitops/minio-root-password

# Create and seal secret
kubectl create secret generic minio-shared-root \
  --from-literal=config.env="export MINIO_ROOT_USER=${MINIO_ROOT_USER}
export MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}" \
  --namespace=minio \
  --dry-run=client -o yaml | \
  kubeseal --format=yaml > infrastructure/minio/base/root-credentials-sealed.yaml

# Add to kustomization
echo "- root-credentials-sealed.yaml" >> infrastructure/minio/base/kustomization.yaml

# Commit sealed secret
git add infrastructure/minio/base/root-credentials-sealed.yaml
git add infrastructure/minio/base/kustomization.yaml
git commit -m "feat: add MinIO root credentials"
git push
```

### TLS Configuration

TLS handled by cert-manager (ADR 0008):
- Certificate: `minio-shared-tls`
- Domains: `minio.ops.last-try.org`, `*.minio.ops.last-try.org`, `minio-shared-console.ops.last-try.org`
- Issuer: `letsencrypt-prod` ClusterIssuer
- Challenge: DNS-01 via Cloudflare

### Storage Configuration

- **StorageClass**: longhorn-single-replica (1 replica)
- **Rationale**: MinIO EC:2 provides application-level redundancy (ADR 0007)
- **Size**: 5Gi per drive (small for testing, increase for production)

## Deployment

1. **Prerequisites:**
   - cert-manager deployed with letsencrypt-prod ClusterIssuer
   - longhorn-single-replica StorageClass exists
   - Cloudflare DNS-01 configured

2. **Create root credentials** (see above)

3. **Apply ArgoCD Applications:**
   ```bash
   kubectl apply -f apps/infrastructure/minio-operator.yaml
   kubectl apply -f apps/infrastructure/minio.yaml
   ```

4. **Verify deployment:**
   ```bash
   # Operator
   kubectl get pods -n minio-operator

   # Tenant
   kubectl get tenant -n minio minio-shared
   kubectl get pods -n minio

   # Storage (expect 4 PVCs)
   kubectl get pvc -n minio

   # Certificate
   kubectl get certificate -n minio minio-shared-tls
   ```

## Scaling (Future)

**Adding server pools when multi-node:**

1. New pool must have ≥ 4 drives (EC:2 parity level)
2. Add pool to tenant spec (cannot modify existing pools)
3. MinIO automatically distributes new objects across pools
4. Existing data stays in original pool

## S3 API Access

```bash
# Port-forward
kubectl port-forward -n minio svc/minio-shared-hl 9000:9000

# Configure mc client
mc alias set minio-local https://localhost:9000 admin <PASSWORD> --insecure

# Create bucket
mc mb minio-local/test-bucket

# Upload object
echo "hello" | mc pipe minio-local/test-bucket/hello.txt

# List
mc ls minio-local/test-bucket/
```

## Backup Strategy

**Critical**: Do NOT use MinIO for Longhorn backups (circular dependency, ADR 0002)

Longhorn should backup to external S3 (AWS S3, Backblaze B2).

MinIO itself should backup to external S3 via MinIO replication.

## References

- ADR 0006: MinIO Operator with 4-Drive Configuration
- ADR 0007: Longhorn StorageClass Strategy
- ADR 0008: cert-manager for TLS
- ADR 0009: Secrets Management Strategy
