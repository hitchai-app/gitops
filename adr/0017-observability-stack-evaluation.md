# 0017. Observability Stack Evaluation

**Status**: Accepted

**Date**: 2025-10-14

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
- ⚠️ **Storage risk**: 10GB intentionally below vendor minimum; may exhaust during Phase 1

### Neutral
- Phased evaluation reduces upfront resource commitment and allows early exit if SigNoz satisfies requirements
- 10GB storage is below SigNoz's 30GB minimum but acceptable for evaluation on idle cluster with low log volume; risk of exhaustion is intentional (informs production sizing)
- Retention policies (7-day) set conservatively during evaluation, expandable later
- Either stack can be promoted to primary after evaluation
- Evaluation period allows real-world usage patterns to emerge
- Infrastructure and application observability may consolidate or remain separate

## Implementation Considerations

**Storage strategy:**
- **Phase 1:** 10GB ClickHouse storage with 7-day retention
  - Intentionally below SigNoz's 30GB minimum recommendation
  - Acceptable for evaluation due to low log frequency on idle cluster
  - Single-node cluster has limited total storage (280GB SSD)
  - Risk of early exhaustion accepted as learning opportunity (informs production sizing)
  - No volume expansion enabled; manual intervention required if storage fills
  - Monitor actual growth to inform long-term capacity planning
- **Phase 2 (if needed):** Additional 10-20GB for Grafana stack (Loki + Tempo)

**Collection architecture:**
- **Phase 1:** SigNoz k8s-infra collector
  - otelAgent DaemonSet: node-level metrics, logs (1 CPU / 1Gi per node)
  - otelCollector Deployment: cluster-level metrics, k8s events (500m CPU / 512Mi)
  - Maintained by SigNoz team, optimized for their backend
- **Phase 2 (if needed):** Separate OpenTelemetry Collector for Grafana stack
  - Dual exporters (Loki + Tempo)
  - Deployed in separate namespace for clean separation
- Manual instrumentation for application traces (both phases)

**Evaluation criteria:**

*Phase 1 (SigNoz standalone):*
- Log search speed and query effectiveness
- Auto-dashboard quality vs manual Grafana dashboards
- Operational overhead (deployment, updates, troubleshooting)
- Actual storage usage vs projections
- Query interface usability for team
- API integration ease for automation and agents

*Phase 2 (comparative, if needed):*
- Which system is accessed first during production incidents
- Dashboard creation time investment (SigNoz auto vs Grafana manual)
- Trace debugging effectiveness across both platforms
- Query language preference (ClickHouse SQL vs PromQL/LogQL)

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
- Storage constraints tighten (10GB proves insufficient even for idle cluster)
- Application instrumentation requirements change (heavier trace volume)
- Cluster scales to multi-node (changes resource availability)
- Team composition changes (different observability expertise)

## References

- [Grafana Documentation](https://grafana.com/docs/)
- [SigNoz Documentation](https://signoz.io/docs/)
- [OpenTelemetry](https://opentelemetry.io/)
- ADR 0013: Observability Foundation
