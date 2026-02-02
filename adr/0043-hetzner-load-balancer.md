# 0043. Hetzner Load Balancer for Cluster Ingress

**Status**: Accepted

**Date**: 2026-02-02

**Supersedes**: ADR 0012 (MetalLB) for external traffic routing

## Context

The cluster is migrating from single control-plane to HA (3 control-plane nodes). This requires:
1. A stable `controlPlaneEndpoint` for Kubernetes API HA
2. External traffic routing that survives node failures
3. Consolidated ingress for all external services (HTTPS, HTTP, GitLab SSH)

Current setup uses MetalLB Layer 2 mode, which has limitations:
- Single node handles all traffic per IP (leader election)
- ~10 second failover on node failure
- Not true load balancing
- Cannot provide external controlPlaneEndpoint

## Decision

Use a **single Hetzner Cloud Load Balancer** for all external cluster traffic.

### Configuration

| Service | LB Port | Target Port | Purpose |
|---------|---------|-------------|---------|
| kubernetes-api | 6443 | 6443 | HA control-plane endpoint |
| https-ingress | 443 | 443 | Web traffic (Traefik hostNetwork) |
| http-ingress | 80 | 80 | HTTP → HTTPS redirect |
| gitlab-ssh | 22 | 30022 | Git over SSH (NodePort) |

### Targets

All cluster nodes added as targets:
- k8s-03: 88.99.208.86
- k8s-04: 116.202.39.186
- k8s-02: 142.132.202.253

### Tier Selection

**LB11** (€5.39/month): 5 services, 25 targets, 1 TB traffic

Sufficient for current needs (4 services, 3-4 nodes). Upgrade to LB21 only if adding more ports or scaling beyond 25 nodes.

## Alternatives Considered

### 1. Keep MetalLB Only
- **Pros**: Already deployed, no additional cost
- **Cons**: Cannot provide external controlPlaneEndpoint, L2 mode limitations
- **Why not**: HA control-plane requires stable external endpoint

### 2. kube-vip for Control Plane
- **Pros**: Free, in-cluster, fast failover
- **Cons**: Only for control-plane, separate solution needed for ingress
- **Why not**: Single LB for everything is simpler

### 3. Hetzner Cloud Controller Manager
- **Pros**: GitOps, automatic LB provisioning from K8s
- **Cons**: Designed for Cloud VMs, not dedicated servers
- **Why not**: Our nodes are dedicated servers (Robot), not Cloud

### 4. HAProxy on Nodes
- **Pros**: Free, full control
- **Cons**: Must manage HA of HAProxy itself (needs keepalived/VRRP), additional complexity
- **Why not**: Managed LB reduces operational burden

### 5. Cloudflare Tunnel (Free Tier)
- **Pros**: Free for HTTP/HTTPS, DDoS protection, WAF, no exposed ports, zero-trust model
- **Cons**: TCP traffic (K8s API 6443, SSH 22) requires paid Cloudflare Spectrum
- **Why not**: Can't handle K8s API or GitLab SSH on free tier

### 6. kube-vip (Free, In-Cluster)
- **Pros**: Free, handles all TCP, fast ARP-based failover, can use vSwitch VIP (10.0.0.x)
- **Cons**: Single node handles traffic (leader election, no load balancing), VIP on vSwitch is private (needs routing for external access)
- **Why not**: Additional complexity for external routing

### 7. DNS Round-Robin
- **Pros**: Free, simple, works for all traffic types
- **Cons**: No health checks, clients cache failed IPs, slow failover (TTL-based)
- **Why not**: No real HA - failed node stays in rotation until TTL expires

### Future: Hybrid Cost Optimization

If LB cost becomes concern, consider:
- **Cloudflare Tunnel** for HTTP/HTTPS (free, protected)
- **Direct node access** for K8s API and SSH (admin-only, HA less critical)
- **kube-vip** for internal controlPlaneEndpoint on vSwitch

## Consequences

### Positive
- Single external IP for all services
- Managed HA by Hetzner (no operational burden)
- Health checks route only to healthy nodes
- Enables HA control-plane (controlPlaneEndpoint)
- DNS simplified: `*.ops.last-try.org` → LB IP

### Negative
- Monthly cost (~€5.39/month for LB11)
- External dependency (Hetzner Cloud, not just Robot)
- Adds latency (traffic goes through LB)

### Neutral
- MetalLB can remain for internal LoadBalancer services if needed
- One-time manual setup (not GitOps managed)

## Implementation Notes

### Setup via Hetzner Cloud Console

1. Create Load Balancer (LB11, same datacenter as servers)
2. Add all nodes as targets (public IPs)
3. Configure 4 services (6443, 443, 80, 22)
4. Update DNS wildcard to LB IP

### Kubernetes Changes

1. Update `kubeadm-config` ConfigMap with `controlPlaneEndpoint: <LB_IP>:6443`
2. Regenerate API server certificates to include LB IP as SAN
3. Update Traefik to `hostNetwork: true` (binds directly to :80/:443)
4. Update GitLab Shell to `hostPort: 22`

### SSH Port Strategy

- **Node SSH**: Standard port 22, accessed via node's own IP (direct)
- **GitLab SSH**: LB port 22 → NodePort 30022 → GitLab shell pod
- No conflict because LB IP ≠ Node IPs

### MetalLB Migration

With Hetzner LB handling all external traffic:
1. Traefik uses hostNetwork instead of LoadBalancer service
2. MetalLB becomes optional
3. Can remove MetalLB once verified (reduces complexity)

## Pricing Reference

| Tier | Monthly | Services | Targets | Traffic |
|------|---------|----------|---------|---------|
| **LB11** | €5.39–5.99 | 5 | 25 | 1 TB |
| LB21 | €16–18 | 15 | 75 | 2 TB |
| LB31 | €32–36 | 30 | 150 | 3 TB |

Supports both Cloud servers and dedicated root servers as targets.

## When to Reconsider

- LB11 limits exceeded (>5 services or >25 targets)
- Cost becomes concern (evaluate kube-vip alternative)
- Need GitOps management (evaluate Crossplane provider)
- Hetzner Cloud availability issues

## References

- [Hetzner Load Balancer](https://www.hetzner.com/cloud/load-balancer/)
- [Hetzner Load Balancer Docs](https://docs.hetzner.com/cloud/load-balancers/)
- ADR 0012: MetalLB for LoadBalancer (superseded for external traffic)
- ADR 0042: Adding New Cluster Nodes
