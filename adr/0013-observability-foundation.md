# 0013. Observability Foundation with kube-prometheus-stack

**Status**: Accepted

**Date**: 2025-10-09

## Context

We currently have no observability stack in the cluster. Basic monitoring is needed before workloads arrive so we can track cluster health, storage pressure, and future workload signals. Requirements:

- GitOps-managed deployment that fits our ArgoCD workflow
- Metrics, alerting, and dashboards out of the box
- Minimal footprint on a single-node Hetzner server (12 vCPU / 128 GB RAM / 280 GB SSD)
- Alert notifications to Discord without maintaining a custom relay initially
- Leave room to add logging and tracing later without churn

## Decision

Adopt the `kube-prometheus-stack` Helm chart (Prometheus Operator, Prometheus, Alertmanager, Grafana) as the initial observability stack. Deploy it via an ArgoCD application that wraps the chart with Kustomize overlays in `infrastructure/observability/kube-prometheus-stack/`.

Key configuration choices:

- **Storage**: Longhorn-backed PVCs sized 20 Gi (Prometheus, 7 day retention with 15 Gi cap), 2 Gi (Alertmanager), 2 Gi (Grafana).
- **Access**: Grafana exposed through Traefik ingress using native admin auth; Prometheus and Alertmanager remain cluster-internal (access via `kubectl port-forward`).
- **Alerting**: Alertmanager posts directly to a Discord webhook using a minimal template; webhook URL stored as a SealedSecret.
- **Deployment**: Namespace + CRDs + chart applied through Argo sync waves. Validate manifests with `kubectl apply --dry-run=server -k infrastructure/observability/kube-prometheus-stack` prior to syncing.

Future enhancements (logging, tracing, OIDC SSO) will be handled in follow-up ADRs once the base stack is proven.

## Consequences

- Provides immediate cluster metrics, default Kubernetes alerts, and Grafana dashboards with low operational overhead.
- Single-node retention is capped to keep within current storage limits; we must expand PVCs and retention when workloads scale.
- Without OIDC, Grafana credentials are managed locally; exposure beyond the platform team should wait until SSO is introduced.
- Alertmanager notifications rely on the Discord webhook; formatting is basic, and rate limiting should be monitored. If richer formatting is required, we can introduce a relay later.
- Ownership: Alexander (current platform owner) maintains alert routes, dashboards, and adjustments until a broader team assumes responsibility.

## Alternatives Considered

1. **Grafana Agent + Grafana Cloud**
   - Pros: Offloads storage/alerting to SaaS.
   - Cons: External dependency, recurring cost, and less control. Rejected to keep everything self-hosted initially.

2. **VictoriaMetrics stack**
   - Pros: Lower resource usage, simple single-binary model.
   - Cons: Fewer community dashboards/rules; would require more custom wiring. Rejected in favor of the richer kube-prometheus ecosystem.

3. **Direct Prometheus + Alertmanager + Grafana (no Operator)**
   - Pros: Minimal components.
   - Cons: Larger manual configuration burden (ServiceMonitors, rules, dashboards). Operator bundle provides faster time-to-value.

## Follow-up Work

- Implement ArgoCD application and Kustomize wrapper for kube-prometheus-stack.
- Add SealedSecrets for Grafana admin credentials and Discord webhook.
- Create dashboards/alert rules for Longhorn, Traefik, CloudNativePG as workloads onboard.
- Draft a separate ADR for logging/tracing (Loki, Tempo, Alloy) and another for OIDC single sign-on when needed.
