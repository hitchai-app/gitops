# GitLab Deployment

Operations reference for GitLab CE.

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

Daily automated backups at 2 AM to `/var/opt/gitlab/backups` (Toolbox pod).

Manual backup:
```bash
kubectl exec -n gitlab <toolbox-pod> -- \
  backup-utility --skip artifacts,registry,uploads
```

### Monitoring

```bash
kubectl port-forward -n gitlab svc/gitlab-prometheus-server 9090:80
```

Key metrics: `gitlab_transaction_duration_seconds`, `gitlab_ci_pending_builds`, `sidekiq_queue_size`

### Scaling

Edit `values.yaml` to increase `replicaCount` or resource limits, then:
```bash
argocd app sync gitlab
```

## Troubleshooting

```bash
# Pod issues
kubectl describe pod <pod> -n gitlab
kubectl logs -n gitlab <pod>

# Certificate issues
kubectl get certificate gitlab-tls -n gitlab

# Ingress issues
kubectl get ingress -n gitlab
kubectl logs -n traefik deployment/traefik
```

## Migration to External Services

When scaling up, can migrate bundled services to dedicated infrastructure:
- CloudNativePG (PostgreSQL)
- Valkey (Redis)
- MinIO Tenant (S3 storage)

Saves ~2-3GB RAM. See ADRs 0004, 0005, 0006.
