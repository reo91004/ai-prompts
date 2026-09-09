#!/usr/bin/env python3
"""Pause kit Headroom for installation using only Python's standard library."""
import configparser
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import signal
import socket
import subprocess
import sys
import time
import urllib.request

HOME = Path.home()
KIT = HOME / ".universal-research-agent-kit"
PROFILE = "research-agent-kit"
SERVICE = "headroom-" + PROFILE
LABEL = "com.headroom." + PROFILE
DOMAIN = "gui/" + str(os.getuid())
DEPLOY = HOME / ".headroom/deploy" / PROFILE
PORT = 8787
STOP_TIMEOUT = 20


def fail(message):
    raise RuntimeError(message)


def select_profile(profile):
    global PROFILE, SERVICE, LABEL, DEPLOY
    if profile not in ("research-agent-kit", "default"):
        fail("Unsupported kit Headroom profile; its service was preserved.")
    PROFILE = profile
    SERVICE = "headroom-" + profile
    LABEL = "com.headroom." + profile
    DEPLOY = HOME / ".headroom/deploy" / profile


def safe_path(path):
    for parent in (path, *path.parents):
        if parent == HOME.parent:
            break
        if parent.is_symlink():
            fail("Refusing a symlinked maintenance path: " + str(parent))


def command(args):
    return subprocess.run(args, capture_output=True, text=True, timeout=30,
                          env={**os.environ, "LC_ALL": "C"})


def processes():
    result = command(["ps", "-ww", "-u", str(os.getuid()), "-o", "pid=", "-o", "lstart=", "-o", "args="])
    if result.returncode or not result.stdout.strip():
        fail("Cannot inspect processes; nothing was cleared for replacement.")
    found = {}
    for line in result.stdout.splitlines():
        fields = line.split(None, 6)
        if len(fields) != 7 or not fields[0].isdigit():
            fail("Invalid process inspection; nothing was cleared for replacement.")
        found[int(fields[0])] = (" ".join(fields[1:6]), fields[6])
    return found


def owned_mcp(arguments):
    # Match complete known invocation prefixes, including HOME with spaces.
    # Never interpret -c source, arbitrary Python jobs, or external Headroom.
    for root in {KIT / "tooling", KIT.resolve() / "tooling"}:
        entries = [root / "bin/headroom", root / "uv-tools/headroom-ai/bin/headroom",
                   root / "python-venv/bin/headroom"]
        interpreters = [directory / name
                        for directory in (root / "uv-tools/headroom-ai/bin", root / "python-venv/bin")
                        for name in ("python", "python3", "python3.13", "Python")]
        interpreters += list((root / "python").glob("cpython-*/bin/python3*"))
        prefixes = [(str(entry), [entry.parent]) for entry in entries]
        prefixes += [(str(python) + " " + str(entry), [python.parent, entry.parent])
                     for python in interpreters for entry in entries]
        prefixes += [(str(python) + " -m headroom.cli", [python.parent]) for python in interpreters]
        for prefix, directories in prefixes:
            target = prefix + " mcp serve"
            if arguments == target or arguments.startswith(target + " "):
                # Directory aliases can lead to a separate user environment.
                # Venv interpreter and uv entrypoint symlinks remain valid.
                safe_path(KIT / "tooling")
                for directory in directories:
                    safe_path(directory)
                return True
    return False


def service_path():
    if sys.platform == "darwin":
        return HOME / "Library/LaunchAgents" / (LABEL + ".plist")
    if sys.platform.startswith("linux"):
        return HOME / ".config/systemd/user" / (SERVICE + ".service")
    fail("Automatic Headroom maintenance supports macOS and Linux.")


