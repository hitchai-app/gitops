# Agent RBAC Profiles

This bundle defines a cluster-scoped observer role:

- `agent-readonly` ClusterRole: cluster-wide read access to workloads and core resources (no `secrets`). Bound to the `agent-readers` group via ClusterRoleBinding.

Namespace-specific write access is **not** applied by default. Sample manifests are provided in this directory (`role-agent-writer-workloads.yaml`, `rolebinding-agent-writer-workloads.yaml`, `resourcequota-agent-workloads.yaml`, `limitrange-agent-workloads.yaml`). Copy or reference them from a separate Kustomization when you are ready to grant controlled write access to a particular namespace.
