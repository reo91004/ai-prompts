"""Behavioral tests for ownership, health and session isolation (no OS services)."""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("kit_runtime", Path(__file__).resolve().parents[1] / "headroom/runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        home = Path(self.temp.name)
        for name, path in {
            "HOME": home, "KIT": home / ".universal-research-agent-kit",
            "STATE": home / ".universal-research-agent-kit/headroom.json",
            "DEPLOY": home / ".headroom/deploy/research-agent-kit",
            "CONFIG": home / ".codex/config.toml",
        }.items():
            self.enterContext(patch.object(runtime, name, path))
        runtime.KIT.mkdir()
        runtime.CONFIG.parent.mkdir()
        self.enterContext(patch.dict(os.environ, {"HOME": str(home)}, clear=True))
        self.calls = []
        self.running = False
        self.enterContext(patch.object(runtime, "headroom", self.headroom))
        self.enterContext(patch.object(runtime, "start_service", self.start_service))
        self.enterContext(patch.object(runtime, "remove_service", self.remove_service))
        self.enterContext(patch.object(runtime, "restore_thread_routing"))
        self.enterContext(patch.object(runtime, "codex_oauth", return_value=False))
        self.enterContext(patch.object(runtime, "probe", self.probe))
        self.enterContext(patch.object(runtime, "port_open", lambda: self.running))
        self.enterContext(patch.object(runtime.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)))
        runtime.CONFIG.write_text('model_provider = "openai"\nmodel = "user-model"\n[features]\nuser_flag = true\n')

    def headroom(self, *args, capture=False):
        self.calls.append(args)
        action = args[1]
        if action == "apply":
            runtime.DEPLOY.mkdir(parents=True)
            runtime.write_json(runtime.DEPLOY / "manifest.json", {
                "profile": runtime.PROFILE, "port": runtime.PORT, "host": "127.0.0.1",
                "preset": "persistent-service", "runtime_kind": "python",
                "supervisor_kind": "service", "scope": "provider", "targets": ["codex"],
            })
            (runtime.DEPLOY / "run-headroom.sh").write_text("exec " + shlex.quote(sys.executable) + " -m headroom.cli install agent run\n")
            runtime.service_path().parent.mkdir(parents=True, exist_ok=True)
            runtime.service_path().write_text("service fixture")
            original = runtime.CONFIG.read_text().replace('model_provider = "openai"\n', "")
            runtime.CONFIG.write_text(runtime.START + '\nmodel_provider = "headroom"\n'
                                      '[model_providers.headroom]\nbase_url = "' + runtime.BASE_URL + '/v1"\n'
                                      'supports_websockets = true\n' + runtime.END + '\n' + original)
            # Place user root keys before the managed provider table, as upstream does.
            runtime.CONFIG.write_text('model = "user-model"\n' + runtime.CONFIG.read_text().replace('model = "user-model"\n', ''))
            self.running = True
        elif action == "start":
            self.running = True
        elif action == "remove":
            self.running = False
            (runtime.DEPLOY / "manifest.json").unlink()
            runtime.service_path().unlink()
            text = runtime.CONFIG.read_text()
            begin, end = text.index(runtime.START), text.index(runtime.END) + len(runtime.END)
            runtime.CONFIG.write_text(text[:begin] + text[end:])
        status = "running" if self.running else "stopped"
        return subprocess.CompletedProcess(args, 0, f"Status:     {status}\nHealthy:    yes\n")

    def probe(self, endpoint):
        if not self.running:
            return None
        return {"version": runtime.VERSION, "deployment": {"profile": runtime.PROFILE, "preset": "persistent-service"}}

    def install(self):
        runtime.install()

    def start_service(self):
        self.calls.append(("service", "start"))
        self.running = True

    def remove_service(self):
        self.calls.append(("service", "remove"))
        self.running = False
        runtime.service_path().unlink(missing_ok=True)
        if runtime.DEPLOY.exists():
            runtime.shutil.rmtree(runtime.DEPLOY)

    def test_first_repeat_install_and_read_only_check(self):
        self.install()
        before = {p: p.read_bytes() for p in runtime.HOME.rglob("*") if p.is_file()}
        runtime.install()
        runtime.check()
        self.assertEqual(before, {p: p.read_bytes() for p in runtime.HOME.rglob("*") if p.is_file()})
        self.assertEqual(sum(call[1] == "apply" for call in self.calls), 1)
        self.assertIn(("--target", "codex"), list(zip(self.calls[0], self.calls[0][1:])))

    def test_reject_ephemeral_or_unrelated_listener_without_killing(self):
        self.running = True
        with self.assertRaisesRegex(RuntimeError, "occupied"):
            runtime.install()
        self.assertEqual(self.calls, [])

    def test_reject_user_owned_profile_even_when_stopped(self):
        other = runtime.HOME / ".headroom/deploy/user/manifest.json"
        runtime.write_json(other, {"port": runtime.PORT})
        with self.assertRaisesRegex(RuntimeError, "another Headroom profile"):
            runtime.install()
        self.assertEqual(self.calls, [])

    def test_stopped_service_with_healthy_wrong_proxy_is_not_success(self):
        self.install()
        self.running = False
        with patch.object(runtime, "probe", return_value={"deployment": {"profile": "other"}}):
            with self.assertRaisesRegex(RuntimeError, "not running and ready"):
                runtime.check()

    def test_stale_service_interpreter_fails(self):
        self.install()
        (runtime.DEPLOY / "run-headroom.sh").write_text("exec /some/other/python -m headroom.cli\n")
        with self.assertRaisesRegex(RuntimeError, "different Python"):
            runtime.check()
        runtime.remove()
        self.assertFalse(runtime.STATE.exists())

    def test_upstream_entrypoint_runner_uses_managed_python(self):
        self.install()
        target = runtime.KIT / "tooling/uv-tools/headroom-ai/bin/headroom"
        target.parent.mkdir(parents=True)
        target.write_text("#!" + sys.executable + "\n")
        entrypoint = runtime.KIT / "tooling/bin/headroom"
        entrypoint.parent.mkdir(parents=True)
        entrypoint.symlink_to(target)
        (runtime.DEPLOY / "run-headroom.sh").write_text("exec " + shlex.quote(str(entrypoint)) + " install agent run --profile " + runtime.PROFILE)
        runtime.check()
        target.write_text("#!/unrelated/python\n")
        with self.assertRaisesRegex(RuntimeError, "different Python"):
            runtime.check()

    def test_stopped_start_preserves_table_scoped_provider_settings(self):
        self.install()
        runtime.CONFIG.write_text(runtime.CONFIG.read_text() + '\n[profiles.saved]\nmodel_provider = "headroom"\nopenai_base_url = "http://127.0.0.1:9876/v1"\n')
        before = runtime.CONFIG.read_bytes()
        self.running = False
        runtime.ensure_running()
        self.assertEqual(before, runtime.CONFIG.read_bytes())
        self.assertIn(("service", "start"), self.calls)
        self.assertNotIn(("install", "start", "--profile", runtime.PROFILE), self.calls)

    def test_reinstall_after_login_updates_only_owned_auth_flag(self):
        self.install()
        runtime.CONFIG.write_text(runtime.CONFIG.read_text() + '\n[profiles.user]\nrequires_openai_auth = true\n')
        original = runtime.CONFIG.read_bytes()
        with patch.object(runtime, "codex_oauth", return_value=True):
            with self.assertRaisesRegex(RuntimeError, "authentication changed"):
                runtime.check()
            runtime.install()
            oauth = runtime.CONFIG.read_bytes()
            self.assertTrue(runtime.tomllib.loads(oauth.decode())["model_providers"]["headroom"]["requires_openai_auth"])
            runtime.install()
            self.assertEqual(oauth, runtime.CONFIG.read_bytes())
        runtime.install()
        self.assertEqual(original, runtime.CONFIG.read_bytes())
        self.assertEqual(sum(call[1] == "apply" for call in self.calls), 1)

    def test_failed_cleanup_retains_ownership_even_without_upstream_manifest(self):
        original = runtime.CONFIG.read_bytes()
        def fail_apply(*args, **kwargs):
            self.headroom(*args, **kwargs)
            (runtime.DEPLOY / "manifest.json").unlink()
            raise RuntimeError("upstream cleanup incomplete")
        with patch.object(runtime, "headroom", side_effect=fail_apply), \
                patch.object(runtime, "remove_service", side_effect=RuntimeError("cannot stop service")):
            with self.assertRaisesRegex(RuntimeError, "cannot stop"):
                runtime.install()
        self.assertTrue(runtime.STATE.exists())
        self.assertTrue(runtime.service_path().exists())
        self.assertTrue(self.running)
        self.assertEqual(original, runtime.CONFIG.read_bytes())
        runtime.remove()
        self.assertFalse(runtime.STATE.exists())
        self.assertFalse(self.running)

    def test_custom_provider_and_symlink_are_preserved(self):
        runtime.CONFIG.write_text('model_provider = "personal"\n')
        with self.assertRaisesRegex(RuntimeError, "custom Codex provider"):
            runtime.install()
        runtime.CONFIG.unlink()
        target = runtime.HOME / "target"
        target.write_text("private content")
        runtime.CONFIG.symlink_to(target)
        with self.assertRaisesRegex(RuntimeError, "symlinked"):
            runtime.install()
        self.assertEqual(target.read_text(), "private content")

    def test_readiness_failure_removes_new_runtime(self):
        with patch.object(runtime, "probe", return_value=None):
            with self.assertRaises(RuntimeError):
                runtime.install()
        self.assertFalse(runtime.STATE.exists())
        self.assertFalse(runtime.service_path().exists())
        self.assertTrue(any(call[1] == "remove" for call in self.calls))

    def test_remove_restores_original_provider_and_later_user_edits(self):
        self.install()
        runtime.CONFIG.write_text(runtime.CONFIG.read_text() + '\n[user]\nnew = "keep me"\n')
        runtime.remove()
        config = runtime.tomllib.loads(runtime.CONFIG.read_text())
        self.assertEqual(config["model_provider"], "openai")
        self.assertEqual(config["model"], "user-model")
        self.assertEqual(config["user"]["new"], "keep me")
        self.assertFalse(runtime.STATE.exists())

    def test_same_version_missing_proxy_import_is_not_accepted(self):
        with patch.object(runtime.importlib.metadata, "version", return_value=runtime.VERSION), \
                patch.object(runtime.importlib, "import_module", side_effect=ImportError("No module named fastapi")):
            with self.assertRaisesRegex(ImportError, "fastapi"):
                runtime.dependencies(runtime.VERSION)

    def test_session_routing_preserves_home_settings_and_arguments(self):
        self.install()
        before = runtime.CONFIG.read_bytes()
        captured = []
        with patch.object(runtime.shutil, "which", side_effect=lambda tool: "/bin/" + tool), \
                patch.object(runtime.os, "execvpe", side_effect=lambda binary, args, env: captured.append((args, env.copy()))):
            with patch.dict(os.environ, {"HEADROOM_PROJECT": 'project "A"'}):
                runtime.launch("codex", ["exec", "--", "literal --rc"])
            with patch.dict(os.environ, {"HEADROOM_PROJECT": "project-B"}):
                runtime.launch("codex", ["resume"])
            runtime.launch("claude", ["--settings", '{"env":{"KEEP":"yes"},"model":"user"}', "-p", "hello"])
        self.assertEqual(runtime.CONFIG.read_bytes(), before)
        self.assertEqual(captured[0][0][-3:], ["exec", "--", "literal --rc"])
        self.assertIn('project \\"A\\"', captured[0][0][2])
        self.assertEqual(captured[1][1]["HEADROOM_PROJECT"], "project-B")
        settings = json.loads(captured[2][0][2])
        self.assertEqual(settings["env"]["KEEP"], "yes")
        self.assertEqual(settings["model"], "user")
        self.assertEqual(settings["env"]["ANTHROPIC_BASE_URL"], runtime.BASE_URL)

    def test_managed_cli_precedes_path_and_broken_link_does_not_fallback(self):
        self.install()
        managed_dir = runtime.KIT / "cli/bin"
        managed_dir.mkdir(parents=True)
        for tool in ("codex", "claude"):
            with self.subTest(tool=tool):
                managed = managed_dir / tool
                target = runtime.KIT / (tool + "-executable")
                target.write_text("#!/bin/sh\nexit 0\n")
                target.chmod(0o755)
                managed.symlink_to(target)
                with patch.object(runtime.shutil, "which", side_effect=AssertionError("PATH fallback")), \
                        patch.object(runtime.os, "execvpe") as execute:
                    runtime.launch(tool, ["--version"])
                    self.assertEqual(execute.call_args.args[0], str(managed))
                    self.assertEqual(execute.call_args.args[1][0], str(managed))
                    execute.reset_mock()
                    target.unlink()
                    with self.assertRaisesRegex(RuntimeError, "Managed .* missing or not executable"):
                        runtime.launch(tool, ["--version"])
                    execute.assert_not_called()

    def test_running_stale_runner_install_fails_without_config_mutation(self):
        self.install()
        runner = runtime.DEPLOY / "run-headroom.sh"
        runner.write_text("exec /old/python -m headroom.cli\n")
        before = {p: p.read_bytes() for p in runtime.HOME.rglob("*") if p.is_file()}
        with self.assertRaisesRegex(RuntimeError, "running with a stale runner"):
            runtime.install()
        self.assertEqual(before, {p: p.read_bytes() for p in runtime.HOME.rglob("*") if p.is_file()})
        self.assertEqual(sum(call[1] == "apply" for call in self.calls), 1)

    def test_claude_remote_detects_settings_env_without_editing(self):
        path = runtime.HOME / ".claude/settings.json"
        runtime.write_json(path, {"env": {"ANTHROPIC_BASE_URL": runtime.BASE_URL}, "user": "keep"})
        before = path.read_bytes()
        with self.assertRaisesRegex(RuntimeError, "direct Anthropic"):
            runtime.claude_direct_check()
        self.assertEqual(path.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
