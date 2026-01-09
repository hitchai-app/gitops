# GitOps Infrastructure

GitOps repository for Kubernetes cluster infrastructure using ArgoCD.

For contributor expectations and workflow checklists, see [`AGENTS.md`](AGENTS.md).

## Project Overview

This repository manages infrastructure for an in-house Kubernetes cluster running on Hetzner (12 CPU / 128GB RAM / 280GB SSD). The cluster hosts microservices architecture with stage and prod environments, following GitOps practices with ArgoCD.

## Repository Structure

```
gitops/
├── bootstrap/          # Manual installation (ArgoCD, Sealed Secrets key)
├── apps/              # ArgoCD Application CRDs (app-of-apps pattern)
├── infrastructure/    # Platform services (shared PostgreSQL, MinIO, monitoring)
├── workloads/         # Your products and applications
└── adr/               # Architecture Decision Records
```

**Key principle:** Infrastructure exists FOR products, workloads ARE products.

See @adr/0010-gitops-repository-structure.md for details.

## Key Technologies

- **GitOps**: ArgoCD (@adr/0001-gitops-with-argocd.md)
- **Storage**: Longhorn (@adr/0002-longhorn-storage-from-day-one.md, @adr/0007-longhorn-storageclass-strategy.md)
- **Databases**: CloudNativePG (@adr/0004-cloudnativepg-for-postgresql.md)
- **Cache**: Valkey StatefulSet (@adr/0005-statefulset-for-valkey.md)
- **Object Storage**: MinIO Operator (@adr/0006-minio-operator-single-drive-bootstrap.md)
- **Certificates**: cert-manager + Let's Encrypt DNS-01 (@adr/0008-cert-manager-for-tls.md)
- **Secrets**: Sealed Secrets BYOK (@adr/0009-secrets-management-strategy.md)
- **Ingress**: Traefik (@adr/0011-traefik-ingress-controller.md)
- **LoadBalancer**: MetalLB Layer 2 (@adr/0012-metallb-load-balancer.md)

## Environments

- **Stage**: Testing environment with lower resource quotas
- **Prod**: Production environment with higher resource quotas

Current: Single-node Hetzner server → Future: Multi-node cluster

## Getting Started

### Prerequisites
- Kubernetes cluster (v1.30+)
- kubectl configured
- Access to cluster

### Bootstrap Process
1. Install ArgoCD: `helm install argocd ...` (see @adr/0010-gitops-repository-structure.md)
2. Generate and inject Sealed Secrets key (see @adr/0009-secrets-management-strategy.md)
3. Apply root apps: `kubectl apply -f apps/infrastructure.yaml`
4. Everything else automated via ArgoCD

See @adr/0010-gitops-repository-structure.md for detailed bootstrap workflow.

## Architecture Decisions

All major architectural decisions are documented in `adr/`:

- @adr/0001-gitops-with-argocd.md
- @adr/0002-longhorn-storage-from-day-one.md
- @adr/0003-operators-over-statefulsets.md
- @adr/0004-cloudnativepg-for-postgresql.md
- @adr/0005-statefulset-for-valkey.md
- @adr/0006-minio-operator-single-drive-bootstrap.md
- @adr/0007-longhorn-storageclass-strategy.md
- @adr/0008-cert-manager-for-tls.md
- @adr/0009-secrets-management-strategy.md
- @adr/0010-gitops-repository-structure.md
- @adr/0011-traefik-ingress-controller.md
- @adr/0012-metallb-load-balancer.md

See @adr/README.md for ADR format guidelines.

## Related Repositories

- **Product Environment**: ../hi-env (development environment with Tilt)
- **Services**: Managed as git submodules in hi-env repository

## Cluster Specifications

- Provider: Hetzner
- Nodes: 2
  - k8s-mn (control-plane): 12 CPU / 128GB RAM / 280GB SSD
  - k8s-02 (worker): 8 CPU / 64GB RAM / 2x 954GB NVMe
- Total resources: 20 CPU / 192GB RAM / ~2TB storage
- Target availability: 99%
- Domain: `*.ops.last-try.org` (internal infrastructure services)

See individual ADRs for infrastructure and workload details.

## Development Workflow

**IMPORTANT: All changes MUST go through pull requests. Never commit directly to master.**

**🚨 CRITICAL: ALWAYS BRANCH FROM LATEST MASTER 🚨** - Before creating any new branch, ALWAYS ensure you're on the latest master: `git checkout master && git pull origin master`. Then create your feature branch. This prevents creating branches from stale state and avoids merge conflicts.

