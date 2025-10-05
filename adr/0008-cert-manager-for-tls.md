# 0008. cert-manager for TLS Certificates

**Status**: Accepted

**Date**: 2025-10-05

## Context

We need TLS certificates for external-facing services:
- ArgoCD UI
- MinIO Console
- Grafana
- Future ingress controllers

Requirements:
- Publicly trusted certificates (browser-compatible)
- Automatic renewal
- GitOps-compatible (declarative)
- Minimal operational overhead

DNS provider: Cloudflare

## Decision

We will use **cert-manager** (CNCF Graduated) with **Let's Encrypt DNS-01 challenge** via Cloudflare.

Configuration:
- Let's Encrypt ClusterIssuer (production + staging)
- DNS-01 challenge using Cloudflare webhook
- Explicit Certificate CRDs per service
- 90-day certificates with automatic renewal

## Alternatives Considered

### 1. HTTP-01 Challenge (Instead of DNS-01)
- **Pros**: Simpler setup, no DNS API credentials needed
- **Cons**:
  - Cannot issue wildcard certificates
  - Requires services publicly accessible on port 80
  - Requires ingress controller first
- **Why not chosen**: DNS-01 more flexible, supports wildcards, works for services behind firewall

### 2. Self-Signed Certificates
- **Pros**: No external dependencies, complete control
- **Cons**:
  - Browser warnings (not publicly trusted)
  - Complex trust distribution (every client must trust CA)
  - Operational overhead of running PKI
- **Why not chosen**: Let's Encrypt provides public trust without PKI complexity

### 3. Manual Certificate Management
- **Pros**: Full control, no dependencies
- **Cons**: Manual renewal, human error risk, not GitOps-friendly
- **Why not chosen**: Automation critical for reliability

## Consequences

### Positive

**Operational:**
- ✅ Automatic renewal (certs renew at ~60 days before 90-day expiry)
- ✅ Declarative configuration (Certificate CRDs in Git)
- ✅ No manual intervention
- ✅ Publicly trusted (no browser warnings)

**Technical:**
- ✅ DNS-01 supports wildcard certificates (`*.example.com`)
- ✅ Works for services behind firewall (no public HTTP exposure needed)
- ✅ Can issue certificates before deploying services
- ✅ Cloudflare webhook well-maintained

**Production Readiness:**
- ✅ CNCF Graduated (Sept 2024)
- ✅ 500M downloads/month
- ✅ Industry standard (86% of production clusters)

### Negative

**Dependencies:**
- ❌ Requires Let's Encrypt availability
- ❌ Requires Cloudflare API access
- ❌ 90-day validity requires robust automation (built-in)
- ❌ Rate limits (50 certs/domain/week - mitigated by staging endpoint)

**Operational:**
- ⚠️ Cloudflare API token must be secured (bootstrap secret)
- ⚠️ DNS-01 requires webhook installation

### Neutral
- Let's Encrypt staging endpoint available for testing
- Can add self-signed CA later if internal TLS needed (separate use case)

## DNS-01 vs HTTP-01

**DNS-01 (our choice):**
- cert-manager creates TXT record via Cloudflare API
- Let's Encrypt verifies DNS record
- Supports wildcards, works behind firewall

**HTTP-01 (not chosen):**
- Let's Encrypt makes HTTP request to `/.well-known/acme-challenge/`
- Requires port 80 publicly accessible
- No wildcard support

## Implementation Notes

### ClusterIssuer Configuration

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
```

### Certificate Example

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: argocd-tls
  namespace: argocd
spec:
  secretName: argocd-server-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - argocd.example.com
  rotationPolicy: Always
```

### Cloudflare Setup

- Webhook: `cert-manager-webhook-cloudflare` (official Cloudflare webhook)
- API token: `Zone:DNS:Edit` permission
- Token stored as Kubernetes Secret (use Sealed Secrets for GitOps)

### MinIO Integration

Disable MinIO auto-cert (broken), use cert-manager:

```yaml
apiVersion: minio.min.io/v2
kind: Tenant
spec:
  requestAutoCert: false
  externalCertSecret:
  - name: minio-tenant-tls
    type: kubernetes.io/tls
```

## Monitoring

**Prometheus metrics:**
- `certmanager_certificate_expiration_timestamp_seconds`
- `certmanager_certificate_ready_status`

**Alerts:**
- Certificate expiring < 7 days
- Certificate not ready after 1 hour

## When to Reconsider

**Revisit if:**
1. Compliance requires private PKI
2. Air-gapped environment (no Let's Encrypt access)
3. Cloudflare unavailable (switch DNS provider webhook)
4. Let's Encrypt rate limits problematic

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [CNCF Graduation](https://www.cncf.io/announcements/2024/09/19/cert-manager-graduates/)
- [Cloudflare Webhook](https://github.com/cloudflare/cert-manager-webhook-cloudflare)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [MinIO Integration](https://github.com/minio/operator/blob/master/docs/cert-manager.md)
