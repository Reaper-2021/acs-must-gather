#!/usr/bin/env python3
"""Tests for analysis/acs-analyze.

Self-contained: each test builds a synthetic must-gather bundle in a temp dir,
runs the analyzer as a subprocess, and asserts on exit code / output. Stdlib
only - run with `python3 -m unittest` or `make test`.
"""

import json
import os
import subprocess
import sys
import tempfile
import textwrap
import types
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ANALYZER = os.path.join(HERE, "..", "analysis", "acs-analyze")


def load_module():
    """Load the extension-less acs-analyze script as a module for unit tests."""
    src = open(ANALYZER, encoding="utf-8").read()
    mod = types.ModuleType("acs_analyze")
    exec(compile(src, ANALYZER, "exec"), mod.__dict__)
    return mod


ACS = load_module()


def _write(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(content)


def _write_json(path, obj):
    _write(path, json.dumps(obj))


def build_bundle(root, *, healthy=True):
    """Create a minimal image sub-directory under root and return its path."""
    img = os.path.join(root, "quay-io-example-acs-must-gather-sha256-deadbeef")
    diag = os.path.join(img, "acs-diagnostics")
    bundle = os.path.join(img, "acs-diagnostic-bundle")

    _write_json(os.path.join(diag, "central-metadata.json"),
                {"version": "4.11.2", "buildFlavor": "release",
                 "releaseBuild": True,
                 "licenseStatus": "VALID" if healthy else "EXPIRED"})
    _write_json(os.path.join(bundle, "versions.json"),
                {"MainVersion": "4.11.2", "CollectorVersion": "4.11.2",
                 "ScannerVersion": "4.11.2", "Database": "PostgresDB",
                 "DatabaseServerVersion": "15.18"})
    _write_json(os.path.join(diag, "central-db-status.json"),
                {"databaseAvailable": healthy, "databaseType": "PostgresDB",
                 "databaseVersion": "15.18", "databaseIsExternal": False})
    _write_json(os.path.join(diag, "central-clusters.json"),
                {"clusters": [{
                    "name": "my-cluster", "collectionMethod": "CORE_BPF",
                    "status": {"sensorVersion": "4.11.2"}}]})

    # A pod manifest under namespaces/ (regex-scanned for restart/OOM).
    pod_dir = os.path.join(img, "namespaces", "stackrox", "pods", "scanner-x")
    oom = "reason: OOMKilled" if not healthy else "reason: Completed"
    _write(os.path.join(pod_dir, "scanner-x.yaml"), textwrap.dedent(f"""\
        status:
          containerStatuses:
          - name: scanner
            restartCount: {0 if healthy else 12}
            lastState:
              terminated:
                {oom}
        """))
    return img


def run(path):
    env = dict(os.environ, NO_COLOR="1")
    proc = subprocess.run([sys.executable, ANALYZER, path],
                          capture_output=True, text=True, env=env)
    return proc.returncode, proc.stdout + proc.stderr


class AnalyzeTest(unittest.TestCase):
    def test_healthy_bundle_exits_zero(self):
        with tempfile.TemporaryDirectory() as d:
            build_bundle(d, healthy=True)
            code, out = run(d)
            self.assertEqual(code, 0, out)
            self.assertIn("Central 4.11.2", out)
            self.assertIn("Verdict: healthy", out)

    def test_unhealthy_bundle_exits_one(self):
        with tempfile.TemporaryDirectory() as d:
            build_bundle(d, healthy=False)
            code, out = run(d)
            self.assertEqual(code, 1, out)
            self.assertIn("OOMKilled", out)
            self.assertIn("license status is EXPIRED", out)
            self.assertIn("FAILING checks", out)

    def test_missing_bundle_exits_two(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = run(d)
            self.assertEqual(code, 2, out)
            self.assertIn("could not find", out)

    def test_auto_discovery_through_nested_dir(self):
        # Simulate must-gather.local.XXXX/quay-.../ nesting.
        with tempfile.TemporaryDirectory() as d:
            nested = os.path.join(d, "must-gather.local.123")
            os.makedirs(nested)
            build_bundle(nested, healthy=True)
            code, out = run(d)  # point at the parent, not the image dir
            self.assertEqual(code, 0, out)


class MemParsingTest(unittest.TestCase):
    def test_mem_to_bytes(self):
        self.assertEqual(ACS.mem_to_bytes("512Mi"), 512 * 1024**2)
        self.assertEqual(ACS.mem_to_bytes("4Gi"), 4 * 1024**3)
        self.assertEqual(ACS.mem_to_bytes("1000Mi"), 1000 * 1024**2)
        self.assertEqual(ACS.mem_to_bytes("2000000"), 2000000)
        self.assertEqual(ACS.mem_to_bytes("1G"), 1000**3)
        self.assertIsNone(ACS.mem_to_bytes("not-a-quantity"))

    def test_container_mem_limit_sorted_yaml(self):
        # Mirrors `oc get -o yaml` output: keys alphabetical, so the list item
        # starts with `- command:` and `name:`/`resources:` are plain keys.
        manifest = textwrap.dedent("""\
            spec:
              containers:
              - command:
                - /entrypoint.sh
                env:
                - name: ROX_MEMLIMIT
                  value: "1Gi"
                image: example/central
                name: central
                resources:
                  limits:
                    cpu: 500m
                    memory: 1000Mi
                  requests:
                    cpu: 200m
                    memory: 200Mi
              - name: central-db
                resources:
                  limits:
                    memory: 4Gi
            """)
        self.assertEqual(ACS.container_mem_limit(manifest, "central"),
                         1000 * 1024**2)
        self.assertEqual(ACS.container_mem_limit(manifest, "central-db"),
                         4 * 1024**3)
        self.assertIsNone(ACS.container_mem_limit(manifest, "nope"))


class ScannerV4Test(unittest.TestCase):
    def _run_check(self, status_text):
        with tempfile.TemporaryDirectory() as d:
            adv = os.path.join(d, "advanced-acs-diagnostics")
            _write(os.path.join(adv, "scanner-v4", "stackrox",
                                "scanner-v4-status.txt"), status_text)
            rep = ACS.Report()
            ACS.check_scanner_v4(adv, rep)
            return rep.results

    def test_healthy_scanner_v4(self):
        text = textwrap.dedent("""\
            # Scanner V4 pod status
            === scanner-v4-indexer-abc  [scanner-v4-indexer] ===
              phase: Running
              ready: true
              restarts: 0
              lastState:
            === scanner-v4-matcher-def  [scanner-v4-matcher] ===
              phase: Running
              ready: true
              restarts: 1
              lastState:
            """)
        results = self._run_check(text)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0].status, ACS.OK)

    def test_not_ready_scanner_v4(self):
        text = textwrap.dedent("""\
            === scanner-v4-matcher-def  [scanner-v4-matcher] ===
              phase: Running
              ready: false
              restarts: 9
              lastState: terminated
            """)
        results = self._run_check(text)
        self.assertEqual(results[0].status, ACS.WARN)
        self.assertIn("not ready", results[0].detail)

    def test_absent_scanner_v4_is_silent(self):
        with tempfile.TemporaryDirectory() as d:
            adv = os.path.join(d, "advanced-acs-diagnostics")
            os.makedirs(adv)
            rep = ACS.Report()
            ACS.check_scanner_v4(adv, rep)
            self.assertEqual(rep.results, [])


