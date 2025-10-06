# 0010. GitOps Repository Structure

**Status**: Accepted

**Date**: 2025-10-05

## Context

We need a clear directory structure for the GitOps repository using ArgoCD app-of-apps pattern.

Requirements:
- Separate cluster infrastructure from workloads
- Support stage/prod environments
- Handle shared vs per-product resources
- Clear what's manual vs ArgoCD-managed
- Allow future growth (multiple products, dedicated databases)

Current: Single cluster, public GitHub repo, stage/prod namespaces

## Decision

**Two-layer structure with product-owned resource declarations:**

```
gitops/
├── bootstrap/          # Manual installation only
├── apps/               # ArgoCD Application CRDs
├── infrastructure/     # Platform services (shared, serves products)
└── workloads/         # Your products and applications
```

**Key principle:** Infrastructure exists FOR products, workloads ARE products.

**Resource strategy:**
- Infrastructure provides shared resources (PostgreSQL, MinIO, Redis)
- Products declare what they need (databases, buckets, queues) in their folders
- Dedicated resources can live under product if not shared

## Alternatives Considered

### 1. Three Folders (infrastructure/services/workloads)
- **Why not chosen**: Arbitrary distinction between "services" and "workloads", operators split from what they manage

### 2. Colocate Application CRDs with Manifests
- **Why not chosen**: Standard pattern is centralized `apps/` directory for app-of-apps

### 3. Separate Databases Folder
- **Why not chosen**: Products should own their database declarations

## Consequences

### Positive
- ✅ Clear separation: manual bootstrap vs ArgoCD-managed
- ✅ Products own their database needs
- ✅ Shared resources explicit (postgres-shared)
- ✅ Can add dedicated databases per product later
- ✅ CloudNativePG supports declarative DB/user management via GitOps

### Negative
- ⚠️ Database declarations scattered across products
- ⚠️ Renaming shared resources later is painful (plan names carefully)
- ⚠️ Requires understanding ArgoCD app-of-apps pattern

## Structure

```
gitops/
├── bootstrap/
│   ├── argocd/
│   │   └── install/
│   │       └── values.yaml              # ArgoCD Helm values
│   └── sealed-secrets-key.yaml          # Private key injection (manual)
│
├── apps/                                # ArgoCD Application CRDs
│   ├── infrastructure.yaml              # Root app: infrastructure
│   ├── workloads-stage.yaml             # Root app: workloads (stage)
│   ├── workloads-prod.yaml              # Root app: workloads (prod)
│   ├── infrastructure/
│   │   ├── sealed-secrets.yaml
│   │   ├── longhorn.yaml
│   │   ├── cert-manager.yaml
│   │   ├── cloudnativepg.yaml
│   │   └── monitoring.yaml
│   └── workloads/
│       ├── postgres-stage.yaml
│       ├── postgres-prod.yaml
│       ├── product-a-stage.yaml
│       └── product-a-prod.yaml
│
├── infrastructure/                      # Platform services (shared)
│   ├── sealed-secrets/
│   ├── longhorn/
│   ├── cert-manager/
│   ├── monitoring/
│   ├── cloudnativepg/                   # PostgreSQL operator
│   ├── postgres/                        # Shared PostgreSQL cluster
│   │   ├── base/
│   │   │   └── cluster.yaml
│   │   └── overlays/
│   │       ├── stage/
│   │       └── prod/
│   ├── minio-operator/
│   ├── minio/                           # Shared MinIO cluster
│   └── redis/                           # Shared Redis
│
└── workloads/                           # Your products
    └── product-a/
        ├── databases/                   # What DBs product-a needs
        │   ├── api-db.yaml              # Database CRD
        │   ├── worker-db.yaml
        │   └── users.yaml
        ├── buckets/                     # What S3 buckets product-a needs
        │   └── uploads-bucket.yaml
        ├── api/
        │   ├── base/
        │   └── overlays/
        │       ├── stage/
        │       └── prod/
        ├── worker/
        └── frontend/
```

## Bootstrap Process

```bash
# 1. Install ArgoCD
helm install argocd argo/argo-cd -n argocd \
  -f bootstrap/argocd/install/values.yaml

# 2. Generate and inject Sealed Secrets key
openssl req -x509 -nodes -newkey rsa:4096 \
  -keyout sealed-secrets.key -out sealed-secrets.crt \
  -subj "/CN=sealed-secret/O=sealed-secret"

kubectl create namespace sealed-secrets
kubectl -n sealed-secrets create secret tls sealed-secrets-key \
  --cert=sealed-secrets.crt --key=sealed-secrets.key
kubectl -n sealed-secrets label secret sealed-secrets-key \
  sealedsecrets.bitnami.com/sealed-secrets-key=active

# Backup key to secure storage

# 3. Apply root apps
kubectl apply -f apps/infrastructure.yaml
kubectl apply -f apps/workloads-stage.yaml
kubectl apply -f apps/workloads-prod.yaml
```

**After this:** All changes via Git → ArgoCD syncs automatically.

## Database Management

**CloudNativePG supports declarative databases/users:**

```yaml
# product-a/databases/api-db.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: product-a-api-stage
  namespace: postgres-stage
spec:
  cluster:
    name: postgres-shared
  name: api_db
  owner: api_user
```

**Flow:**
1. Shared `postgres` cluster exists (managed by ArgoCD)
2. Product declares Database CRDs in `databases/`
3. CloudNativePG operator creates databases in cluster
4. Application uses credentials via Secrets

**Later, if need dedicated cluster:**
```
workloads/product-b/
├── postgres/              # Dedicated cluster
│   ├── stage/
│   └── prod/
└── databases/
```

## Folder Purposes

**`bootstrap/`** - Manual installation only (ArgoCD, Sealed Secrets key)

**`apps/`** - All ArgoCD Application CRDs (app-of-apps pattern)

**`infrastructure/`** - Platform services that exist FOR products (shared PostgreSQL, MinIO, monitoring, cert-manager)

**`workloads/`** - Your actual products and applications (business logic)

**Simple rule:** If removing it breaks OTHER products → infrastructure. If removing it only breaks THIS product → workload.

## Naming Convention

**Shared resources:** Name with `-shared` or descriptive purpose from start
- Good: `postgres-shared`, `redis-shared`, `litellm-shared`
- Avoid: `postgres` (ambiguous when adding dedicated instances)

**Product resources:** Nest under product name
- `workloads/product-a/api/`
- `workloads/product-a/databases/`

**Renaming later is painful** - plan names carefully.

## Future Growth

**Multi-repo:** Change `repoURL` in Application CRDs

**Move resources:** Update `path` in Application CRD, commit

**Add product:**
```
workloads/product-b/
├── databases/
└── api/
```

**Dedicated database:**
```
workloads/product-b/
├── postgres/          # Dedicated cluster
└── databases/
```

## When to Reconsider

**Revisit if:**
1. Managing > 5 clusters (consider ApplicationSets)
2. Team > 20 people (consider multi-repo)
3. Database declarations become too scattered

## References

- [ArgoCD App-of-Apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [CloudNativePG Database Management](https://cloudnative-pg.io/documentation/current/database_management/)
- ADR 0001: GitOps with ArgoCD
- ADR 0009: Secrets Management Strategy
