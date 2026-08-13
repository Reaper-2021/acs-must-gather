# Diagnostic Collection Analysis: StackRox vs ACS Must-Gather

## Overview

This document compares three diagnostic collection methods:
1. **Diagnostic Bundle** (`/api/extensions/diagnostics`) - Production support bundle
2. **Debug Dump** (`/debug/dump`) - Performance debugging bundle
3. **ACS Must-Gather** (current implementation) - OpenShift must-gather

---

## Collection Methods Comparison

### 1. Diagnostic Bundle (`/api/extensions/diagnostics`)

**Purpose**: Production troubleshooting and customer support cases  
**Default Timeout**: 5 minutes (hard limit: 1 hour)  
**Authentication**: Requires `View(resources.Administration)` permission  
**CLI Command**: `roxctl central debug download-diagnostics`

#### Data Collected

**Central Metrics & Profiling:**
- ✅ Prometheus metrics (snapshot before data collection)
- ✅ Version information (Central, Sensor, Database versions)
- ✅ PostgreSQL database diagnostics:
  - `pg_stat_statements` (top 1000 queries)
  - `pg_stat_user_tables` (analyze stats)
  - `pg_stat_user_tables` (dead tuple stats)
  - `pg_stat_activity` (active sessions)
  - `pg_stat_user_indexes` (index health)
  - Database extensions and versions
  - Connection string (sanitized)
- ❌ No CPU profiling (disabled by default)
- ❌ No heap/goroutine/mutex profiles

**Kubernetes Resources (from ALL clusters):**
- ✅ Deployments (apps/v1)
- ✅ DaemonSets (apps/v1)
- ✅ ReplicaSets (apps/v1)
- ✅ ConfigMaps (v1)
- ✅ Services (v1)
- ✅ Central CRs (platform.stackrox.io/v1alpha1)
- ✅ SecuredCluster CRs (platform.stackrox.io/v1alpha1)
- ✅ Pod logs (20-minute window by default, configurable via `since` param)

**Sensor Data (from connected secured clusters):**
- ✅ Kubernetes resources from Sensor clusters (pulled via gRPC)
- ✅ Prometheus metrics from Sensors
- ✅ Pod logs from secured clusters

**Telemetry Data:**
- ✅ Central telemetry (enabled by default)
- ✅ Sensor telemetry (enabled by default)

**Access Control & Configuration:**
- ✅ Auth providers (sanitized, no passwords/tokens)
- ✅ Auth provider groups
- ✅ Access control roles (resolved with permission sets)
- ✅ Notifier configurations (scrubbed of credentials)
- ✅ System configuration
- ✅ Delegated scanning configuration
- ✅ LogImbue audit logs (JSON array format)

**Optional Parameters:**
- `cluster=<name>` - Filter specific clusters
- `since=<ISO8601>` - Custom log collection window (default: 20 minutes)
- `compliance-operator=true` - Include Compliance Operator resources
- `database-only=true` - Collect ONLY database diagnostics

**Environment Variables:**
- `ROX_ENABLE_CENTRAL_DIAGNOSTICS` - Controls Central data inclusion (default: true)
- `ROX_DIAGNOSTIC_DATA_COLLECTION_TIMEOUT` - Sensor-side timeout (default: 2m)

---

### 2. Debug Dump (`/debug/dump`)

**Purpose**: Performance debugging, memory leaks, CPU hotspots  
**Default Timeout**: 5 minutes (hard limit: 1 hour)  
**Authentication**: Requires `View(resources.Administration)` permission  
**CLI Command**: `roxctl central debug dump`

#### Data Collected

**Central Metrics & Profiling:**
- ✅ Prometheus metrics (before CPU profiling)
- ✅ Prometheus metrics (after CPU profiling)
- ✅ Version information
- ✅ PostgreSQL database diagnostics (same as Diagnostic Bundle)
- ✅ **CPU profile** (30 seconds, pprof format)
- ✅ **Heap profile** (memory profiling, pb.gz)
- ✅ **Goroutine dump** (all active goroutines, text)
- ✅ **Mutex profile** (lock contention data, pb.gz)

**Logs:**
- ✅ Local Central logs (optional, via `?logs=true`)
- ❌ No Kubernetes pod logs from other components
- ❌ No Sensor logs