def _vuln(cve, sev, fixed_by=None, cvss=7.0, suppressed=False):
    v = {"cve": cve, "severity": sev, "cvss": cvss}
    if fixed_by:
        v["fixedBy"] = fixed_by
    if suppressed:
        v["suppressed"] = True
    return v


def _workload_line(dep_ns, dep_name, image_full, vulns):
    """One NDJSON line as the vuln-mgmt export emits it."""
    return json.dumps({"result": {
        "deployment": {"namespace": dep_ns, "name": dep_name},
        "images": [{
            "name": {"fullName": image_full},
            "scan": {"components": [{"name": "openssl", "vulns": vulns}]},
        }],
    }})


class ImageCveTest(unittest.TestCase):
    def _write_export(self, adv, lines):
        _write(os.path.join(adv, "vuln-report", "vuln-mgmt-workloads.json"),
               "\n".join(lines) + "\n")

    def test_absent_is_silent(self):
        with tempfile.TemporaryDirectory() as d:
            adv = os.path.join(d, "advanced-acs-diagnostics")
            os.makedirs(adv)
            rep = ACS.Report()
            ACS.check_image_cves(adv, rep)
            self.assertEqual(rep.results, [])

    def test_fixable_critical_warns(self):
        with tempfile.TemporaryDirectory() as d:
            adv = os.path.join(d, "advanced-acs-diagnostics")
            self._write_export(adv, [_workload_line(
                "stackrox", "central", "quay.io/rhacs/main:4.5",
                [_vuln("CVE-2024-1", "CRITICAL_VULNERABILITY_SEVERITY", "1.1.1w"),
                 _vuln("CVE-2024-2", "LOW_VULNERABILITY_SEVERITY")])])
            rep = ACS.Report()
            ACS.check_image_cves(adv, rep)
            r = rep.results[0]
            self.assertEqual(r.status, ACS.WARN)
            self.assertIn("FIXABLE CRITICAL", r.detail)

    def test_no_fixable_is_info(self):
        with tempfile.TemporaryDirectory() as d:
            adv = os.path.join(d, "advanced-acs-diagnostics")
            self._write_export(adv, [_workload_line(
                "stackrox", "central", "quay.io/rhacs/main:4.5",
                [_vuln("CVE-2024-3", "MODERATE_VULNERABILITY_SEVERITY")])])
            rep = ACS.Report()
            ACS.check_image_cves(adv, rep)
            self.assertEqual(rep.results[0].status, ACS.INFO)

    def test_suppressed_cve_ignored(self):
        with tempfile.TemporaryDirectory() as d:
            adv = os.path.join(d, "advanced-acs-diagnostics")
            self._write_export(adv, [_workload_line(
                "stackrox", "central", "quay.io/rhacs/main:4.5",
                [_vuln("CVE-2024-4", "CRITICAL_VULNERABILITY_SEVERITY",
                       "1.1.1w", suppressed=True)])])
            rep = ACS.Report()
            ACS.check_image_cves(adv, rep)
            # Only suppressed CVE present -> no fixable critical -> INFO.
            self.assertEqual(rep.results[0].status, ACS.INFO)

    def test_image_filter_drilldown(self):
        with tempfile.TemporaryDirectory() as d:
            adv = os.path.join(d, "advanced-acs-diagnostics")
            self._write_export(adv, [
                _workload_line("stackrox", "central", "quay.io/rhacs/main:4.5",
                               [_vuln("CVE-2024-1", "CRITICAL_VULNERABILITY_SEVERITY", "1.1.1w")]),
                _workload_line("app", "web", "docker.io/library/nginx:1.20",
                               [_vuln("CVE-2024-9", "LOW_VULNERABILITY_SEVERITY")]),
            ])
            rep = ACS.Report()
            ACS.check_image_cves(adv, rep, image_filter="nginx")
            self.assertEqual(len(rep.results), 1)
            self.assertIn("nginx", rep.results[0].name)
            self.assertIn("CVE-2024-9", " ".join(rep.results[0].lines))

    def test_image_filter_no_match(self):
        with tempfile.TemporaryDirectory() as d:
            adv = os.path.join(d, "advanced-acs-diagnostics")
            self._write_export(adv, [_workload_line(
                "stackrox", "central", "quay.io/rhacs/main:4.5",
                [_vuln("CVE-2024-1", "CRITICAL_VULNERABILITY_SEVERITY", "1.1.1w")])])
            rep = ACS.Report()
            ACS.check_image_cves(adv, rep, image_filter="doesnotexist")
            self.assertEqual(rep.results[0].status, ACS.INFO)
            self.assertIn("no scanned image matches", rep.results[0].detail)


