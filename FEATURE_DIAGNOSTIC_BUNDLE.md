# Feature: Diagnostic Bundle Collection

This branch adds support for collecting Central's comprehensive diagnostic bundle via the `/api/extensions/diagnostics` endpoint.

## What is the Diagnostic Bundle?

The diagnostic bundle is a production troubleshooting bundle created by Central that includes:

### PostgreSQL Deep Diagnostics
- **`pg_stat_statements`** - Top 1000 slow queries with execution stats
- **Index health** - Index usage statistics, unused indexes
- **Analyze stats** - Table statistics freshness
- **Tuple stats** - Dead tuple counts, vacuum status
- **Active sessions** - Currently executing queries, connection states
- **Connection info** - Database version, extensions, connection string

### Telemetry Data
- **Central telemetry** - Deployment stats, policy/deployment/image counts, feature usage
- **Sensor telemetry** - Metrics from all connected secured clusters
- **Error rates** - API request rates and errors

### Access Control & Configuration
- **Auth providers** - LDAP, SAML, OIDC configurations (credentials scrubbed)
- **Groups** - Auth provider group mappings
- **Roles** - All roles with resolved permission sets and access scopes
- **Notifiers** - Integration configs for email, Slack, PagerDuty, etc. (credentials scrubbed)
- **System config** - Feature flags, retention settings
- **Delegated scanning config** - Scanner delegation settings
- **LogImbue audit logs** - Complete audit trail

### Multi-Cluster Data
- **Kubernetes resources** - From all connected secured clusters (via Sensor)
  - Deployments, DaemonSets, ReplicaSets, ConfigMaps, Services
  - Central and SecuredCluster CRs
  - Pod logs (20-minute window by default)
- **Sensor metrics** - Prometheus metrics from all Sensors

## Why This Feature?

Currently, acs-must-gather collects Kubernetes resources via `oc adm inspect` but misses critical Central internals:

**Gap 1: Database Performance** - Cannot diagnose slow queries, missing indexes, vacuum issues
**Gap 2: Multi-Cluster Visibility** - Cannot see resources from other secured clusters
**Gap 3: Configuration Details** - Missing auth provider, RBAC, notifier troubleshooting data
**Gap 4: Audit Trail** - No access to LogImbue audit logs
**Gap 5: Telemetry** - No deployment health or feature usage statistics

This feature closes these gaps by collecting Central's native diagnostic bundle.

## How It Works

### Authentication
The diagnostic bundle endpoint requires authentication (`View(resources.Administration)` permission).

The script retrieves the admin password from one of these Secrets (in order):
1. `central-htpasswd` (current deployments)
2. `stackrox-admin-password` (older versions)

### Collection Method
1. Find running Central pod
2. Retrieve admin password from Secret
3. Establish port-forward to Central pod (finds available port automatically)
4. Download bundle via authenticated `curl` request
5. Clean up port-forward

### Error Handling
- Gracefully fails if Central is not running
- Provides detailed error messages if password cannot be retrieved
- Includes manual collection instructions in error files
- Timeout handling with helpful guidance for large deployments

## Usage

### Enable Diagnostic Bundle Collection

```bash
oc adm must-gather \
  --image=quay.io/rhn_support_shaising/acs-must-gather:latest \
  -- /usr/bin/gather \
  GATHER_DIAGNOSTIC_BUNDLE=true
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GATHER_DIAGNOSTIC_BUNDLE` | Enable diagnostic bundle collection | `false` (disabled by default) |
| `DIAGNOSTIC_BUNDLE_TIMEOUT` | Collection timeout in seconds | `600` (10 minutes) |

### Example with Custom Timeout

```bash
oc adm must-gather \
  --image=quay.io/rhn_support_shaising/acs-must-gather:latest \
  -- /usr/bin/gather \
  GATHER_DIAGNOSTIC_BUNDLE=true \
  DIAGNOSTIC_BUNDLE_TIMEOUT=1200
```

## Output

### Success
```
/must-gather/acs-diagnostics/stackrox-diagnostic-bundle.zip
```

The ZIP file contains all diagnostic data organized in directories matching the StackRox diagnostic bundle structure.

### Failure
```
/must-gather/acs-diagnostics/diagnostic-bundle-error.txt
```

Error file includes:
- Reason for failure
- Troubleshooting steps
- Manual collection instructions
- Alternative collection methods (`roxctl` commands)

## Collection Time

**Expected duration**: 2-10 minutes
- Depends on number of connected clusters
- Depends on database size and query history
- Default timeout: 10 minutes
- For large deployments (>10 clusters), consider increasing timeout

## Security Considerations

### Credentials
- Admin password is retrieved from Kubernetes Secret (requires RBAC)
- Password is used only in-memory, never written to disk
- Port-forward is local to must-gather pod
- Bundle is collected via localhost connection

### Data Sensitivity
Central automatically scrubs sensitive data in the bundle:
- ✅ Auth provider passwords/tokens removed
- ✅ Notifier API keys/tokens removed
- ✅ Database connection passwords sanitized
- ❌ Audit logs may contain sensitive user actions (review before sharing)
- ❌ Query text in `pg_stat_statements` may contain data (review before sharing)

**Recommendation**: Review bundle contents before sharing externally.

## Comparison with roxctl

### acs-must-gather with GATHER_DIAGNOSTIC_BUNDLE=true
**Pros:**
- ✅ Collects both Kubernetes state AND Central diagnostics
- ✅ Works from cluster-admin access (no Central credentials needed externally)
- ✅ Single command for comprehensive collection
- ✅ Works when Central external routes are down

