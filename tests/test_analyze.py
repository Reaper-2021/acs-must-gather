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
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ANALYZER = os.path.join(HERE, "..", "analysis", "acs-analyze")


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


if __name__ == "__main__":
    unittest.main()
