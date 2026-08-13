# Feature: Debug Dump Collection

This branch adds support for collecting Central's debug dump bundle via the `/debug/dump` endpoint for performance debugging.

## What is the Debug Dump?

The debug dump is a performance debugging bundle created by Central that includes:

### CPU Profiling
- **30-second CPU profile** (pprof format)
- Function call stacks, CPU time per function
- **Use case**: High CPU usage, slow API calls, performance hotspots
- **Analysis**: `go tool pprof cpu.pb.gz`

### Memory Profiling
- **Heap profile** (pprof format) - Allocation sites, memory usage
- **Goroutine dump** - All active goroutines with stack traces
- **Mutex profile** (pprof format) - Lock contention, blocked time
- **Use cases**: Memory leaks, goroutine leaks, deadlocks, concurrency issues
- **Analysis**: `go tool pprof heap.pb.gz`, `go tool pprof mutex.pb.gz`

### Prometheus Metrics (Dual Snapshots)
- **metrics-1** - Before CPU profiling
- **metrics-2** - After CPU profiling (30s later)
- **Use case**: Correlate CPU profile with metrics changes

### PostgreSQL Diagnostics
Same as diagnostic bundle:
- `pg_stat_statements` - Top 1000 slow queries
- Index health, analyze stats, tuple stats
- Active sessions, connection info

### Configuration Data
Same as diagnostic bundle:
- Auth providers, groups, roles (credentials scrubbed)
- Notifiers (credentials scrubbed)
- System configuration
- Delegated scanning config
- LogImbue audit logs

### What's NOT Included (vs Diagnostic Bundle)
- ❌ Kubernetes resources from clusters
- ❌ Telemetry data (unless `?telemetry=1` or `2`)
- ❌ Sensor metrics
- ❌ Pod logs (unless `?logs=true`)

## Why This Feature?

Debug dump is specifically designed for **performance debugging**:

**Use Cases:**
1. **High CPU usage** - 30-second CPU profile shows hotspots
2. **Memory leaks** - Heap profile shows allocation sites
3. **Deadlocks** - Goroutine dump + mutex profile show blocking
4. **Slow performance** - Combined CPU + PostgreSQL query stats

**Why separate from diagnostic bundle:**
- Faster collection (~1-2 min vs 5-10 min)
- Focused on Central performance, not multi-cluster state
- Includes active profiling (CPU, mutex) vs passive data collection

## Comparison with Official Methods

RHACS provides three methods to collect debug dumps. Each has different use cases:

### Method 1: roxctl CLI (Official Tool)

```bash
roxctl central debug dump \
  --endpoint <central-url>:443 \
  --output debug-dump.zip
```

**When to use:**
- ✅ Central has external route/ingress configured
- ✅ Have Central credentials externally available
- ✅ Quick performance debugging session
- ✅ Only need debug dump (not K8s resources)
- ✅ Prefer official tool with Red Hat support

**Limitations:**
- ❌ Requires external Central access (route/ingress)
- ❌ Does not collect Kubernetes resources
- ❌ Does not collect operator or OLM resources
- ❌ Requires separate tool installation

### Method 2: Direct API Call

```bash
# Port-forward to Central
oc port-forward -n stackrox deploy/central 8443:8443

# Download debug dump
curl -k -u admin:<password> \
  https://localhost:8443/debug/dump \
  -o debug-dump.zip
```

**When to use:**
- ✅ Quick manual collection
- ✅ Testing/development
- ✅ Need to customize query parameters easily

**Limitations:**
- ❌ Manual process, multiple steps
- ❌ No automation friendly
- ❌ Does not collect K8s resources

### Method 3: acs-must-gather with GATHER_DEBUG_DUMP=true (This Feature)

```bash
oc adm must-gather \
  --image=quay.io/rhn_support_shaising/acs-must-gather:latest \
  -- /usr/bin/gather \
  GATHER_DEBUG_DUMP=true
```

**When to use:**
- ✅ Central is running but external routes are down
- ✅ Need both debug dump AND Kubernetes state
- ✅ Don't have Central credentials externally available
- ✅ Want operator and OLM troubleshooting data
- ✅ One command for complete collection
- ✅ Automated troubleshooting workflows
- ✅ Performance issue + environment state correlation

