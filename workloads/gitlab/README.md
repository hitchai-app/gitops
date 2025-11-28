# GitLab Deployment

Operations reference for GitLab CE with dedicated infrastructure.

## Architecture

All services deployed in `gitlab` namespace:
- **PostgreSQL**: CloudNativePG cluster (`gitlab-postgres`) - ADR 0004
- **Redis**: Valkey StatefulSet (`gitlab-valkey`) - ADR 0005
- **Object Storage**: MinIO tenant (`gitlab-minio`) - ADR 0006

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

## Troubleshooting

```bash
# Pod status
kubectl get pods -n gitlab

# Database connectivity
kubectl exec -n gitlab <webservice-pod> -- gitlab-rails dbconsole -p

# Component logs
kubectl logs -n gitlab deployment/gitlab-webservice-default
kubectl logs -n gitlab statefulset/gitlab-postgres-1
kubectl logs -n gitlab statefulset/gitlab-valkey
```
