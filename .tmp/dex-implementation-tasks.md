# Dex Authentication Implementation Tasks

**Reference**: ADR 0018 - Dex Authentication Provider

**Goal**: Deploy Dex as centralized OIDC provider and protect services

**Start with**: dev-ui (stage) using oauth2-proxy as pilot

---

## Phase 1: Dex Core Infrastructure

### Task 1.1: GitHub OAuth Application Setup

**Manual steps** (one-time, not GitOps):

```bash
# 1. Create GitHub OAuth App
# Visit: https://github.com/organizations/hitchai-app/settings/applications
# New OAuth App with:
#   Name: Dex Authentication (ops cluster)
#   Homepage URL: https://auth.ops.last-try.org
#   Authorization callback URL: https://auth.ops.last-try.org/callback

# 2. Save credentials (will be Sealed Secret)
export GITHUB_CLIENT_ID="..."
export GITHUB_CLIENT_SECRET="..."
```

### Task 1.2: Create Dex Namespace and Resources

**Files to create**:

```
infrastructure/dex/
├── namespace.yaml
├── deployment.yaml          # Dex deployment (2 replicas)
├── service.yaml             # ClusterIP service
├── ingress.yaml             # auth.ops.last-try.org
├── configmap.yaml           # Dex configuration
└── secrets-sealed.yaml      # GitHub OAuth + client secrets
```

**Dex ConfigMap structure**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: dex
  namespace: dex
data:
  config.yaml: |
    issuer: https://auth.ops.last-try.org
    storage:
      type: memory  # Stateless
    web:
      http: 0.0.0.0:5556

    connectors:
      - type: github
        id: github
        name: GitHub
        config:
          clientID: $GITHUB_CLIENT_ID
          clientSecret: $GITHUB_CLIENT_SECRET
          orgs:
            - name: hitchai-app

    staticClients:
      - id: oauth2-proxy-dev-ui
        redirectURIs:
          - 'https://app-stage.steady.ops.last-try.org/oauth2/callback'
        name: 'dev-ui OAuth2 Proxy'
        secretEnv: DEX_CLIENT_SECRET_DEV_UI

    staticPasswords: []  # Add later if needed
```

### Task 1.3: Create ArgoCD Application

**File**: `apps/infrastructure/dex.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dex
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/hitchai-app/gitops
    targetRevision: master
    path: infrastructure/dex
  destination:
    server: https://kubernetes.default.svc
    namespace: dex
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Task 1.4: Generate and Seal Client Secrets

```bash
# Generate random client secret for oauth2-proxy
openssl rand -hex 32

# Create sealed secret
kubectl create secret generic dex-clients \
  -n dex \
  --from-literal=github-client-id=$GITHUB_CLIENT_ID \
  --from-literal=github-client-secret=$GITHUB_CLIENT_SECRET \
  --from-literal=dev-ui-client-secret=<generated-secret> \
  --dry-run=client -o yaml | \
  kubeseal --cert pub.pem > infrastructure/dex/secrets-sealed.yaml
```

### Task 1.5: Deploy and Verify Dex

```bash
# Commit and push
git add apps/infrastructure/dex.yaml infrastructure/dex/
git commit -m "feat(auth): add Dex OIDC provider with GitHub connector"
git push

# Verify deployment
kubectl get pods -n dex
kubectl get ingress -n dex
curl https://auth.ops.last-try.org/.well-known/openid-configuration
```

**Expected**: Dex running, OIDC discovery endpoint returns config

---

## Phase 2: OAuth2 Proxy for dev-ui (Stage)

### Task 2.1: Deploy OAuth2 Proxy

**Strategy**: Deploy oauth2-proxy as separate deployment (shared pattern)

