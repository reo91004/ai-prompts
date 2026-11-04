"""Readiness deadlines and upstream CLI integration without host services."""
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
import urllib.error


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("runtime", ROOT / "headroom/runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.deployment = SimpleNamespace(profile=runtime.PROFILE)
        self.clock = 0
        self.enterContext(patch.object(runtime, "READY_TIMEOUT", 180))
        self.enterContext(patch.object(runtime.time, "monotonic", side_effect=lambda: self.clock))
        self.enterContext(patch.object(runtime.time, "sleep", side_effect=self.advance))
        self.status = Mock(return_value="running")
        self.enterContext(patch.dict(sys.modules, {
            "headroom.install.runtime": SimpleNamespace(runtime_status=self.status),
        }))
        self.stderr = self.enterContext(patch.object(sys, "stderr", new_callable=io.StringIO))

    def advance(self, seconds):
        self.clock += seconds

    def response(self, endpoint, **kwargs):
        if endpoint == "/health":
            return {"deployment": {"profile": self.deployment.profile}}
        return {"ready": self.clock >= 75, "checks": {"upstream": {
            "ready": False, "error": "SECRET_CREDENTIAL", "url": "PRIVATE_URL"}}}

    def test_cold_start_can_take_longer_than_upstream_45_seconds(self):
        with patch.object(runtime, "probe", side_effect=self.response):
            self.assertTrue(runtime.wait_ready(self.deployment, timeout_seconds=45, require_identity=True))
        self.assertEqual(self.clock, 75)
        self.status.assert_called_with(self.deployment)

    def test_timeout_reports_failed_checks_without_sensitive_errors(self):
        with patch.object(runtime, "probe", side_effect=lambda endpoint, **kw:
                          self.response("/readyz") if endpoint == "/readyz" else None):
            self.assertFalse(runtime.wait_ready(self.deployment, timeout_seconds=45))
        self.assertEqual(self.clock, 180)
        output = self.stderr.getvalue()
        self.assertIn("upstream", output)
        self.assertIn("runner.log", output)
        self.assertNotIn("SECRET_CREDENTIAL", output)
        self.assertNotIn("PRIVATE_URL", output)

    def test_healthy_different_profile_or_unmanaged_process_is_rejected(self):
        for wrong_profile in (True, False):
            self.clock = 0
            self.status.return_value = "running" if wrong_profile else "unknown"
            with patch.object(runtime, "probe", return_value={
                    "ready": True, "deployment": {"profile": "other" if wrong_profile else runtime.PROFILE}}):
                self.assertFalse(runtime.wait_ready(self.deployment, require_identity=True))

    def test_503_body_is_available_only_to_readiness_waiter(self):
        opener = Mock()
        opener.open.side_effect = lambda *a, **kw: (_ for _ in ()).throw(urllib.error.HTTPError(
            "http://127.0.0.1:8787/readyz", 503, "unready", {}, io.BytesIO(b'{"ready":false}')))
        with patch.object(runtime.urllib.request, "build_opener", return_value=opener):
            self.assertIsNone(runtime.probe("/readyz"))
            self.assertEqual(runtime.probe("/readyz", allow_unready=True), {"ready": False})

    def test_new_install_cli_uses_same_waiter_and_retains_failure_exit(self):
        install = SimpleNamespace(wait_ready=object())
        cli = Mock(side_effect=SystemExit(7))
        with patch.dict(sys.modules, {"headroom.cli": SimpleNamespace(install=install, main=cli)}):
            with self.assertRaises(SystemExit) as error:
                runtime.apply_with_readiness(["install", "apply", "--profile", runtime.PROFILE])
        self.assertEqual(error.exception.code, 7)
        self.assertIs(install.wait_ready, runtime.wait_ready)
        cli.assert_called_once_with(args=["install", "apply", "--profile", runtime.PROFILE], prog_name="headroom")

    def test_apply_subprocess_has_time_for_cold_start(self):
        with patch.object(runtime.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run:
            runtime.headroom("install", "apply")
        args, kwargs = run.call_args
        self.assertEqual(args[0][-3:], ["apply", "install", "apply"])
        self.assertGreater(kwargs["timeout"], 180)

    def test_only_readiness_exit_is_retried_once_after_cleanup(self):
        for code, port_busy, attempts in ((75, False, 2), (1, False, 1), (75, True, 1)):
            with self.subTest(code=code, port_busy=port_busy):
                error = subprocess.CalledProcessError(code, ["headroom"])
                with patch.object(runtime.subprocess, "run", side_effect=error) as run, \
                        patch.object(runtime, "port_open", return_value=port_busy), \
                        patch.object(runtime.Path, "exists", return_value=False):
                    with self.assertRaises(subprocess.CalledProcessError):
                        runtime.headroom("install", "apply")
                self.assertEqual(run.call_count, attempts)

    def test_apply_retry_succeeds_without_repeating_other_commands(self):
        error = subprocess.CalledProcessError(75, ["headroom"])
        success = subprocess.CompletedProcess([], 0)
        with patch.object(runtime.subprocess, "run", side_effect=[error, success]) as run, \
                patch.object(runtime, "port_open", return_value=False), \
                patch.object(runtime.Path, "exists", return_value=False):
            self.assertIs(runtime.headroom("install", "apply"), success)
            self.assertEqual(run.call_count, 2)

    def test_existing_service_retries_once_and_protects_other_listener(self):
        start = Mock()
        with patch.dict(sys.modules, {
                "headroom.install.state": SimpleNamespace(load_manifest=lambda profile: self.deployment),
                "headroom.install.supervisors": SimpleNamespace(start_supervisor=start)}), \
                patch.object(runtime, "probe", return_value=None), \
                patch.object(runtime, "wait_ready", side_effect=[False, True]):
            runtime.start_service()
        self.assertEqual(start.call_count, 2)
        start.reset_mock()
        with patch.dict(sys.modules, {
                "headroom.install.state": SimpleNamespace(load_manifest=lambda profile: self.deployment),
                "headroom.install.supervisors": SimpleNamespace(start_supervisor=start)}), \
                patch.object(runtime, "probe", return_value={"deployment": {"profile": "other"}}):
            with self.assertRaisesRegex(RuntimeError, "restart refused"):
                runtime.start_service()
        start.assert_not_called()

    def test_failed_waiter_produces_retry_exit_for_new_apply(self):
        install = SimpleNamespace(wait_ready=None)
        def cli(**kwargs):
            self.assertFalse(install.wait_ready(self.deployment, timeout_seconds=45))
            raise SystemExit(1)
        with patch.dict(sys.modules, {"headroom.cli": SimpleNamespace(install=install, main=cli)}), \
                patch.object(runtime, "probe", return_value=None):
            with self.assertRaises(SystemExit) as error:
                runtime.apply_with_readiness(["install", "apply"])
        self.assertEqual(error.exception.code, 75)


if __name__ == "__main__":
    unittest.main()
