# 0035. Cluster Target Architecture

**Status**: Accepted

**Date**: 2026-01-09

## Context

Scaling from single-node cluster to multi-node HA. Need to define target architecture for capacity planning and hardware procurement.

Current state:
- k8s-mn: 12C/128GB/280GB SSD (control-plane, legacy)
- k8s-02: 8C/64GB/2x954GB NVMe (worker, first expansion)

## Decision

**Target: 3 identical nodes with distributed control plane.**

| Node | Hardware | Role |
|------|----------|------|
| k8s-01 | 8C/64GB/2x~1TB NVMe | control-plane + worker |
| k8s-02 | 8C/64GB/2x~1TB NVMe | control-plane + worker |
| k8s-03 | 8C/64GB/2x~1TB NVMe | control-plane + worker |

**Total resources**: 24 CPU / 192GB RAM / ~6TB NVMe

## Migration Path

1. ✅ Add k8s-02 as worker
2. Add k8s-03, promote both to control-plane (3-node etcd quorum)
3. Replace k8s-mn with k8s-01 (same spec as others)
4. Retire k8s-mn hardware

## Consequences

### Positive
- HA control plane (etcd quorum survives 1 node failure)
- 3-replica Longhorn volumes across all nodes
- No single point of failure
- Uniform hardware simplifies operations

### Negative
- Less total RAM than keeping k8s-mn (192GB vs 256GB)
- Migration requires careful orchestration

## References

- ADR 0034: Node Naming Convention
- [kubeadm HA topology](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/ha-topology/)