**File**: `infrastructure/oauth2-proxy/dev-ui-stage.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oauth2-proxy-dev-ui-stage
  namespace: steady-stage
spec:
  replicas: 2
  selector:
    matchLabels:
      app: oauth2-proxy-dev-ui
  template:
    metadata:
      labels:
        app: oauth2-proxy-dev-ui
    spec:
      containers:
      - name: oauth2-proxy
        image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
        args:
          - --provider=oidc
          - --provider-display-name=Dex
          - --oidc-issuer-url=https://auth.ops.last-try.org
          - --client-id=oauth2-proxy-dev-ui
          - --client-secret-file=/secrets/client-secret
          - --cookie-secret-file=/secrets/cookie-secret
          - --email-domain=*
          - --upstream=http://dev-ui.steady-stage.svc.cluster.local:3000
          - --http-address=0.0.0.0:4180
          - --redirect-url=https://app-stage.steady.ops.last-try.org/oauth2/callback
          - --skip-provider-button=true
        ports:
        - containerPort: 4180
          name: http
        volumeMounts:
        - name: secrets
          mountPath: /secrets
          readOnly: true
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
      volumes:
      - name: secrets
        secret:
          secretName: oauth2-proxy-dev-ui-secrets
---
apiVersion: v1
kind: Service
metadata:
  name: oauth2-proxy-dev-ui
  namespace: steady-stage
spec:
  selector:
    app: oauth2-proxy-dev-ui
  ports:
  - port: 4180
    targetPort: 4180
```

### Task 2.2: Create OAuth2 Proxy Secrets

```bash
# Generate cookie secret
openssl rand -base64 32

# Create sealed secret
kubectl create secret generic oauth2-proxy-dev-ui-secrets \
  -n steady-stage \
  --from-literal=client-secret=<from-dex-secrets> \
  --from-literal=cookie-secret=<generated-cookie-secret> \
  --dry-run=client -o yaml | \
  kubeseal --cert pub.pem > infrastructure/oauth2-proxy/dev-ui-stage-secrets-sealed.yaml
```

### Task 2.3: Update dev-ui Ingress (Stage)

**Before** (no auth):
```yaml
spec:
  rules:
  - host: app-stage.steady.ops.last-try.org
    http:
      paths:
      - path: /
        backend:
          service:
            name: dev-ui
            port: 3000
```

**After** (oauth2-proxy):
```yaml
spec:
  rules:
  - host: app-stage.steady.ops.last-try.org
    http:
      paths:
      - path: /oauth2
        backend:
          service:
            name: oauth2-proxy-dev-ui
            port: 4180
      - path: /
        backend:
          service:
            name: oauth2-proxy-dev-ui  # Changed to proxy
            port: 4180
```

**Note**: oauth2-proxy forwards authenticated requests to upstream (dev-ui)

### Task 2.4: Deploy and Test

```bash
# Commit and push
git add infrastructure/oauth2-proxy/
git commit -m "feat(auth): protect dev-ui stage with oauth2-proxy + Dex"
git push

# Test authentication flow
# 1. Visit https://app-stage.steady.ops.last-try.org
# 2. Should redirect to https://auth.ops.last-try.org
# 3. Click "Login with GitHub"
# 4. GitHub OAuth consent (first time)
# 5. Redirect back to dev-ui with session cookie
# 6. Access granted

# Verify cookie
# Check browser dev tools: cookie `_oauth2_proxy` should be set
```

**Success criteria**:
- ✅ Unauthenticated access redirects to Dex
- ✅ GitHub login works (hitchai-app org members)
- ✅ Authenticated users see dev-ui
- ✅ Session persists (cookie)

---

## Phase 3: Replicate to dev-ui (Prod)

### Task 3.1: Copy Pattern to Prod

```bash
# Copy oauth2-proxy deployment to prod namespace
cp infrastructure/oauth2-proxy/dev-ui-stage.yaml \
   infrastructure/oauth2-proxy/dev-ui-prod.yaml

# Update:
# - namespace: steady-stage → steady-prod
# - upstream: steady-stage → steady-prod
# - redirect-url: app-stage → app (prod domain)

# Generate separate cookie secret for prod (isolation)
```

