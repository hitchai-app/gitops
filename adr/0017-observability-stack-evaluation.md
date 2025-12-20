# 0017. Observability Stack Evaluation

**Status**: Superseded by [ADR 0030](0030-remove-signoz-evaluation.md)

**Date**: 2025-10-14

**Superseded**: 2025-12-20 - SigNoz evaluation concluded; stack removed (see ADR 0030).

## Context

Current setup: kube-prometheus-stack provides infrastructure metrics via Prometheus, Grafana, and Alertmanager.

**Missing capabilities:**
- Centralized log storage and search (relying on `kubectl logs`)
- Distributed tracing across services
- Application performance monitoring

**Operational pain:**
- Dashboard customization requires significant manual effort
- Grafana dashboards are difficult to version control
- Small team cannot dedicate resources to dashboard maintenance

**Scale considerations:**
- Single-node cluster with sufficient resources for expansion
- Growing from infrastructure monitoring to application observability

## Decision

**Deploy SigNoz for initial evaluation (Phase 1), with option to add Grafana stack for comparison (Phase 2) if evaluation requires it.**

**Phase 1: SigNoz Evaluation (2-4 weeks)**
- Deploy SigNoz (metrics + logs + traces in single platform)
- Use SigNoz k8s-infra collector (otelAgent DaemonSet + otelCollector Deployment)
- Collect infrastructure telemetry (nodes, pods, cluster metrics, system logs)
- Evaluate log search, auto-dashboards, query performance, operational overhead
- Track actual storage usage patterns

**Phase 2: Comparative Evaluation (optional, 2 weeks)**
- Deploy if Phase 1 shows gaps or requires validation against familiar tools
- Add: Grafana stack (Loki + Tempo) alongside existing Prometheus/Grafana
- Deploy separate OpenTelemetry Collector for Grafana stack
- Accept 20-30GB total storage consumption during comparison
- Track which system is used during actual incidents
- Compare dashboard maintenance effort
- Assess API usability for automation

**Exit after Phase 1 or Phase 2:**
- Keep SigNoz if it meets operational needs
- Keep Grafana stack if ecosystem maturity/flexibility outweighs operational complexity
- Keep both if different layers (infrastructure vs application) benefit from specialized tools

## Alternatives Considered

### 1. Complete Grafana Stack Only
- **Pros**: Extend existing investment, mature ecosystem
- **Cons**: Multiple backends to manage, requires query language expertise for each component, dashboard maintenance burden remains
- **Why not chosen**: Does not address operational complexity or dashboard customization overhead

### 2. Replace with SigNoz
- **Pros**: Unified platform, auto-generated dashboards, simpler operations
- **Cons**: Migration cost, lose existing dashboards, younger ecosystem, no fallback
- **Why not chosen**: Too risky without validation; need evidence before committing

### 3. Keep Metrics-Only
- **Pros**: No additional complexity
- **Cons**: Cannot effectively debug production issues, no historical log analysis, blind to request flows
- **Why not chosen**: Logs and traces are essential for production operations

### 4. Dual-Stack Parallel Evaluation
- **Pros**: Direct comparison with same data in both systems, objective assessment
- **Cons**: 20-30GB storage from day one, dual management overhead, wastes resources if SigNoz proves sufficient
- **Why not chosen**: Phased approach reduces upfront commitment; Phase 1 may satisfy requirements without Phase 2 overhead

## Consequences

### Positive
- ✅ **Low-risk evaluation**: Keep working Prometheus/Grafana stack, add SigNoz alongside
- ✅ **Phased commitment**: Phase 1 requires minimal resources; Phase 2 only if needed
- ✅ **Early exit option**: Can stop after Phase 1 if SigNoz satisfies requirements
- ✅ **Dashboard burden test**: Evaluate if auto-dashboards reduce maintenance overhead
- ✅ **Operational validation**: Phase 2 enables direct comparison if needed
- ✅ **Reversible decision**: Can remove SigNoz cleanly; existing Prometheus/Grafana unaffected

### Negative
- ⚠️ **Phase 2 resource spike**: 20-30GB storage + dual management if comparison needed
- ⚠️ **Learning curve**: Team learns SigNoz interface and workflows
- ⚠️ **Instrumentation effort**: Applications require OpenTelemetry integration for traces
- ⚠️ **Storage allocation**: 30GB (~11% of 280GB SSD) committed for evaluation period

### Neutral
- Phased evaluation reduces upfront resource commitment and allows early exit if SigNoz satisfies requirements
- 30GB storage matches SigNoz minimum recommendation; sufficient for evaluation with default retention (15d logs/traces, 30d metrics)
- Retention policies use SigNoz defaults, adjustable via UI during evaluation
- Either stack can be promoted to primary after evaluation
- Evaluation period allows real-world usage patterns to emerge
- Infrastructure and application observability may consolidate or remain separate

## Implementation Considerations

