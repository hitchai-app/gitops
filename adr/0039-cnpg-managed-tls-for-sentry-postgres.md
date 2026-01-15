# 0039. CNPG-Managed TLS and Password Auth for Sentry Postgres

**Status**: Accepted

**Date**: 2026-01-15

## Context

The Sentry deployment uses CloudNativePG for PostgreSQL. We initially attempted to reuse a cert-manager issued CA for client certificate authentication to keep a single CA across Sentry services and avoid passwords. In practice, CloudNativePG expects client CA secrets containing `ca.crt`/`ca.key`, while cert-manager stores CA material as `tls.crt`/`tls.key`. Bridging the key names introduces rotation drift and makes GitOps state non-reproducible without a controller that keeps the secrets in sync. CloudNativePG can instead manage TLS for its own cluster automatically.

## Decision

Use CloudNativePG operator-managed TLS for the Sentry PostgreSQL cluster and authenticate applications with a password from the CloudNativePG `-app` secret. Do not use cert-manager-issued CA material for CloudNativePG client auth in this deployment.

## Alternatives Considered

1. **Reuse cert-manager CA for CloudNativePG client auth**
   - Pros: Unified CA across Sentry stateful services
   - Cons: Secret key name mismatch, rotation drift, non-reproducible without a sync controller

2. **Bridge cert-manager CA to a CNPG-compatible secret**
   - Pros: Keeps cert-manager as CA authority
   - Cons: Requires a controller/Job to keep CA secrets in sync on rotation; adds operational complexity

3. **Disable TLS for Postgres**
   - Pros: Simplest configuration
   - Cons: Avoids transport security entirely; not acceptable for production

## Consequences

### Positive
- Uses CloudNativePG defaults with automatic TLS management and rotation
- Keeps GitOps state reproducible without secret translation controllers
- Aligns with CNPG's application connection model and generated `-app` secret

### Negative
- Loses a single shared CA for Postgres client auth across Sentry services
- Requires password-based auth for Sentry database connections

### Neutral
- cert-manager remains the CA authority for other Sentry services (ClickHouse, Valkey)
- Sentry must reference the CNPG application secret for database credentials

## References

- CloudNativePG Certificates (operator-managed mode) - https://cloudnative-pg.io/documentation/1.19/certificates/
- CloudNativePG Applications (generated `-app` secret contents) - https://cloudnative-pg.io/documentation/current/applications/
- ADR 0004: CloudNativePG for PostgreSQL
- ADR 0021: Sentry Error Tracking Platform