class ViolationsTest(unittest.TestCase):
    def _run(self, alerts_obj):
        with tempfile.TemporaryDirectory() as d:
            adv = os.path.join(d, "advanced-acs-diagnostics")
            _write_json(os.path.join(adv, "vuln-report", "violations.json"),
                        alerts_obj)
            rep = ACS.Report()
            ACS.check_violations(adv, rep)
            return rep.results

    def test_critical_violation_warns(self):
        results = self._run({"alerts": [
            {"policy": {"severity": "CRITICAL_SEVERITY"}, "lifecycleStage": "RUNTIME"},
            {"policy": {"severity": "LOW_SEVERITY"}, "lifecycleStage": "DEPLOY"},
        ]})
        self.assertEqual(results[0].status, ACS.WARN)
        self.assertIn("CRITICAL=1", results[0].detail)

    def test_empty_alerts_ok(self):
        results = self._run({"alerts": []})
        self.assertEqual(results[0].status, ACS.OK)

    def test_absent_is_silent(self):
        with tempfile.TemporaryDirectory() as d:
            adv = os.path.join(d, "advanced-acs-diagnostics")
            os.makedirs(adv)
            rep = ACS.Report()
            ACS.check_violations(adv, rep)
            self.assertEqual(rep.results, [])


if __name__ == "__main__":
    unittest.main()
