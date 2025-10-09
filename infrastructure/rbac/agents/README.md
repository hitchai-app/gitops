# Agent RBAC Profiles

This bundle defines two access tiers driven by Kubernetes RBAC:

- `agent-readonly` ClusterRole: cluster-wide read access to workloads and core resources (no `secrets`). Bound to the `agent-readers` group via ClusterRoleBinding.
- `agent-writer` namespace Role (scoped to `workloads`): limited create privileges for pods/services plus read-only access elsewhere. No delete verbs and no job creation powers. Bound to `agent-writers` group via RoleBinding.

ResourceQuota and LimitRange in the `workloads` namespace cap agent-created resources to prevent exhaustion. Add or remove namespace-specific RoleBindings as needed for other environments.
