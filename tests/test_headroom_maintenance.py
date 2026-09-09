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
        for name, value in {"HOME": home, "KIT": home / ".universal-research-agent-kit", "PROFILE": "research-agent-kit",
                            "SERVICE": "headroom-research-agent-kit", "LABEL": "com.headroom.research-agent-kit",
                            "DEPLOY": home / ".headroom/deploy/research-agent-kit"}.items():
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

    def seed_service(self, adopting=False):
        if adopting:
            maintenance.select_profile("default")
        maintenance.DEPLOY.mkdir(parents=True, exist_ok=True)
        state = {"profile": maintenance.PROFILE, "port": maintenance.PORT}
        (maintenance.KIT / "headroom.json").write_text(json.dumps(state))
        manifest = {**state, "host": "127.0.0.1", "preset": "persistent-service", "runtime_kind": "python",
                    "supervisor_kind": "service", "scope": "provider", "targets": ["codex"],
                    "service_name": maintenance.SERVICE}
        exports = ""
        if adopting:
            (maintenance.KIT / "headroom.json").unlink()
            env = {"HEADROOM_PORT": "8787", "HEADROOM_HOST": "127.0.0.1", "HEADROOM_MODE": "cache",
                   "HEADROOM_BACKEND": "anthropic", "HEADROOM_TELEMETRY": "off"}
            manifest.update(backend="anthropic", anyllm_provider=None, region=None, proxy_mode="cache",
                            memory_enabled=False, telemetry_enabled=False, base_env=env,
                            tool_envs={"codex": {"OPENAI_BASE_URL": "http://127.0.0.1:8787/v1"}},
                            proxy_args=["--host", "127.0.0.1", "--port", "8787", "--mode", "cache", "--backend", "anthropic", "--no-telemetry"],
                            mutations=[{"target": "codex", "kind": "toml-block", "path": str(maintenance.HOME / ".codex/config.toml"), "data": {}}])
            exports = "".join("export " + key + "=" + value + "\n" for key, value in env.items())
        (maintenance.DEPLOY / "manifest.json").write_text(json.dumps(manifest))
        runner = str(maintenance.DEPLOY / "run-headroom.sh")
        Path(runner).write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + exports + "exec /owned/headroom install agent run --profile " + maintenance.PROFILE + "\n")
        path = maintenance.service_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        if sys.platform == "darwin":
            path.write_bytes(plistlib.dumps({"Label": maintenance.LABEL, "ProgramArguments": [runner], "KeepAlive": True, "RunAtLoad": True}))
        elif adopting:
            path.write_text("[Unit]\nDescription=Headroom (default)\nAfter=network-online.target\n\n"
                            "[Service]\nType=simple\nExecStart=" + runner + "\nRestart=on-failure\nRestartSec=5\n\n"
                            "[Install]\nWantedBy=default.target\n")
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

    def test_other_deployment_is_named_before_stopping_anything(self):
        self.add_mcp()
        deployment = maintenance.HOME / ".headroom/deploy/custom"
        deployment.mkdir(parents=True)
        manifest = deployment / "manifest.json"
        original = '{"profile":"default","port":8787}'
        manifest.write_text(original)
        with self.assertRaisesRegex(RuntimeError, "another Headroom deployment") as error:
            maintenance.pause(self.record)
        self.assertIn(str(deployment), str(error.exception))
        self.assertIn("Stopping its process alone", str(error.exception))
        self.assertEqual(self.events, [])
        self.assertIn(246, self.table)
        self.assertEqual(manifest.read_text(), original)
        self.assertFalse(self.record.exists())

    def test_standard_default_service_can_pause_and_resume_without_kit_record(self):
        self.seed_service(adopting=True)
        before = {path: path.read_bytes() for path in maintenance.HOME.rglob("*") if path.is_file()}
        maintenance.pause(self.record)
        self.assertFalse(self.active)
        saved = json.loads(self.record.read_text())
        self.assertEqual(saved["profile"], "default")
        self.assertTrue(saved["adopt_service"])
        self.assertEqual(before, {path: path.read_bytes() for path in before})
        self.assertFalse((maintenance.KIT / "headroom.json").exists())
        maintenance.resume(self.record)
        self.assertTrue(self.active)
        self.assertIn(("systemctl", "--user", "stop", "headroom-default"), self.events)
        self.assertIn(("systemctl", "--user", "start", "headroom-default"), self.events)

    def test_custom_default_runtime_is_preserved_before_service_commands(self):
        self.seed_service(adopting=True)
        path = maintenance.DEPLOY / "manifest.json"
        manifest = json.loads(path.read_text())
        manifest["base_env"]["CUSTOM_OPTION"] = "keep"
        path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(RuntimeError, "custom runtime/provider settings"):
            maintenance.pause(self.record)
        self.assertEqual(self.events, [])
        self.assertTrue(self.active)
        self.assertFalse(self.record.exists())

    def test_default_service_file_environment_and_hooks_are_preserved(self):
        for platform, setting in (("darwin", "EnvironmentVariables"), ("darwin", "WorkingDirectory"),
                                  ("linux", "Environment"), ("linux", "EnvironmentFile"), ("linux", "ExecStartPre")):
            with self.subTest(platform=platform, setting=setting), patch.object(sys, "platform", platform):
                self.seed_service(adopting=True)
                path = maintenance.service_path()
                if platform == "darwin":
                    definition = plistlib.loads(path.read_bytes())
                    definition[setting] = {"HEADROOM_CONFIG_DIR": "/custom/config"} if setting == "EnvironmentVariables" else "/custom"
                    path.write_bytes(plistlib.dumps(definition))
                else:
                    path.write_text(path.read_text().replace("[Service]\n", "[Service]\n" + setting + "=/custom\n"))
                before = path.read_bytes()
                with self.assertRaisesRegex(RuntimeError, "custom service settings"):
                    maintenance.pause(self.record)
                self.assertEqual(path.read_bytes(), before)
                self.assertEqual(self.events, [])
                self.assertTrue(self.active)
                self.assertFalse(self.record.exists())

    def test_loaded_default_environment_and_hooks_are_preserved(self):
        for platform, setting in (("darwin", "environment"), ("darwin", "inherited environment"),
                                  ("linux", "Environment"), ("linux", "EnvironmentFiles"), ("linux", "ExecStartPre")):
            with self.subTest(platform=platform, setting=setting), patch.object(sys, "platform", platform):
                self.seed_service(adopting=True)
                self.events.clear()
                def loaded_custom(args):
                    result = self.os_command(args)
                    extra = ("\n" + setting + " = {\nHEADROOM_CONFIG_DIR => /custom/config\n}\n" if platform == "darwin"
                             else "\n" + setting + "=/custom/config\n")
                    return subprocess.CompletedProcess(args, result.returncode, result.stdout + extra, result.stderr)
                with patch.object(maintenance, "command", side_effect=loaded_custom):
                    with self.assertRaisesRegex(RuntimeError, "loaded default.*custom runtime"):
                        maintenance.pause(self.record)
                self.assertTrue(self.active)
                self.assertFalse(self.record.exists())
                self.assertTrue(all(event[:2] == ("launchctl", "print") or event[:3] == ("systemctl", "--user", "show") for event in self.events))

    def test_default_loaded_platform_defaults_are_accepted(self):
        for platform in ("darwin", "linux"):
            with self.subTest(platform=platform), patch.object(sys, "platform", platform):
                self.seed_service(adopting=True)
                def loaded_defaults(args):
                    result = self.os_command(args)
                    extra = ("\ninherited environment = {\nSSH_AUTH_SOCK => /tmp/user-socket\n}\n"
                             "default environment = {\nPATH => /usr/bin:/bin\n}\n"
                             "environment = {\nOSLogRateLimit => 64\nXPC_SERVICE_NAME => com.headroom.default\n}\n"
                             if platform == "darwin" else "\nWorkingDirectory=!" + str(maintenance.HOME) + "\nEnvironment=\n")
                    return subprocess.CompletedProcess(args, result.returncode, result.stdout + extra, result.stderr)
                with patch.object(maintenance, "command", side_effect=loaded_defaults):
                    self.assertEqual(maintenance.inspect()[:3], (True, True, True))
                self.assertFalse(self.record.exists())

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
