# 0036. Hetzner vSwitch Internal Network

**Status**: Accepted

**Date**: 2026-01-09

## Context

Cluster expanded to multi-node (k8s-mn + k8s-02) with servers communicating over public internet. This presents issues:

- **Traffic costs**: Egress traffic counts against Hetzner limits
- **Security**: Cluster traffic exposed to public internet
- **HA limitations**: kube-vip requires L2 network (same subnet) for floating IPs
- **Future control plane HA**: etcd peer communication needs reliable low-latency network

Current server IPs are in different /24 subnets (88.99.x.x vs 142.132.x.x), preventing direct L2 communication.

## Decision

**Use Hetzner vSwitch for internal cluster communication.**

Network configuration:

| Node | Public IP | Internal IP (vSwitch) |
|------|-----------|----------------------|
| k8s-mn | 88.99.214.26 | 10.0.0.1 |
| k8s-02 | 142.132.202.253 | 10.0.0.2 |
| k8s-03 (future) | TBD | 10.0.0.3 |

vSwitch: `k8s-sw-1` (VLAN ID 4000)

**Migration scope:**

| Component | IP Used | Notes |
|-----------|---------|-------|
| kubelet --node-ip | Internal (10.0.0.x) | Node InternalIP for pod scheduling |
| Calico VXLAN | Internal (10.0.0.x) | Auto-detected from node IP |
| API server cert | Both IPs | Allows internal and external access |
| API server listen | Public | External kubectl access required |
| etcd | Public | Deferred - see rationale below |

## Alternatives Considered

### 1. Keep Public IPs Only
- **Pros**: No configuration changes, simpler
- **Cons**: Traffic costs, no kube-vip option, security exposure
- **Why not chosen**: Limits future HA options

### 2. Full Migration (Including etcd)
- **Pros**: All traffic internal, cleaner architecture
- **Cons**: Complex etcd peer URL migration, risk of cluster downtime
- **Why not chosen**: Single-node etcd doesn't benefit; defer until adding control plane nodes

### 3. Hetzner Cloud Network (Instead of vSwitch)
- **Pros**: Works with cloud servers
- **Cons**: Dedicated servers require vSwitch, not Cloud Networks directly
- **Why not chosen**: Our servers are dedicated, not cloud

## Consequences

### Positive
- **Free internal traffic**: vSwitch traffic doesn't count against egress limits
- **kube-vip ready**: Same L2 network enables floating IPs for HA
- **Lower latency**: ~0.5ms (same as public, but guaranteed)
- **Security**: Cluster traffic not exposed to internet
- **No cost**: vSwitch is free for dedicated servers

### Negative
- **Hybrid state**: etcd still uses public IP (acceptable for single-node)
- **Configuration complexity**: Must manage both public and internal IPs
- **MTU considerations**: vSwitch requires MTU 1400

### Neutral
- Calico automatically uses node's InternalIP for VXLAN tunnels
- API server remains externally accessible (required for kubectl, webhooks)

## Implementation Details

### vSwitch Setup (Hetzner Robot)

1. Create vSwitch with VLAN ID 4000
2. Add both servers to vSwitch
3. Configure netplan on each node:

```yaml
# /etc/netplan/60-vswitch.yaml
network:
  version: 2
  vlans:
    vlan4000:
      id: 4000
      link: <main-interface>  # enp4s0 or enp0s31f6
      mtu: 1400
      addresses:
        - 10.0.0.X/24
```

### Kubelet Configuration

Update `/var/lib/kubelet/kubeadm-flags.env`:
```
KUBELET_KUBEADM_ARGS="--node-ip=10.0.0.X ..."
```

### API Server Certificate

Regenerate with internal IP in SANs:
```bash
kubeadm init phase certs apiserver --config <config-with-certSANs>
```

### etcd Migration (Deferred)

For single-node etcd, migration provides no benefit. When adding control plane nodes:

1. New nodes join with internal IPs from start
2. Use `etcdctl member update` to change existing member's peer URLs
3. Update etcd manifest to listen on internal IP
4. Requires quorum - do sequentially

Per etcd documentation: "updating peer URLs changes the cluster wide configuration and can affect the health of the etcd cluster."

## Verification

```bash
# Check node IPs
kubectl get nodes -o wide
# Should show INTERNAL-IP as 10.0.0.x

# Check Calico VXLAN tunnels
bridge fdb show dev vxlan.calico
# Should show dst 10.0.0.x for peer nodes

# Test internal connectivity
ping -c 3 10.0.0.2  # from k8s-mn
```

## When to Revisit

- **Adding control plane nodes**: Migrate etcd to internal IPs
- **kube-vip deployment**: Verify L2 connectivity works for floating IP
- **Performance issues**: Consider dedicated network interface if vSwitch bandwidth insufficient

## References

### Hetzner Documentation
- [vSwitch Overview](https://docs.hetzner.com/robot/dedicated-server/network/vswitch/)
- [Connect Dedicated Servers](https://docs.hetzner.com/cloud/networks/connect-dedi-vswitch/)
- [Networks FAQ](https://docs.hetzner.com/networking/networks/faq/)

### Kubernetes Documentation
- [Operating etcd clusters](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)
- [kubeadm --node-ip discussion](https://github.com/kubernetes/kubeadm/issues/203)
- [Changing node IP guide](https://devopstales.github.io/kubernetes/k8s-change-ip/)

### etcd Documentation
- [Runtime Reconfiguration](https://etcd.io/docs/v3.5/op-guide/runtime-configuration/)
- [Updating member peer URLs](https://etcd.io/docs/v3.3/op-guide/runtime-configuration/#update-a-member)

### Related ADRs
- ADR 0034: Node Naming Convention
- ADR 0035: Cluster Target Architecture
