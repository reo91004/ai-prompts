#!/usr/bin/env python3
"""Real Headroom 0.34.0 lifecycle contract with OS calls intercepted.

Run with Headroom's Python, optionally --runtime /path/to/headroom/runtime.py.
Upstream manifest, runner and supervisor implementations are exercised. Only
service-manager subprocess results and readiness/port probes are simulated.
No real service, account, listener or user configuration is accessed.
"""
import argparse
from contextlib import ExitStack
import hashlib
import importlib.metadata
import importlib.util
import json
import os
from pathlib import Path
import platform
import socket
import sqlite3
import subprocess
import sys
import tempfile
from unittest.mock import patch


def forbidden(*args, **kwargs):
    raise AssertionError(f"Unexpected process execution or PID signal: {args}")


def closed_port(*args, **kwargs):
    raise ConnectionRefusedError("Simulated closed port; no socket created")


def smoke(runtime_path):
    assert importlib.metadata.version("headroom-ai") == "0.34.0"
    root = Path(__file__).resolve().parents[1]
    (root / ".agent_tmp").mkdir(exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix="headroom-lifecycle-", dir=root / ".agent_tmp"))
    print(f"Artifacts: {artifacts}", flush=True)
    home = artifacts / "home"
    home.mkdir()
    env = {"HOME": str(home), "CODEX_HOME": str(home / ".codex"),
           "PATH": str(home / ".universal-research-agent-kit/tooling/bin"),
           "HEADROOM_TELEMETRY": "off", "HEADROOM_UPDATE_CHECK": "off"}
    evidence = {"scope": "real upstream lifecycle implementation; simulated OS services and probes",
                "python": sys.version, "platform": platform.platform(), "seed": None,
                "headroom_version": importlib.metadata.version("headroom-ai"), "environment": env,
                "runtime": str(runtime_path),
                "runtime_sha256": hashlib.sha256(runtime_path.read_bytes()).hexdigest(),
                "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "cases": []}
    (artifacts / "run.json").write_text(json.dumps(evidence, indent=2))
    with patch.dict(os.environ, env, clear=True), ExitStack() as stack:
        stack.enter_context(patch("subprocess.Popen", side_effect=forbidden))
        stack.enter_context(patch("os.kill", side_effect=forbidden))
        stack.enter_context(patch("os.killpg", side_effect=forbidden))
        stack.enter_context(patch("socket.create_connection", side_effect=closed_port))
        spec = importlib.util.spec_from_file_location("kit_headroom_runtime", runtime_path)
        adapter = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(adapter)
        from headroom.install.models import DeploymentManifest
        from headroom.install.state import save_manifest
        from headroom.install import runtime as upstream_runtime, supervisors

        entrypoint = adapter.KIT / "tooling/bin/headroom"
        managed = adapter.KIT / "tooling/uv-tools/headroom-ai/bin/headroom"
        managed.parent.mkdir(parents=True)
        entrypoint.parent.mkdir(parents=True)
        managed.write_text("#!" + sys.executable + "\nraise SystemExit('synthetic entrypoint must not execute')\n")
        managed.chmod(0o755)
        entrypoint.symlink_to(managed)
        adapter.CONFIG.parent.mkdir(parents=True)
        adapter.CONFIG.write_text('model_provider = "headroom"\n# unrelated synthetic configuration\n'
                                  '[model_providers.headroom]\nname = "Headroom"\n'
                                  'base_url = "http://127.0.0.1:8787/v1"\nwire_api = "responses"\n')
        database = adapter.CONFIG.parent / "state_5.sqlite"
        with sqlite3.connect(database) as connection:
            connection.execute("CREATE TABLE sentinel (value TEXT)")
            connection.execute("INSERT INTO sentinel VALUES ('preserve synthetic database')")
        original = {p: p.read_bytes() for p in (adapter.CONFIG, database)}
        probes = []

        def ready(url):
            probes.append(url)
            assert url == adapter.BASE_URL + "/readyz", url
            return True

        stack.enter_context(patch.object(upstream_runtime, "probe_ready", side_effect=ready))
        for system in ("darwin", "linux"):
            commands = []

            def os_command(command, **kwargs):
                commands.append(command)
                with (artifacts / "os-commands.jsonl").open("a") as stream:
                    stream.write(json.dumps({"platform": system, "command": command}) + "\n")
                assert command[0] in ("launchctl", "systemctl"), command
                return subprocess.CompletedProcess(command, 0, "loaded\n" if "show" in command else "", "")

            with patch.object(sys, "platform", system), patch("subprocess.run", side_effect=os_command):
                deployment = DeploymentManifest(
                    profile=adapter.PROFILE, preset="persistent-service", runtime_kind="python",
                    supervisor_kind="service", scope="provider", provider_mode="manual", targets=["codex"],
                    port=adapter.PORT, host="127.0.0.1", backend="anthropic",
                    service_name="headroom-" + adapter.PROFILE, telemetry_enabled=False)
                deployment.artifacts = supervisors.render_runner_scripts(deployment)
                save_manifest(deployment)
                runner = (adapter.DEPLOY / "run-headroom.sh").read_text()
                (artifacts / f"{system}-run-headroom.sh").write_text(runner)
                assert str(entrypoint) + " install agent run" in runner, runner
                assert adapter.manifest()["profile"] == adapter.PROFILE
                valid_entrypoint = managed.read_text()
                managed.write_text("#!/wrong/python\nraise SystemExit(1)\n")
                try:
                    adapter.manifest()
                except RuntimeError as error:
                    assert "different Python" in str(error), error
                else:
                    raise AssertionError("Wrong interpreter was accepted")
                adapter.STATE.parent.mkdir(parents=True, exist_ok=True)
                adapter.write_json(adapter.STATE, {"profile": adapter.PROFILE, "python": "/old/python"})
                identity_before = {p: p.read_bytes() for p in (adapter.STATE, adapter.DEPLOY / "manifest.json")}
                stale_runner = (adapter.DEPLOY / "run-headroom.sh").read_bytes()
                with patch.object(adapter, "port_open", return_value=True):
                    try:
                        adapter.repair_runner()
                    except RuntimeError as error:
                        assert "running with a stale runner" in str(error), error
                    else:
                        raise AssertionError("Running stale deployment was silently changed")
                assert (adapter.DEPLOY / "run-headroom.sh").read_bytes() == stale_runner
                adapter.repair_runner()
                repaired = (adapter.DEPLOY / "run-headroom.sh").read_text()
                assert sys.executable + " -m headroom.cli install agent run" in repaired, repaired
                (artifacts / f"{system}-repaired-run-headroom.sh").write_text(repaired)
                assert all(p.read_bytes() == value for p, value in identity_before.items())
                adapter.manifest()
                managed.write_text(valid_entrypoint)
                service = adapter.service_path()
                service.parent.mkdir(parents=True, exist_ok=True)
                service.write_text("synthetic service artifact; never installed\n")
                # A pidfile must not cause direct signaling, even during removal.
                (adapter.DEPLOY / "runner.pid").write_text("999999999\n")
                adapter.start_service()
                assert all(p.read_bytes() == contents for p, contents in original.items())
                if system == "darwin":
                    identity = f"gui/{os.getuid()}/com.headroom.{adapter.PROFILE}"
                    assert commands == [["launchctl", "kickstart", "-k", identity]], commands
                else:
                    identity = "headroom-" + adapter.PROFILE
                    assert commands == [["systemctl", "--user", "restart", identity]], commands
                adapter.remove_service()
                assert not service.exists() and not adapter.DEPLOY.exists()
                # A failed upstream cleanup can leave a registered job without
                # either its manifest or local service file. Recover by identity.
                commands.clear()
                adapter.remove_service()
                if system == "darwin":
                    expected = [["launchctl", "bootout", identity]] * 2
                else:
                    expected = [["systemctl", "--user", "show", identity, "-p", "LoadState", "--value"],
                                ["systemctl", "--user", "stop", identity],
                                ["systemctl", "--user", "disable", "--now", identity],
                                ["systemctl", "--user", "daemon-reload"]]
                assert commands == expected, commands
                assert all(p.read_bytes() == contents for p, contents in original.items())
                evidence["cases"].append({"platform": system, "generated_runner_accepted": True,
                    "wrong_interpreter_rejected": True, "stopped_runner_repaired": True,
                    "state_and_manifest_unchanged": True, "running_stale_repair_refused": True,
                    "config_and_sqlite_unchanged": True,
                    "missing_manifest_cleanup": commands, "pid_signals": 0})
        assert len(probes) == 2, probes
        # Exercise the real upstream auth detector against synthetic metadata.
        # No account token or keyring is used, and login status cannot execute.
        auth = adapter.CONFIG.parent / "auth.json"
        owned = (adapter.START + "\n" + adapter.CONFIG.read_text() + adapter.END
                 + '\n[profiles.user]\nrequires_openai_auth = true\n')
        adapter.CONFIG.write_text(owned)
        assert adapter.codex_oauth() is False
        adapter.sync_codex_auth()
        assert adapter.CONFIG.read_text() == owned
        auth.write_text('{"auth_mode":"chatgpt"}')
        assert adapter.codex_oauth() is True
        adapter.sync_codex_auth()
        oauth = adapter.CONFIG.read_text()
        assert adapter.tomllib.loads(oauth)["model_providers"]["headroom"]["requires_openai_auth"] is True
        adapter.sync_codex_auth()
        assert adapter.CONFIG.read_text() == oauth
        auth.write_text('{"auth_mode":"apikey"}')
        adapter.sync_codex_auth()
        assert adapter.CONFIG.read_text() == owned
        assert database.read_bytes() == original[database]
        evidence["auth_transition"] = "logged-out -> OAuth -> API-key: owned field only, repeat unchanged"
        evidence["readiness_probes"] = probes
        evidence["status"] = "passed"
        (artifacts / "summary.json").write_text(json.dumps(evidence, indent=2))
        print(json.dumps({"status": "passed", "platforms": [c["platform"] for c in evidence["cases"]],
                          "scope": evidence["scope"]}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path,
                        default=Path(__file__).resolve().parents[1] / "headroom/runtime.py")
    smoke(parser.parse_args().runtime.resolve())
