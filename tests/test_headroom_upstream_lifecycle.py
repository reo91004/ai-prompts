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


def default_adoption(adapter, maintenance, database, artifacts):
    """Use upstream-generated default deployments, intercepting all OS work."""
    from headroom.install import planner, supervisors
    from headroom.install.state import save_manifest
    from headroom.providers.codex import install as provider
    results = []
    database_before = database.read_bytes()
    for system in ("darwin", "linux"):
        with patch.object(sys, "platform", system):
            adapter.STATE.unlink(missing_ok=True)
            adapter.select_profile("default")
            maintenance.select_profile("default")
            adapter.CONFIG.write_text('model = "user-model"\n[profiles.user]\nmodel_provider = "headroom"\n')
            deployment = planner.build_manifest(
                profile="default", preset="persistent-service", runtime_kind="python", scope="provider",
                provider_mode="manual", targets=["codex"], port=8787, backend="anthropic", anyllm_provider=None,
                region=None, proxy_mode="cache", memory_enabled=False, telemetry_enabled=False,
                image="ghcr.io/headroomlabs-ai/headroom:latest")
            with patch.object(provider, "retag_to_headroom"):
                deployment.mutations = [provider.apply_provider_scope(deployment)]
            deployment.artifacts = supervisors.render_runner_scripts(deployment)
            save_manifest(deployment)
            runner = adapter.DEPLOY / "run-headroom.sh"
            runner.write_text(runner.read_text().replace(str(adapter.KIT / "tooling/bin/headroom"), "/old/bin/headroom"))
            service = adapter.service_path()
            service.parent.mkdir(parents=True, exist_ok=True)
            _, definition = (supervisors._macos_launchd_plist(deployment, runner) if system == "darwin"
                             else supervisors._linux_service_unit(deployment, runner))
            service.write_text(definition)
            before = {p: p.read_bytes() for p in (adapter.CONFIG, database, runner, service, adapter.DEPLOY / "manifest.json")}
            state = {"active": True, "registered": True}
            calls = []

            def service_command(args, **kwargs):
                calls.append(args)
                text = ""
                if args[0] == "ps":
                    text = "42 Wed Sep 9 10:00:00 2026 /usr/bin/idle-fixture\n"
                elif args[:3] == ["systemctl", "--user", "show"]:
                    text = ("LoadState=loaded\nActiveState=" + ("active" if state["active"] else "inactive")
                            + "\nFragmentPath=" + str(service) + "\nExecStart={ path=" + str(runner)
                            + " ; argv[]=" + str(runner) + " ; }\n")
                elif args[:2] == ["launchctl", "print"] and len(args) == 3 and "/com.headroom." in args[2]:
                    if not state["registered"]:
                        return subprocess.CompletedProcess(args, 113, "", "Could not find service")
                    text = ("path = " + str(service) + "\nprogram = " + str(runner) + "\narguments = {\n"
                            + str(runner) + "\n}\nstate = " + ("running" if state["active"] else "waiting"))
                elif "bootout" in args or "stop" in args:
                    state["active"] = False
                    if "bootout" in args:
                        state["registered"] = False
                elif "kickstart" in args and not state["registered"]:
                    return subprocess.CompletedProcess(args, 113, "", "service is not registered")
                elif any(action in args for action in ("kickstart", "bootstrap", "restart", "start")):
                    state.update(active=True, registered=True)
                elif args not in (["launchctl", "print", maintenance.DOMAIN], ["systemctl", "--user", "show-environment"]):
                    raise AssertionError(args)
                return subprocess.CompletedProcess(args, 0, text, "")

            def headroom_status(*args, **kwargs):
                assert args == ("install", "status", "--profile", "default"), args
                assert state["active"]
                return subprocess.CompletedProcess(args, 0, "Status: running\nHealthy: yes\n")

            with patch("subprocess.run", side_effect=service_command), \
                    patch.object(adapter, "port_open", side_effect=lambda: state["active"]), \
                    patch.object(maintenance, "port_open", side_effect=lambda: state["active"]), \
                    patch.object(maintenance, "ready", side_effect=lambda: state["active"]), \
                    patch.object(adapter, "probe", return_value={"version": adapter.VERSION, "deployment": {"profile": "default", "preset": "persistent-service"}}), \
                    patch.object(adapter, "headroom", side_effect=headroom_status), \
                    patch.object(adapter, "restore_thread_routing", side_effect=forbidden):
                record = adapter.KIT / "default-maintenance.json"
                maintenance.pause(record)
                assert not state["active"]
                adapter.adopt_default(record)
                adapter.select_profile("research-agent-kit")
                with patch.object(sys, "argv", ["runtime.py", "install"]):
                    adapter.main()
                assert state["active"] and adapter.read_json(adapter.STATE)["profile"] == "default"
                assert sys.executable + " -m headroom.cli install agent run --profile default" in runner.read_text()
                assert all(p.read_bytes() == content for p, content in before.items() if p != runner)
                installed_runner = runner.read_bytes()
                adapter.install()
                assert runner.read_bytes() == installed_runner
                maintenance.select_profile("research-agent-kit")
                with patch.object(sys, "argv", ["maintenance.py", "stop-service"]):
                    maintenance.main()
                adapter.STATE.unlink()
                runner.write_bytes(before[runner])
                maintenance.resume(record)
                assert state["active"] and all(p.read_bytes() == content for p, content in before.items())
                results.append({"platform": system, "adopted_in_place": True, "repeat_reused": True,
                                "config_and_database_unchanged": True, "previous_service_resumed": True})
            (artifacts / (system + "-default-adoption-commands.json")).write_text(json.dumps(calls, indent=2))
            adapter.shutil.rmtree(adapter.DEPLOY)
            service.unlink()
    assert database.read_bytes() == database_before
    adapter.select_profile("research-agent-kit")
    maintenance.select_profile("research-agent-kit")
    return results


