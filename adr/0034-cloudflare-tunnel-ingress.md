# 0034. Cloudflare Tunnel for Ingress

**Status**: Proposed

**Date**: 2026-01-06

## Context

Currently we use Traefik + MetalLB for ingress, which requires:
- Public IP exposed on nodes
- cert-manager for TLS certificates
- MetalLB for LoadBalancer service IPs
- Manual DDoS protection configuration

Cloudflare Tunnel offers an alternative where traffic flows through Cloudflare's edge without exposing public IPs.

## Proposal

Replace or complement current ingress with Cloudflare Tunnel:

```
Internet → Cloudflare Edge (TLS, WAF, DDoS) → Tunnel → K8s Services
```

### Components

1. **Crossplane provider-cloudflare** (native, not Terraform)
   - `Tunnel` - Creates tunnel, outputs credentials
   - `TunnelConfig` - Defines hostname → service routing

2. **cloudflared Deployment** - Runs in cluster, connects outbound to CF

### What This Replaces

| Component | With Tunnel | Current |
|-----------|-------------|---------|
| Public IP | Not needed | Required |
| MetalLB | Optional (internal only) | Required |
| cert-manager | Optional (CF handles TLS) | Required |
| Traefik | Optional | Required |
| DDoS protection | Included | None |
| WAF | Included | None |

### Architecture

```
                    ┌─────────────────┐
   Internet ───────▶│ Cloudflare Edge │
                    │ (TLS, WAF, CDN) │
                    └────────┬────────┘
                             │ Tunnel (outbound connection)
                             ▼
┌─────────────────────────────────────────────┐
│              Kubernetes Cluster             │
│  ┌──────────────────────────────────────┐  │
│  │ cloudflared (Deployment/DaemonSet)   │  │
│  └──────────────────┬───────────────────┘  │
│                     ▼                       │
│            ClusterIP Services               │
└─────────────────────────────────────────────┘
```

### Crossplane Resources

```yaml
apiVersion: argo.cloudflare.upbound.io/v1alpha1
kind: Tunnel
metadata:
  name: k8s-cluster
spec:
  forProvider:
    accountId: <account-id>
    name: k8s-cluster
    secret: <tunnel-secret>

---
apiVersion: argo.cloudflare.upbound.io/v1alpha1
kind: TunnelConfig
metadata:
  name: k8s-ingress
spec:
  forProvider:
    accountId: <account-id>
    tunnelId: <from-tunnel>
    config:
      ingressRule:
        - hostname: "argocd.ops.last-try.org"
          service: "http://argocd-server.argocd:80"
        - hostname: "grafana.ops.last-try.org"
          service: "http://grafana.monitoring:80"
        - service: "http_status:404"  # catch-all
```

## Benefits

- **No public IP exposure** - Tunnel connects outbound only
- **Automatic TLS** - Cloudflare handles certificates
- **Built-in security** - DDoS, WAF, bot protection
- **Multi-node ready** - No IP failover complexity
- **Simpler architecture** - Fewer components to manage

## Drawbacks

- **Cloudflare dependency** - All traffic through CF
- **Non-HTTP limitations** - TCP/UDP requires Spectrum (paid)
- **Latency** - Extra hop through CF edge (usually negligible)
- **Debugging** - Traffic inspection happens at CF, not locally

## When to Adopt

Consider adopting when:
1. Adding second node (avoids LB/IP failover complexity)
2. Security requirements increase (need WAF/DDoS)
3. Want to simplify TLS management
4. Need to hide origin IPs

## Migration Path

1. Deploy cloudflared alongside existing Traefik
2. Configure tunnel for new/test services first
3. Gradually migrate services from Traefik to Tunnel
4. Remove Traefik/MetalLB when fully migrated

## References

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [cloudflared Kubernetes Deployment](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/deploy-tunnels/deployment-guides/kubernetes/)
- [Crossplane provider-cloudflare](https://github.com/cdloh/provider-cloudflare)
- ADR 0011: Traefik Ingress Controller
- ADR 0012: MetalLB for LoadBalancer