**Access Control & Configuration:**
- ✅ Auth providers
- ✅ Auth provider groups
- ✅ Access control roles
- ✅ Notifier configurations
- ✅ System configuration
- ✅ Delegated scanning configuration
- ✅ LogImbue audit logs

**What's Missing (vs Diagnostic Bundle):**
- ❌ No Kubernetes resources collection
- ❌ No Sensor metrics
- ❌ No telemetry data (disabled by default)
- ❌ No cluster filtering
- ❌ No pod logs from any components

**Optional Parameters:**
- `logs=true` - Include Central logs
- `telemetry=0|1|2` - Control telemetry (0=none, 1=central, 2=central+sensors)

---

### 3. ACS Must-Gather (Current Implementation)

**Purpose**: OpenShift must-gather for RHACS diagnostics  
**Authentication**: Requires cluster-admin access (via must-gather SA)  
**CLI Command**: `oc adm must-gather --image=quay.io/rhn_support_shaising/acs-must-gather:latest`

#### Data Collected

**Operator Resources:**
- ✅ Operator namespace (full inspection: pods, logs, events, deployments, configmaps, services)
- ✅ RHACS operator deployment
- ✅ OLM resources (ClusterServiceVersion, Subscription, InstallPlan)

**Central Services (per namespace):**
- ✅ Namespace inspection (full)
- ✅ Central deployment
- ✅ Central DB (StatefulSet or Deployment)
- ✅ Scanner V4 Indexer deployment
- ✅ Scanner V4 Matcher deployment
- ✅ Scanner V4 DB (StatefulSet or Deployment)
- ✅ Legacy Scanner deployment (if exists)
- ✅ Legacy Scanner DB deployment (if exists)
- ✅ NetworkPolicies
- ✅ PersistentVolumeClaims
- ✅ Routes (OpenShift only)
- ✅ HorizontalPodAutoscalers

**Secured Cluster Services (per namespace):**
- ✅ Namespace inspection (full)
- ✅ Sensor deployment
- ✅ Collector DaemonSet
- ✅ Admission Controller deployment
- ✅ NetworkPolicies

**Cluster-Scoped Resources:**
- ✅ ACS CRDs (all CRDs from *.stackrox.io)
- ✅ Central CR instances (all namespaces)
- ✅ SecuredCluster CR instances (all namespaces)
- ✅ ValidatingWebhookConfigurations (filtered by stackrox/rhacs/admission-control)
- ✅ MutatingWebhookConfigurations (filtered by stackrox/rhacs)
- ✅ ClusterRoles (filtered by stackrox)
- ✅ ClusterRoleBindings (filtered by stackrox)
- ✅ SecurityContextConstraints (OpenShift only, filtered by stackrox)
- ✅ Node summary (`oc get nodes -o wide`)

**Central Diagnostics (via `/debug/*` endpoints):**
- ✅ Central metadata (`/v1/metadata`)
- ✅ Connected clusters list (`/v1/clusters`)
- ✅ Upgrade/rollback status (`/v1/centralhealth/upgradestatus`)
- ✅ Database status (`/v1/database/status`)
- ✅ Goroutine dump (`/debug/goroutine?debug=2`)
- ✅ Heap profile (`/debug/heap`)

**Environment Variables:**
- `MUST_GATHER_SINCE` - Log duration filter (e.g., `8h`, `30m`)
- `MUST_GATHER_SINCE_TIME` - ISO 8601 timestamp for log start
- `GATHER_DIAGNOSTICS` - Enable Central diagnostics (default: true)
- `INSPECT_TIMEOUT` - Timeout per `oc adm inspect` (default: 120s)
- `DIAG_TIMEOUT` - Timeout per diagnostic endpoint (default: 30s)

---

## Gap Analysis

### What Diagnostic Bundle Has That We Don't