def mcp_registration(adapter):
    """Exercise real registrars on isolated TOML/JSON; no CLI or service runs."""
    from headroom.mcp_registry import any_succeeded, install_everywhere
    from headroom.mcp_registry.base import RegisterStatus
    from headroom.mcp_registry.codex import CodexRegistrar
    from headroom.mcp_registry.claude import ClaudeRegistrar
    registrars = [CodexRegistrar(home_dir=adapter.HOME), ClaudeRegistrar(home_dir=adapter.HOME, claude_cli=None)]
    (adapter.HOME / ".claude").mkdir(exist_ok=True)
    claude_config = adapter.HOME / ".claude.json"
    command = str(adapter.KIT / "tooling/bin/headroom")

    def seed(agent, env):
        entry = {"command": command, "args": ["mcp", "serve"], "env": env}
        if agent == "codex":
            path = adapter.CONFIG
            text = ('# preserve formatting\n[mcp_servers.headroom]\ncommand = ' + json.dumps(command)
                    + '\nargs = ["mcp", "serve"]\n[mcp_servers.headroom.env]\n'
                    + ''.join(key + ' = ' + json.dumps(value) + '\n' for key, value in env.items())
                    + '\n[profiles.user]\nmodel_provider = "headroom"\n')
        else:
            path = claude_config
            text = json.dumps({"user_setting": "keep", "mcpServers": {"headroom": {"type": "stdio", **entry}}}, indent=4)
        path.write_text(text)
        return path

    seed("codex", {"HEADROOM_PROXY_URL": adapter.BASE_URL})
    seed("claude", {})
    before = {path: path.read_bytes() for path in (adapter.CONFIG, claude_config)}
    baseline = install_everywhere(proxy_url=adapter.BASE_URL, registrars=registrars)
    assert baseline["codex"].status == RegisterStatus.MISMATCH
    assert baseline["claude"].status == RegisterStatus.ALREADY
    calls = []

    def register(*args):
        assert args[:3] == ("mcp", "install", "--agent"), args
        calls.append(args)
        result = install_everywhere(agents=[args[3]], registrars=registrars)
        if not any_succeeded(result):
            raise subprocess.CalledProcessError(1, args)

    with patch.object(adapter, "headroom", side_effect=register):
        for agent in ("codex", "claude"):
            adapter.install_mcp(agent)
        assert not calls and all(path.read_bytes() == data for path, data in before.items())
        for agent in ("codex", "claude"):
            for env in ({}, {"HEADROOM_PROXY_URL": adapter.BASE_URL}):
                path = seed(agent, env)
                original = path.read_bytes()
                adapter.install_mcp(agent)
                assert path.read_bytes() == original and not calls
        adapter.CONFIG.write_text('[features]\nuser_setting = true\n')
        claude_config.write_text('{"user_setting":"keep"}')
        for agent in ("codex", "claude"):
            adapter.install_mcp(agent)
        assert len(calls) == 2
        installed = {path: path.read_bytes() for path in (adapter.CONFIG, claude_config)}
        for agent in ("codex", "claude"):
            adapter.install_mcp(agent)
        assert len(calls) == 2 and all(path.read_bytes() == data for path, data in installed.items())
        for agent in ("codex", "claude"):
            for env in ({"HEADROOM_PROXY_URL": "http://127.0.0.1:9999"}, {"USER_SETTING": "keep"}):
                path = seed(agent, env)
                original = path.read_bytes()
                try:
                    adapter.install_mcp(agent)
                except subprocess.CalledProcessError:
                    pass
                else:
                    raise AssertionError("Custom MCP settings were accepted")
                assert path.read_bytes() == original
    return {"explicit_default_mismatch_reproduced": True, "equivalent_existing_bytes_preserved": True,
            "fresh_and_repeat_install": True, "custom_url_and_env_conflicts_preserved": True}


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
        maintenance_spec = importlib.util.spec_from_file_location("kit_headroom_maintenance", root / "headroom/maintenance.py")
        maintenance = importlib.util.module_from_spec(maintenance_spec)
        maintenance_spec.loader.exec_module(maintenance)
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
                if system == "darwin":
                    _, definition = supervisors._macos_launchd_plist(deployment, adapter.DEPLOY / "run-headroom.sh")
                else:
                    _, definition = supervisors._linux_service_unit(deployment, adapter.DEPLOY / "run-headroom.sh")
                service.write_text(definition)
                assert maintenance.owned_service()
                # A pidfile must not cause direct signaling, even during removal.
                (adapter.DEPLOY / "runner.pid").write_text("999999999\n")
                adapter.start_service()
                assert all(p.read_bytes() == contents for p, contents in original.items())
                if system == "darwin":
                    identity = f"gui/{os.getuid()}/com.headroom.{adapter.PROFILE}"
                    assert commands == [["launchctl", "kickstart", "-k", identity]], commands
                    commands.clear()
                    def after_bootout(command, **kwargs):
                        result = os_command(command, **kwargs)
                        if command[1] == "kickstart":
                            return subprocess.CompletedProcess(command, 113, "", "service is not registered")
                        return result
                    with patch("subprocess.run", side_effect=after_bootout):
                        adapter.start_service()
                    assert commands == [["launchctl", "kickstart", "-k", identity],
                                        ["launchctl", "bootstrap", f"gui/{os.getuid()}", str(service)]], commands
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
                    "maintenance_accepts_upstream_service_definition": True,
                    "start_after_bootout": system == "darwin",
                    "missing_manifest_cleanup": commands, "pid_signals": 0})
        assert len(probes) == 3, probes
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
        evidence["default_adoption"] = default_adoption(adapter, maintenance, database, artifacts)
        evidence["mcp_registration"] = mcp_registration(adapter)
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