def owned_service():
    state = KIT / "headroom.json"
    for path in (state, DEPLOY, service_path()):
        safe_path(path)
    adopting = not state.exists() and PROFILE == "default"
    if not state.exists() and not adopting:
        if DEPLOY.exists() or service_path().exists():
            fail("The Headroom service has no kit ownership record; it was preserved.")
        return False
    if state.exists() and json.loads(state.read_text()).get("profile") != PROFILE:
        fail("The Headroom ownership record does not identify the kit service.")
    expected = {"profile": PROFILE, "port": PORT, "host": "127.0.0.1",
                "preset": "persistent-service", "runtime_kind": "python",
                "supervisor_kind": "service", "scope": "provider", "targets": ["codex"],
                "service_name": SERVICE}
    manifest_path = DEPLOY / "manifest.json"
    safe_path(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    if any(manifest.get(key) != value for key, value in expected.items()):
        fail("The Headroom deployment was customized; automatic service stop was refused.")
    if adopting:
        expected_env = {"HEADROOM_PORT": str(PORT), "HEADROOM_HOST": "127.0.0.1", "HEADROOM_MODE": "cache",
                        "HEADROOM_BACKEND": "anthropic", "HEADROOM_TELEMETRY": "off"}
        standard = {"backend": "anthropic", "anyllm_provider": None, "region": None,
                    "proxy_mode": "cache", "memory_enabled": False, "telemetry_enabled": False,
                    "base_env": expected_env, "tool_envs": {"codex": {"OPENAI_BASE_URL": "http://127.0.0.1:8787/v1"}},
                    "proxy_args": ["--host", "127.0.0.1", "--port", "8787", "--mode", "cache", "--backend", "anthropic", "--no-telemetry"],
                    "mutations": [{"target": "codex", "kind": "toml-block", "path": str(HOME / ".codex/config.toml"), "data": {}}]}
        if any(manifest.get(key) != value for key, value in standard.items()):
            fail("The default Headroom deployment has custom runtime/provider settings. "
                 "Preserved " + str(manifest_path) + "; automatic adoption requires the standard local Codex deployment.")
    runner = str(DEPLOY / "run-headroom.sh")
    safe_path(Path(runner))
    lines = Path(runner).read_text().splitlines()
    if len(lines) < 3 or lines[:2] != ["#!/usr/bin/env bash", "set -euo pipefail"]:
        fail("The Headroom runner was customized; automatic service stop was refused.")
    exports = {}
    for line in lines[2:-1]:
        assignment = re.fullmatch(r"export ([A-Za-z_][A-Za-z0-9_]*)=(.*)", line)
        values = shlex.split(assignment[2]) if assignment else []
        if len(values) != 1 or line != "export " + assignment[1] + "=" + shlex.quote(values[0]):
            fail("The Headroom runner was customized; automatic service stop was refused.")
        if assignment[1] in exports:
            fail("The Headroom runner has duplicate exports; automatic service stop was refused.")
        exports[assignment[1]] = values[0]
    if adopting and exports != expected_env:
        fail("The default Headroom runner has custom environment settings; it was preserved.")
    invocation = shlex.split(lines[-1])
    prefix = invocation[1:-5]
    module = (len(prefix) == 3 and re.fullmatch(r"[Pp]ython[0-9.]*", Path(prefix[0]).name)
              and prefix[1:] == ["-m", "headroom.cli"])
    executable = len(prefix) == 1 and Path(prefix[0]).name == "headroom"
    if (invocation[:1] != ["exec"] or invocation[-5:] != ["install", "agent", "run", "--profile", PROFILE]
            or not (module or executable) or lines[-1] != " ".join(shlex.quote(arg) for arg in invocation)):
        fail("The Headroom runner does not execute the kit profile; automatic service stop was refused.")
    if sys.platform == "darwin":
        with service_path().open("rb") as stream:
            definition = plistlib.load(stream)
        if (definition.get("Label") != LABEL or definition.get("ProgramArguments") != [runner]
                or definition.get("Program", runner) != runner):
            fail("The launchd definition does not run the kit runner; it was preserved.")
        if adopting and definition != {"Label": LABEL, "ProgramArguments": [runner], "RunAtLoad": True, "KeepAlive": True}:
            fail("The default launchd definition has custom service settings; it was preserved.")
    else:
        definition = configparser.ConfigParser(interpolation=None)
        definition.read_string(service_path().read_text())
        service = definition["Service"]
        if service.get("ExecStart") != runner or any(key in service for key in ("ExecStop", "ExecStopPost")):
            fail("The systemd definition was customized; automatic service stop was refused.")
        if adopting:
            standard_unit = {"Unit": {"description": "Headroom (default)", "after": "network-online.target"},
                             "Service": {"type": "simple", "execstart": runner, "restart": "on-failure", "restartsec": "5"},
                             "Install": {"wantedby": "default.target"}}
            if definition.defaults() or {name: dict(definition[name]) for name in definition.sections()} != standard_unit:
                fail("The default systemd definition has custom service settings; it was preserved.")
    return True


def service_state():
    """Return registration and activity, checking the loaded service identity."""
    runner = str(DEPLOY / "run-headroom.sh")
    adopting = PROFILE == "default" and not (KIT / "headroom.json").exists()
    if sys.platform == "darwin":
        result = command(["launchctl", "print", DOMAIN + "/" + LABEL])
        if result.returncode in (3, 113) and "Could not find service" in result.stderr:
            return False, False
        if result.returncode:
            fail("Cannot inspect the kit launchd job; service stop was refused.")
        fields = dict(re.findall(r"^\s*(path|program|state) = (.*?)\s*$", result.stdout, re.M))
        arguments = re.search(r"^\s*arguments = \{\s*\n(.*?)^\s*\}", result.stdout, re.M | re.S)
        loaded_args = [line.strip() for line in arguments[1].splitlines() if line.strip()] if arguments else []
        if fields.get("path") != str(service_path()) or fields.get("program") != runner or loaded_args != [runner]:
            fail("The loaded launchd job does not match the kit runner; it was preserved.")
        if adopting:
            for kind, block in re.findall(r"^\s*(inherited environment|default environment|environment) = \{\s*\n(.*?)^\s*\}", result.stdout, re.M | re.S):
                for line in block.splitlines():
                    if not line.strip():
                        continue
                    key, separator, value = line.strip().partition(" => ")
                    injected = (key == "XPC_SERVICE_NAME" and value == LABEL) or (key == "OSLogRateLimit" and value.isdigit())
                    if (not separator or (kind == "environment" and not injected)
                            or key.startswith(("HEADROOM_", "PYTHON", "DYLD_")) or key == "LD_PRELOAD"):
                        fail("The loaded default launchd job has custom runtime environment; it was preserved.")
        return True, fields.get("state") in ("running", "spawn scheduled")
    properties = ["LoadState", "ActiveState", "FragmentPath", "ExecStart", "ExecStop", "ExecStopPost", "DropInPaths"]
    custom_properties = ["Environment", "EnvironmentFiles", "PassEnvironment", "UnsetEnvironment",
                         "ExecStartPre", "ExecStartPost", "ExecCondition", "ExecReload", "RootDirectory", "RootImage", "PAMName"]
    if adopting:
        properties += custom_properties + ["WorkingDirectory"]
    result = command(["systemctl", "--user", "show", SERVICE, *[arg for name in properties for arg in ("-p", name)]])
    if result.returncode:
        fail("Cannot inspect the kit systemd service; service stop was refused.")
    fields = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    if fields.get("LoadState") == "not-found":
        return False, False
    if (fields.get("LoadState") != "loaded" or fields.get("FragmentPath") != str(service_path())
            or "path=" + runner + " ;" not in fields.get("ExecStart", "")
            or "argv[]=" + runner + " ;" not in fields.get("ExecStart", "")
            or any(fields.get(key) for key in ("ExecStop", "ExecStopPost", "DropInPaths"))):
        fail("The loaded systemd service does not match the kit runner; it was preserved.")
    if adopting and (any(fields.get(key) for key in custom_properties)
                     or fields.get("WorkingDirectory", "") not in ("", str(HOME), "!" + str(HOME), "-" + str(HOME))):
        fail("The loaded default systemd service has custom runtime settings; it was preserved.")
    return True, fields.get("ActiveState") not in ("inactive", "failed")


def port_open():
    try:
        with socket.create_connection(("127.0.0.1", PORT), timeout=0.2):
            return True
    except OSError:
        return False


def inspect():
    for name, expected in (("HEADROOM_WORKSPACE_DIR", HOME / ".headroom"),
                           ("HEADROOM_CONFIG_DIR", HOME / ".headroom/config")):
        if os.environ.get(name) and Path(os.environ[name]).expanduser() != expected:
            fail(name + " points outside the kit paths; no process was stopped.")
    state = KIT / "headroom.json"
    safe_path(state)
    if state.exists():
        select_profile(json.loads(state.read_text()).get("profile"))
    elif (HOME / ".headroom/deploy/default/manifest.json").exists():
        select_profile("default")
    else:
        select_profile("research-agent-kit")
    for path in sorted((HOME / ".headroom/deploy").glob("*/manifest.json")):
        if path.parent != DEPLOY and json.loads(path.read_text()).get("port") == PORT:
            fail("Port " + str(PORT) + " is reserved by another Headroom deployment: "
                 + str(path.parent) + ". Back up its configuration and use its original installer "
                 "to remove or relocate that profile before retrying. Stopping its process alone "
                 "leaves the conflicting deployment record. No process was stopped.")
    owned = owned_service()
    registered, active = service_state() if owned else (False, False)
    mcps = {pid: identity for pid, identity in processes().items() if owned_mcp(identity[1])}
    if not owned and not mcps:
        fail("No safely identifiable kit service or MCP server can be stopped. Close the reported process with its owning application.")
    return owned, registered, active, mcps


def stop_service():
    if not owned_service():
        return
    registered, _ = service_state()
    if registered:
        args = (["launchctl", "bootout", DOMAIN + "/" + LABEL] if sys.platform == "darwin"
                else ["systemctl", "--user", "stop", SERVICE])
        if command(args).returncode:
            fail("The kit service manager could not stop Headroom; its environment was preserved.")
    deadline = time.monotonic() + STOP_TIMEOUT
    while time.monotonic() < deadline:
        if not service_state()[1] and not port_open():
            return
        time.sleep(0.2)
    fail("Headroom did not stop in time; its environment was preserved.")


def pause(record):
    _, _, active, mcps = inspect()
    record = Path(record)
    safe_path(record)
    record.write_text(json.dumps({"profile": PROFILE, "resume_service": active,
                                  "adopt_service": PROFILE == "default" and not (KIT / "headroom.json").exists(),
                                  "mcp_pids": sorted(mcps)}) + "\n")
    record.chmod(0o600)
    stop_service()
    for pid, identity in mcps.items():
        # Recheck start time and complete command immediately before SIGTERM.
        # ps snapshots cannot atomically exclude PID reuse; never use pidfiles.
        if processes().get(pid) == identity:
            try:
                os.kill(pid, signal.SIGTERM)
                print("Requested normal shutdown of kit Headroom MCP (PID " + str(pid) + ").")
            except ProcessLookupError:
                pass
    deadline = time.monotonic() + STOP_TIMEOUT
    while time.monotonic() < deadline:
        current = processes()
        if not any(current.get(pid) == identity for pid, identity in mcps.items()):
            if any(owned_mcp(identity[1]) for identity in current.values()):
                fail("A client restarted Headroom MCP during installation. Close that client and rerun; the environment was preserved.")
            return
        time.sleep(0.2)
    fail("Headroom MCP did not exit after SIGTERM. Close its client and rerun; no environment replacement was allowed.")


def ready():
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open("http://127.0.0.1:8787/health", timeout=1) as response:
            health = json.load(response)
        with opener.open("http://127.0.0.1:8787/readyz", timeout=1):
            return health.get("deployment", {}).get("profile") == PROFILE
    except (OSError, ValueError):
        return False


def resume(record):
    saved = json.loads(Path(record).read_text())
    select_profile(saved.get("profile"))
    if not saved.get("resume_service"):
        return
    if not owned_service():
        fail("The previous kit service is missing; automatic recovery could not resume it.")
    registered, active = service_state()
    if not active:
        if sys.platform == "darwin":
            if registered:
                result = command(["launchctl", "kickstart", "-k", DOMAIN + "/" + LABEL])
            else:
                result = None
            if result is None or result.returncode:
                for _ in range(30):
                    result = command(["launchctl", "bootstrap", DOMAIN, str(service_path())])
                    if not result.returncode:
                        break
                    time.sleep(0.5)
        else:
            result = command(["systemctl", "--user", "start", SERVICE])
        if result.returncode:
            fail("The previous Headroom service could not be resumed; its files and recovery record were preserved.")
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if ready():
            print("Resumed the previous kit Headroom service.")
            return
        time.sleep(0.2)
    fail("The previous Headroom service did not become ready; inspect its service log.")


def main():
    action, *args = sys.argv[1:]
    state = KIT / "headroom.json"
    if action == "stop-service" and state.exists():
        safe_path(state)
        select_profile(json.loads(state.read_text()).get("profile"))
    if action == "probe":
        if sys.version_info < (3, 8):
            fail("Python 3.8+ is required for maintenance.")
    elif action == "inspect":
        inspect()
    elif action == "pause":
        pause(args[0])
    elif action == "profile":
        safe_path(Path(args[0]))
        select_profile(json.loads(Path(args[0]).read_text()).get("profile"))
        print(PROFILE)
    elif action == "stop-service":
        stop_service()
    elif action == "resume":
        resume(args[0])
    else:
        fail("Unknown maintenance action: " + action)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, configparser.Error, subprocess.SubprocessError) as exc:
        print("Headroom maintenance: " + str(exc), file=sys.stderr)
        sys.exit(1)
