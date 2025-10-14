# 0018. Dex Authentication Provider

**Status**: Proposed

**Date**: 2025-10-14

## Context

We need centralized authentication for infrastructure and workload services:

**Infrastructure services:**
- ArgoCD (`argocd.ops.last-try.org`)
- Grafana (`grafana.ops.last-try.org`)
- SigNoz (`signoz.ops.last-try.org`)

**Workload services:**
- dev-ui stage (`app-stage.steady.ops.last-try.org`)
- dev-ui prod (`app.steady.ops.last-try.org`)

**Requirements:**
- Centralized user management (add user once, access all services)
- Small team (2-3 users initially)
- GitOps-compatible (users in Git, not database)
- Support GitHub authentication (team convenience)
- Support local accounts (contractors, fallback)
- Minimal operational overhead

**Current state:** No authentication on most services (publicly accessible)

## Decision

Deploy **Dex** as our OIDC authentication provider with a **two-tier integration strategy**:

**Tier 1: Native OIDC** (for services with built-in OIDC support)
- ArgoCD: Native OIDC integration
- Grafana: Native OIDC integration
- MinIO Console: Native OIDC integration

**Tier 2: OAuth2 Proxy** (for services without OIDC support)
- SigNoz: via oauth2-proxy (if no native OIDC)
- dev-ui (stage/prod): via oauth2-proxy
- Future services without native OIDC

**User sources:**
- **Primary:** GitHub organization connector (team members)
- **Fallback:** Static passwords in Git (contractors, non-GitHub users)

**Architecture:**
```
User → Traefik Ingress → Service (native OIDC) → Dex (login) → GitHub/Static
User → Traefik Ingress → OAuth2 Proxy → Service (no OIDC) → Dex → GitHub/Static
```

## Alternatives Considered

### 1. Authentik
- **Pros**: Web UI for user management, PostgreSQL backend, advanced features (LDAP, SAML, RBAC)
- **Cons**:
  - Requires PostgreSQL cluster (operational overhead)
  - Users in database (not GitOps)
  - ~500MB RAM vs Dex ~50MB
  - Overkill for 2-3 users
- **Why not chosen**: Contradicts GitOps-first approach, too heavy for small team

### 2. Keycloak
- **Pros**: Enterprise features, fine-grained RBAC, federation, extensive protocols
- **Cons**:
  - Heavy (~1GB RAM, Java-based)
  - Complex configuration
  - Requires database
  - Massive overkill for 2-3 users
- **Why not chosen**: Complexity and resource overhead unjustified

