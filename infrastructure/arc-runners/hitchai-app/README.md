# hitchai-app Runner Scale Set

GitHub Actions self-hosted runners for the `hitchai-app` organization.

## Overview

This runner scale set provides ephemeral GitHub Actions runners that:
- Scale automatically based on workflow demand (0-5 runners)
- Use Docker-in-Docker for containerized jobs
- Run in the `arc-runners` namespace
- Are managed by the ARC controller in `arc-systems`

## Setup

### Prerequisites

1. **ARC Controller** must be installed first (see `infrastructure/arc-controller/`)
2. **Sealed Secrets** controller must be running
3. **GitHub PAT** with appropriate permissions

### GitHub Authentication

This runner scale set uses **GitHub App authentication** (more secure than PAT):
- ✅ Fine-grained permissions (not tied to user account)
- ✅ Can be scoped to specific repositories
- ✅ Better audit trail
- ✅ Doesn't expire when user leaves org

GitHub App requirements:
- App installed on `hitchai-app` organization
- Permissions: Actions (read/write), Metadata (read)
- App has access to repositories where runners will be used

See [GitHub App authentication docs](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/authenticating-to-the-github-api)

### Create Sealed Secret from Existing Secret

Since you already have the secret (`pre-defined-secret`) in the cluster, just extract and seal it:

```bash
# 1. Fetch sealed-secrets public cert
kubeseal --fetch-cert > sealed-secrets-pub.pem

# 2. Extract existing secret and rename it
kubectl get secret pre-defined-secret -n arc-runners -o yaml | \
  sed 's/name: pre-defined-secret/name: hitchai-app-github-app/' | \
  sed '/uid:/d' | sed '/resourceVersion:/d' | sed '/creationTimestamp:/d' \
  > /tmp/github-app-secret.yaml

# 3. Seal it
kubeseal --format=yaml --cert=sealed-secrets-pub.pem \
  < /tmp/github-app-secret.yaml \
  > github-app-sealed.yaml

# 4. Clean up temporary file
rm /tmp/github-app-secret.yaml

# 5. Commit sealed secret
git add github-app-sealed.yaml
git commit -m "chore(arc): add sealed GitHub App credentials for hitchai-app runners"
```

## Usage in Workflows

Reference this runner scale set in your GitHub Actions workflows:

```yaml
name: Example Workflow
on: push

jobs:
  build:
    runs-on: hitchai-app-runners  # ← Use this runner scale set
    steps:
      - uses: actions/checkout@v4
      - run: echo "Running on self-hosted ARC runner!"
```

## Configuration

Key settings in `values.yaml`:
- **Min runners**: 0 (scale to zero when idle)
- **Max runners**: 5
- **Runner group**: Default
- **Container mode**: Docker-in-Docker
- **Resources**: 500m-2 CPU, 1-4Gi memory per runner

## Monitoring

Check runner status:

```bash
# Check runner pods
kubectl get pods -n arc-runners

# Check listener pod
kubectl get pods -n arc-systems -l app.kubernetes.io/name=hitchai-app-runners

# Check autoscaling events
kubectl describe autoscalingrunnerset hitchai-app-runners -n arc-runners
```

## Troubleshooting

### Runners not scaling up

1. Check listener pod logs:
   ```bash
   kubectl logs -n arc-systems -l app.kubernetes.io/name=hitchai-app-runners
   ```

2. Verify GitHub token secret:
   ```bash
   kubectl get secret hitchai-app-github-token -n arc-runners
   ```

3. Check controller logs:
   ```bash
   kubectl logs -n arc-systems deployment/arc-gha-rs-controller
   ```

### Runner pods failing

1. Check runner pod logs:
   ```bash
   kubectl logs -n arc-runners <pod-name> -c runner
   ```

2. Check Docker-in-Docker container:
   ```bash
   kubectl logs -n arc-runners <pod-name> -c dind
   ```

### Authentication errors

- Verify GitHub PAT has correct scopes
- Check token hasn't expired
- Ensure `githubConfigUrl` matches your organization

## Scaling

To adjust runner scaling:

1. Edit `values.yaml`:
   ```yaml
   minRunners: 1  # Keep 1 runner warm
   maxRunners: 10  # Allow up to 10 concurrent runners
   ```

2. Commit and push - ArgoCD will sync automatically

## Security Notes

- Runners use ephemeral pods (destroyed after each job)
- Docker-in-Docker requires privileged containers
- GitHub token stored as sealed secret (encrypted in Git)
- Consider using GitHub App authentication for better security

## References

- [ARC Documentation](https://github.com/actions/actions-runner-controller)
- [GitHub App Authentication](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/authenticating-to-the-github-api)
- ADR: (to be created)
