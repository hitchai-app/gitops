# 0037. Strimzi Kafka Operator

**Status**: Superseded by ADR 0040

**Date**: 2026-01-14

## Context

Need distributed event streaming platform for workloads requiring reliable message delivery. Kafka provides durable event streaming with acknowledgments and replay.

## Decision

Deploy **Strimzi Kafka operator** (CNCF incubating).

- KRaft mode (no ZooKeeper)
- Single broker initially
- Longhorn single-replica storage

## Alternatives Considered

| Option | Decision | Reason |
|--------|----------|--------|
| Bitnami Kafka | Avoid | Less mature, smaller community |
| Bundled (StatefulSet) | Avoid | Manual ops, painful migration later |
| Strimzi | **Chosen** | CNCF project, production-ready since 2017 |

## Consequences

**Positive**:
- Kafka custom resources (Kafka, Topic, User)
- KRaft mode removes ZooKeeper dependency
- CNCF backing (incubating 2024)
- Reusable across multiple workloads
- Rack awareness for future multi-node

**Negative**:
- New operator dependency
- Resource overhead (~512Mi RAM)
- Manual resource configuration required

## When to Reconsider

- Strimzi abandoned (unlikely - CNCF project)
- Need managed cloud Kafka

## Implementation Notes

**KRaft mode** (Kafka Raft metadata mode):
- Eliminates ZooKeeper dependency (simpler architecture)
- Reduced resource overhead (no separate ZooKeeper cluster)
- Default in Strimzi 0.49+ (our chosen version)
- Ideal for Sentry's event streaming use case

**TLS Authentication:** Strimzi has excellent native TLS support via operator certificates:
- Self-signed CA via cert-manager (ClusterIssuer)
- Operator-managed broker certificates with automatic rotation
- TLS listener on port 9093 (mTLS authentication required)
- Client certificates for applications
- Certificate auto-renewal (30 days before 1-year expiry)

## References

- [Strimzi operator](https://github.com/strimzi/strimzi-kafka-operator)
- [Strimzi 0.49.1 release](https://github.com/strimzi/strimzi-kafka-operator/releases/tag/0.49.1) (2025-12-05, fixes CVE-2025-66623)
- [CNCF announcement](https://www.cncf.io/blog/2024/02/08/strimzi-joins-the-cncf-incubator/)
- ADR 0003: Operators over StatefulSets