### Task 3.2: Add Prod Client to Dex

**Update**: `infrastructure/dex/configmap.yaml`

```yaml
staticClients:
  - id: oauth2-proxy-dev-ui-stage
    redirectURIs: ['https://app-stage.steady.ops.last-try.org/oauth2/callback']
    name: 'dev-ui Stage'
    secretEnv: DEX_CLIENT_SECRET_DEV_UI_STAGE

  - id: oauth2-proxy-dev-ui-prod  # New
    redirectURIs: ['https://app.steady.ops.last-try.org/oauth2/callback']
    name: 'dev-ui Prod'
    secretEnv: DEX_CLIENT_SECRET_DEV_UI_PROD
```

### Task 3.3: Deploy Prod Protection

```bash
git commit -m "feat(auth): protect dev-ui prod with oauth2-proxy + Dex"
git push

# Test same flow on https://app.steady.ops.last-try.org
```

---

## Phase 4: ArgoCD Native OIDC

### Task 4.1: Update ArgoCD ConfigMap

**File**: `infrastructure/argocd/oidc-config.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  oidc.config: |
    name: Dex
    issuer: https://auth.ops.last-try.org
    clientID: argocd
    clientSecret: $oidc.dex.clientSecret
    requestedScopes:
      - openid
      - profile
      - email
      - groups
```

### Task 4.2: Add ArgoCD to Dex Clients

**Update**: `infrastructure/dex/configmap.yaml`

```yaml
staticClients:
  # ... existing ...
  - id: argocd
    redirectURIs: ['https://argocd.ops.last-try.org/auth/callback']
    name: 'ArgoCD'
    secretEnv: DEX_CLIENT_SECRET_ARGOCD
```

### Task 4.3: Configure ArgoCD RBAC

**File**: `infrastructure/argocd/rbac-config.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    # GitHub org members get admin
    g, hitchai-app:team-admins, role:admin

    # All authenticated users get readonly
    p, role:readonly, applications, get, */*, allow
    p, role:readonly, repositories, get, *, allow
```

### Task 4.4: Test ArgoCD Login

```bash
# Visit https://argocd.ops.last-try.org
# Click "LOG IN VIA DEX"
# GitHub OAuth
# Should see ArgoCD UI with appropriate permissions
```

---

## Phase 5: Grafana Native OIDC

### Task 5.1: Update Grafana Helm Values

**File**: `infrastructure/observability/values.yaml`

```yaml
grafana:
  grafana.ini:
    server:
      root_url: https://grafana.ops.last-try.org

    auth.generic_oauth:
      enabled: true
      name: Dex
      allow_sign_up: true
      client_id: grafana
      client_secret: $__file{/etc/secrets/oauth/client-secret}
      scopes: openid profile email groups
      auth_url: https://auth.ops.last-try.org/auth
      token_url: https://auth.ops.last-try.org/token
      api_url: https://auth.ops.last-try.org/userinfo
      allowed_domains: ""
      role_attribute_path: contains(groups[*], 'hitchai-app:team-admins') && 'Admin' || 'Viewer'

  extraSecretMounts:
    - name: oauth-secret
      secretName: grafana-oauth-secret
      defaultMode: 0440
      mountPath: /etc/secrets/oauth
      readOnly: true
```

### Task 5.2: Add Grafana to Dex Clients

```yaml
staticClients:
  # ... existing ...
  - id: grafana
    redirectURIs: ['https://grafana.ops.last-try.org/login/generic_oauth']
    name: 'Grafana'
    secretEnv: DEX_CLIENT_SECRET_GRAFANA
```

---

## Phase 6: SigNoz OIDC (Research Required)

### Task 6.1: Research SigNoz OIDC Support