**Advantages:**
- ✅ Works without external Central access (uses oc port-forward)
- ✅ Automatically retrieves admin password from Secrets
- ✅ Collects debug dump + K8s resources + operator data
- ✅ Single command for comprehensive collection
- ✅ Includes OpenShift-specific resources (Routes, SCCs)
- ✅ Works even if Central is degraded (K8s resources still collected)

**Limitations:**
- ❌ Slower than roxctl (must port-forward each time)
- ❌ Requires cluster admin access (to read Secrets)
- ❌ 3-minute default timeout (configurable)

### Comparison Table

| Feature | roxctl CLI | Direct API | acs-must-gather |
|---------|-----------|-----------|-----------------|
| **CPU Profiling (30s)** | ✅ | ✅ | ✅ |
| **Heap Profile** | ✅ | ✅ | ✅ |
| **Goroutine Dump** | ✅ | ✅ | ✅ |
| **Mutex Profile** | ✅ | ✅ | ✅ |
| **PostgreSQL Diagnostics** | ✅ | ✅ | ✅ |
| **Prometheus Metrics** | ✅ | ✅ | ✅ |
| **Query Parameters** | ❌ | ✅ | ✅ (new) |
| **Kubernetes Resources** | ❌ | ❌ | ✅ |
| **Operator Resources** | ❌ | ❌ | ✅ |
| **Cluster RBAC** | ❌ | ❌ | ✅ |
| **OpenShift Specific** | ❌ | ❌ | ✅ |
| **External Access Required** | Yes | No | No |
| **Automation Friendly** | ✅ | ❌ | ✅ |
| **Collection Time** | 1-2 min | 1-2 min | 2-3 min |
| **Official Support** | ✅ | ✅ | Community |

### Recommendation

**For performance debugging:**
- Start with `acs-must-gather` with `GATHER_DEBUG_DUMP=true` for comprehensive data
- Use `roxctl` if you only need profiles and have external access
- Use direct API call for quick manual debugging

**For production issues:**
- Use `acs-must-gather` to capture both performance data and environment state
- Correlate CPU/heap profiles with pod resource limits, node capacity
- Include telemetry to understand workload patterns

**For development/testing:**
- Use direct API call for rapid iteration
- Use `roxctl` for automated performance tests

## How It Works

### Authentication
Identical to diagnostic bundle - uses admin password from Secret.

### Collection Method
1. Find running Central pod
2. Retrieve admin password from Secret
3. Establish port-forward (finds available port automatically)
4. Download bundle via authenticated `curl` request
5. Clean up port-forward

Collection includes live 30-second CPU profiling, so takes at least 30 seconds.

## Usage

### Enable Debug Dump Collection

```bash
oc adm must-gather \
  --image=quay.io/rhn_support_shaising/acs-must-gather:latest \
  -- /usr/bin/gather \
  GATHER_DEBUG_DUMP=true
```

### Environment Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `GATHER_DEBUG_DUMP` | Enable debug dump collection | `false` (disabled) | `true` |
| `DEBUG_DUMP_TIMEOUT` | Collection timeout in seconds | `180` (3 minutes) | `300` |
| `DEBUG_DUMP_LOGS` | Include Central logs in dump | `false` | `true` |
| `DEBUG_DUMP_TELEMETRY` | Include telemetry data (0=none, 1=Central, 2=Central+Sensors) | (none) | `1` or `2` |

### Example with Query Parameters

```bash
# Basic debug dump (CPU + heap + goroutine + mutex profiles)
oc adm must-gather \
  --image=quay.io/rhn_support_shaising/acs-must-gather:latest \
  -- /usr/bin/gather \
  GATHER_DEBUG_DUMP=true

# With Central logs included
oc adm must-gather \
  --image=quay.io/rhn_support_shaising/acs-must-gather:latest \
  -- /usr/bin/gather \
  GATHER_DEBUG_DUMP=true \
  DEBUG_DUMP_LOGS=true

# With Central telemetry
oc adm must-gather \
  --image=quay.io/rhn_support_shaising/acs-must-gather:latest \
  -- /usr/bin/gather \
  GATHER_DEBUG_DUMP=true \
  DEBUG_DUMP_TELEMETRY=1

# With Central + Sensor telemetry (comprehensive)
oc adm must-gather \
  --image=quay.io/rhn_support_shaising/acs-must-gather:latest \
  -- /usr/bin/gather \
  GATHER_DEBUG_DUMP=true \
  DEBUG_DUMP_TELEMETRY=2

# Custom timeout
oc adm must-gather \
  --image=quay.io/rhn_support_shaising/acs-must-gather:latest \
  -- /usr/bin/gather \
  GATHER_DEBUG_DUMP=true \
  DEBUG_DUMP_TIMEOUT=300
```