1. Ensure master is up-to-date: `git checkout master && git pull origin master`
2. Create feature branch from master
3. Make changes in feature branch
4. Submit PR for review
5. Merge to master → ArgoCD auto-syncs to cluster

### Working with Automated Reviews

This repository uses automated code review via GitHub Actions. See [`AGENTS.md`](AGENTS.md) for detailed guidance on:
- Correcting reviewer errors with evidence-based comments
- Reminding the reviewer it has **full `gh` CLI access** (it often assumes it lacks permissions)
- Using `@claude` mentions to trigger re-evaluation

**Cluster Access:** The automated reviewer runs on self-hosted GitHub Actions runners inside the cluster (`hitchai-app-runners-lite`) with read-only kubectl access. It can:
- Verify ArgoCD Application health: `kubectl get applications -n argocd`
- Check pod status: `kubectl get pods -n <namespace>`
- View resource usage: `kubectl top pods -n <namespace>`
- Inspect events: `kubectl get events -n <namespace> --sort-by='.lastTimestamp'`
- Read logs: `kubectl logs <pod> -n <namespace>`

**GitHub CLI Access:** The automated reviewer has full `gh` CLI permissions and **MUST** use it for formal PR reviews:
- **REQUIRED**: Submit formal review using `gh pr review <pr-number> --approve` or `--request-changes`
- **NOT SUFFICIENT**: Posting a comment alone (without formal review) does NOT count as a review
- The reviewer has permissions to approve/request changes and MUST use them
- See workflow configuration in `.github/workflows/claude-code-review.yml` for review process

**Key reminder:** The automated reviewer has kubectl and gh CLI access. If it claims it cannot verify something, remind it to use these tools.

**How it works:**
1. GitHub Actions workflows run on self-hosted runners (Actions Runner Controller in `arc-runners` namespace)
2. Runner pods use ServiceAccount `github-actions-reviewer` with ClusterRole `github-actions-readonly`
3. No kubeconfig needed - uses in-cluster authentication
4. RBAC permissions: `get`, `list`, `watch` on all resources + `pods/log` and `pods/exec` (read-only commands only)

## Best Practices

### ArgoCD Applications with Helm Charts

**We use ArgoCD's native multi-source Helm** (not kustomize helmCharts):

```yaml
spec:
  project: default
  sources:
    # 1. Helm chart from OCI registry (no oci:// prefix per ArgoCD docs)
    - repoURL: ghcr.io/org/charts
      chart: my-chart
      targetRevision: 1.0.0
      helm:
        releaseName: my-release
        valueFiles:
          - $values/infrastructure/my-app/values.yaml
    # 2. Git repo with values file
    - repoURL: https://github.com/org/gitops.git
      targetRevision: HEAD
      ref: values
    # 3. (Optional) Git repo with additional manifests (sealed secrets, etc.)
    - repoURL: https://github.com/org/gitops.git
      targetRevision: HEAD
      path: infrastructure/my-app
```

**OCI Helm chart syntax** ([ArgoCD docs](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)):
- `repoURL`: Registry path WITHOUT `oci://` prefix (e.g., `ghcr.io/org/charts`)
- `chart`: Chart name as separate field
- `targetRevision`: Chart version

**OCI credential matching**: ArgoCD uses PREFIX matching. A secret with `url: ghcr.io` matches ALL ghcr.io requests. For public charts, use anonymous access (no secret). For private charts, use narrowly-scoped secrets (e.g., `url: ghcr.io/your-org`).

**Why this approach:**
- ✅ Works perfectly with app-of-apps pattern (no field stripping)
- ✅ Simpler - no kustomization files needed
- ✅ ArgoCD handles Helm natively
- ✅ Can combine Helm charts with plain manifests (sealed secrets, configmaps)
- ✅ No `--enable-helm` flags or middleware complexity

**Why NOT kustomize helmCharts:**
- ❌ In app-of-apps pattern, `kustomize.buildOptions` field gets stripped during Server-Side Apply
- ❌ Requires kustomization.yaml files that add unnecessary complexity
- ❌ Needs `--enable-helm` flag that may not survive parent→child Application sync

**Examples:** `apps/infrastructure/woodpecker.yaml`, `apps/infrastructure/forgejo.yaml`

### Kubernetes Manifests

