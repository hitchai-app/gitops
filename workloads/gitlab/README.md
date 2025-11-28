# GitLab Deployment

Operations reference for GitLab CE with external infrastructure.

## Architecture

Uses shared infrastructure per ADRs:
- **PostgreSQL**: CloudNativePG cluster (`postgres-shared`) - ADR 0004
- **Redis**: Valkey StatefulSet - ADR 0005
- **Object Storage**: MinIO tenant - ADR 0006

## Quick Access

- **URL**: https://gitlab.ops.last-try.org
- **Registry**: https://registry.ops.last-try.org
- **Namespace**: `gitlab`

## Initial Setup

```bash
# Get root password
kubectl get secret gitlab-gitlab-initial-root-password \
  -n gitlab -o jsonpath='{.data.password}' | base64 -d
```

**First login**: Disable sign-ups in Admin Area → Settings → General

## Operations

### Registry Usage

```bash
docker login registry.ops.last-try.org
docker push registry.ops.last-try.org/myproject/image:tag
```

### Backups

Daily automated backups at 2 AM. Manual:
```bash
kubectl exec -n gitlab <toolbox-pod> -- backup-utility
```

### Monitoring

Metrics via kube-prometheus-stack ServiceMonitors.

Key metrics: `gitlab_transaction_duration_seconds`, `sidekiq_queue_size`

## Troubleshooting

```bash
# Pod issues
kubectl describe pod <pod> -n gitlab

# Database connectivity
kubectl exec -n gitlab <webservice-pod> -- \
  gitlab-rails dbconsole -p

# External services
kubectl get pods -n postgres   # PostgreSQL
kubectl get pods -n valkey     # Redis
kubectl get pods -n minio      # MinIO
```
