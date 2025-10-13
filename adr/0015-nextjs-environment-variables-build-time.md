# 0015. Next.js Environment Variables: Build-Time Strategy

**Status**: Accepted

**Date**: 2025-10-13

## Context

Next.js applications using `NEXT_PUBLIC_` prefixed environment variables face a fundamental challenge: these variables are inlined into the JavaScript bundle at build time, not runtime. This creates tension between the "build once, deploy many" principle and the need for environment-specific configuration (different API URLs for stage vs prod).

Requirements:
- dev-ui needs different API endpoints per environment:
  - Stage: `https://api-stage.steady.ops.last-try.org`
  - Prod: `https://api.steady.ops.last-try.org`
- Browser-based (client-side) code needs access to these URLs
- Small team with limited operational overhead tolerance
- GitOps deployment via ArgoCD

Current situation:
- Single Hetzner node, scaling to multi-node
- Two environments: steady-stage and steady-prod namespaces
- Automated CI/CD: push to dev → stage, push to master → prod

## Decision

We will use **build-time environment variables** passed as Docker build arguments, creating separate images for stage and prod environments.

Configuration:
- Pass `NEXT_PUBLIC_API_URL` and `NEXT_PUBLIC_WS_URL` as build args in GitHub Actions workflow
- Build separate images tagged `stage-{SHA}` and `prod-{SHA}`
- No runtime environment variable injection needed

## Alternatives Considered

### 1. Runtime Configuration with Find-and-Replace Script (PostHog/Cal.com approach)
- **Pros**:
  - True "build once, deploy many"
  - Same image works across all environments
  - Can override with Kubernetes env vars
  - Used by major production apps (PostHog, Cal.com)
- **Cons**:
  - Slightly hacky (text replacement in compiled JavaScript)
  - Adds 2-5 seconds to container startup
  - Risk of unintended replacements
  - Additional operational complexity
- **Why not chosen**: Complexity not justified for two-environment setup with automated builds

### 2. next-runtime-env Package
- **Pros**:
  - Clean API, purpose-built solution
  - ~1M weekly downloads, actively maintained
  - Proper Next.js 14 support
- **Cons**:
  - External dependency to maintain
  - Requires code refactoring (wrap app, change API imports)
  - Learning curve for team
- **Why not chosen**: External dependency overhead not worth it for simple case

### 3. Server-Side API Endpoint (/api/config)
- **Pros**:
  - Official Next.js recommendation
  - Full control, no external dependencies
  - Can add caching, validation logic
- **Cons**:
  - Most code changes required
  - Extra HTTP request on app initialization
  - Must implement proper caching to avoid performance hit
- **Why not chosen**: Overengineered for current needs

## Consequences

### Positive
- ✅ Standard Next.js approach (zero surprises)
- ✅ No additional code or dependencies
- ✅ Simple to understand and debug
- ✅ Works perfectly with existing CI/CD pipeline
- ✅ Each environment has optimized bundle with correct URLs

### Negative
- ❌ Cannot reuse same image across environments
- ❌ Slightly larger image storage (two images instead of one)
- ❌ Must rebuild to change URLs (but CI/CD handles this automatically)
- ⚠️ Violates strict "build once, deploy many" principle

### Neutral
- Build time increase negligible (environment-specific config minimal)
- CI/CD already builds per-environment, so no workflow changes needed
- Migration path exists if requirements change (see "When to Reconsider")

## Implementation Notes

### Dockerfile (Builder stage)
```yaml
FROM base AS builder
WORKDIR /app

# Accept build arguments
ARG NEXT_PUBLIC_API_URL
ARG NEXT_PUBLIC_WS_URL

# ... copy deps and code ...

# Set as environment variables for build
ENV NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}
ENV NEXT_PUBLIC_WS_URL=${NEXT_PUBLIC_WS_URL}

RUN npm run build
```

### GitHub Actions Workflow
```yaml
- name: Determine environment and image tag
  id: env
  run: |
    if [ "${{ github.ref }}" == "refs/heads/master" ]; then
      echo "api_url=https://api.steady.ops.last-try.org" >> $GITHUB_OUTPUT
      echo "ws_url=wss://ws.steady.ops.last-try.org" >> $GITHUB_OUTPUT
    else
      echo "api_url=https://api-stage.steady.ops.last-try.org" >> $GITHUB_OUTPUT
      echo "ws_url=wss://ws-stage.steady.ops.last-try.org" >> $GITHUB_OUTPUT
    fi

- name: Build and push Docker image
  uses: docker/build-push-action@v5
  with:
    build-args: |
      NEXT_PUBLIC_API_URL=${{ steps.env.outputs.api_url }}
      NEXT_PUBLIC_WS_URL=${{ steps.env.outputs.ws_url }}
```

### Kubernetes Manifests
No environment variables needed in deployment manifests - URLs are baked into image.

## When to Reconsider

**Migrate to runtime configuration if:**

1. **> 5 environments**: Build-time becomes unwieldy with many environments (dev, staging, qa, uat, prod, etc.)
2. **Frequent URL changes**: Need to change URLs without full rebuild/redeploy cycle
3. **Multi-tenant**: Same codebase needs different URLs per customer/tenant
4. **External configuration requirement**: Compliance/security requires runtime config from secrets management
5. **True "build once"**: Strict adherence to 12-factor app principle becomes mandatory

**Migration path options:**
- Find-and-replace script (fastest, ~1 hour implementation)
- next-runtime-env package (cleanest API, ~2-3 hours including code refactor)
- Server-side API endpoint (most flexible, ~4-6 hours including caching)

## Cost-Benefit Analysis

**Current scale (2 environments):**
- Build-time: Simple, works
- Runtime: Overengineered

**Future scale (5+ environments or frequent changes):**
- Build-time: Becomes painful
- Runtime: Justified complexity

**Decision**: Start simple, migrate when pain is real.

## References

- [Next.js Environment Variables Documentation](https://nextjs.org/docs/pages/guides/environment-variables)
- [Phase: Updating Next.js public variables without rebuilds](https://phase.dev/blog/nextjs-public-runtime-variables/)
- [GitHub Discussion: Better support for runtime environment variables](https://github.com/vercel/next.js/discussions/44628)
- [next-runtime-env npm package](https://www.npmjs.com/package/next-runtime-env)
- [Cal.com approach](https://github.com/vercel/next.js/discussions/17641)
