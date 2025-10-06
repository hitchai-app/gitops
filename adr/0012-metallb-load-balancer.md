# 0012. MetalLB for LoadBalancer on Bare Metal

**Status**: Accepted

**Date**: 2025-10-06

## Context

Kubernetes LoadBalancer services require external IP provisioning. Cloud providers handle this automatically, but on bare metal (Hetzner dedicated server), LoadBalancer services remain stuck in `<pending>` state.

Requirements:
- Expose Traefik ingress controller externally
- Support for future multi-node scaling
- Minimal operational complexity

Current setup: Single Hetzner dedicated server (will scale to multi-node)

## Decision

We will use **MetalLB in Layer 2 mode** as our bare metal LoadBalancer implementation.

Configuration:
- Layer 2 mode (ARP-based)
- IP pool: Server's main IP initially
- When scaling: Add floating IP for automatic failover

## Alternatives Considered

### 1. kube-vip
- **Pros**: Lightweight, good for control plane HA
- **Cons**: Primarily for control plane, MetalLB better for service LoadBalancing
- **Why not chosen**: MetalLB is standard for service LoadBalancing on bare metal

### 2. NodePort (no LoadBalancer)
- **Pros**: Simple, no additional components
- **Cons**: Ugly URLs with ports, no automatic failover, non-standard
- **Why not chosen**: LoadBalancer type is standard Kubernetes pattern

### 3. BGP mode (MetalLB)
- **Pros**: True load balancing across nodes
- **Cons**: Requires BGP-capable router (Hetzner doesn't provide)
- **Why not chosen**: Layer 2 sufficient for our scale

## Consequences

### Positive
- ✅ Standard LoadBalancer service type works
- ✅ Automatic IP assignment to services
- ✅ Scales to multi-node with automatic failover
- ✅ Industry standard (CNCF project)
- ✅ Can share single IP across services (different ports)

### Negative
- ⚠️ Layer 2 mode: one node handles all traffic per IP (leader election)
- ⚠️ ~10 second failover on node failure
- ⚠️ Not true load balancing (all traffic through leader node)

### Neutral
- Single node: No failover benefit yet (only 1 node)
- Multi-node: Can use floating IP for cleaner failover

## Implementation Notes

### Single Node Phase (Current)
```yaml
addresses:
- <server-ip>/32  # Main server IP
```

### Multi-Node Phase (Future)
```yaml
# Option A: Use node IPs (free)
addresses:
- <node1-ip>/32
- <node2-ip>/32

# Option B: Use floating IP (recommended, ~€1/month)
addresses:
- <floating-ip>/32  # Automatic failover, no DNS changes
```

**Recommendation:** Start with server IP, add floating IP when scaling to multi-node.

## Layer 2 Mode Behavior

- MetalLB responds to ARP requests claiming ownership of LoadBalancer IPs
- Leader election: one node per IP handles all traffic
- On leader failure: standby node takes over (~10 seconds)
- IP sharing: Multiple services can share same IP (different ports)

## When to Reconsider

**Revisit if:**
1. Need true load balancing across nodes (consider external LB or BGP if available)
2. Layer 2 failover too slow (10s) for requirements
3. Scale beyond 5 nodes (consider BGP mode or cloud migration)

## References

- [MetalLB Documentation](https://metallb.universe.tf/)
- [Layer 2 Mode](https://metallb.universe.tf/concepts/layer2/)
- [Hetzner Additional IPs](https://docs.hetzner.com/robot/dedicated-server/ip/additional-ip-adresses/)