**Cons:**
- ❌ Requires Central to be running
- ❌ Disabled by default (opt-in)
- ❌ Longer collection time

### roxctl central debug download-diagnostics
**Pros:**
- ✅ Direct access to Central API
- ✅ Supports filtering by cluster (`--cluster`)
- ✅ Supports database-only mode (`--database-only`)
- ✅ Native tool maintained by StackRox team

**Cons:**
- ❌ Requires Central credentials
- ❌ Requires network access to Central's external endpoint
- ❌ Doesn't collect Kubernetes resources (separate must-gather needed)

### Recommendation
**For support cases**: Use both
- Run `acs-must-gather` with `GATHER_DIAGNOSTIC_BUNDLE=true` for comprehensive collection
- If must-gather fails, fall back to `roxctl` for just the diagnostic bundle

**For production emergencies**: Use `acs-must-gather` without diagnostic bundle
- Faster collection (Kubernetes resources only)
- Works even if Central is degraded
- Add diagnostic bundle later if needed

## Testing

### Prerequisites
- Running RHACS deployment with Central
- Central admin password stored in Secret
- `curl` available in must-gather container image
- `lsof` available for port detection

### Test Cases

1. **Happy path** - Central running, password available
   - Expected: Bundle collected successfully

2. **Central down** - Central pod not running
   - Expected: Error file created with explanation

3. **No password Secret** - central-htpasswd secret missing
   - Expected: Error file with manual collection instructions

4. **Timeout** - Large deployment, slow collection
   - Expected: Timeout error with guidance to increase timeout

5. **Port conflict** - Port 8443 already in use
   - Expected: Script finds alternative port automatically

### Manual Testing

```bash
# Build test image
cd ~/Projects/acs-must-gather
make build

# Run must-gather with diagnostic bundle
oc adm must-gather \
  --image=localhost/acs-must-gather:latest \
  -- /usr/bin/gather \
  GATHER_DIAGNOSTIC_BUNDLE=true

# Check results
ls -lh must-gather-*/acs-diagnostics/
unzip -l must-gather-*/acs-diagnostics/stackrox-diagnostic-bundle.zip | head -20
```

## Implementation Details

### File: `collection-scripts/gather_diagnostic_bundle`
- Standalone script for diagnostic bundle collection
- Can be called independently or from main `gather` script
- Uses `common.sh` for shared utilities

### Changes to `collection-scripts/gather`
- Added optional launch of `gather_diagnostic_bundle`
- Controlled by `GATHER_DIAGNOSTIC_BUNDLE` environment variable
- Runs in parallel with other collectors

### Error Handling
- All failures are non-fatal (graceful degradation)
- Error files include actionable troubleshooting steps
- No impact on existing Kubernetes resource collection

## Known Limitations

1. **Requires Central running** - Cannot collect if Central is crashed
   - Mitigation: Falls back to existing endpoints in `gather_diagnostics`

2. **Requires authentication** - Cannot collect without admin password
   - Mitigation: Clear error message with manual instructions

3. **Collection time** - Can take 5-10 minutes for large deployments
   - Mitigation: Runs in parallel, configurable timeout

4. **Port-forward dependency** - Requires `oc port-forward` to work
   - Mitigation: Script tests port-forward before proceeding

5. **Local curl dependency** - Requires curl in must-gather container
   - Mitigation: Dockerfile should include curl

## Future Enhancements

1. **Query parameters** - Support `?cluster=`, `?since=`, `?database-only=`
2. **Service account auth** - Alternative to admin password
3. **Retry logic** - Retry on transient failures
4. **Progress indication** - Show progress for long-running collections
5. **Compression** - Stream to compressed file to save space

## Review Checklist

- [ ] Script passes shellcheck
- [ ] Error handling covers all failure modes
- [ ] Documentation is complete and accurate
- [ ] Environment variables are documented
- [ ] Security considerations are addressed
- [ ] Testing instructions are clear
- [ ] Manual collection fallback is documented
- [ ] Integration with main gather script is clean
- [ ] Graceful degradation when disabled
- [ ] No impact on existing functionality

## Questions for Reviewers

1. **Default behavior** - Should this be enabled by default or opt-in?
   - Current: Opt-in (`GATHER_DIAGNOSTIC_BUNDLE=false` by default)
   - Rationale: Adds 2-10 minutes to collection time

2. **Timeout** - Is 10 minutes appropriate?
   - Current: 10 minutes (600s)
   - Alternative: 5 minutes (faster) or 15 minutes (safer for large deployments)

3. **Authentication** - Should we support alternative auth methods?
   - Current: Admin password from Secret only
   - Alternative: Service account tokens, API tokens

4. **Error verbosity** - Are error messages too detailed?
   - Current: Includes troubleshooting steps and manual commands
   - Alternative: Brief error message only

5. **Separate script vs inline** - Should this be in gather_diagnostics?
   - Current: Separate `gather_diagnostic_bundle` script
   - Alternative: Integrated into `gather_diagnostics`

## Related Work

- **Debug Dump branch** (`feature/debug-dump`) - Similar implementation for `/debug/dump`
- **Analysis document** (`diagnostic-collection-analysis.md`) - Gap analysis and comparison
- **Original (reverted) commit** (`a836c39`) - Initial implementation with issues