**Labels**: Do NOT add labels manually to Kubernetes resources. ArgoCD automatically adds tracking labels to all resources it manages. Manual labels are redundant and create maintenance overhead.

```yaml
# ❌ Don't do this
metadata:
  labels:
    app.kubernetes.io/managed-by: argocd
    app.kubernetes.io/name: my-app

# ✅ Do this instead - minimal, let ArgoCD handle tracking
metadata:
  name: my-resource
```

ArgoCD automatically adds:
- `app.kubernetes.io/instance: <app-name>`
- `argocd.argoproj.io/instance: <namespace>_<app-name>`

These are sufficient for resource tracking and querying.

### Version Management

**CRITICAL: Always use latest stable versions unless explicitly specified otherwise.**

Before adding or updating any infrastructure component:

1. **Check official releases**: Always verify the latest stable version from the official source:
   - GitHub releases page (e.g., `https://github.com/oauth2-proxy/oauth2-proxy/releases`)
   - Official Helm chart repositories
   - Container registry tags (verify what "latest" actually points to)

2. **Never assume**: Don't use versions from examples, old documentation, or other repositories without verification.

3. **Document version choice**: In PR description, include:
   - Version selected and why (latest stable, or specific version with reason)
   - Link to official releases page
   - Any relevant changelog entries

4. **Feature availability**: When using specific CLI flags or features:
   - Verify the feature exists in your chosen version
   - Check when the feature was introduced
   - Ensure version supports all required functionality

**Example:**
```markdown
## Version Selection
- **oauth2-proxy**: v7.12.0 (latest stable as of 2025-10-15)
- **Source**: https://github.com/oauth2-proxy/oauth2-proxy/releases/tag/v7.12.0
- **Rationale**: Requires --cookie-secret-file flag (added in v7.8.0)
```

### Working with Sealed Secrets

**Public Certificate Location:** `.sealed-secrets-pub.pem` (repository root)

**Creating New Sealed Secrets:**

```bash
# 1. Create plaintext secret YAML
cat > /tmp/my-secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: my-namespace
type: Opaque
stringData:
  key1: value1
  key2: value2
EOF

# 2. Seal the secret using repository public cert
kubeseal --cert .sealed-secrets-pub.pem --format yaml < /tmp/my-secret.yaml > infrastructure/my-app/my-secret-sealed.yaml

# 3. Commit the sealed secret to Git
git add infrastructure/my-app/my-secret-sealed.yaml
```

**Adding Keys to Existing Sealed Secret:**

```bash
# 1. Fetch current secret from cluster (preserves existing keys)
kubectl get secret my-secret -n my-namespace -o yaml > /tmp/my-secret.yaml

# 2. Edit to add new keys (keep existing data section)
# Add your new keys to the 'data' or 'stringData' section

# 3. Re-seal the entire secret
kubeseal --cert .sealed-secrets-pub.pem --format yaml < /tmp/my-secret.yaml > infrastructure/my-app/my-secret-sealed.yaml

# 4. Commit updated sealed secret
git add infrastructure/my-app/my-secret-sealed.yaml
```

**Alternative: Encrypt Individual Key Only (No Cluster Access Needed):**

```bash
# 1. Create temporary secret with ONLY the new key
kubectl create secret generic temp-secret \
  --namespace=my-namespace \
  --from-literal=new-key=new-value \
  --dry-run=client -o yaml | \
  kubeseal --cert .sealed-secrets-pub.pem --format yaml > /tmp/new-key-sealed.yaml

# 2. Extract the encrypted value from the sealed output
grep "new-key:" /tmp/new-key-sealed.yaml
# Copy the encrypted value: AgB...

# 3. Manually add to existing sealed secret file
# Edit infrastructure/my-app/my-secret-sealed.yaml
# Add under spec.encryptedData:
#   new-key: AgB...

# 4. Commit updated sealed secret
git add infrastructure/my-app/my-secret-sealed.yaml
```

**When to use each method:**
- **Full re-seal** (Method 1): When you have cluster access, need to verify existing keys, or adding multiple keys
- **Individual key encryption** (Method 2): When working offline, no cluster access, or adding a single key to a large secret

**Important Notes:**
- **Never commit plaintext secrets** - always use sealed secrets
- **The public cert is safe in Git** - it can only encrypt, not decrypt
- **Re-sealing is normal** - when adding keys, entire secret is re-encrypted
- **Existing keys preserved** - fetch from cluster to keep current values
- **Private key backup** - stored securely outside Git (see @adr/0009-secrets-management-strategy.md)
- **Individual keys work independently** - each key in encryptedData is decrypted separately by the controller