| Feature | Diagnostic Bundle | Must-Gather | Gap Impact |
|---------|------------------|-------------|------------|
| **PostgreSQL Deep Diagnostics** | ✅ Full (pg_stat_statements, analyze stats, tuple stats, activity, index health) | ❌ Only `/v1/database/status` | **CRITICAL** - Missing query performance data, index issues, slow queries |
| **Telemetry Data** | ✅ Central + Sensors | ❌ None | **HIGH** - Missing deployment stats, feature usage, error rates |
| **Auth Providers (detailed)** | ✅ Full provider configs (scrubbed) | ❌ None | **MEDIUM** - Missing SSO/LDAP troubleshooting data |
| **Auth Groups** | ✅ All groups | ❌ None | **MEDIUM** - Missing RBAC mapping data |
| **Roles (resolved)** | ✅ Roles with resolved permission sets | ❌ None | **MEDIUM** - Missing detailed RBAC troubleshooting |
| **Notifier Configs** | ✅ All notifiers (scrubbed) | ❌ None | **LOW** - Missing integration troubleshooting |
| **System Config** | ✅ Full system configuration | ❌ None | **MEDIUM** - Missing runtime config details |
| **Delegated Scanning Config** | ✅ Delegated registry configs | ❌ None | **LOW** - Missing scanner delegation setup |
| **LogImbue Audit Logs** | ✅ Full audit trail | ❌ None | **MEDIUM** - Missing security audit data |
| **Sensor Kubernetes Resources** | ✅ From all connected clusters | ❌ Only from local cluster | **HIGH** - Missing multi-cluster visibility |
| **Sensor Metrics** | ✅ Prometheus metrics from sensors | ❌ None | **HIGH** - Missing secured cluster performance data |
| **ReplicaSets** | ✅ Collected | ❌ Not collected | **LOW** - Missing rollout history |
| **Prometheus Metrics** | ✅ Full scrape | ❌ Only heap profile | **MEDIUM** - Missing runtime metrics |

### What Debug Dump Has That We Don't

| Feature | Debug Dump | Must-Gather | Gap Impact |
|---------|-----------|-------------|------------|
| **CPU Profile** | ✅ 30-second pprof | ❌ None | **CRITICAL** - Cannot debug CPU hotspots |
| **Mutex Profile** | ✅ Lock contention data | ❌ None | **MEDIUM** - Cannot debug deadlocks/contention |
| **Prometheus Metrics (2 snapshots)** | ✅ Before/after CPU profiling | ❌ Only heap | **MEDIUM** - Missing CPU profiling context |

### What We Have That They Don't

| Feature | Must-Gather | Diagnostic Bundle | Debug Dump | Unique Value |
|---------|-------------|------------------|------------|--------------|
| **Operator Resources** | ✅ Full operator namespace | ❌ None | ❌ None | **HIGH** - Operator lifecycle issues |
| **OLM Resources** | ✅ CSV, Subscription, InstallPlan | ❌ None | ❌ None | **HIGH** - OLM troubleshooting |
| **Routes** | ✅ OpenShift routes | ❌ None | ❌ None | **MEDIUM** - Route config issues |
| **HPAs** | ✅ HorizontalPodAutoscalers | ❌ None | ❌ None | **LOW** - Autoscaling config |
| **SecurityContextConstraints** | ✅ OpenShift SCCs | ❌ None | ❌ None | **MEDIUM** - Permission troubleshooting |
| **ClusterRoles/ClusterRoleBindings** | ✅ RBAC resources | ❌ None | ❌ None | **MEDIUM** - RBAC troubleshooting |
| **ValidatingWebhookConfigurations** | ✅ Webhook configs | ❌ None | ❌ None | **MEDIUM** - Admission control issues |
| **MutatingWebhookConfigurations** | ✅ Webhook configs | ❌ None | ❌ None | **LOW** - Mutation debugging |
| **Node Summary** | ✅ Node list | ❌ None | ❌ None | **LOW** - Cluster topology |
| **Namespace Full Inspection** | ✅ Events, all resources | ⚠️ Partial | ❌ None | **HIGH** - Complete namespace state |

---

## Key Differences in Collection Method

### Diagnostic Bundle Approach
- **Pull-based from Central**: Central reaches out to Sensors via gRPC
- **Multi-cluster aware**: Collects from all connected clusters
- **Requires Central running**: Central must be operational
- **Requires authentication**: Needs valid Central user with Admin View permission
- **Telemetry-driven**: Uses existing telemetry infrastructure
- **Network-dependent**: Requires Central ↔ Sensor connectivity

