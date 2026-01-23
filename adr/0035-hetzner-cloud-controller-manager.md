# 0035. Hetzner Cloud Controller Manager

**Status**: Proposed

**Date**: 2026-01-06

## Context

Currently we use MetalLB in L2 mode for LoadBalancer services. This works on single-node but has limitations:
- L2 mode: Single node handles all traffic per IP (no true load balancing)
- ~10 second failover on node failure
- Requires manual IP management
- No integration with Hetzner infrastructure

Hetzner Cloud Controller Manager (CCM) provides native Kubernetes integration with Hetzner Cloud infrastructure.

## Proposal

Add hcloud-cloud-controller-manager for native Hetzner LoadBalancer support:

```
Internet → Hetzner Load Balancer → K8s Nodes → Pods
```

### Components

1. **hcloud-cloud-controller-manager** - Deployment in kube-system
2. **Hetzner API token** - For provisioning LBs
3. **Node labels** - CCM adds Hetzner metadata to nodes

### What This Provides

| Feature | MetalLB L2 | Hetzner CCM |
|---------|------------|-------------|
| LoadBalancer type | ✅ | ✅ |
| True load balancing | ❌ (leader only) | ✅ |
| Automatic LB provisioning | ❌ | ✅ |
| Health checks | Basic | Full L4/L7 |
| Failover speed | ~10s | ~5s |
| Cost | Free | ~€5.39/mo per LB |
| Node registration | Manual | Automatic |

### Architecture

```
                    ┌─────────────────┐
   Internet ───────▶│ Hetzner LB      │
                    │ (L4/L7, HA)     │
                    └────────┬────────┘
                             │
            ┌────────────────┼────────────────┐
            ▼                ▼                ▼
       ┌─────────┐      ┌─────────┐      ┌─────────┐
       │ Node 1  │      │ Node 2  │      │ Node 3  │
       │ (CP)    │      │ (Worker)│      │ (Worker)│
       └─────────┘      └─────────┘      └─────────┘
```

### Installation

```yaml
# ArgoCD Application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hcloud-ccm
  namespace: argocd
spec:
  source:
    repoURL: https://charts.hetzner.cloud
    chart: hcloud-cloud-controller-manager
    targetRevision: 1.x.x
    helm:
      valuesObject:
        networking:
          enabled: true
        env:
          HCLOUD_TOKEN:
            valueFrom:
              secretKeyRef:
                name: hcloud-credentials
                key: token
  destination:
    namespace: kube-system
```

### LoadBalancer Annotations

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  annotations:
    # Use Hetzner LB instead of MetalLB
    load-balancer.hetzner.cloud/location: fsn1
    load-balancer.hetzner.cloud/use-private-ip: "true"
    load-balancer.hetzner.cloud/type: lb11  # Smallest LB type
spec:
  type: LoadBalancer
```

## Benefits

- **Native K8s integration** - Standard LoadBalancer services just work
- **True load balancing** - Traffic distributed across nodes
- **Automatic provisioning** - LB created/deleted with Service
- **Health checks** - Proper L4/L7 health checking
- **Node management** - Automatic node registration and cleanup

## Drawbacks

- **Cost** - ~€5.39/mo per LoadBalancer
- **Hetzner-specific** - Not portable to other clouds
- **API dependency** - Requires Hetzner API access
- **Not for bare metal** - Only works with Hetzner Cloud VMs

## Comparison with Alternatives

| Option | Best For |
|--------|----------|
| **MetalLB L2** | Single node, budget, bare metal |
| **Hetzner CCM** | Multi-node Hetzner Cloud, true HA |
| **Cloudflare Tunnel** | HTTP-only, security-focused |

## When to Adopt

Consider adopting when:
1. Migrating to Hetzner Cloud VMs (from dedicated server)
2. Need true load balancing across nodes
3. Want automatic LB lifecycle management
4. Budget allows ~€5-10/mo for LB

## Migration Path

1. Install hcloud-ccm alongside MetalLB
2. Create new services with Hetzner LB annotations
3. Test failover and load distribution
4. Migrate existing services gradually
5. Remove MetalLB when fully migrated

## Crossplane Integration

Can manage Hetzner resources via Crossplane:
- [AlexM4H/provider-hcloud](https://github.com/AlexM4H/provider-hcloud) (Upjet-based)
- Or use Terraform provider like R2 setup

For LBs specifically, CCM is preferred (native K8s integration).

## References

- [hcloud-cloud-controller-manager](https://github.com/hetznercloud/hcloud-cloud-controller-manager)
- [Hetzner Cloud Load Balancers](https://docs.hetzner.com/cloud/load-balancers/overview/)
- [Hetzner CCM Helm Chart](https://github.com/hetznercloud/hcloud-cloud-controller-manager/tree/main/chart)
- ADR 0012: MetalLB for LoadBalancer