**🚨 CRITICAL SECURITY WARNING - NEVER EXPOSE SECRETS 🚨**

**ABSOLUTELY PROHIBITED:**
- ❌ **NEVER** post plaintext secret values in GitHub PR comments, descriptions, or issues
- ❌ **NEVER** include base64-decoded values in public communications
- ❌ **NEVER** show actual secret values when explaining changes
- ❌ **NEVER** use real secrets as examples in documentation

**When working with secrets:**
- ✅ Discuss that values were regenerated WITHOUT showing the actual values
- ✅ Explain sealed-secrets encryption changes WITHOUT exposing plaintext
- ✅ Reference secrets by name/purpose, NEVER by value

**Example - WRONG:**
```
The client-secret value 8b439c4a... was preserved
```

**Example - CORRECT:**
```
The client-secret was preserved (fetched from cluster)
```

**SEVERITY:** Exposing secrets in public GitHub repositories is a **CRITICAL SECURITY INCIDENT**. If this happens:
1. Delete the comment immediately using `gh pr comment <pr-number> --delete-last`
2. Rotate the exposed secret immediately
3. Update all sealed secrets files that reference the exposed secret

### Cross-Namespace Secret Replication

The cluster uses [kubernetes-replicator](https://github.com/mittwald/kubernetes-replicator) to share secrets across namespaces without duplicating sealed secret definitions.

**How it works:**
1. Add annotation to source secret's template metadata
2. Replicator automatically syncs the secret to target namespaces
3. Target namespaces reference the replicated secret by name

**Adding replication to a sealed secret:**

```yaml
# infrastructure/my-app/secret-sealed.yaml
spec:
  template:
    metadata:
      annotations:
        # Comma-separated list of target namespaces
        replicator.v1.mittwald.de/replicate-to: "namespace-a,namespace-b"
```

**Example: MinIO credentials for GitLab Runner cache**

```yaml
# infrastructure/minio-infra/config-sealed.yaml
spec:
  template:
    metadata:
      annotations:
        replicator.v1.mittwald.de/replicate-to: gitlab-runner
```

The `minio-infra-config` secret is then available in `gitlab-runner` namespace with the same name.

**When to use replication vs. new sealed secret:**
- ✅ **Use replication**: Same credentials needed in multiple namespaces (e.g., shared MinIO, shared DB)
- ❌ **Create new secret**: Different credentials per namespace, namespace-specific configuration

**Viewing replicated secrets:**
```bash
kubectl get secrets -A -l replicator.v1.mittwald.de/replicated-from
```

## Working with Alerts

The cluster uses Prometheus for metrics and Alertmanager for alert routing.

**Web UIs (require Dex authentication):**
- Prometheus: `https://prometheus.ops.last-try.org/alerts` - view all alert rules and their states
- Alertmanager: `https://am.ops.last-try.org` - view active alerts, silences, inhibitions
- Grafana: `https://grafana.ops.last-try.org` - dashboards and alert visualization

**CLI commands to check alerts:**

```bash
# List active alerts (formatted)
kubectl exec -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 -- \
  wget -qO- http://localhost:9093/api/v2/alerts | \
  jq -r '.[] | select(.status.state == "active") | "[\(.labels.severity)] \(.labels.alertname) (\(.labels.namespace // "cluster")): \(.annotations.summary // .annotations.description)"'

# Count alerts by severity
kubectl exec -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 -- \
  wget -qO- http://localhost:9093/api/v2/alerts | \
  jq -r '.[] | select(.status.state == "active") | .labels.severity' | sort | uniq -c

# Get full alert details as JSON
kubectl exec -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 -- \
  wget -qO- http://localhost:9093/api/v2/alerts | jq '.[] | select(.status.state == "active")'
```

**Note on `Watchdog` alert:**
- `Watchdog` is a "dead man's switch" that should ALWAYS be firing - it verifies the alerting pipeline is working

## Disaster Recovery

- **Storage**: Longhorn S3 backups (@adr/0002-longhorn-storage-from-day-one.md)
- **Database**: CloudNativePG PITR (@adr/0004-cloudnativepg-for-postgresql.md)
- **Secrets**: Sealed Secrets key backup (@adr/0009-secrets-management-strategy.md)

See individual ADRs for RTO/RPO targets.