### Must-Gather Approach
- **Push-based via Kubernetes API**: Direct `oc` commands
- **Single-cluster focused**: Only collects from the cluster it runs on
- **Works with Central down**: Can collect even if Central is crashed
- **Requires cluster-admin**: Uses must-gather ServiceAccount
- **Kubernetes-native**: Uses `oc adm inspect` and direct API calls
- **Network-independent**: Local cluster API only

---

## Recommendations

### CRITICAL Additions Needed

1. **Add Diagnostic Bundle Endpoint** (`/api/extensions/diagnostics`)
   - Collect via `curl` to Central pod (similar to current diagnostic endpoints)
   - Provides: PostgreSQL deep diagnostics, telemetry, auth providers, roles, notifiers, system config, audit logs
   - **Impact**: Closes the biggest gaps in database troubleshooting and configuration visibility

2. **Add Debug Dump Endpoint** (`/debug/dump`)
   - Collect for performance-related cases
   - Provides: CPU profile, mutex profile, dual Prometheus snapshots
   - **Impact**: Enables performance debugging capabilities

3. **Add Prometheus Metrics Collection**
   - Scrape `/metrics` from Central pod
   - Provides: Runtime metrics, resource usage, request rates
   - **Impact**: Better visibility into Central health

### MEDIUM Priority Additions

4. **Add Sensor Metrics Collection**
   - If multi-cluster visibility is needed, would require Central to be running
   - Alternative: Document that this is available via Diagnostic Bundle
   - **Impact**: Secured cluster performance visibility

5. **Add ReplicaSets to K8s Collection**
   - Add to `gather_central` and `gather_secured_cluster`
   - Provides: Rollout history, previous versions
   - **Impact**: Better deployment troubleshooting

### LOW Priority / Consider

6. **Database-only Mode**
   - Add `--database-only` flag to skip K8s collection
   - Mirrors Diagnostic Bundle's `database-only=true` parameter
   - **Impact**: Faster collection for DB-specific issues

7. **Cluster Filtering**
   - If implementing multi-cluster via Diagnostic Bundle
   - **Impact**: Reduce bundle size for specific clusters

---

## Implementation Strategy

### Phase 1: Core Diagnostic Endpoints (Week 1)
- [ ] Add `/api/extensions/diagnostics` collection to `gather_diagnostics`
- [ ] Add `/debug/dump` collection (separate file or optional)
- [ ] Add `/metrics` (Prometheus) collection from Central pod
- [ ] Update README with new data collected
- [ ] Test with Central running and crashed scenarios

### Phase 2: Additional Metrics (Week 2)
- [ ] Add ReplicaSets to K8s resource collection
- [ ] Add optional database-only mode
- [ ] Document differences between must-gather and native StackRox bundles

### Phase 3: Documentation (Week 3)
- [ ] Update CLAUDE.md or create DIAGNOSTICS.md
- [ ] Document when to use must-gather vs `roxctl central debug download-diagnostics`
- [ ] Document collection methods and authentication requirements

---

## Use Case Guidance

**When to use ACS Must-Gather:**
- ✅ Central is down/crashed/won't start
- ✅ Operator lifecycle issues (installation, upgrade failures)
- ✅ Need cluster-wide RBAC/webhook troubleshooting
- ✅ OpenShift-specific issues (Routes, SCCs, OLM)
- ✅ Don't have Central credentials
- ✅ Need comprehensive Kubernetes state snapshot

**When to use Diagnostic Bundle (`roxctl central debug download-diagnostics`):**
- ✅ Central is running
- ✅ Need multi-cluster visibility
- ✅ Need database performance analysis (slow queries, index issues)
- ✅ Need telemetry and usage data
- ✅ Need auth provider/RBAC configuration details
- ✅ Need audit logs (LogImbue)
- ✅ Need Sensor metrics and logs

**When to use Debug Dump (`roxctl central debug dump`):**
- ✅ Central performance issues (high CPU, memory leaks)
- ✅ Need CPU profiling data
- ✅ Need goroutine/mutex profiling
- ✅ Investigating lock contention or deadlocks

**Ideal Support Bundle:**
- Use **both** ACS Must-Gather AND Diagnostic Bundle
- Must-gather provides Kubernetes/operator view
- Diagnostic Bundle provides Central internals + multi-cluster data
- Together they provide complete visibility