### 3. GitHub OAuth Only
- **Pros**: No infrastructure, leverages existing accounts, simple
- **Cons**:
  - Vendor lock-in (GitHub controls access)
  - External dependency (GitHub down = can't access infra)
  - No local users (can't add contractors without GitHub)
  - Can't switch providers later (locked to GitHub)
- **Why not chosen**: Not "our" service, lack of control

### 4. OAuth2 Proxy + GitHub Direct
- **Pros**: Lightweight, no OIDC provider needed
- **Cons**:
  - No central user management (configure GitHub per service)
  - Can't mix GitHub + local users
  - No OIDC for services that support it
  - Each service needs GitHub OAuth app
- **Why not chosen**: Doesn't centralize user management

### 5. Service-Native Auth (per-service users)
- **Pros**: No additional infrastructure
- **Cons**:
  - Add user to each service separately (ArgoCD, Grafana, SigNoz, etc.)
  - Different credentials per service
  - No SSO experience
  - Operational burden scales with services
- **Why not chosen**: Doesn't solve "add user once" requirement

## Consequences

### Positive
- ✅ **GitOps-native**: Users/config in Git, declarative, version-controlled
- ✅ **Zero persistence**: Stateless deployment, no database dependency
- ✅ **Lightweight**: ~50MB RAM vs Authentik ~500MB
- ✅ **Audit trail**: Git history shows who added/removed users
- ✅ **Flexible auth**: GitHub (convenience) + static passwords (fallback)
- ✅ **CNCF project**: Well-maintained, used by Kubernetes ecosystem
- ✅ **Single user management**: Add user once, access all services
- ✅ **Disaster recovery**: Git backup = user backup
- ✅ **No vendor lock-in**: Can change GitHub → GitLab without reconfiguring services

### Negative
- ⚠️ **No self-service**: Users can't reset passwords themselves (acceptable for 2-3 users)
- ⚠️ **Manual password hashing**: Use `htpasswd` to generate bcrypt hashes
- ⚠️ **No Web UI**: Manage users via YAML editing (acceptable for GitOps team)
- ⚠️ **OAuth2 Proxy overhead**: Additional pod per service without native OIDC
- ⚠️ **Per-service OIDC config**: Each service needs Dex client configuration (one-time)

### Neutral
- Dex configuration lives in Git (ConfigMap + Sealed Secrets)
- GitHub connector requires GitHub OAuth app creation
- Static passwords use bcrypt hashes (secure, standard)
- Migration to Authentik/Keycloak possible if team grows (export users)

## Implementation

### Phase 1: Dex Core Deployment

**Components:**
- Dex Deployment (stateless, 2 replicas for HA)
- ConfigMap: Dex configuration (users, connectors, clients)
- Sealed Secrets: Client secrets, GitHub OAuth credentials
- Service: ClusterIP for internal access
- Ingress: `auth.ops.last-try.org` (Dex login UI)

**Resource allocation:**
- Dex: 100m CPU / 128Mi RAM (limits: 200m / 256Mi)
- Total: ~0.2 CPU / 0.5Gi RAM (negligible on 12 CPU / 128GB cluster)

**Configuration:**
```yaml
# Dex config structure (actual in ConfigMap)
issuer: https://auth.ops.last-try.org

connectors:
  - type: github
    id: github
    name: GitHub
    config:
      clientID: $GITHUB_CLIENT_ID
      clientSecret: $GITHUB_CLIENT_SECRET
      orgs:
        - name: hitchai-app  # GitHub organization

staticPasswords:
  - email: user@company.com
    hash: $2a$10$...  # bcrypt hash via htpasswd
    username: user

staticClients:
  - id: argocd
    redirectURIs: ['https://argocd.ops.last-try.org/auth/callback']
    name: 'ArgoCD'
    secret: <sealed>
  - id: grafana
    redirectURIs: ['https://grafana.ops.last-try.org/login/generic_oauth']
    name: 'Grafana'
    secret: <sealed>
  # ... more clients
```

### Phase 2: OAuth2 Proxy for Non-OIDC Services

**Deploy oauth2-proxy as sidecar pattern:**
```
User → Traefik → oauth2-proxy sidecar → dev-ui container
                       ↓
                    Dex OIDC
```

**Example: dev-ui protection**
- Add oauth2-proxy sidecar to dev-ui deployment
- Configure Traefik to route through oauth2-proxy
- OAuth2-proxy validates Dex token, proxies to dev-ui

**Resource per oauth2-proxy instance:**
- 50m CPU / 64Mi RAM (limits: 100m / 128Mi)

### Phase 3: Native OIDC Integration

**ArgoCD:**
```yaml
# ArgoCD ConfigMap
data:
  oidc.config: |
    name: Dex
    issuer: https://auth.ops.last-try.org
    clientID: argocd
    clientSecret: $oidc.dex.clientSecret
    requestedScopes: ["openid", "profile", "email", "groups"]
```

**Grafana:**
```yaml
# Grafana values
grafana.ini:
  auth.generic_oauth:
    enabled: true
    name: Dex
    client_id: grafana
    client_secret: $GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET
    auth_url: https://auth.ops.last-try.org/auth
    token_url: https://auth.ops.last-try.org/token
    api_url: https://auth.ops.last-try.org/userinfo
```

**SigNoz:**
- Check if SigNoz v0.94.0 supports OIDC (verify in docs)
- If yes: Native OIDC config
- If no: Deploy oauth2-proxy sidecar

### Phase 4: Workload Protection (dev-ui)

**Priority:** Start with dev-ui (stage/prod) using oauth2-proxy

**Rationale:**
- Dev-ui likely has no native auth
- Non-critical (good test case)
- Both stage/prod use same pattern

**Implementation:**
1. Deploy oauth2-proxy as deployment (shared for both stage/prod)
2. Update Traefik IngressRoute to authenticate via oauth2-proxy
3. Verify login flow works
4. Apply same pattern to prod

### Phased Rollout Order

1. **Dex deployment** (infrastructure)
2. **dev-ui stage** (oauth2-proxy test)
3. **dev-ui prod** (apply proven pattern)
4. **ArgoCD** (native OIDC, critical infra)
5. **Grafana** (native OIDC)
6. **SigNoz** (native or oauth2-proxy)

## User Management Workflow

### Add New User (GitHub)

If user is in `hitchai-app` GitHub organization:
- No config change needed
- User visits service → redirects to Dex → "Login with GitHub" → access granted

### Add New User (Static Password)

```bash
# 1. Generate bcrypt hash
htpasswd -bnBC 10 "" password | sed 's/^://'

# 2. Add to Dex ConfigMap
staticPasswords:
  - email: contractor@external.com
    hash: $2a$10$...
    username: contractor

# 3. Commit to Git, ArgoCD syncs, Dex reloads
```

### Remove User

**GitHub user:**
- Remove from GitHub organization → immediately loses access

**Static user:**
- Remove from Dex ConfigMap → commit → sync → Dex reloads

## Security Considerations

**TLS:**
- All Dex communication over HTTPS (cert-manager issued certs)
- Client secrets stored as Sealed Secrets (encrypted in Git)

**Token lifetime:**
- ID tokens: 24 hours (Dex default)
- Refresh tokens: 30 days

**GitHub permissions:**
- Only members of `hitchai-app` org can login via GitHub
- Can restrict to specific teams if needed

**Password policy:**
- Static passwords: bcrypt cost 10 (secure)
- Recommend strong passwords (no enforcement, small team trust-based)

## Monitoring

**Metrics:**
- Dex exposes Prometheus metrics on `/metrics`
- Track: login attempts, failures, token issuance

**Alerts:**
- Dex pod down
- Login failure rate > threshold
- GitHub connector errors

**Logging:**
- Dex logs all authentication events
- Centralized via observability stack (ADR 0017)

## When to Reconsider

**Migrate to Authentik/Keycloak if:**
1. Team grows to 10+ users (self-service becomes valuable)
2. Need complex RBAC (per-user permissions, groups)
3. Compliance requires audit trails beyond Git history
4. Need LDAP/SAML support
5. Non-technical users need to reset passwords

**Switch to managed service (Auth0, Okta) if:**
1. Auth becomes critical path (need 99.9% SLA)
2. Team can't maintain Dex
3. Need 24/7 support

## Migration Path

**From Dex to Authentik:**
1. Deploy Authentik alongside Dex
2. Recreate users in Authentik (export from Git)
3. Update service OIDC configs to point to Authentik
4. Decommission Dex

**Services remain unchanged** (OIDC standard, just change issuer URL)

## References

- [Dex Documentation](https://dexidp.io/docs/)
- [Dex GitHub Connector](https://dexidp.io/docs/connectors/github/)
- [ArgoCD OIDC](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#dex)
- [OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/)
- ADR 0001: GitOps with ArgoCD
- ADR 0009: Secrets Management Strategy
