# 0026. Forgejo Actions with Ephemeral Runners

**Status**: Accepted

**Date**: 2025-12-10

## Context

Need CI/CD runners for Forgejo Actions. Two approaches considered:

1. **Persistent daemon**: Single long-running pod, always consuming resources
2. **Ephemeral (KEDA)**: Scale 0→N based on pending jobs, fresh pod per job

Requirements:
- Scale to zero when idle
- Clean environment per job (no state leakage)
- Docker-in-Docker support for container builds
- Minimal resource usage when no jobs pending

## Decision

Deploy **KEDA ScaledJob** with ephemeral Forgejo runners using `one-job` command.

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│  KEDA Controller                                        │
│  ┌─────────────────────┐                                │
│  │ Forgejo Scaler      │ ← Polls Forgejo API            │
│  │ (forgejo-runner)    │                                │
│  └──────────┬──────────┘                                │
│             │ Scales 0→N                                │
│             ▼                                           │
│  ┌─────────────────┐  ┌─────────────────┐              │
│  │ Job Pod         │  │ Job Pod         │ (ephemeral)  │
│  │ runner + dind   │  │ runner + dind   │              │
│  │ --one-job       │  │ --one-job       │              │
│  └────────┬────────┘  └────────┬────────┘              │
│           ↓                    ↓                        │
│       Job done             Job done                     │
│       Pod terminates       Pod terminates               │
└─────────────────────────────────────────────────────────┘
```

### Components

- **KEDA operator**: Watches Forgejo API for pending jobs
- **ScaledJob**: Creates Kubernetes Jobs when work pending
- **TriggerAuthentication**: Forgejo API token for KEDA
- **Runner registration**: Pre-registered via shared secret
- **DinD sidecar**: Native K8s sidecar pattern (initContainer + restartPolicy: Always)

## Alternatives Considered

| Approach | Pros | Cons |
|----------|------|------|
| Persistent daemon | Simple setup | Wastes resources when idle |
| KEDA + ScaledJob | Scale to zero, clean environments | More complex setup |
| Woodpecker CI | Separate mature CI | Extra system to maintain |

## Consequences

### Positive

- Zero resource usage when idle (scale to 0)
- Fresh environment per job (no cache pollution)
- Automatic scaling based on queue depth
- Similar pattern to GitHub's ARC

### Negative

- Cold start latency (~30s for pod + DinD startup)
- Requires KEDA operator (additional component)
- Pre-registration step required

## Implementation

### Prerequisites

- Forgejo v11+ (job metrics endpoint)
- Runner v6.1+ (`one-job` command)
- KEDA v2.18+

### Files

- `apps/infrastructure/keda.yaml` - KEDA operator
- `apps/infrastructure/forgejo-runner.yaml` - ArgoCD app
- `infrastructure/keda/values.yaml` - KEDA config
- `infrastructure/forgejo-runner/scaledjob.yaml` - KEDA ScaledJob
- `infrastructure/forgejo-runner/trigger-auth.yaml` - KEDA auth
- `infrastructure/forgejo-runner/runner-registration-sealed.yaml` - Pre-registered runner
- `infrastructure/forgejo-runner/keda-auth-sealed.yaml` - API token

## References

- [KEDA Forgejo Scaler](https://keda.sh/docs/2.18/scalers/forgejo/)
- [Forgejo Runner `one-job`](https://code.forgejo.org/forgejo/runner)
- [KEDA ScaledJob](https://keda.sh/docs/2.18/concepts/scaling-jobs/)
- ADR 0023: Forgejo + Woodpecker CI (partially superseded for CI)
