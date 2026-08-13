# ACS Must-Gather Bundle Contents Reference

This document provides a complete breakdown of all data collected by the ACS must-gather for support and troubleshooting teams.

## Table of Contents
- [Collection Structure](#collection-structure)
- [Operator Resources](#operator-resources)
- [Central Services](#central-services)
- [Secured Cluster Services](#secured-cluster-services)
- [Cluster-Scoped Resources](#cluster-scoped-resources)
- [Diagnostic Bundles](#diagnostic-bundles)
- [Troubleshooting Collection Issues](#troubleshooting-collection-issues)

---

## Collection Structure

The must-gather creates the following directory structure:

```
/must-gather/
├── version                          # Collection metadata and oc version
├── timestamp                        # Collection start/end timestamps
├── gather.log                       # Collection process log
├── cluster-scoped-resources/        # CRDs, CRs, webhooks, RBAC, SCCs, nodes
├── namespaces/                      # Per-namespace resources
│   ├── <operator-namespace>/        # Operator deployment and OLM resources
│   ├── <central-namespace>/         # Central, Scanner, DB resources
│   └── <secured-cluster-namespace>/ # Sensor, Collector, Admission Controller
└── acs-diagnostics/                 # Central API diagnostics and bundles
    ├── central-metadata.json
    ├── central-clusters.json
    ├── central-upgrade-status.json
    ├── central-db-status.json
    ├── central-goroutine-dump.txt
    ├── central-heap-profile.pb.gz
    ├── central-prometheus-metrics.txt
    ├── stackrox-diagnostic-bundle.zip    # Comprehensive production bundle
    └── stackrox-debug-dump.zip           # Performance debugging bundle
```

---

## Operator Resources

**Directory**: `/must-gather/namespaces/<operator-namespace>/`

**Collected From**: Operator namespace (e.g., `rhacs-operator`, `openshift-operators`)

### OLM Resources
- **ClusterServiceVersion** (`clusterserviceversions.operators.coreos.com`)
  - Operator version, deployment spec, install strategy
  - CRD ownership and API definitions
  - Useful for: Operator version verification, installation issues

- **Subscription** (`subscriptions.operators.coreos.com`)
  - Channel, catalog source, update strategy
  - Useful for: Upgrade path verification, catalog connectivity issues

- **InstallPlan** (`installplans.operators.coreos.com`)
  - Resolved operator versions and dependencies
  - Installation status and conditions
  - Useful for: Installation failures, dependency conflicts

### Operator Deployment
- **Deployment**: `rhacs-operator-controller-manager`
  - Pod spec, replicas, resource requests/limits
  - Environment variables, volumes, security context
  - Useful for: Operator pod failures, resource constraints

### Namespace Resources
- Pods, logs, events
- ConfigMaps, Secrets (sanitized)
- Services, NetworkPolicies
- ReplicaSets (operator rollout history)

**Collection Time**: ~10-30 seconds

---

## Central Services

**Directory**: `/must-gather/namespaces/<central-namespace>/`

**Collected From**: Namespace containing Central deployment (discovered via Central CR)

### Core Components

#### Central
- **Deployment**: `central`
  - Pod spec, image versions, replicas
  - Resource requests/limits, environment variables
  - Security context, volumes, init containers
  - Useful for: Central startup failures, version identification, resource issues

- **Logs**: Central pod logs (default: all logs, configurable via `MUST_GATHER_SINCE`)
  - Application logs, error traces, API request logs
  - Useful for: Application errors, API failures, policy evaluation issues

#### Central Database
- **StatefulSet or Deployment**: `central-db`
  - PostgreSQL version, replicas, volumes
  - Resource configuration, persistence settings
  - Useful for: Database startup failures, storage issues, connection problems

- **PersistentVolumeClaims**: Central DB storage
  - Storage class, capacity, access modes
  - Useful for: Storage provisioning issues, capacity problems

#### Scanner V4
- **Deployment**: `scanner-v4-indexer`
  - Indexer configuration, replicas, resources
  - Useful for: Image indexing failures, performance issues

- **Deployment**: `scanner-v4-matcher`
  - Matcher configuration, replicas, resources
  - Useful for: Vulnerability matching failures, CVE database issues

- **StatefulSet or Deployment**: `scanner-v4-db`
  - PostgreSQL configuration, persistence
  - Useful for: Scanner database issues, storage problems

#### Legacy Scanner (if present)
- **Deployment**: `scanner`
  - Legacy scanner configuration (Scanner V2)
  - Useful for: Migration troubleshooting, legacy scanning issues

- **Deployment**: `scanner-db`
  - Legacy scanner database
  - Useful for: Legacy scanner data migration

### Supporting Resources
- **ConfigMaps**: All ConfigMaps in namespace
  - Central configuration, feature flags
  - Useful for: Configuration validation, feature flag verification

- **Services**: All Services in namespace
  - Central, Central DB, Scanner services
  - Useful for: Service discovery issues, port configuration

- **Routes** (OpenShift only): All Routes in namespace
  - Central UI/API route configuration
  - Useful for: External access issues, TLS configuration

- **NetworkPolicies**: Network isolation policies
  - Useful for: Connectivity issues, network segmentation

- **HorizontalPodAutoscalers**: Autoscaling configuration
  - Useful for: Scaling behavior, resource management

**Collection Time**: ~30-60 seconds per namespace

---

## Secured Cluster Services

**Directory**: `/must-gather/namespaces/<secured-cluster-namespace>/`

**Collected From**: Namespace containing Sensor deployment (discovered via SecuredCluster CR)

### Core Components

#### Sensor
- **Deployment**: `sensor`
  - Sensor version, configuration, replicas
  - Central connection settings, TLS configuration
  - Useful for: Sensor-Central connectivity, certificate issues, version compatibility

- **Logs**: Sensor pod logs
  - Central connection logs, admission control events
  - Useful for: Connection failures, admission control issues

#### Collector
- **DaemonSet**: `collector`
  - Collector agent running on all nodes
  - Kernel module configuration, eBPF settings
  - Useful for: Runtime activity collection, node-level issues

- **Logs**: Collector pod logs (from all nodes)
  - Runtime event collection, kernel module loading
  - Useful for: Collection failures, kernel compatibility issues

#### Admission Controller
- **Deployment**: `admission-control`
  - Admission webhook configuration
  - Policy enforcement settings
  - Useful for: Admission failures, policy enforcement issues

- **Logs**: Admission Controller pod logs
  - Admission decisions, webhook requests
  - Useful for: Policy violations, webhook failures

### Supporting Resources
- **NetworkPolicies**: Sensor network isolation
  - Useful for: Sensor-Central connectivity, egress issues

- **Namespace**: Events, resource quotas, limits
  - Useful for: Resource constraints, pod failures

**Collection Time**: ~30-60 seconds per namespace

---

## Cluster-Scoped Resources

**Directory**: `/must-gather/cluster-scoped-resources/`

**Collected From**: Cluster-wide resources (no namespace)

### Custom Resources

#### CRDs (CustomResourceDefinitions)
- `centrals.platform.stackrox.io`
- `securedclusters.platform.stackrox.io`
- `securitypolicies.config.stackrox.io`
- Any other CRDs from `*.stackrox.io` domain

**Useful for**: CRD version verification, API changes, upgrade compatibility

#### CR Instances
- **Central CRs**: All Central instances across all namespaces
  - Central configuration spec (version, persistence, scanner settings)
  - Status conditions, observed generation
  - Useful for: Operator reconciliation issues, desired vs actual state

- **SecuredCluster CRs**: All SecuredCluster instances across all namespaces
  - Secured cluster configuration spec (sensor, admission control, collector settings)
  - Status conditions, cluster ID
  - Useful for: Sensor registration issues, cluster configuration

### Admission Control

#### ValidatingWebhookConfigurations
- StackRox/RHACS admission webhooks
- Webhook rules, namespaceSelectors, failure policy
- **Useful for**: Admission control failures, webhook configuration issues, policy enforcement

#### MutatingWebhookConfigurations
- StackRox/RHACS mutation webhooks (if any)
- **Useful for**: Mutation failures, injector issues

### RBAC Resources

#### ClusterRoles
- All ClusterRoles with "stackrox" in the name
- Permissions granted at cluster scope
- **Useful for**: Permission issues, access denied errors

#### ClusterRoleBindings
- All ClusterRoleBindings with "stackrox" in the name
- Service account to ClusterRole bindings
- **Useful for**: RBAC troubleshooting, permission verification

### OpenShift-Specific

#### SecurityContextConstraints (SCCs)
- All SCCs with "stackrox" in the name
- Security policies for pods (capabilities, volumes, host access)
- **Useful for**: Pod startup failures due to SCC restrictions

### Node Information
- **File**: `cluster-scoped-resources/core/nodes-summary.txt`
- Node names, status, roles, version, OS
- **Useful for**: Cluster topology, node availability, version verification

**Collection Time**: ~20-40 seconds

---

## Diagnostic Bundles

**Directory**: `/must-gather/acs-diagnostics/`

**Collected From**: Central pod via `oc exec ... curl https://localhost:8443/...`

### Lightweight Endpoints (Always Collected)

#### 1. Central Metadata
- **File**: `central-metadata.json`
- **Endpoint**: `https://localhost:8443/v1/metadata`
- **Contents**:
  - Central version, build info, release build flag
  - License status and expiration
  - **Useful for**: Version verification, license issues

#### 2. Cluster List
- **File**: `central-clusters.json`
- **Endpoint**: `https://localhost:8443/v1/clusters`
- **Contents**:
  - All connected secured clusters
  - Cluster IDs, names, types (Kubernetes/OpenShift)
  - Sensor health status, last contact time
  - **Useful for**: Multi-cluster connectivity, sensor registration

#### 3. Upgrade Status
- **File**: `central-upgrade-status.json`
- **Endpoint**: `https://localhost:8443/v1/centralhealth/upgradestatus`
- **Contents**:
  - Current upgrade/rollback state
  - Upgrade progress, errors
  - **Useful for**: Upgrade failures, rollback issues

#### 4. Database Status
- **File**: `central-db-status.json`
- **Endpoint**: `https://localhost:8443/v1/database/status`
- **Contents**:
  - Database connectivity status
  - Basic health check
  - **Useful for**: Database connectivity issues

#### 5. Goroutine Dump
- **File**: `central-goroutine-dump.txt`
- **Endpoint**: `https://localhost:8443/debug/goroutine?debug=2`
- **Contents**:
  - All active goroutines with full stack traces
  - Goroutine IDs, states, wait reasons
  - **Useful for**: Deadlocks, goroutine leaks, stuck processes

#### 6. Heap Profile
- **File**: `central-heap-profile.pb.gz`
- **Endpoint**: `https://localhost:8443/debug/heap`
- **Contents**:
  - Memory heap snapshot (pprof format)
  - Allocation sites, heap usage
  - **Useful for**: Memory leaks, high memory usage

#### 7. Prometheus Metrics
- **File**: `central-prometheus-metrics.txt`
- **Endpoint**: `https://localhost:8443/metrics`
- **Contents**:
  - All Prometheus metrics from Central
  - Request rates, error rates, latencies
  - Go runtime metrics (goroutines, GC, memory)
  - gRPC connection metrics
  - PostgreSQL connection pool metrics
  - **Useful for**: Performance analysis, resource usage trends

**Collection Time**: ~5-10 seconds total (parallel collection)

---

### Diagnostic Bundle (Production Troubleshooting)

- **File**: `stackrox-diagnostic-bundle.zip`
- **Endpoint**: `https://localhost:8443/api/extensions/diagnostics`
- **Timeout**: 10 minutes (may take 5-10 minutes to collect)
- **Size**: Varies (typically 10-100 MB depending on cluster size)
- **Requires**: Central running and healthy

#### Contents Inside ZIP:

##### 1. Version Information
- **File**: `versions.json`
- Central, Sensor, Scanner, Database versions
- Build info, Git commit SHAs

##### 2. PostgreSQL Deep Diagnostics

**File**: `central-db.json`
- Database name, client version, server version
- Installed PostgreSQL extensions
- Connection string (sanitized)

**File**: `central-db-pg-stats.json`
- Top 1000 queries from `pg_stat_statements`
- Query text, call counts, execution times
- Rows processed, buffer hits/misses
- **CRITICAL for**: Slow query analysis, query optimization, database performance issues

**File**: `central-db-pg-analyze-stats.json`
- Table analyze statistics from `pg_stat_user_tables`
- Last analyze times, automatic vs manual analyze counts
- **Useful for**: Query planner issues, stale statistics

**File**: `central-db-pg-tuples.json`
- Dead tuple statistics from `pg_stat_user_tables`
- Live tuples, dead tuples, last vacuum/autovacuum times
- **Useful for**: Database bloat, vacuum issues, performance degradation

**File**: `central-db-pg-activity.json`
- Active sessions from `pg_stat_activity`
- Currently executing queries, connection states
- Wait events, backend types
- **Useful for**: Connection pool issues, stuck queries, connection limits

**File**: `central-db-pg-index-stats.json`
- Index usage statistics from `pg_stat_user_indexes`
- Index scans, tuples read/fetched
- **Useful for**: Unused indexes, missing indexes, index performance

##### 3. Prometheus Metrics
- **File**: `metrics-1` (snapshot before data collection)
- Same as standalone Prometheus metrics collection

##### 4. Telemetry Data

**File**: `telemetry-data.json`
- **Central Telemetry**:
  - Deployment environment (cloud provider, Kubernetes/OpenShift version)
  - Cluster count, node count, namespace count
  - Policy count, deployment count, image count
  - Feature usage stats (network policies, admission control, vulnerability scanning)
  - Integration counts (notifiers, registries, signature verifications)
  - Error rates, API request rates
- **Sensor Telemetry** (from all connected clusters):
  - Secured cluster sizes, runtime activity volume
  - Collector deployment statistics
  - Admission control enforcement statistics
- **Useful for**: Deployment health assessment, feature usage analysis, capacity planning

##### 5. Access Control & Configuration

**File**: `auth-providers.json`
- Auth provider configurations (LDAP, SAML, OIDC, basic auth)
- Connection settings, attribute mappings
- **Credentials scrubbed** (no passwords/tokens)
- **Useful for**: SSO issues, authentication failures, LDAP troubleshooting

**File**: `auth-provider-groups.json`
- All auth provider groups
- Role mappings, attribute selectors
- **Useful for**: RBAC issues, group mapping problems

**File**: `access-control-roles.json`
- All roles with resolved permission sets
- Permissions by resource (read/write access)
- Access scopes (clusters, namespaces)
- **Useful for**: Permission denied errors, RBAC troubleshooting

**File**: `notifiers.json`
- All notifier configurations (email, Slack, PagerDuty, webhooks, etc.)
- **Credentials scrubbed** (no API keys/tokens)
- **Useful for**: Integration failures, notification issues

**File**: `system-configuration.json`
- System-wide configuration settings
- Feature flags, retention settings, data retention policies
- **Useful for**: Configuration validation, behavior verification

**File**: `delegated-scanning-config.json`
- Delegated scanning registry configurations
- Scanner instances, registry integrations
- **Useful for**: Scanner delegation issues, registry connectivity

**File**: `logimbue-data.json`
- Audit logs (JSON array)
- User actions, API calls, admin operations
- Timestamps, user identities, actions performed
- **Useful for**: Security audits, compliance, troubleshooting user actions

##### 6. Kubernetes Resources (Multi-Cluster)

**Directory prefix**: `kubernetes/`

Contains resources from **all connected secured clusters** (not just the local cluster):

- **Central Cluster** (`_central-cluster/`)
  - Deployments, DaemonSets, ReplicaSets
  - ConfigMaps, Services
  - Central CR, SecuredCluster CRs
  - Pod logs (20-minute window by default, configurable via `?since=`)

- **Secured Clusters** (`<cluster-name>/`)
  - Same resource types as Central cluster
  - Collected from each connected Sensor via gRPC
  - **Unique value**: Multi-cluster visibility without accessing remote clusters

- **Missing Clusters** (`missing-clusters.txt`)
  - Lists clusters without active Sensor connections
  - Explains why data is unavailable

**Optional**: Compliance Operator resources (if `?compliance-operator=true` is used)

##### 7. Sensor Metrics

**Directory prefix**: `sensor-metrics/`

- Prometheus metrics from all connected Sensors
- Per-cluster metrics files
- **Useful for**: Secured cluster performance, Sensor health

#### Query Parameters

The diagnostic bundle endpoint supports these optional parameters:

- `?cluster=<name>` - Filter to specific cluster(s), can be repeated
- `?since=<ISO8601>` - Custom log collection window (default: 20 minutes)
  - Example: `?since=2026-08-13T10:00:00Z`
- `?compliance-operator=true` - Include Compliance Operator resources
- `?database-only=true` - Collect ONLY database diagnostics (skips K8s resources, telemetry)

#### When Collection Fails

**File**: `stackrox-diagnostic-bundle.zip.error`
- Created if collection times out (>10 minutes) or fails
- Contains error message
- Common reasons:
  - Central not running or unhealthy
  - Large multi-cluster deployment (increase timeout)
  - Network issues with Sensors
  - Database connectivity problems

**Collection Time**: 2-10 minutes (depends on cluster size, number of connected clusters)

---

### Debug Dump (Performance Debugging)

- **File**: `stackrox-debug-dump.zip`
- **Endpoint**: `https://localhost:8443/debug/dump`
- **Timeout**: 3 minutes
- **Size**: Typically 5-50 MB
- **Requires**: Central running and healthy

#### Contents Inside ZIP:

##### 1. Version Information
- **File**: `versions.json`
- Same as Diagnostic Bundle

##### 2. CPU Profiling
- **File**: `cpu.pb.gz`
- 30-second CPU profile (pprof format)
- Function call stacks, CPU time per function
- **CRITICAL for**: High CPU usage, performance hotspots, slow API calls
- **Analysis**: Use `go tool pprof cpu.pb.gz`

##### 3. Memory Profiling
- **File**: `heap.pb.gz`
- Heap memory snapshot (pprof format)
- Allocation sites, memory usage
- **CRITICAL for**: Memory leaks, high memory usage
- **Analysis**: Use `go tool pprof heap.pb.gz`

##### 4. Goroutine Profiling
- **File**: `goroutine.txt`
- All active goroutines with full stack traces
- Same as standalone goroutine dump
- **Useful for**: Goroutine leaks, deadlocks

##### 5. Mutex Profiling
- **File**: `mutex.pb.gz`
- Lock contention profile (pprof format)
- Blocked time per mutex, contention points
- **CRITICAL for**: Deadlocks, lock contention, concurrency issues
- **Analysis**: Use `go tool pprof mutex.pb.gz`

##### 6. Prometheus Metrics (Dual Snapshots)
- **File**: `metrics-1` - Before CPU profiling
- **File**: `metrics-2` - After CPU profiling (30s later)
- **Useful for**: Correlating CPU profile with metrics changes

##### 7. PostgreSQL Diagnostics
- **Files**: Same as Diagnostic Bundle
  - `central-db.json`
  - `central-db-pg-stats.json`
  - `central-db-pg-analyze-stats.json`
  - `central-db-pg-tuples.json`
  - `central-db-pg-activity.json`
  - `central-db-pg-index-stats.json`

##### 8. Configuration Data
- **Files**: Same as Diagnostic Bundle
  - `auth-providers.json`
  - `auth-provider-groups.json`
  - `access-control-roles.json`
  - `notifiers.json`
  - `system-configuration.json`
  - `delegated-scanning-config.json`
  - `logimbue-data.json`

#### What's NOT Included (vs Diagnostic Bundle)
- ❌ Kubernetes resources from clusters
- ❌ Telemetry data (unless `?telemetry=1` or `?telemetry=2` is used)
- ❌ Sensor metrics
- ❌ Pod logs (unless `?logs=true` is used - only local Central logs)

#### Query Parameters
- `?logs=true` - Include local Central logs
- `?telemetry=0` - No telemetry (default)
- `?telemetry=1` - Central telemetry only
- `?telemetry=2` - Central + Sensor telemetry

#### When Collection Fails
**File**: `stackrox-debug-dump.zip.error`
- Created if collection times out (>3 minutes) or fails
- Contains error message
- Common reasons:
  - Central not running
  - CPU profiling cannot start (rare)
  - Database connectivity issues

**Collection Time**: ~1-2 minutes (includes 30s CPU profiling)

---

## Troubleshooting Collection Issues

### Central Not Running
**Symptom**: Files in `acs-diagnostics/` have `.error` suffix
**Impact**: Diagnostic bundles not collected, but all Kubernetes resources are still collected
**Resolution**: 
- Check if Central pod is running: `oc get pods -n <namespace> -l app=central`
- Review Central pod logs in the must-gather bundle
- Kubernetes resources provide most troubleshooting data even without Central diagnostics

### Collection Timeout
**Symptom**: `stackrox-diagnostic-bundle.zip.error` contains "Collection timed out"
**Impact**: Incomplete diagnostic bundle
**Cause**: Large multi-cluster deployment, slow Sensor connections
**Resolution**:
- For support cases, note timeout in case notes
- Collect individual endpoint data from Central: `oc exec -n <namespace> central-xxx -c central -- curl -sSk https://localhost:8443/v1/metadata`
- Use `?cluster=<name>` to filter specific clusters
- Use `?database-only=true` for faster database-only collection

### Permission Denied
**Symptom**: Collection fails with RBAC errors
**Impact**: Incomplete resource collection
**Cause**: Must-gather ServiceAccount lacks required permissions
**Resolution**:
- Ensure must-gather runs with cluster-admin or equivalent permissions
- Check: `oc auth can-i get pods --all-namespaces --as=system:serviceaccount:openshift-must-gather-xxx:must-gather-xxx`

### Large Bundle Size
**Symptom**: Bundle >500 MB
**Cause**: 
- Many connected clusters in Diagnostic Bundle
- Long log retention (`MUST_GATHER_SINCE` not set)
- Large number of pods/containers
**Resolution**:
- Use `MUST_GATHER_SINCE=1h` to limit log window
- Use `?cluster=<problem-cluster>` to filter Diagnostic Bundle
- This is expected for large deployments

### Missing Namespaces
**Symptom**: Expected namespace not in bundle
**Cause**: 
- No Central or SecuredCluster CR in that namespace
- Operator namespace discovery failed
**Resolution**:
- Check `gather.log` for discovery results
- Manually verify CRs exist: `oc get Central,SecuredCluster -A`
- Check operator deployment: `oc get deployment -A | grep rhacs-operator`

---

## Analysis Tools

### Viewing pprof Profiles
```bash
# CPU profile
go tool pprof stackrox-debug-dump/cpu.pb.gz
# Commands: top, list, web

# Heap profile
go tool pprof stackrox-debug-dump/heap.pb.gz

# Mutex profile
go tool pprof stackrox-debug-dump/mutex.pb.gz
```

### Extracting ZIP Bundles
```bash
# Extract diagnostic bundle
unzip acs-diagnostics/stackrox-diagnostic-bundle.zip -d diagnostic-bundle/

# Extract debug dump
unzip acs-diagnostics/stackrox-debug-dump.zip -d debug-dump/
```

### Analyzing PostgreSQL Stats
```bash
# View slow queries
jq '.Results[] | select(.mean_exec_time > 100) | {query: .query, calls: .calls, mean_time: .mean_exec_time}' \
  diagnostic-bundle/central-db-pg-stats.json

# View active sessions
jq '.Results[] | select(.state == "active")' \
  diagnostic-bundle/central-db-pg-activity.json
```

### Checking Telemetry
```bash
# View cluster summary
jq '.clusters | {total: length, names: [.[].name]}' \
  diagnostic-bundle/telemetry-data.json

# View feature usage
jq '.kubernetes' \
  diagnostic-bundle/telemetry-data.json
```

---

## Support Case Best Practices

### Attach All Three Bundles
For comprehensive troubleshooting, provide:
1. **Full must-gather tarball** - Kubernetes state
2. **stackrox-diagnostic-bundle.zip** - Production diagnostics (if collected)
3. **stackrox-debug-dump.zip** - Performance data (if collected)

### Describe the Issue Context
When diagnostic bundle collection fails:
- Note Central pod state at collection time
- Include relevant error messages from `gather.log`
- Specify if Central was down/restarting

### For Performance Issues
- Always try to collect Debug Dump (has CPU profiling)
- Note when the issue started
- Include time range of slow behavior

### For Multi-Cluster Issues
- Specify affected cluster(s)
- Note if issue is in Central cluster or secured cluster
- Check `central-clusters.json` for Sensor connectivity

---

## Version History

- **v1.1.0** (2026-08-13): Added Diagnostic Bundle, Debug Dump, Prometheus metrics
- **v1.0.0** (2026-08-06): Initial release
