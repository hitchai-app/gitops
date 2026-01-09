# 0034. Node Naming Convention

**Status**: Accepted

**Date**: 2026-01-09

## Context

Adding second node to the cluster. Need consistent naming that:
- Stays meaningful as cluster grows
- Supports nodes changing roles (worker → hybrid → control-plane)
- Remains simple and memorable

Current node: `k8s-mn` (legacy name from single-node era)

## Decision

Use **minimal role-agnostic numbering**: `k8s-01`, `k8s-02`, `k8s-03`, etc.

Node roles are defined by Kubernetes labels/taints, not hostnames:
- `node-role.kubernetes.io/control-plane`
- `node-role.kubernetes.io/worker` (optional, implicit)

## Node Inventory

| Hostname | IP | Hardware | Role | Notes |
|----------|-----|----------|------|-------|
| k8s-mn | 88.99.214.26 | 12C/128GB/280GB SSD | control-plane | Legacy name, may rename to k8s-01 |
| k8s-02 | 142.132.202.253 | 8C/64GB/2x954GB NVMe | worker | First expansion node |

## Target Architecture

**Goal: 3 worker nodes** matching k8s-02 specs (8C/64GB/2x~1TB NVMe):

| Node | Role | Status |
|------|------|--------|
| k8s-mn | control-plane | ✅ Active |
| k8s-02 | worker | ✅ Active |
| k8s-03 | worker | 🔲 Planned |
| k8s-04 | worker | 🔲 Planned |

**Total target resources**: 36 CPU / 320GB RAM / ~6TB NVMe storage

This provides:
- 3-replica Longhorn volumes spread across 3 nodes
- High availability for stateful workloads
- Sufficient capacity for CI/CD runners and production workloads

## Alternatives Considered

1. **Role-based** (`k8s-master-1`, `k8s-worker-1`): Problematic when nodes change roles
2. **Location-based** (`htz-1`, `htz-2`): Useful for multi-provider, overkill for now
3. **Fun names** (`atlas`, `prometheus`): Memorable but doesn't scale

## Consequences

### Positive
- Hostnames never need changing when roles change
- Simple to remember and type
- Scales to any cluster size

### Negative
- Less immediately obvious what role a node has (use `kubectl get nodes` instead)
- Legacy `k8s-mn` breaks convention until renamed

## References

- Kubernetes labels for node roles: https://kubernetes.io/docs/reference/labels-annotations-taints/