```bash
# Check SigNoz v0.94.0 documentation
# https://signoz.io/docs/
# Search for: OIDC, OAuth, authentication, SSO

# If supported: Native OIDC config
# If not supported: Deploy oauth2-proxy (same pattern as dev-ui)
```

### Task 6.2a: Native OIDC (if supported)

**TODO**: Add config similar to Grafana

### Task 6.2b: OAuth2 Proxy (if not supported)

**TODO**: Apply same pattern as dev-ui (separate deployment)

---

## Resource Summary

**After full implementation**:

| Component | CPU (request/limit) | Memory (request/limit) | Count |
|-----------|-------------------|---------------------|-------|
| Dex | 100m / 200m | 128Mi / 256Mi | 2 pods |
| oauth2-proxy (dev-ui stage) | 50m / 100m | 64Mi / 128Mi | 2 pods |
| oauth2-proxy (dev-ui prod) | 50m / 100m | 64Mi / 128Mi | 2 pods |
| oauth2-proxy (signoz, if needed) | 50m / 100m | 64Mi / 128Mi | 2 pods |
| **Total** | **400m / 800m** | **512Mi / 1Gi** | **8 pods** |

**Percentage of cluster**: ~3% CPU / ~0.4% RAM (acceptable overhead for centralized auth)

---

## Testing Checklist

### Per-Service Tests

- [ ] Dex: `/.well-known/openid-configuration` returns valid OIDC config
- [ ] Dex: GitHub login redirects and succeeds
- [ ] dev-ui stage: Unauthenticated redirects to Dex
- [ ] dev-ui stage: GitHub auth grants access
- [ ] dev-ui stage: Session cookie persists across page reloads
- [ ] dev-ui prod: Same tests as stage
- [ ] ArgoCD: "Login via Dex" button appears
- [ ] ArgoCD: GitHub members get correct RBAC role
- [ ] Grafana: OAuth login option appears
- [ ] Grafana: GitHub members get correct role (Admin/Viewer)
- [ ] SigNoz: Authentication flow works

### Security Tests

- [ ] Direct access to backend bypasses auth? (should fail if oauth2-proxy)
- [ ] Invalid token rejected
- [ ] Token expiry enforced (24h)
- [ ] Logout clears session
- [ ] Non-org GitHub users denied (if using org restriction)

### Operational Tests

- [ ] Add static user: edit ConfigMap, commit, Dex reloads
- [ ] Remove user: remove from ConfigMap, access revoked
- [ ] Dex pod restart: sessions survive (cookie-based)
- [ ] Metrics exposed: Dex `/metrics`, oauth2-proxy `/metrics`

---

## Rollback Plan

### Per-Service Rollback

**dev-ui**:
```bash
# Revert ingress to point directly to dev-ui service
git revert <commit-hash>
git push
# Immediate: traffic flows to dev-ui without auth
```

**ArgoCD/Grafana**:
```bash
# Remove OIDC config from values
# Existing admin credentials still work
git revert <commit-hash>
git push
```

**Full Dex Removal**:
```bash
# Delete ArgoCD Application
kubectl delete application dex -n argocd
# All services revert to previous auth (or no auth)
```

**No data loss**: Dex is stateless, no persistence to backup/restore

---

## Next Steps After Implementation

1. **Add static users** (if needed for contractors)
2. **Configure session timeout** (default 24h, adjust if needed)
3. **Set up monitoring alerts** (Dex down, login failures)
4. **Document user onboarding** (how to add/remove users)
5. **Test disaster recovery** (Dex pod deletion, GitHub OAuth app misconfiguration)

---

## References

- ADR 0018: Dex Authentication Provider
- [Dex GitHub Connector Docs](https://dexidp.io/docs/connectors/github/)
- [OAuth2 Proxy Docs](https://oauth2-proxy.github.io/oauth2-proxy/)
- [ArgoCD OIDC Docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#dex)
- [Grafana OAuth Docs](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/generic-oauth/)
