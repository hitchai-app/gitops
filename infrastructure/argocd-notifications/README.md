# ArgoCD Notifications

Discord notifications for ArgoCD deployment events.

## Overview

ArgoCD Notifications sends real-time updates to Discord when applications are deployed, sync fails, or health degrades.

## What Gets Notified

### 🚀 Successful Deployment (`on-deployed`)
- Triggers when: Sync succeeds **and** app is healthy
- Color: Green (3066993)
- Shows: Environment, sync status, health, git revision

### ❌ Sync Failed (`on-sync-failed`)
- Triggers when: Sync fails or errors
- Color: Red (15158332)
- Shows: Environment, sync status, error message

### ⚠️ Health Degraded (`on-health-degraded`)
- Triggers when: App health changes to degraded
- Color: Yellow (16776960)
- Shows: Environment, health status, sync status

## Configuration

### Discord Webhook

Webhook URL is configured in `configmap.yaml`:

```yaml
service.webhook.discord: |
  url: https://discord.com/api/webhooks/...
  headers:
  - name: Content-Type
    value: application/json
```

**To update webhook:**
1. Get new webhook from Discord: Server Settings → Integrations → Webhooks
2. Edit `configmap.yaml` with new URL
3. Apply: `kubectl apply -f infrastructure/argocd-notifications/configmap.yaml`

### Default Subscriptions

All applications automatically subscribe to:
- `on-deployed`
- `on-sync-failed`
- `on-health-degraded`

This is configured in the `subscriptions` section of the ConfigMap.

### Per-App Subscriptions

To override subscriptions for specific apps, add annotations:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    # Subscribe to specific triggers
    notifications.argoproj.io/subscribe.on-deployed.discord: ""
    notifications.argoproj.io/subscribe.on-sync-failed.discord: ""

    # Or unsubscribe from all
    notifications.argoproj.io/subscribe: ""
```

## Installation

ArgoCD Notifications is included in standard ArgoCD installation (v2.0+).

**Enable notifications in ArgoCD Helm values:**

```yaml
notifications:
  enabled: true
```

**Apply this ConfigMap:**

```bash
kubectl apply -f infrastructure/argocd-notifications/configmap.yaml
```

## Testing

Test notifications without waiting for actual deployments:

```bash
# Trigger a test notification
kubectl patch app <app-name> -n argocd \
  -p '{"metadata":{"annotations":{"notifications.argoproj.io/test.discord":""}}}' \
  --type merge
```

## Troubleshooting

### Notifications not sending

1. **Check notifications controller is running:**
   ```bash
   kubectl get pods -n argocd | grep notifications
   ```

2. **Check controller logs:**
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-notifications-controller
   ```

3. **Verify Discord webhook URL:**
   ```bash
   curl -X POST https://discord.com/api/webhooks/... \
     -H "Content-Type: application/json" \
     -d '{"content":"Test message"}'
   ```

4. **Check app subscriptions:**
   ```bash
   kubectl get app <app-name> -n argocd \
     -o jsonpath='{.metadata.annotations}'
   ```

### Discord returns 404

- Webhook URL is incorrect or webhook was deleted
- Get new webhook from Discord server settings

### Messages not formatted correctly

- Check ConfigMap templates for syntax errors
- Verify JSON is valid (no trailing commas)
- Test with simple template first

## Customization

### Add New Triggers

1. Define trigger in ConfigMap:
   ```yaml
   trigger.on-out-of-sync: |
     - when: app.status.sync.status == 'OutOfSync'
       send: [app-out-of-sync]
   ```

2. Create template:
   ```yaml
   template.app-out-of-sync: |
     webhook:
       discord:
         method: POST
         body: |
           { ... }
   ```

3. Add to subscriptions or app annotations

### Change Message Format

Edit templates in `configmap.yaml`. See [Discord Embed Documentation](https://discord.com/developers/docs/resources/channel#embed-object) for formatting options.

### Available Template Variables

- `{{.app.metadata.name}}` - Application name
- `{{.app.metadata.namespace}}` - Namespace
- `{{.app.status.sync.status}}` - Sync status (Synced/OutOfSync)
- `{{.app.status.sync.revision}}` - Git commit SHA
- `{{.app.status.health.status}}` - Health status (Healthy/Degraded/Progressing)
- `{{.app.status.operationState.message}}` - Error message
- `{{.context.argocdUrl}}` - ArgoCD UI URL

See [ArgoCD Notification Docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/templates/) for full list.

## References

- [ArgoCD Notifications Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/notifications/)
- [Discord Webhook Format](https://discord.com/developers/docs/resources/webhook)
- [ArgoCD Notification Catalog](https://github.com/argoproj/argo-cd/tree/master/notifications_catalog)
