# 0011. Traefik Ingress Controller

**Status**: Accepted

**Date**: 2025-10-06

## Context

We need an ingress controller to expose services externally (ArgoCD UI, MinIO Console, Grafana, product apps with WebSocket).

Requirements:
- TLS termination (cert-manager integration)
- WebSocket support (Centrifugo)
- GitOps-compatible
- Small team operational overhead
- Single Hetzner node → multi-node scaling

## Decision

We will use **Traefik v3** as our ingress controller.

Configuration:
- Single Traefik instance
- Standard Ingress API (not Traefik CRDs)
- TLS termination at ingress
- Explicit IngressClass `traefik`

## Alternatives Considered

### 1. Nginx Ingress Controller
- **Pros**: Most battle-tested, huge community, extensive documentation
- **Cons**:
  - **Maintenance mode** (no new features)
  - IngressNightmare CVEs (patched, but architectural risk)
  - Memory leaks (Prometheus, backend reloads)
  - WebSocket drops during config reload
  - Heavier (~100MB vs Traefik ~50MB)
- **Why not chosen**: Maintenance mode + memory leaks worse long-term bet

### 2. HAProxy Ingress
- **Pros**: High performance, enterprise features
- **Cons**: Smaller community, more complex
- **Why not chosen**: Complexity not justified

### 3. Contour (Envoy)
- **Pros**: CNCF, modern architecture
- **Cons**: Steeper learning curve
- **Why not chosen**: Traefik simpler for small team

## Consequences

### Positive
- ✅ Not affected by IngressNightmare (architecture immune)
- ✅ Active development (vs nginx maintenance mode)
- ✅ Hot-reload routing (no connection drops)
- ✅ Lighter weight (~50MB)
- ✅ WebSocket support (needs middleware config)
- ✅ GitOps-compatible (standard Ingress API)

### Negative
- ⚠️ Smaller community than nginx
- ⚠️ Advanced TCP/UDP routing paywalled (Enterprise)
- ⚠️ Less battle-tested at extreme scale
- ⚠️ WebSocket requires explicit middleware setup

### Neutral
- Migration to nginx possible (change `ingressClassName`, ~2-4 hours)
- Can use standard Ingress API (no vendor lock-in)
- "Auto-discovery" = standard K8s controller behavior (watches API)

## Implementation Notes

- Install via Helm (managed by ArgoCD)
- WebSocket middleware: Custom headers for upgrade
- Single instance initially (add second for internal/external separation if needed)
- Standard Ingress API (avoid Traefik-specific CRDs)

## When to Reconsider

**Revisit if:**
1. Need advanced TCP/UDP routing (Enterprise paywall)
2. Traefik maintenance declines
3. Extreme scale requirements (millions RPS)

## References

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Traefik vs IngressNightmare](https://traefik.io/blog/traefik-vs-ingressnightmare-security-by-design-in-the-age-of-critical-vulnerabilities)
- ADR 0008: cert-manager for TLS
