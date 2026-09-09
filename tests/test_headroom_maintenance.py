"""Installer shutdown/recovery contracts; OS services are always simulated."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("maintenance", ROOT / "headroom/maintenance.py")
maintenance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(maintenance)


class MaintenanceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        home = Path(temporary.name) / "home with spaces"
        home.mkdir()
        for name, value in {"HOME": home, "KIT": home / ".universal-research-agent-kit",
                            "DEPLOY": home / ".headroom/deploy" / maintenance.PROFILE}.items():
            self.enterContext(patch.object(maintenance, name, value))
        self.enterContext(patch.dict(os.environ, {"HOME": str(home)}, clear=True))
        self.enterContext(patch.object(sys, "platform", "linux"))
        self.enterContext(patch.object(maintenance, "STOP_TIMEOUT", 0.01))
        self.enterContext(patch.object(maintenance.time, "sleep"))
        self.table = {42: ("Wed Sep 9 10:00:00 2026", "/usr/bin/idle-fixture")}
        self.enterContext(patch.object(maintenance, "processes", side_effect=lambda: self.table.copy()))
        self.registered = self.active = False
        self.events = []
        self.enterContext(patch.object(maintenance, "port_open", side_effect=lambda: self.active))
        self.enterContext(patch.object(maintenance, "ready", side_effect=lambda: self.active))
        self.enterContext(patch.object(maintenance, "command", side_effect=self.os_command))
        self.enterContext(patch.object(maintenance.os, "kill", side_effect=self.terminate))
        maintenance.KIT.mkdir()
        self.record = maintenance.KIT / "resume.json"

    def seed_service(self):
        maintenance.DEPLOY.mkdir(parents=True)
        state = {"profile": maintenance.PROFILE, "port": maintenance.PORT}
        (maintenance.KIT / "headroom.json").write_text(json.dumps(state))
        manifest = {**state, "host": "127.0.0.1", "preset": "persistent-service", "runtime_kind": "python",
                    "supervisor_kind": "service", "scope": "provider", "targets": ["codex"],
                    "service_name": maintenance.SERVICE}
        (maintenance.DEPLOY / "manifest.json").write_text(json.dumps(manifest))
        runner = str(maintenance.DEPLOY / "run-headroom.sh")
        Path(runner).write_text("#!/usr/bin/env bash\nset -euo pipefail\nexec /owned/headroom install agent run --profile " + maintenance.PROFILE + "\n")
        path = maintenance.service_path()
        path.parent.mkdir(parents=True)
        if sys.platform == "darwin":
            path.write_bytes(plistlib.dumps({"Label": maintenance.LABEL, "ProgramArguments": [runner], "KeepAlive": True}))
        else:
            path.write_text("[Service]\nExecStart=" + runner + "\nRestart=on-failure\n")
        self.registered = self.active = True

    def add_mcp(self, pid=246):
        root = maintenance.KIT / "tooling"
        command = str(root / "uv-tools/headroom-ai/bin/python3") + " " + str(root / "bin/headroom") + " mcp serve"
        self.table[pid] = ("Wed Sep 9 10:00:00 2026", command)

    def terminate(self, pid, sig):
        self.assertEqual(sig, signal.SIGTERM)
        self.assertTrue(maintenance.owned_mcp(self.table[pid][1]))
        self.events.append(("term", pid))
        del self.table[pid]

    def os_command(self, args):
        self.events.append(tuple(args))
        runner = str(maintenance.DEPLOY / "run-headroom.sh")
        if args[:2] == ["launchctl", "print"]:
            if not self.registered:
                return subprocess.CompletedProcess(args, 113, "", 'Could not find service "' + maintenance.LABEL + '"')
            text = ("path = " + str(maintenance.service_path()) + "\nprogram = " + runner
                    + "\narguments = {\n" + runner + "\n}\nstate = " + ("running" if self.active else "waiting"))
        elif args[:3] == ["systemctl", "--user", "show"]:
            text = ("LoadState=loaded\nActiveState=" + ("active" if self.active else "inactive")
                    + "\nFragmentPath=" + str(maintenance.service_path()) + "\nExecStart={ path=" + runner + " ; argv[]=" + runner + " ; }\n")
        else:
            if "bootout" in args or "stop" in args:
                self.active = False
                if "bootout" in args:
                    self.registered = False
            elif "bootstrap" in args or "kickstart" in args or "start" in args:
                self.active = self.registered = True
            else:
                raise AssertionError(args)
            text = ""
        return subprocess.CompletedProcess(args, 0, text, "")

    def test_pause_and_resume_preserve_service_provider_and_auth_files(self):
        for platform in ("linux", "darwin"):
            with self.subTest(platform=platform), patch.object(sys, "platform", platform):
                if maintenance.DEPLOY.exists():
                    import shutil
                    shutil.rmtree(maintenance.DEPLOY)
                self.seed_service()
                self.add_mcp()
                auth = maintenance.HOME / "auth-fixture.json"
                auth.write_text('{"token":"fixture-only"}')
                before = {path: path.read_bytes() for path in maintenance.HOME.rglob("*") if path.is_file() and path != self.record}
                maintenance.pause(self.record)
                self.assertFalse(self.active)
                self.assertNotIn(246, self.table)
                self.assertTrue(json.loads(self.record.read_text())["resume_service"])
                self.assertTrue(all(path.read_bytes() == value for path, value in before.items()))
                maintenance.resume(self.record)
                self.assertTrue(self.active)
                self.assertNotIn(246, self.table)  # The client owns its stdio reconnect.
                self.assertTrue(all(path.read_bytes() == value for path, value in before.items()))
        self.assertIn(("launchctl", "bootout", maintenance.DOMAIN + "/" + maintenance.LABEL), self.events)
        self.assertIn(("launchctl", "bootstrap", maintenance.DOMAIN, str(maintenance.HOME / "Library/LaunchAgents" / (maintenance.LABEL + ".plist"))), self.events)
        self.assertIn(("systemctl", "--user", "stop", maintenance.SERVICE), self.events)
        self.assertIn(("systemctl", "--user", "start", maintenance.SERVICE), self.events)

    def test_mcp_only_shutdown_needs_no_headroom_import_or_service_record(self):
        self.add_mcp()
        self.table[247] = ("same start", str(maintenance.KIT / "tooling/python-venv/bin/python") + " my-research.py")
        self.table[248] = ("same start", "/outside/bin/headroom mcp serve")
        maintenance.pause(self.record)
        self.assertEqual(self.events, [("term", 246)])
        self.assertIn(247, self.table)
        self.assertIn(248, self.table)
        maintenance.resume(self.record)
        self.assertEqual(self.events, [("term", 246)])

    def test_recognition_excludes_prompt_code_and_unrelated_commands(self):
        self.add_mcp()
        command = self.table[246][1]
        self.assertTrue(maintenance.owned_mcp(command))
        for other in ("/usr/bin/python3 -c '" + command + "'", command.replace(" mcp serve", " proxy"),
                      command.replace("/bin/headroom mcp", "/bin/headroom-helper mcp"),
                      "/outside/bin/headroom mcp serve", str(maintenance.KIT / "tooling/python-venv/bin/python") + " user-job.py"):
            self.assertFalse(maintenance.owned_mcp(other), other)

    def test_symlinked_mcp_directories_never_stop_external_work(self):
        for index, relative in enumerate(("tooling", "tooling/bin", "tooling/uv-tools/headroom-ai")):
            with self.subTest(relative=relative):
                external = maintenance.HOME / ("external-venv-" + str(index))
                external.mkdir()
                sentinel = external / "keep"
                sentinel.write_text("external environment")
                link = maintenance.KIT / relative
                link.parent.mkdir(parents=True, exist_ok=True)
                link.symlink_to(external, target_is_directory=True)
                self.add_mcp()
                with self.assertRaisesRegex(RuntimeError, "symlinked maintenance path"):
                    maintenance.pause(self.record)
                self.assertEqual(self.events, [])
                self.assertFalse(self.record.exists())
                self.assertIn(246, self.table)
                self.assertEqual(sentinel.read_text(), "external environment")
                link.unlink()

    def test_custom_service_name_definition_and_loaded_identity_are_refused(self):
        self.seed_service()
        self.add_mcp()
        manifest = maintenance.DEPLOY / "manifest.json"
        original = manifest.read_text()
        manifest.write_text(original.replace(maintenance.SERVICE, "unrelated-service"))
        with self.assertRaisesRegex(RuntimeError, "customized"):
            maintenance.pause(self.record)
        self.assertFalse(self.record.exists())
        self.assertFalse(any(event[0] == "term" for event in self.events))
        manifest.write_text(original)
        definition = maintenance.service_path().read_text()
        maintenance.service_path().write_text(definition + "ExecStop=/outside/action\n")
        with self.assertRaisesRegex(RuntimeError, "customized"):
            maintenance.pause(self.record)
        maintenance.service_path().write_text(definition)
        with patch.object(maintenance, "command", return_value=subprocess.CompletedProcess([], 0, "LoadState=loaded\nFragmentPath=/outside\n", "")):
            with self.assertRaisesRegex(RuntimeError, "loaded systemd"):
                maintenance.pause(self.record)
        self.assertIn(246, self.table)

    def test_service_stop_failure_keeps_mcp_and_resume_record(self):
        self.seed_service()
        self.add_mcp()
        def reject_stop(args):
            if "stop" in args:
                return subprocess.CompletedProcess(args, 1, "", "permission denied")
            return self.os_command(args)
        with patch.object(maintenance, "command", side_effect=reject_stop):
            with self.assertRaisesRegex(RuntimeError, "could not stop"):
                maintenance.pause(self.record)
        self.assertTrue(json.loads(self.record.read_text())["resume_service"])
        self.assertIn(246, self.table)

    def test_custom_runner_and_loaded_stop_hooks_are_preserved(self):
        self.seed_service()
        self.add_mcp()
        runner = maintenance.DEPLOY / "run-headroom.sh"
        original = runner.read_text()
        runner.write_text(original.replace("/owned/headroom install agent run --profile " + maintenance.PROFILE,
                                           "/usr/bin/python3 important-user-job.py"))
        with self.assertRaisesRegex(RuntimeError, "does not execute the kit profile"):
            maintenance.pause(self.record)
        runner.write_text(original)
        def loaded_custom_stop(args):
            result = self.os_command(args)
            return subprocess.CompletedProcess(args, result.returncode, result.stdout + "\nExecStop=/outside/action\n", result.stderr)
        with patch.object(maintenance, "command", side_effect=loaded_custom_stop):
            with self.assertRaisesRegex(RuntimeError, "loaded systemd"):
                maintenance.pause(self.record)
        self.assertIn(246, self.table)
        self.assertFalse(self.record.exists())

    def test_mcp_timeout_preserves_environment_and_never_uses_sigkill(self):
        self.add_mcp()
        sentinel = maintenance.KIT / "environment-sentinel"
        sentinel.write_text("keep")
        with patch.object(maintenance.os, "kill") as kill:
            with self.assertRaisesRegex(RuntimeError, "did not exit after SIGTERM"):
                maintenance.pause(self.record)
        kill.assert_called_once_with(246, signal.SIGTERM)
        self.assertEqual(sentinel.read_text(), "keep")

    def test_changed_pid_identity_is_never_signalled(self):
        self.add_mcp()
        def process_reused():
            self.table[246] = ("a new start", "/usr/bin/unrelated-job")
        with patch.object(maintenance, "stop_service", side_effect=process_reused):
            maintenance.pause(self.record)
        self.assertEqual(self.events, [])
        self.assertIn(246, self.table)

    def test_client_respawn_is_reported_without_repeated_kills(self):
        self.add_mcp()
        def respawn(pid, sig):
            self.terminate(pid, sig)
            self.add_mcp(247)
        with patch.object(maintenance.os, "kill", side_effect=respawn):
            with self.assertRaisesRegex(RuntimeError, "client restarted"):
                maintenance.pause(self.record)
        self.assertEqual(self.events, [("term", 246)])
        self.assertIn(247, self.table)

    def test_inactive_service_is_not_resumed_on_failure(self):
        self.seed_service()
        self.active = False
        maintenance.pause(self.record)
        self.assertFalse(json.loads(self.record.read_text())["resume_service"])
        maintenance.resume(self.record)
        self.assertFalse(self.active)
        self.assertFalse(any("start" in event or "bootstrap" in event for event in self.events))

    def test_snapshot_parser_uses_start_time_without_logging_arguments(self):
        with patch.object(maintenance, "command", return_value=subprocess.CompletedProcess([], 0, "246 Wed Sep 9 10:00:00 2026 /bin/example SECRET_ARG\n", "")):
            # Bypass this test class's snapshot fixture to exercise the parser.
            parsed = REAL_PROCESSES()
        self.assertEqual(parsed[246], ("Wed Sep 9 10:00:00 2026", "/bin/example SECRET_ARG"))
        with patch.object(maintenance, "command", return_value=subprocess.CompletedProcess([], 0, "malformed SECRET_ARG\n", "")):
            with self.assertRaisesRegex(RuntimeError, "Invalid process inspection") as error:
                REAL_PROCESSES()
        self.assertNotIn("SECRET_ARG", str(error.exception))


REAL_PROCESSES = maintenance.processes


class RealMcpProcessTest(unittest.TestCase):
    def test_sigterm_of_test_owned_mcp_process(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home with spaces"
            kit = home / ".universal-research-agent-kit"
            python = kit / "tooling/uv-tools/headroom-ai/bin/python"
            script = kit / "tooling/bin/headroom"
            python.parent.mkdir(parents=True)
            script.parent.mkdir(parents=True)
            python.symlink_to(sys.executable)
            script.write_text("print('ready', flush=True)\ninput()\n")
            process = subprocess.Popen([str(python), str(script), "mcp", "serve"], stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, text=True)
            real_kill = os.kill
            try:
                self.assertEqual(process.stdout.readline().strip(), "ready")
                def only_test_process():
                    snapshot = REAL_PROCESSES()
                    if process.poll() is not None:
                        return {42: ("fixture", "/usr/bin/idle-fixture")}
                    return {process.pid: snapshot[process.pid]}
                def only_test_signal(pid, sig):
                    self.assertEqual(pid, process.pid)
                    self.assertEqual(sig, signal.SIGTERM)
                    real_kill(pid, sig)
                with patch.multiple(maintenance, HOME=home, KIT=kit, DEPLOY=home / ".headroom/deploy" / maintenance.PROFILE), \
                        patch.object(maintenance, "processes", side_effect=only_test_process), \
                        patch.object(maintenance.os, "kill", side_effect=only_test_signal):
                    maintenance.pause(kit / "resume.json")
                self.assertEqual(process.wait(timeout=5), -signal.SIGTERM)
            finally:
                if process.poll() is None:
                    process.communicate("finish\n", timeout=5)
                else:
                    process.communicate(timeout=5)


if __name__ == "__main__":
    unittest.main()
