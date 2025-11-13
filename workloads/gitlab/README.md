# GitLab Production Deployment

Minimal GitLab CE deployment with full feature set for small teams.

## Overview

**Target Resources**: ~10GB RAM, 4-6 CPU cores
**Features**: Git + CI/CD + Container Registry + Issues/MRs + Wiki + Pages
**User Capacity**: 5-10 active users
**CI/CD Capacity**: 1-2 concurrent pipelines

## Architecture

**Deployment Model**: Bundled services (PostgreSQL, Redis, MinIO included)

**Components**:
- GitLab Webservice (API/UI): 1.5GB RAM
- Sidekiq (background jobs): 1.2GB RAM
- Gitaly (Git storage): 1GB RAM
- Container Registry: 800MB RAM
- Bundled PostgreSQL: 1GB RAM
- Bundled Redis: 512MB RAM
- Bundled MinIO: 1GB RAM
- Supporting components: ~2GB RAM

**Storage**:
- Gitaly (Git repositories): 50GB PVC
- PostgreSQL (metadata): 20GB PVC
- MinIO (LFS, artifacts, registry): 50GB PVC
- Prometheus (metrics): 10GB PVC
- Backup storage: 10GB PVC

## Prerequisites

**Infrastructure**:
- ✅ Longhorn storage class available
- ✅ cert-manager with `letsencrypt-prod` ClusterIssuer
- ✅ Traefik ingress controller
- ✅ MetalLB LoadBalancer

**DNS Configuration**:
- `gitlab.ops.last-try.org` → Traefik LoadBalancer IP
- `registry.ops.last-try.org` → Traefik LoadBalancer IP

**Resources Available**:
- Minimum 12GB RAM free (10GB for GitLab + 2GB headroom)
- Minimum 6 CPU cores
- 150GB disk space (for all PVCs)

## Deployment

### 1. Apply Certificate

```bash
kubectl apply -f workloads/gitlab/certificates/gitlab-tls.yaml

# Wait for certificate issuance
kubectl wait --for=condition=Ready certificate/gitlab-tls -n gitlab-prod --timeout=5m
```

### 2. Deploy GitLab via ArgoCD

```bash
# Apply ArgoCD Application
kubectl apply -f apps/workloads/gitlab-prod.yaml

# Watch deployment progress
kubectl get application gitlab-prod -n argocd -w
```

**Expected deployment time**: 10-15 minutes

### 3. Monitor Pod Startup

```bash
# Watch all pods come up
kubectl get pods -n gitlab-prod -w

# Check specific components
kubectl get pods -n gitlab-prod -l app=webservice
kubectl get pods -n gitlab-prod -l app=sidekiq
kubectl get pods -n gitlab-prod -l app=gitaly
kubectl get pods -n gitlab-prod -l app=registry
```

**Pod startup order**:
1. PostgreSQL, Redis, MinIO (30-60s)
2. Shared Secrets, Migrations (1-2 min)
3. Gitaly (30s)
4. Webservice, Sidekiq (2-3 min)
5. Registry, kas, Pages (1 min)

### 4. Retrieve Root Password

```bash
kubectl get secret gitlab-gitlab-initial-root-password \
  -n gitlab-prod \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

### 5. Access GitLab

**URL**: https://gitlab.ops.last-try.org
**Username**: `root`
**Password**: (from step 4)

**First Login Checklist**:
- [ ] Change root password
- [ ] Disable sign-ups: Admin Area → Settings → General → Sign-up restrictions
- [ ] Configure email (optional): Admin Area → Settings → Email
- [ ] Create first project
- [ ] Test git push/pull
- [ ] Test Container Registry push

## Configuration

### Container Registry

**Push an image**:
```bash
# Login to registry
docker login registry.ops.last-try.org

# Tag and push
docker tag myimage:latest registry.ops.last-try.org/myproject/myimage:latest
docker push registry.ops.last-try.org/myproject/myimage:latest
```

**Registry storage**: MinIO (bundled S3-compatible)
**Garbage collection**: Manual trigger via Toolbox pod (or configure CronJob)

### CI/CD Runners

**Option 1**: Use existing ARC runners (ADR 0014)
**Option 2**: Install GitLab Runners separately (see GitLab docs)

### Backups

**Automated backups**:
- Schedule: Daily at 2 AM
- Location: `/var/opt/gitlab/backups` (inside Toolbox pod)
- Storage: 10GB PVC (`gitlab-backup-storage`)

**Manual backup**:
```bash
kubectl exec -n gitlab-prod <toolbox-pod> -- \
  backup-utility --skip artifacts,registry,uploads
