# 0030. Remove SigNoz Evaluation Stack

**Status**: Accepted

**Date**: 2025-12-20

## Context

SigNoz was deployed for a time-boxed evaluation alongside the existing Prometheus/Grafana stack. Ongoing operation of SigNoz adds additional pods, storage, and maintenance overhead without clear adoption, and current cluster capacity is needed for other workloads.

## Decision

Remove the SigNoz stack and its Kubernetes infrastructure components. Continue using the existing Prometheus/Grafana stack for observability.

## Alternatives Considered

| Option | Reason Not Chosen |
| --- | --- |
| Keep SigNoz running | Extra resource and operational overhead without adoption |
| Replace Prometheus/Grafana with SigNoz | Higher migration effort and risk without clear benefit |

## Consequences

**Positive**: Frees cluster resources and reduces operational overhead.

**Negative**: SigNoz-specific UI and workflows are no longer available.

## References

- ADR 0017: Observability Stack Evaluation
- ADR 0013: Observability Foundation
