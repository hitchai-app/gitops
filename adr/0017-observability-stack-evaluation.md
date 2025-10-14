# 0017. Observability Stack Evaluation

**Status**: Proposed

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

**Deploy dual observability stacks in parallel for comparative evaluation:**

**Stack A (Grafana Ecosystem):**
- Existing: Prometheus (metrics) + Grafana (visualization) + Alertmanager
- Add: Loki (logs) + Tempo (traces)

**Stack B (Unified Platform):**
- SigNoz (metrics + logs + traces in single platform)

**Data collection:**
- Single OpenTelemetry Collector feeding both stacks
- Collect infrastructure telemetry (nodes, pods, system logs)
- Collect application telemetry (service logs, traces, metrics)

**Evaluation approach:**
- Run both for defined period
- Track which system is used during actual incidents
- Compare dashboard maintenance effort
- Assess API usability for automation

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

## Consequences

### Positive
- ✅ **Low-risk evaluation**: Keep working stack, add experimental stack alongside
- ✅ **Direct comparison**: Same data in both systems enables objective assessment
- ✅ **Operational validation**: Discover which tool is reached for during incidents
- ✅ **Dashboard burden test**: Evaluate if auto-dashboards reduce maintenance overhead
- ✅ **Reversible decision**: Can remove either stack after evaluation

### Negative
- ⚠️ **Dual management overhead**: Two systems to maintain during evaluation period
- ⚠️ **Resource consumption**: Additional RAM and storage for parallel systems
- ⚠️ **Learning curve**: Team learns two different interfaces and workflows
- ⚠️ **Instrumentation effort**: Applications require OpenTelemetry integration

### Neutral
- Retention policies set conservatively during evaluation, expandable later
- Either stack can be promoted to primary after evaluation
- Evaluation period allows real-world usage patterns to emerge
- Infrastructure and application observability may consolidate or remain separate

## Implementation Considerations

**Storage strategy:**
- Conservative initial allocation with aggressive retention
- Expandable volumes if evaluation extends or data proves valuable
- Monitor actual growth to inform long-term capacity planning

**Collection architecture:**
- OpenTelemetry Collector with dual exporters
- Automatic discovery of infrastructure components
- Manual instrumentation for application traces

**Evaluation criteria:**
- Which system is accessed during production incidents
- Dashboard creation and maintenance time investment
- Log query complexity and effectiveness
- Trace debugging value for multi-service issues
- API integration ease for automation and agents

**Exit conditions:**
- Clear preference emerges from actual usage patterns
- One system proves insufficient for critical use cases
- Operational burden of dual stacks becomes untenable
- Resource constraints require consolidation

## When to Reconsider

**Keep both systems if:** Different layers (infrastructure vs application) are better served by specialized tools

**Consolidate to Grafana if:** Ecosystem maturity and flexibility outweigh operational complexity

**Consolidate to SigNoz if:** Unified platform and auto-dashboards significantly reduce maintenance burden

**Extend evaluation if:** Usage patterns remain unclear or capabilities evolve during trial

## References

- [Grafana Documentation](https://grafana.com/docs/)
- [SigNoz Documentation](https://signoz.io/docs/)
- [OpenTelemetry](https://opentelemetry.io/)
- ADR 0013: Observability Foundation