```

**What's backed up**:
- PostgreSQL database (metadata, issues, MRs)
- Git repositories (via Gitaly)
- CI/CD variables and secrets

**What's NOT backed up** (S3-backed, recoverable from MinIO):
- LFS objects
- CI/CD artifacts
- Container registry images
- User uploads

## Operations

### Scaling Up

**When to scale**:
- RAM usage sustained >90%
- CI/CD queue wait time >5 minutes
- Web UI response time >3 seconds
- Team size >10 users

**Increase replicas**:
```yaml
# In values.yaml
gitlab:
  webservice:
    replicaCount: 2  # Was: 1
    resources:
      limits:
        memory: 2Gi  # Was: 1.5Gi
  sidekiq:
    replicaCount: 2  # Was: 1
    pods:
      - concurrency: 20  # Was: 10
```

**Re-sync application**:
```bash
argocd app sync gitlab-prod
```

### Monitoring

**Key metrics**:
- `gitlab_transaction_duration_seconds` (request latency)
- `gitlab_ci_pending_builds` (CI queue depth)
- `sidekiq_queue_size` (background job backlog)
- `container_memory_working_set_bytes` (pod memory usage)

**Access Prometheus**:
```bash
kubectl port-forward -n gitlab-prod svc/gitlab-prometheus-server 9090:80
open http://localhost:9090
```

### Troubleshooting

**Pod stuck in Pending**:
```bash
kubectl describe pod <pod-name> -n gitlab-prod
# Check: Insufficient resources, PVC not bound, image pull errors
```

**Migrations failed**:
```bash
kubectl logs -n gitlab-prod <migrations-pod>
# Common causes: Database not ready, schema conflict
```

**Web UI not accessible**:
```bash
# Check certificate
kubectl get certificate gitlab-tls -n gitlab-prod

# Check ingress
kubectl get ingress -n gitlab-prod

# Check Traefik
kubectl logs -n traefik deployment/traefik
```

**Registry push fails**:
```bash
# Check registry pod logs
kubectl logs -n gitlab-prod <registry-pod>

# Check MinIO connectivity
kubectl exec -n gitlab-prod <registry-pod> -- \
  curl http://gitlab-minio-svc:9000
```

## Uninstallation

**⚠️ WARNING: This deletes ALL GitLab data**

```bash
# Delete ArgoCD Application (keeps PVCs)
kubectl delete application gitlab-prod -n argocd

# Optionally delete PVCs (DESTROYS DATA)
kubectl delete pvc -n gitlab-prod -l app=gitaly
kubectl delete pvc -n gitlab-prod -l app=postgresql
kubectl delete pvc -n gitlab-prod -l app=minio
```

## Performance Expectations

### What Works Well

- ✅ Git operations (clone, push, pull, merge)
- ✅ Code review (merge requests, diffs, comments)
- ✅ Issue tracking, project management
- ✅ CI/CD pipelines (1-2 concurrent jobs)
- ✅ Container Registry (push/pull images)
- ✅ GitLab Pages (static sites)
- ✅ 5-10 concurrent users

### What's Limited

- ⚠️ Web UI page loads: 2-3 seconds (acceptable)
- ⚠️ Image push times: 1-2 min per 500MB
- ⚠️ CI/CD queue: Jobs wait if >2 pipelines
- ⚠️ Large repos (>1GB): Slower clone/fetch
- ⚠️ No high availability (single replica)

### Breaking Points

- ❌ >3 concurrent CI/CD pipelines → Queue backlog
- ❌ >5 concurrent image pushes → Registry OOM
- ❌ >10 active users → Web UI slowness
- ❌ Large repo operations + CI build → Memory pressure

## Migration Path

### To External Services (Future Optimization)

When team/load grows, migrate to dedicated infrastructure:

1. **CloudNativePG** (PostgreSQL operator)
   - Create Cluster CRD
   - Migrate database via `pg_dump` / `pg_restore`
   - Update `values.yaml`: `postgresql.install: false`

2. **Valkey** (Redis-compatible)
   - Deploy StatefulSet (ADR 0005)
   - Update `values.yaml`: `redis.install: false`

3. **MinIO Tenant** (Dedicated S3 storage)
   - Create Tenant via MinIO Operator (ADR 0006)
   - Create buckets via MinIOJob CRD
   - Migrate data via `mc mirror`
   - Update `values.yaml`: `minio.install: false`

**Resource savings**: ~2-3GB RAM (shared infrastructure vs bundled)

## Related Documentation

- **ADR 0001**: GitOps with ArgoCD
- **ADR 0008**: cert-manager for TLS
- **ADR 0010**: GitOps Repository Structure
- **ADR 0011**: Traefik Ingress Controller
- **GitLab Helm Chart Docs**: https://docs.gitlab.com/charts/

## Support

**Issues**: Report in #infrastructure Slack channel or GitHub Issues
**Runbooks**: See `docs/runbooks/gitlab-operations.md`
**Monitoring**: Grafana dashboard `GitLab Overview` (TBD)