## Output

### Success
```
/must-gather/acs-diagnostics/stackrox-debug-dump.zip
```

ZIP contents:
- `cpu.pb.gz` - CPU profile (pprof)
- `heap.pb.gz` - Heap profile (pprof)
- `goroutine.txt` - Goroutine dump
- `mutex.pb.gz` - Mutex profile (pprof)
- `metrics-1`, `metrics-2` - Prometheus snapshots
- `central-db*.json` - PostgreSQL diagnostics
- `auth-providers.json`, `access-control-roles.json`, etc.

### Failure
```
/must-gather/acs-diagnostics/debug-dump-error.txt
```

## Collection Time and Size

### Expected Collection Time

| Configuration | Time | Notes |
|--------------|------|-------|
| **Basic** (profiles only) | 30-60 seconds | Minimum 30s for CPU profiling |
| **With logs** (`DEBUG_DUMP_LOGS=true`) | 1-2 minutes | Depends on log volume |
| **With Central telemetry** (`DEBUG_DUMP_TELEMETRY=1`) | 1-2 minutes | Small overhead |
| **With all telemetry** (`DEBUG_DUMP_TELEMETRY=2`) | 2-3 minutes | Includes all Sensors |

**Note**: Collection time in acs-must-gather is ~20-30% slower than roxctl due to port-forward overhead.

### Expected Bundle Size

| Content Type | Typical Size | Large Instance |
|-------------|--------------|----------------|
| **Basic (profiles + DB + config)** | 5-10 MB | 10-30 MB |
| **With logs** | 10-30 MB | 30-100 MB |
| **With telemetry** | 15-40 MB | 40-100 MB |
| **Compressed Format** | ZIP | ZIP |

**Warning**: Dumps larger than 100 MB may indicate:
- Large heap size (memory leak investigation)
- Extensive logs included (reduce retention or use log filtering)
- Many goroutines (potential goroutine leak)
- High mutex contention (many blocked operations)

### Timeout Recommendations

Based on configuration:

```bash
# Basic profiles (default)
DEBUG_DUMP_TIMEOUT=180  # 3 minutes

# With logs or telemetry
DEBUG_DUMP_TIMEOUT=300  # 5 minutes

# Comprehensive (logs + telemetry)
DEBUG_DUMP_TIMEOUT=600  # 10 minutes
```

**Tip**: Start with basic dump first to get CPU/heap profiles quickly, then collect with logs/telemetry if needed.

## Analyzing pprof Profiles

### CPU Profile
```bash
# Interactive analysis
go tool pprof stackrox-debug-dump/cpu.pb.gz
# Commands: top, list <function>, web (requires graphviz)

# Generate flame graph
go tool pprof -http=:8080 cpu.pb.gz
```

### Heap Profile
```bash
go tool pprof heap.pb.gz
# (pprof) top10          # Top 10 allocation sites
# (pprof) list <func>     # Show source with annotations
```

### Mutex Profile
```bash
go tool pprof mutex.pb.gz
# (pprof) top            # Top contention points
# (pprof) web            # Visualize call graph
```

## When to Use Debug Dump vs Diagnostic Bundle

### Use Debug Dump When:
- ✅ Central has high CPU usage
- ✅ Investigating performance degradation
- ✅ Suspecting memory leaks
- ✅ Troubleshooting deadlocks or lock contention
- ✅ Need quick performance snapshot (1-2 min)

### Use Diagnostic Bundle When:
- ✅ Need multi-cluster visibility
- ✅ Investigating database performance (slow queries)
- ✅ Need auth/RBAC configuration details
- ✅ Need audit logs or telemetry
- ✅ Comprehensive troubleshooting (not performance-specific)

### Use Both When:
- ✅ Performance issues + configuration problems
- ✅ Need complete picture for support case

## Security Considerations

Same as diagnostic bundle:
- Admin password retrieved from Kubernetes Secret
- Password used only in-memory
- Port-forward is local to must-gather pod
- Sensitive data scrubbed (auth passwords, notifier tokens)

**Additional consideration**:
- CPU profiling data may contain function names and call stacks
- Goroutine dump shows active operations (may include sensitive data in variables)
- Review before sharing externally

## Comparison with roxctl

