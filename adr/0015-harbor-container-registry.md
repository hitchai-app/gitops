# 0015. Harbor Container Registry

**Status**: Proposed

**Date**: 2025-10-12

**⚠️ RELATIONSHIP TO ADR 0016 (GitLab):**

Harbor and GitLab can **coexist and complement each other**:

**GitHub + Harbor:**
- Harbor provides registry for GitHub Actions builds
- Harbor proxies external registries (Docker Hub, GHCR, gcr.io)

**GitLab + Harbor (both):**
- GitLab CI builds → Push to Harbor (not GitLab registry)
- Harbor proxies external registries (GitLab registry doesn't do this)
- Harbor provides better scanning/RBAC than GitLab's built-in registry
- Centralized registry management beyond GitLab CI

**GitLab alone (no Harbor):**
- Use GitLab's built-in registry for CI builds
- Accept no pull-through cache for external registries
- Accept basic scanning/RBAC (less features than Harbor)

Harbor makes sense **regardless of GitHub vs GitLab choice** if you want multi-registry caching and advanced features.

## Context

We currently use a simple Docker Registry v2 as a pull-through cache for Docker Hub images. As the cluster grows, we're encountering limitations:

**Current Setup:**
- Docker Registry v2 deployed as pull-through cache
- Configured in DinD runner sidecars via `--registry-mirror` flag
- No UI, no RBAC, no vulnerability scanning
- Only caches Docker Hub (GHCR, gcr.io, quay.io bypass cache)
- Manual garbage collection via CronJob

**Infrastructure Context:**
- PostgreSQL available (CloudNativePG shared cluster)
- Redis available (Valkey StatefulSet)
- Single node → scaling to multi-node
- Small team (developers handle ops)

**Pain Points:**
1. **Security blind spot** - No vulnerability scanning, shipping unknown CVEs
2. **Multi-registry problem** - Pulling from GHCR, gcr.io directly (no cache, rate limits)
3. **No visibility** - Can't see what's cached, disk usage, who pushed what
4. **No access control** - Anyone with cluster access can push anything
5. **Manual cleanup** - CronJob for garbage collection, no retention policies

## Decision

We will deploy **Harbor** as our container registry, replacing the simple Docker Registry.

Configuration:
- Shared PostgreSQL database (CloudNativePG)
- Shared Redis for caching (Valkey)
- Trivy for vulnerability scanning
- Project structure: `public/` (cached external), `apps/` (internal builds)
- Retention policy: keep last 10 tags per project, delete untagged after 7 days
- RBAC: Read-only anonymous for cached images, authenticated push for internal builds

## Alternatives Considered

### 1. Keep Simple Registry + Add Tools Separately

**Approach:** Keep Docker Registry, add vulnerability scanning via separate Trivy deployment, add UI via separate web app, etc.

**Pros:**
- Incremental changes
- Can add features as needed
- Simpler components

**Cons:**
- **Fragmented experience** - Multiple UIs, no integration
- **More operational overhead** - Coordinate updates across multiple tools
- **No unified RBAC** - Registry has no auth, need separate proxy
- **Manual integration** - Custom scripts to connect scanning to registry
- **No multi-registry proxy** - Still can't cache GHCR/gcr.io/quay.io

**Why not chosen:** Ends up more complex than Harbor with worse integration.

### 2. Multiple Registry Mirrors (containerd config)

**Approach:** Configure containerd to mirror each registry (Docker Hub, GHCR, gcr.io) via separate `registry-mirrors` entries.

**Pros:**
- No Harbor overhead
- Works transparently
- Simple configuration

**Cons:**
- **No scanning** - Still shipping vulnerable images
- **No RBAC** - No control over internal pushes
- **No UI** - Still blind to cache contents
- **No retention** - Manual garbage collection
- **Read-only mirrors** - Can't push internal images, need separate registry anyway

**Why not chosen:** Solves caching but ignores security/visibility/control requirements.

### 3. Cloud-Hosted Registry (Docker Hub, GHCR, AWS ECR)

**Approach:** Push all internal images to external registry service.

**Pros:**
- Managed service (no ops burden)
- Built-in CDN, scanning, RBAC
- High availability

**Cons:**
- **Recurring cost** - $5-50/month depending on usage
- **Egress costs** - Pulling images from cloud during builds
- **Latency** - Slower than local registry
- **Vendor lock-in** - Migration complexity if switching providers
- **Doesn't solve caching** - Still need pull-through cache for external images

**Why not chosen:** Adds cost and latency, doesn't eliminate need for local cache.

### 4. Nexus Repository OSS

**Approach:** Use Sonatype Nexus as unified artifact repository (Maven, npm, Docker, etc).

**Pros:**
- Multi-format support (Docker, npm, Maven)
- Mature project (since 2010)
- Strong Java ecosystem support
- Built-in proxy/caching

**Cons:**
- **Heavier resource footprint** - JVM-based, ~3-4GB RAM
- **More complex** - Designed for enterprise multi-format needs
- **Weaker container focus** - Docker support added later, not core feature
- **No Trivy integration** - Uses Sonatype's scanning (requires license for full features)
- **Overkill** - We don't need Maven/npm/Helm repos yet

**Why not chosen:** Harbor is lighter and more container-native for our current needs.

### 5. GitLab Container Registry

**Approach:** Use GitLab's built-in container registry.

**Pros:**
- Integrated with GitLab CI/CD (if using GitLab)
- Built-in scanning
- Part of GitLab suite

**Cons:**
- **We use GitHub** - Would need to run GitLab just for registry
- **Heavy dependency** - GitLab is large (Rails app, Gitaly, etc)
- **Weaker pull-through cache** - Not designed as proxy registry
- **Tight coupling** - Registry tied to GitLab instance lifecycle

**Why not chosen:** Don't use GitLab, running it just for registry is excessive.

### 6. Distribution (CNCF) with Extensions

**Approach:** Use [CNCF Distribution](https://distribution.github.io/distribution/) (Docker Registry v3) with extensions for auth/UI.

**Pros:**
- CNCF project (vendor-neutral)
- Modern architecture
- OCI-native
- Lighter than Harbor

**Cons:**
- **Still immature** - Graduated Dec 2023, ecosystem developing
- **No integrated scanning** - Need external Trivy
- **No built-in UI** - Community UIs exist but fragmented
- **More assembly required** - Build your own solution vs Harbor's batteries-included

**Why not chosen:** Too early, Harbor is more battle-tested with better integration.

## Consequences

### Positive

**Security:**
- ✅ Vulnerability scanning via Trivy (CVE detection before deployment)
- ✅ RBAC per project (control who can push/pull)
- ✅ Audit logs (track image pushes/pulls)
- ✅ Content trust / image signing (Cosign integration)

**Operations:**
- ✅ Web UI (visibility into cached images, disk usage, projects)
- ✅ Retention policies (automated cleanup, keep last N tags)
- ✅ Multi-registry proxy (unified cache for Docker Hub, GHCR, gcr.io, quay.io)
- ✅ Replication (can sync to S3/other Harbor instances for DR)

**Developer Experience:**
- ✅ Single endpoint for all images (no remembering which registry)
- ✅ Image search across projects
- ✅ Vulnerability reports accessible to developers
- ✅ Tag immutability (prevent accidental overwrites of `:prod` tags)

**Infrastructure Efficiency:**
- ✅ Leverage existing PostgreSQL cluster (no new database)
- ✅ Leverage existing Redis (no new cache)
- ✅ Centralized image storage (vs scattered across nodes)

### Negative

**Resource Overhead:**
- ❌ Harbor core: ~300-500MB RAM
- ❌ Harbor jobservice: ~100-200MB RAM
- ❌ Harbor portal (UI): ~50-100MB RAM
- ❌ Trivy scanner: ~200-300MB RAM (spikes during scans)
- ❌ Total: ~650MB-1.1GB RAM additional (acceptable on 128GB node)

**Operational Complexity:**
- ❌ Multi-component upgrades (core, jobservice, registry, portal)
- ❌ PostgreSQL schema migrations during upgrades
- ❌ More components to monitor (core, jobservice, registry, Trivy)
- ❌ More attack surface (web UI, API)

**Migration Effort:**
- ❌ Migrate cached images from old registry to Harbor
- ❌ Update runner configurations to use Harbor endpoint
- ❌ Update workflows that push images
- ❌ Set up projects and RBAC policies
- ⚠️ Estimated: 1 day migration + testing

**Limitations:**
- ⚠️ Trivy scanning adds latency to image pushes (~30s-2min depending on image size)
- ⚠️ Proxy cache has eventual consistency (first pull from upstream may be slower)
- ⚠️ PostgreSQL dependency (if DB down, registry unavailable)

### Neutral

- Can revert to simple registry if Harbor proves too complex
- Harbor community active (CNCF incubating project)
- Comparable resource usage to Nexus, lighter than GitLab Registry

## Implementation Notes

### Harbor Chart Configuration

```yaml
# Use existing infrastructure
database:
  type: external
  external:
    host: postgres-shared-rw.postgres-shared.svc.cluster.local
    port: 5432
    username: harbor
    database: harbor

redis:
  type: external
  external:
    addr: redis-shared.redis-shared.svc.cluster.local:6379

# Resource limits
core:
  resources:
    requests: { cpu: 100m, memory: 256Mi }
    limits: { cpu: 500m, memory: 512Mi }

jobservice:
  resources:
    requests: { cpu: 50m, memory: 128Mi }
    limits: { cpu: 200m, memory: 256Mi }

# Enable Trivy scanning
trivy:
  enabled: true
  resources:
    requests: { cpu: 100m, memory: 256Mi }
    limits: { cpu: 500m, memory: 512Mi }

# Storage
persistence:
  persistentVolumeClaim:
    registry:
      storageClass: longhorn-single-replica
      size: 100Gi
```

### Project Structure

```
harbor.ops.last-try.org/
├── public/              # Proxy cache (anonymous read)
│   ├── docker.io/       # Docker Hub mirror
│   ├── ghcr.io/         # GitHub Container Registry mirror
│   ├── gcr.io/          # Google Container Registry mirror
│   └── quay.io/         # Red Hat Quay mirror
└── apps/                # Internal builds (authenticated push)
    ├── inference-backend/
    ├── dev-ui/
    ├── landing/
    └── platform-backend/
```

### Migration Plan

1. Deploy Harbor in parallel with existing registry
2. Configure Harbor as proxy cache for external registries
3. Test pulling cached images through Harbor
4. Update one runner scale set to use Harbor
5. Verify builds work correctly
6. Migrate remaining runners
7. Decommission old registry after 7 days

### Monitoring

**Alerts:**
- Harbor core unhealthy for > 5 minutes
- Registry disk usage > 80%
- Trivy scan failures > 10% of pushes
- PostgreSQL connection pool exhaustion

**Metrics to track:**
- Image pull throughput (requests/sec)
- Cache hit rate (proxy cache effectiveness)
- Scan duration (Trivy performance)
- Storage growth rate (capacity planning)

## When to Reconsider

**Revisit if:**

1. **Harbor resource overhead becomes problematic** (single node RAM exhaustion)
   - Action: Disable Trivy scanning, use external scanning service
   - Action: Revert to simple registry + manual security

2. **Harbor complexity exceeds team capacity** (frequent incidents, upgrade failures)
   - Action: Switch to managed registry (GHCR, AWS ECR)
   - Action: Simplify to multi-registry mirrors via containerd

3. **Vulnerability scanning not used/valued** (reports ignored, no remediation)
   - Action: Disable Trivy, re-evaluate if Harbor worth it without scanning

4. **Multi-node scaling requires distributed storage** (Longhorn volume constraints)
   - Action: Consider S3-backed registry (Harbor supports S3 storage backend)

5. **Team grows and needs advanced features Harbor lacks**
   - Action: Evaluate Nexus (if need multi-format), GitLab Registry (if adopting GitLab)

## Open Questions

1. **Should we enforce scan-on-push blocking?** (Reject images with HIGH/CRITICAL CVEs)
   - Pro: Forces security fixes before deployment
   - Con: May block urgent hotfixes, requires CVE triage process

2. **How to handle base image vulnerabilities?** (CVEs in `node:24-alpine`, `redis:8-alpine`)
   - Strategy: Accept upstream CVEs, focus on our code CVEs?
   - Strategy: Pin base images to specific digests after scan approval?

3. **Retention policy strictness?** (Keep last 10 tags vs keep last 30 days)
   - Need to balance disk usage vs ability to rollback old versions
   - Should `:prod` tags be immutable and exempt from cleanup?

4. **Anonymous pull access?** (Allow unauthenticated pulls from `public/` project)
   - Pro: Simpler for runners, no credential management
   - Con: Potential abuse, no pull accounting
   - Compromise: Require auth for internal projects, anonymous for proxy cache?

## Related ADRs

- ADR 0002: Longhorn Storage from Day One (provides PVC for Harbor registry storage)
- ADR 0004: CloudNativePG for PostgreSQL (provides Harbor's database)
- ADR 0005: Valkey StatefulSet (provides Harbor's Redis cache)
- ADR 0014: Actions Runner Controller (runners will pull from Harbor)

## References

- [Harbor Documentation](https://goharbor.io/docs/)
- [Harbor GitHub](https://github.com/goharbor/harbor)
- [Harbor Helm Chart](https://github.com/goharbor/harbor-helm)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [CNCF Distribution](https://distribution.github.io/distribution/)
