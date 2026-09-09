"""Recovery contracts; real signals are limited to a listener created by this test."""

from contextlib import ExitStack, redirect_stdout
from dataclasses import replace
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("codex_remote", Path(__file__).resolve().parents[1] / "scripts/codex_remote.py")
rc = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = rc
spec.loader.exec_module(rc)


def result(data=None, error=""):
    return subprocess.CompletedProcess([], bool(error), json.dumps(data), error)


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="rc-", dir="/tmp")
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name)
        self.binary = self.home / ".codex/packages/standalone/current/bin/codex"
        self.owner = rc.Process(98765, os.getuid(), 1, "start", str(self.binary),
                                (str(self.binary), "-c", "a=b", "app-server", "--listen", "unix://"))
        settings = self.home / ".codex/app-server-daemon/settings.json"
        settings.parent.mkdir(parents=True)
        settings.write_text('{"remoteControlEnabled":true}')
        self.auth = self.home / ".codex/auth.json"
        self.auth.write_text("auth sentinel")
        self.output = io.StringIO()
        self.addCleanup(lambda: self.assertEqual("auth sentinel", self.auth.read_text()))

    def recovery_boundaries(self, stack, owners=None, ancestor=1, version=None):
        owner = stack.enter_context(patch.object(rc, "socket_owner", side_effect=owners or [self.owner, self.owner]))
        stack.enter_context(patch.object(rc, "version", return_value=version or {"status": "running", "appServerVersion": "0.153.4"}))
        stack.enter_context(patch.object(rc, "process", side_effect=ProcessLookupError()))
        stack.enter_context(patch.object(rc, "parent_pid", return_value=ancestor))
        stack.enter_context(patch.object(rc.sys, "platform", "darwin"))
        kill = stack.enter_context(patch.object(rc.os, "kill"))
        return owner, kill

    def test_success_and_connecting_never_recover(self):
        for status in ("connected", "connecting"):
            with patch.object(rc, "native", side_effect=[result({"status": status, "environmentId": "PRIVATE"}), result({"status": "running", "backend": "pid"})]), patch.object(rc, "recover") as recover, redirect_stdout(self.output):
                rc.enable(self.binary, self.home)
                recover.assert_not_called()
        self.assertIn("relay connection is pending", self.output.getvalue())
        self.assertNotIn("PRIVATE", self.output.getvalue())

    def test_only_known_native_error_recovers_once(self):
        with patch.object(rc, "native", side_effect=[result(error=rc.UNMANAGED), result({"status": "connected"}), result({"status": "running", "backend": "pid"})]) as native, patch.object(rc, "recover") as recover, redirect_stdout(self.output):
            rc.enable(self.binary, self.home)
            recover.assert_called_once_with(self.binary, self.home)
            self.assertEqual(native.call_count, 3)
        with patch.object(rc, "native", return_value=result(error=rc.UNMANAGED)) as native, patch.object(rc, "recover") as recover:
            with self.assertRaisesRegex(RuntimeError, "reappeared"):
                rc.enable(self.binary, self.home)
            self.assertEqual(native.call_count, 2)
            recover.assert_called_once()

    def test_other_failures_do_not_signal_or_recover(self):
        failures = [result(error="network failed"), subprocess.CompletedProcess([], 0, "PRIVATE invalid JSON", ""), result([]), result({"status": "stopped"})]
        for failure in failures:
            with patch.object(rc, "native", return_value=failure), patch.object(rc, "recover") as recover:
                with self.assertRaises(RuntimeError):
                    rc.enable(self.binary, self.home)
                recover.assert_not_called()
        with patch.object(rc, "native", side_effect=[result({"status": "connected"}), result({"status": "running"})]):
            with self.assertRaisesRegex(RuntimeError, "managed daemon is not running"):
                rc.enable(self.binary, self.home)

    def test_verified_owner_receives_only_sighup(self):
        with ExitStack() as stack, redirect_stdout(self.output):
            _, kill = self.recovery_boundaries(stack)
            rc.recover(self.binary, self.home)
            kill.assert_called_once_with(self.owner.pid, signal.SIGHUP)

    def test_changed_owner_unknown_version_and_ancestor_refuse_signal(self):
        cases = [
            {"owners": [self.owner, replace(self.owner, start="reused PID")]},
            {"owners": [self.owner, replace(self.owner, pid=1234)]},
            {"version": {"status": "running", "appServerVersion": "0.153.3"}},
            {"version": {"status": "running", "backend": "pid", "appServerVersion": "0.153.4"}},
            {"version": {"status": "running", "cliVersion": "0.153.4"}},
            {"ancestor": self.owner.pid},
            {"owners": [replace(self.owner, executable="/usr/bin/python3")]},
        ]
        for case in cases:
            with ExitStack() as stack:
                _, kill = self.recovery_boundaries(stack, **case)
                with self.assertRaises(RuntimeError):
                    rc.recover(self.binary, self.home)
                kill.assert_not_called()

    def test_work_timeout_never_escalates_or_retries_start(self):
        with ExitStack() as stack, redirect_stdout(self.output):
            _, kill = self.recovery_boundaries(stack)
            native = stack.enter_context(patch.object(rc, "native", return_value=result(error=rc.UNMANAGED)))
            stack.enter_context(patch.object(rc.time, "monotonic", side_effect=[0, 31]))
            with self.assertRaisesRegex(RuntimeError, "may exit later"):
                rc.enable(self.binary, self.home)
            kill.assert_called_once_with(self.owner.pid, signal.SIGHUP)
            native.assert_called_once()

    def test_live_reparented_server_keeps_waiting(self):
        with ExitStack() as stack, redirect_stdout(self.output):
            _, kill = self.recovery_boundaries(stack)
            stack.enter_context(patch.object(rc, "process", return_value=replace(self.owner, ppid=222)))
            stack.enter_context(patch.object(rc.time, "monotonic", side_effect=[0, 1, 31]))
            sleep = stack.enter_context(patch.object(rc.time, "sleep"))
            with self.assertRaisesRegex(RuntimeError, "may exit later"):
                rc.recover(self.binary, self.home)
            sleep.assert_called_once()
            kill.assert_called_once_with(self.owner.pid, signal.SIGHUP)

    def test_invalid_preferences_do_not_pass_verification(self):
        settings = self.home / ".codex/app-server-daemon/settings.json"
        for preferences in ([], {}, {"remoteControlEnabled": False}, {"remoteControlEnabled": "false"}):
            settings.write_text(json.dumps(preferences))
            with patch.object(rc, "version", return_value={"status": "running", "backend": "pid"}):
                with self.assertRaisesRegex(RuntimeError, "preference is disabled"):
                    rc.verify(self.binary, self.home)

    def test_launch_scope(self):
        self.assertTrue(rc.known_listener(self.owner, self.home, self.binary))
        for argv in [(str(self.binary), "app-server"), (str(self.binary), "app-server", "--listen", "stdio://"), (str(self.binary), "app-server", "--listen", "unix:///custom.sock"), (str(self.binary), "exec", "app-server", "--listen", "unix://")]:
            self.assertFalse(rc.known_listener(replace(self.owner, argv=argv), self.home, self.binary))
        npm = "/usr/local/lib/node_modules/@openai/codex/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex"
        self.assertTrue(rc.known_listener(replace(self.owner, executable=npm), self.home, self.binary))

    def test_real_socket_credentials_and_graceful_signal_to_test_child(self):
        path = self.home / ".codex/app-server-control/app-server-control.sock"
        path.parent.mkdir()
        child = subprocess.Popen([sys.executable, "-u", "-c", '''
import pathlib, signal, socket, sys
path = pathlib.Path(sys.argv[1])
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(str(path))
server.listen()
def finish(signum, frame):
    path.with_suffix('.signal').write_text(str(signum))
    sys.exit(0)
signal.signal(signal.SIGHUP, finish)
print('ready', flush=True)
while True:
    connection, _ = server.accept()
    connection.close()
''', str(path)], stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(child.stdout.readline().strip(), "ready")
            owner = rc.socket_owner(path)
            self.assertEqual(owner.pid, child.pid)
            self.assertEqual(owner.uid, os.getuid())
            self.assertEqual(owner.argv[1:3], ("-u", "-c"))
            self.assertEqual(Path(owner.executable), Path(sys.executable).resolve())
            with patch.object(rc, "process", return_value=replace(owner, uid=owner.uid + 1)):
                with self.assertRaisesRegex(RuntimeError, "another user"):
                    rc.socket_owner(path)
            wrong_path = path.with_suffix(".other")
            wrong_path.symlink_to(path)
            with self.assertRaisesRegex(RuntimeError, "control socket"):
                rc.socket_owner(wrong_path)
            # Only the executable/launch and native probe are fixtures; PID, UID,
            # socket, process identity, signal and exit wait use the real OS.
            with patch.object(rc, "known_listener", return_value=True), patch.object(rc, "version", return_value={"status": "running", "appServerVersion": "0.153.4"}), redirect_stdout(self.output):
                rc.recover(self.binary, self.home, wait_seconds=5)
            self.assertEqual(child.wait(timeout=2), 0)
            self.assertEqual(path.with_suffix(".signal").read_text(), str(signal.SIGHUP))
        finally:
            if child.poll() is None:
                child.terminate()
                child.wait(timeout=2)
            child.stdout.close()


if __name__ == "__main__":
    unittest.main()