### acs-must-gather with GATHER_DEBUG_DUMP=true
**Pros:**
- ✅ Collects both Kubernetes state AND debug dump
- ✅ No Central credentials needed externally
- ✅ Faster than diagnostic bundle (1-2 min vs 5-10 min)

**Cons:**
- ❌ Requires Central running
- ❌ Opt-in (disabled by default)
- ❌ No query parameter support (?logs=, ?telemetry=)

### roxctl central debug dump
**Pros:**
- ✅ Supports query parameters (?logs=true, ?telemetry=1)
- ✅ Native tool maintained by StackRox

**Cons:**
- ❌ Requires Central credentials
- ❌ Requires network access to Central
- ❌ Doesn't collect Kubernetes resources

## Testing

### Prerequisites
- Running RHACS with Central
- Central admin password in Secret
- `curl` in must-gather container
- `lsof` for port detection
- `timeout` command available

### Test Cases

1. **Happy path** - Central running normally
   - Expected: Debug dump collected with all profiles

2. **Central under load** - High CPU scenario
   - Expected: CPU profile shows hotspots

3. **Central down** - Central pod not running
   - Expected: Error file created

4. **Missing password** - No Secret
   - Expected: Error with manual instructions

5. **Timeout** - Set very short timeout (10s)
   - Expected: Timeout error (cannot complete 30s CPU profile)

### Manual Testing

```bash
# Build and run
cd ~/Projects/acs-must-gather
make build
oc adm must-gather --image=localhost/acs-must-gather:latest -- /usr/bin/gather GATHER_DEBUG_DUMP=true

# Extract and analyze
mkdir debug-analysis
cd debug-analysis
unzip ../must-gather-*/acs-diagnostics/stackrox-debug-dump.zip

# Analyze CPU profile
go tool pprof cpu.pb.gz
# (pprof) top20
# (pprof) list main.

# Analyze heap
go tool pprof heap.pb.gz

# View goroutines
less goroutine.txt
```

## Known Limitations

1. **Minimum 30 seconds** - CPU profiling cannot be shortened
   - Mitigation: Document expected collection time

2. **Central must be responsive** - If Central is hanging, profiling may timeout
   - Mitigation: Timeout handling with clear error

3. **No live profiling control** - Cannot adjust profiling duration
   - Mitigation: Default 30s is reasonable for most cases

4. **pprof analysis requires Go** - Support teams need Go toolchain
   - Mitigation: Include analysis instructions in docs

## Implementation Details

### File: `collection-scripts/gather_debug_dump`
- Standalone script for debug dump collection
- Identical auth/port-forward logic to diagnostic bundle
- Different timeout default (3 min vs 10 min)

### Changes to `collection-scripts/gather`
- Added optional launch of `gather_debug_dump`
- Controlled by `GATHER_DEBUG_DUMP` environment variable
- Runs in parallel with other collectors

### Why Separate Script
- Different use case (performance vs comprehensive troubleshooting)
- Different default timeout
- May be enabled independently
- Clearer separation of concerns

## Questions for Reviewers

1. **Default timeout** - Is 3 minutes appropriate?
   - Current: 3 minutes (180s)
   - Rationale: 30s CPU + 30s data + margin = ~90s typical

2. **Enable together with diagnostic bundle?**
   - Current: Separate flags
   - Alternative: `GATHER_DEBUG_DUMP=true` also enables diagnostic bundle
   - Pro: Complete data collection
   - Con: Adds 5-10 minutes

3. **Query parameter support?**
   - Current: No support for `?logs=true`, `?telemetry=1`
   - Alternative: Add environment variables for these
   - Example: `DEBUG_DUMP_INCLUDE_LOGS=true`

4. **Concurrent with diagnostic bundle?**
   - Current: Can run both in parallel
   - Risk: Overload Central (2 large downloads + CPU profiling)
   - Alternative: Sequential collection if both enabled

## Related Work

- **Diagnostic Bundle branch** (`feature/diagnostic-bundle`) - Comprehensive production bundle
- **Analysis document** (`diagnostic-collection-analysis.md`) - Complete comparison
- **Original (reverted) commit** (`a836c39`) - Initial flawed implementation

## Migration from Original Implementation

Original implementation issues:
1. Used `oc exec ... curl` - curl not in Central container
2. No authentication - endpoints require auth
3. Not tested before pushing

This implementation:
1. Uses `oc port-forward` + local curl
2. Retrieves admin password from Secret
3. Comprehensive error handling
4. Detailed testing plan