**Storage strategy:**
- **Phase 1:** 30GB ClickHouse storage with default retention
  - Matches SigNoz's minimum recommendation
  - Single-node cluster has sufficient total storage (280GB SSD, ~11% allocation)
  - SigNoz default retention: 15 days (logs/traces), 30 days (metrics)
  - Adjustable via SigNoz Settings UI during evaluation if needed
  - No volume expansion enabled; manual intervention required if storage fills
  - Monitor actual growth to inform long-term capacity planning
- **Phase 2 (if needed):** Additional 10-20GB for Grafana stack (Loki + Tempo)

**Resource budget:**
- **Phase 1:** SigNoz stack (~3.0 CPUs / ~4.5Gi RAM, ~25% of cluster capacity)
  - SigNoz platform (ClickHouse, unified service): 2200m CPU / 3768Mi RAM
  - k8s-infra collectors (separate chart): 800m CPU / 768Mi RAM
    - otelAgent DaemonSet (per node): 500m CPU / 512Mi RAM
    - otelCollector Deployment: 300m CPU / 256Mi RAM
- **Phase 2 (if needed):** Additional ~1.5 CPUs / ~2Gi RAM for Grafana stack
  - Loki: 500m CPU / 1Gi RAM
  - Tempo: 500m CPU / 512Mi RAM
  - OTel Collector: 500m CPU / 512Mi RAM
- **Combined (if Phase 2 executed):** ~4.5 CPUs / ~6.5Gi RAM (~38% of cluster capacity)

**Collection architecture:**
- **Phase 1:** Two-chart deployment
  - **Main SigNoz chart** (`signoz/signoz`): Platform backend (ClickHouse, query service, frontend)
  - **k8s-infra chart** (`signoz/k8s-infra`): Separate chart for Kubernetes monitoring
    - otelAgent DaemonSet: node-level metrics, container logs
    - otelCollector Deployment: cluster-level metrics, k8s events
    - Sends data to SigNoz OTel collector endpoint
    - Maintained by SigNoz team, optimized for their backend
- **Phase 2 (if needed):** Additional OpenTelemetry Collector for Grafana stack
  - Dual exporters (Loki + Tempo)
  - Deployed in separate namespace for clean separation
- Manual instrumentation for application traces (both phases)

**Evaluation criteria:**

*Phase 1 (SigNoz standalone):*
- **Log search speed:** Query response time (P50, P95, P99) for common search patterns
- **Dashboard quality:** Auto-dashboard completeness vs manual Grafana dashboards
- **Query performance:** Query execution time vs Prometheus/Grafana for equivalent queries
- **Storage efficiency:** Actual storage growth rate (GB/day) vs projected
- **Resource utilization:** CPU/memory usage under normal and peak load
- **Query interface:** Time to construct queries for common troubleshooting tasks
- **API usability:** Integration effort for automation scripts and agents

*Phase 2 (comparative, if needed):*
- **Incident response:** Which system is accessed first during incidents (tracked)
- **Dashboard creation:** Time investment (hours) to create equivalent dashboards in both systems
- **Query speed comparison:** Side-by-side response time for identical queries
- **Trace debugging:** Time to root-cause issues using traces in both platforms
- **False positive rate:** Alert accuracy comparison between systems
- **Query language preference:** Team survey on ClickHouse SQL vs PromQL/LogQL

**Exit conditions:**

*After Phase 1:*
- SigNoz satisfies log search and visualization needs → Keep SigNoz, skip Phase 2
- SigNoz shows critical gaps or team rejects interface → Proceed to Phase 2
- Storage exhausts too quickly → Reassess retention or deployment strategy

*After Phase 2:*
- Clear preference emerges from actual usage patterns
- One system proves insufficient for critical use cases
- Operational burden of dual stacks becomes untenable
- Resource constraints require consolidation

## When to Reconsider

**After Phase 1:**
- **Proceed to Phase 2 if:** SigNoz shows gaps in critical workflows, team struggles with interface, or need validation against Grafana stack before commitment
- **Skip Phase 2 if:** SigNoz satisfies log search and visualization needs, team adopts it naturally, storage usage sustainable

**After Phase 2 (if executed):**
- **Keep both systems if:** Different layers (infrastructure vs application) are better served by specialized tools
- **Consolidate to Grafana if:** Ecosystem maturity and flexibility outweigh operational complexity
- **Consolidate to SigNoz if:** Unified platform and auto-dashboards significantly reduce maintenance burden
- **Extend evaluation if:** Usage patterns remain unclear or capabilities evolve during trial

**Revisit this ADR if:**
- Storage constraints tighten (30GB proves insufficient even with default retention)
- Application instrumentation requirements change (heavier trace volume)
- Cluster scales to multi-node (changes resource availability)
- Team composition changes (different observability expertise)

## References

- [Grafana Documentation](https://grafana.com/docs/)
- [SigNoz Documentation](https://signoz.io/docs/)
- [OpenTelemetry](https://opentelemetry.io/)
- ADR 0013: Observability Foundation
