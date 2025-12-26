# 0032. GitLab CI PATH Variable Breaks Service Containers

**Status:** Accepted

**Date:** 2025-12-26

## Context

GitLab CI jobs with Kubernetes executor were failing with "executable file not found in $PATH" errors for ALL containers in job pods, including:
- Build container (rust:latest)
- Service containers (postgres:18-alpine)
- Docker-in-Docker service (docker:dind)

**Error examples:**
```
Error: exec: "sh": executable file not found in $PATH
Error: exec: "docker-entrypoint.sh": executable file not found in $PATH
Error: exec: "dockerd-entrypoint.sh": executable file not found in $PATH
```

**Root cause:** `.gitlab-ci.yml` defined `PATH` variable in job's `variables:` section:
```yaml
backend:test:
  variables:
    PATH: /builds/green/green/.cargo/bin:$PATH  # ❌ Breaks all containers
```

## Decision

**Never set `PATH` as a CI variable in `.gitlab-ci.yml`.** Use `before_script` to export it instead.

**Correct approach:**
```yaml
backend:test:
  variables:
    CARGO_HOME: /builds/green/green/.cargo  # OK
    # PATH: removed from variables
  before_script:
    - export PATH="$CARGO_HOME/bin:$PATH"  # ✅ Shell expansion in container
```

## Why This Happens

1. GitLab Runner injects CI variables directly into Kubernetes PodSpec
2. Kubernetes doesn't perform shell expansion on env values
3. Value becomes literal string: `PATH="/builds/green/green/.cargo/bin:$PATH"`
4. System PATH (`/usr/bin:/bin`) is replaced with broken value
5. All containers lose access to standard executables

**Works with shell executor (not relevant for us):**
- Shell executor runs commands in a shell on the host
- Shell expands `$PATH` before executing
- Not applicable to Kubernetes/Docker executors

## Alternatives Considered

### 1. Full PATH in CI Variable
```yaml
variables:
  PATH: "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/builds/green/green/.cargo/bin"
```
- **Why not chosen:** Fragile, varies by image, hard to maintain

### 2. Fix in GitLab Runner
Not an option - this is correct Kubernetes behavior, not a runner bug

### 3. Use shell executor
Not applicable - we use Kubernetes executor

## Consequences

### Positive
- ✅ Service containers work correctly
- ✅ All containers can find entrypoint scripts
- ✅ Standard approach for Kubernetes executor

### Negative
- ⚠️ One extra line in `before_script` per job
- ⚠️ Easy mistake to make (PATH in variables seems intuitive)

### Neutral
- Only affects jobs that need custom PATH
- Shell expansion happens at runtime, not variable injection time

## Implementation Notes

### Pattern for PATH-Dependent Tools

**Rust/Cargo:**
```yaml
variables:
  CARGO_HOME: "$CI_PROJECT_DIR/.cargo"
before_script:
  - export PATH="$CARGO_HOME/bin:$PATH"
```

**Python/pip user base:**
```yaml
variables:
  PIP_USER_BIN: "$HOME/.local/bin"
before_script:
  - export PATH="$PIP_USER_BIN:$PATH"
```

**General:**
```yaml
before_script:
  - export PATH="/custom/path:$PATH"  # Always append to existing PATH
```

### Testing

After fixing PATH variable, verify:
```bash
# Job pods should start successfully
kubectl get pods -n gitlab-runner

# All containers should be ready (1/1, 2/2, 3/3, etc.)
# No "executable file not found" errors
```

## Prevention

**Code review checklist:**
- ❌ Never allow `PATH:` in `variables:` section
- ✅ Use `export PATH=...` in `before_script` instead
- ✅ Document why for future developers

**Pre-commit hook:**
Consider adding a check in `.gitlab-ci.yml` validation:
```bash
# Fail if PATH is in variables section
grep -E '^\s+PATH:' .gitlab-ci.yml && echo "ERROR: PATH in variables" && exit 1
```

## References

- [GitLab CI Variables Documentation](https://docs.gitlab.com/ee/ci/variables/)
- [Kubernetes Pod Environment Variables](https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/)
- Related: ADR 0031 - GitLab Runner Image Pull Policy
