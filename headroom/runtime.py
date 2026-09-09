#!/usr/bin/env python3
"""Host-local Headroom lifecycle and process-local agent routing.

Run with the kit's Headroom interpreter. OS services and provider blocks are
created by Headroom 0.34.0; this adapter checks ownership and limits provider
removal to its owned block while preserving the prior root provider settings.
"""

import importlib
import importlib.metadata
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import socket
import subprocess
import sys
import time
import tomllib
import urllib.error
import urllib.request


PROFILE = "research-agent-kit"
PORT = 8787
BASE_URL = f"http://127.0.0.1:{PORT}"
VERSION = "0.34.0"
HOME = Path.home()
KIT = HOME / ".universal-research-agent-kit"
STATE = KIT / "headroom.json"
DEPLOY = HOME / ".headroom/deploy" / PROFILE
CONFIG = HOME / ".codex/config.toml"
START = "# --- Headroom persistent provider ---"
END = "# --- end Headroom persistent provider ---"
LEGACY_START = "# --- Headroom proxy (auto-injected by headroom wrap codex) ---"
LEGACY_END = "# --- end Headroom ---"


def fail(message):
    raise RuntimeError(message)


def read_json(path):
    return json.loads(path.read_text())


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.chmod(0o600)
    temporary.replace(path)


def select_profile(profile):
    global PROFILE, DEPLOY
    if profile not in ("research-agent-kit", "default"):
        fail("Unsupported kit Headroom profile; its configuration was preserved.")
    PROFILE = profile
    DEPLOY = HOME / ".headroom/deploy" / profile


def safe_path(path):
    for parent in (path, *path.parents):
        if parent == HOME.parent:
            break
        if parent.is_symlink():
            fail(f"Refusing a symlinked runtime/config path: {parent}")


def dependencies(version):
    if importlib.metadata.version("headroom-ai") != version:
        fail(f"Headroom {version} is required in {sys.executable}")
    for module in ("fastapi", "uvicorn", "httpx", "mcp", "websockets",
                   "zstandard", "headroom.proxy.server", "headroom.cli.mcp"):
        importlib.import_module(module)
    environment("headroom-ai", version)
    print(f"Headroom {version}: proxy/MCP imports OK ({sys.executable})")


def environment(distribution, version):
    if importlib.metadata.version(distribution) != version:
        fail(f"{distribution} {version} is required in {sys.executable}")
    if sys.version_info[:2] != (3, 13) or not Path(sys.base_prefix).is_relative_to(KIT / "tooling/python"):
        fail(f"{distribution} needs the kit-managed Python 3.13 runtime; install.sh will provision it automatically.")


def headroom(*args, capture=False):
    return subprocess.run(
        [sys.executable, "-B", "-m", "headroom.cli", *args],
        check=True, text=True, stdout=subprocess.PIPE if capture else None,
        timeout=90,
    )


def probe(endpoint):
    # A host-local readiness probe must not use the user's outbound HTTP proxy.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(BASE_URL + endpoint, timeout=3) as response:
            return json.load(response)
    except (OSError, ValueError, urllib.error.URLError):
        return None


def port_open():
    try:
        with socket.create_connection(("127.0.0.1", PORT), timeout=1):
            return True
    except OSError:
        return False


def service_path():
    if sys.platform == "darwin":
        return HOME / "Library/LaunchAgents" / f"com.headroom.{PROFILE}.plist"
    return HOME / ".config/systemd/user" / f"headroom-{PROFILE}.service"


def manifest(check_runner=True):
    data = read_json(DEPLOY / "manifest.json")
    expected = {"profile": PROFILE, "port": PORT, "host": "127.0.0.1",
                "preset": "persistent-service", "runtime_kind": "python",
                "supervisor_kind": "service", "scope": "provider", "targets": ["codex"]}
    if any(data.get(key) != value for key, value in expected.items()):
        fail("The kit Headroom profile has been changed; preserve it and resolve the conflict before reinstalling.")
    if check_runner:
        runner = (DEPLOY / "run-headroom.sh").read_text()
        entrypoint = KIT / "tooling/bin/headroom"
        managed_entrypoint = KIT / "tooling/uv-tools/headroom-ai/bin/headroom"
        valid = shlex.quote(sys.executable) + " -m headroom.cli" in runner
        if entrypoint.is_file() and entrypoint.resolve() == managed_entrypoint.resolve():
            script = entrypoint.read_text()
            correct_python = script.startswith("#!" + sys.executable + "\n") or (
                "'''exec' " + shlex.quote(sys.executable) + ' "$0" "$@"') in script
            valid = valid or (correct_python and shlex.quote(str(entrypoint)) + " install agent run" in runner)
        if not valid:
            fail("Headroom service uses a different Python. Remove the kit deployment with --remove-headroom, then reinstall.")
    return data


def repair_runner():
    """Regenerate only an owned, stopped deployment's stale launcher scripts."""
    manifest(check_runner=False)
    try:
        manifest()
        return
    except (RuntimeError, FileNotFoundError):
        if port_open():
            fail("The kit service is running with a stale runner. Stop the kit service with its user service manager, then rerun install.sh; no settings were changed.")
    from headroom.install.state import load_manifest
    from headroom.install.supervisors import render_runner_scripts
    # An empty PATH makes upstream resolve its current Python module command,
    # avoiding an obsolete or user-provided headroom executable on PATH.
    previous_path = os.environ.get("PATH")
    try:
        os.environ["PATH"] = ""
        render_runner_scripts(load_manifest(PROFILE))
    finally:
        if previous_path is None:
            os.environ.pop("PATH", None)
        else:
            os.environ["PATH"] = previous_path
    manifest()


def toml_lines(text):
    """Yield lines with whether they begin outside TOML strings and containers."""
    multiline = None
    depth = 0
    for line in text.splitlines(keepends=True):
        outside = multiline is None and depth == 0
        quote = None
        index = 0
        while index < len(line):
            char = line[index]
            if multiline:
                if line.startswith(multiline, index):
                    index += 3
                    while index < len(line) and line[index] == multiline[0]:
                        index += 1
                    multiline = None
                    continue
                if multiline[0] == '"' and char == "\\":
                    index += 2
                    continue
            elif quote:
                if quote == '"' and char == "\\":
                    index += 2
                    continue
                if char == quote:
                    quote = None
            elif char == "#":
                break
            elif char in "[{":
                depth += 1
            elif char in "]}":
                depth -= 1
            elif char in ("'", '"'):
                if line.startswith(char * 3, index):
                    multiline = char * 3
                    index += 3
                    continue
                quote = char
            index += 1
        yield line, outside


def strip_legacy_blocks(text, start, end, owned, preserve_orphan_end=False):
    """Remove balanced owned spans, preserving strings and unrelated blocks."""
    kept, block = [], None
    removed = 0
    opening_line = None
    for line_number, (line, outside) in enumerate(toml_lines(text), 1):
        marker = line.rstrip("\r\n") if outside else ""
        if marker == start:
            if block is not None:
                fail(f"Nested Headroom marker in {CONFIG} at parsed line {line_number}: {start!r}; "
                     f"the block at line {opening_line} has not ended. Configuration was preserved.")
            block = [line]
            opening_line = line_number
        elif marker == end:
            if block is None:
                if preserve_orphan_end:
                    kept.append(line)
                    continue
                fail(f"Unbalanced Headroom marker in {CONFIG} at parsed line {line_number}: {end!r} "
                     f"has no matching {start!r}. Configuration was preserved.")
            if owned(tomllib.loads("".join(block[1:]))):
                removed += 1
            else:
                kept.extend(block + [line])
            block = None
        elif block is not None:
            block.append(line)
        else:
            kept.append(line)
    if block is not None:
        fail(f"Unbalanced Headroom marker in {CONFIG} at parsed line {opening_line}: {start!r} "
             f"has no matching {end!r}. Configuration was preserved.")
    return "".join(kept), removed


def migrate_legacy():
    """Undo evidenced kit wrapper/MCP edits without auth, DB or process work."""
    if not CONFIG.exists():
        return
    safe_path(CONFIG)
    original = CONFIG.read_text()
    known_commands = {str(KIT / "tooling/bin/headroom"), str(KIT / "tooling/python-venv/bin/headroom")}

    def owned_mcp(values):
        servers = values.get("mcp_servers", {})
        return (set(values) == {"mcp_servers"} and isinstance(servers, dict)
                and set(servers) == {"headroom"} and isinstance(servers["headroom"], dict)
                and servers["headroom"].get("command") in known_commands)

    # Known duplicate MCP tables must be removed before full TOML parsing.
    # A custom same-name server is not a candidate for kit replacement.
    # Upstream wrap can consume an MCP opening comment. Its orphan closing
    # comment is inert; retain it without treating preceding tables as owned.
    cleaned, mcp_removed = strip_legacy_blocks(original, "# --- Headroom MCP server ---",
                                               "# --- end Headroom MCP server ---", owned_mcp,
                                               preserve_orphan_end=True)
    current = tomllib.loads(cleaned)
    remaining = current.get("mcp_servers", {}).get("headroom")
    if mcp_removed and remaining is not None and remaining.get("command") not in known_commands:
        fail("Legacy MCP cleanup conflicts with a custom headroom server; Codex configuration was preserved.")
    tooling_state = KIT / "tooling.state"
    wrapper = HOME / ".config/headroom/auto-wrap.sh"
    provider_owned = False
    if tooling_state.is_file() and wrapper.is_file():
        state = tooling_state.read_text().splitlines()
        source = wrapper.read_text()
        provider_owned = "headroom_wrapper=installed" in state and all(fragment in source for fragment in (
            "_universal_research_agent_kit_headroom_command() {",
            'codex() {\n  _universal_research_agent_kit_headroom_command wrap codex -- "$@"\n}',
        ))

    def owned_provider(values):
        providers = values.get("model_providers", {})
        if (set(values) - {"model_provider", "openai_base_url", "model_providers"}
                or not isinstance(providers, dict) or set(providers) - {"headroom"}
                or values.get("model_provider", "headroom") != "headroom"
                or values.get("openai_base_url", BASE_URL + "/v1") != BASE_URL + "/v1"):
            fail("Legacy Headroom markers contain custom settings; Codex configuration was preserved.")
        if "headroom" in providers:
            provider = providers["headroom"]
            allowed = {"name", "base_url", "supports_websockets", "requires_openai_auth", "env_http_headers"}
            expected_headers = {"X-Headroom-Project": "HEADROOM_PROJECT",
                                "X-Headroom-Base-Url": "HEADROOM_CODEX_UPSTREAM_BASE_URL"}
            headers = provider.get("env_http_headers", {}) if isinstance(provider, dict) else None
            if (not isinstance(provider, dict) or set(provider) - allowed
                    or provider.get("name") != "OpenAI via Headroom proxy"
                    or provider.get("base_url") != BASE_URL + "/v1"
                    or provider.get("supports_websockets", True) is not True
                    or provider.get("requires_openai_auth", True) is not True
                    or not isinstance(headers, dict)
                    or any(expected_headers.get(key) != value for key, value in headers.items())):
                fail("The legacy Headroom provider was customized; Codex configuration was preserved.")
        return True

    removed = 0
    if provider_owned:
        cleaned, removed = strip_legacy_blocks(cleaned, LEGACY_START, LEGACY_END, owned_provider)
    if not removed:
        if cleaned != original:
            CONFIG.write_text(cleaned)
            print("Removed known kit legacy MCP spans; other settings preserved.")
        return
    current = tomllib.loads(cleaned)
    backup_path = CONFIG.with_name(CONFIG.name + ".headroom-backup")
    backup = None

    def previous(key):
        nonlocal backup
        if backup is None:
            safe_path(backup_path)
            backup = tomllib.loads(backup_path.read_text()) if backup_path.exists() else {}
        return backup.get(key)

    root = True
    restored = []
    for line, outside in toml_lines(cleaned):
        if outside and line.lstrip().startswith("["):
            root = False
        match = re.match(r"^[ \t]*(model_provider|openai_base_url)[ \t]*=", line) if outside and root else None
        if match:
            key = match[1]
            value = current.get(key)
            redirected = value == "headroom" if key == "model_provider" else value == BASE_URL + "/v1"
            if redirected:
                was = re.search(r"#[ \t]*was:[ \t]*(.*?)\s*$", line)
                value = tomllib.loads('value = "' + was[1] + '"')["value"] if was else previous(key)
                if not isinstance(value, str) or not value or value == current.get(key):
                    fail(f"Cannot safely restore legacy {key}; restore its original root value, then rerun install.sh. Codex configuration was preserved.")
                line = f"{key} = {json.dumps(value, ensure_ascii=False)}\n"
        restored.append(line)
    cleaned = "".join(restored)
    current = tomllib.loads(cleaned)
    # Only the two root keys may come from a snapshot. New MCP entries, tables,
    # model choices and other edits always remain from the current file.
    for key in ("model_provider", "openai_base_url"):
        if key not in current:
            value = previous(key)
            if value is not None:
                if not isinstance(value, str) or value in ("headroom", BASE_URL + "/v1"):
                    fail(f"Ambiguous legacy backup {key}; Codex configuration was preserved.")
                cleaned = f"{key} = {json.dumps(value, ensure_ascii=False)}\n" + cleaned
    final = tomllib.loads(cleaned)
    if final.get("model_provider") == "headroom" or final.get("openai_base_url") == BASE_URL + "/v1":
        fail("Ambiguous legacy root routing remains; Codex configuration was preserved.")
    CONFIG.write_text(cleaned)
    print("Migrated kit legacy Headroom provider; current user settings and backup preserved.")


def check_provider():
    config = tomllib.loads(CONFIG.read_text())
    provider = config.get("model_providers", {}).get("headroom", {})
    if config.get("model_provider") != "headroom" or provider.get("base_url") != BASE_URL + "/v1":
        fail("Codex persistent Headroom provider is missing or changed; rerun install.sh.")
    if not provider.get("supports_websockets"):
        fail("Codex Headroom provider is missing WebSocket support.")
    if bool(provider.get("requires_openai_auth")) != codex_oauth():
        fail("Codex authentication changed since installation. Rerun install.sh, then restart Desktop/daemon.")


def adopt_default(record):
    """Keep the standard deployment and provider; change only kit ownership."""
    safe_path(Path(record))
    saved = read_json(Path(record))
    if not saved.get("adopt_service"):
        return
    if saved.get("profile") != "default" or STATE.exists():
        fail("Default Headroom adoption conflicts with the ownership record.")
    select_profile("default")
    for path in (STATE, DEPLOY, service_path(), CONFIG):
        safe_path(path)
    if port_open():
        fail("Default Headroom restarted before adoption; its environment was preserved.")
    manifest(check_runner=False)
    safe_path(CONFIG)
    original = CONFIG.read_text()
    tomllib.loads(original)

    def standard_provider(values):
        providers = values.get("model_providers", {})
        provider = providers.get("headroom", {}) if isinstance(providers, dict) else {}
        expected = {"model_provider": "headroom", "openai_base_url": BASE_URL + "/v1",
                    "model_providers": {"headroom": {"name": "Headroom persistent proxy", "base_url": BASE_URL + "/v1",
                                                     "supports_websockets": True}}}
        if isinstance(provider, dict) and isinstance(provider.get("requires_openai_auth"), bool):
            expected["model_providers"]["headroom"]["requires_openai_auth"] = provider["requires_openai_auth"]
        if values != expected:
            fail("The default Headroom provider has custom settings; Codex configuration was preserved.")
        return True

    without_provider, count = strip_legacy_blocks(original, START, END, standard_provider)
    if count != 1:
        fail("The default Headroom provider markers are missing or ambiguous; configuration was preserved.")
    outside = tomllib.loads(without_provider)
    previous = {key: outside[key] for key in ("model_provider", "openai_base_url") if key in outside}
    # Upstream does not store pre-install provider values. Do not infer them
    # from old backups or rewrite/retag existing Codex sessions during adoption.
    write_json(STATE, {"profile": PROFILE, "port": PORT, "previous_provider": previous,
                       "python": sys.executable, "version": VERSION, "adopted_default": True})
    print("Adopted the existing default Headroom service; provider configuration and sessions preserved.")


def install_mcp(agent):
    """Reuse the exact kit MCP when its default proxy URL is explicit or omitted."""
    if agent == "codex":
        paths, key = [CONFIG], "mcp_servers"
    elif agent == "claude":
        paths, key = [HOME / ".claude.json", HOME / ".claude/mcp.json"], "mcpServers"
    else:
        fail("Unsupported MCP agent: " + agent)
    for path in paths:
        safe_path(path)
        if not path.exists():
            continue
        data = tomllib.loads(path.read_text()) if agent == "codex" else read_json(path)
        servers = data.get(key, {}) if isinstance(data, dict) else {}
        entry = servers.get("headroom") if isinstance(servers, dict) else None
        if entry is None:
            continue
        if (isinstance(entry, dict) and not set(entry) - {"command", "args", "env", "type"}
                and entry.get("command") == str(KIT / "tooling/bin/headroom")
                and entry.get("args") == ["mcp", "serve"] and entry.get("type", "stdio") == "stdio"
                and entry.get("env", {}) in ({}, {"HEADROOM_PROXY_URL": BASE_URL})):
            print("Reusing the existing kit Headroom MCP for " + agent + "; configuration preserved.")
            return
        break
    # Headroom 0.34 compares env dictionaries literally and omits its default
    # URL even with --proxy-url. Keep its normal conflict handling for all
    # other entries; never force-replace a user's MCP configuration.
    headroom("mcp", "install", "--agent", agent)


def codex_oauth():
    from headroom.providers.codex.install import codex_uses_chatgpt_auth
    return codex_uses_chatgpt_auth(CONFIG.parent / "auth.json")


def sync_codex_auth():
    # First installation may precede login. Refresh only the owned auth flag;
    # provider reapplication would rewrite other settings and thread records.
    original = CONFIG.read_text()
    desired = codex_oauth()
    provider = tomllib.loads(original).get("model_providers", {}).get("headroom", {})
    if bool(provider.get("requires_openai_auth")) == desired:
        return
    if original.count(START) != 1 or original.count(END) != 1:
        fail("Cannot update authentication: kit provider markers are missing or ambiguous.")
    begin, end = original.index(START), original.index(END)
    block = original[begin:end]
    table = re.search(r"(?ms)^(\[model_providers\.headroom\]\n)(.*?)(?=^\[|\Z)", block)
    if table is None:
        fail("Cannot locate the owned Headroom provider table to update authentication.")
    fields = re.sub(r"(?m)^[ \t]*requires_openai_auth[ \t]*=.*\n?", "", table[2])
    if desired:
        fields = "requires_openai_auth = true\n" + fields
    block = block[:table.start()] + table[1] + fields + block[table.end():]
    CONFIG.write_text(original[:begin] + block + original[end:])


def start_service():
    # Upstream `install start` rewrites provider configuration and thread rows.
    # Its supervisor API only starts the already-installed host service.
    from headroom.install.state import load_manifest
    from headroom.install.supervisors import start_supervisor
    from headroom.install.runtime import wait_ready
    deployment = load_manifest(PROFILE)
    start_supervisor(deployment)
    if not wait_ready(deployment, timeout_seconds=45):
        fail("Headroom did not become ready after service start.")


def remove_service():
    # Upstream apply can delete its manifest even when cleanup fails. The kit
    # record still identifies this exact user service for a recovery attempt.
    from headroom.install.models import DeploymentManifest
    from headroom.install.supervisors import stop_supervisor, remove_supervisor
    deployment = DeploymentManifest(
        profile=PROFILE, preset="persistent-service", runtime_kind="python",
        supervisor_kind="service", scope="provider", provider_mode="manual",
        targets=["codex"], port=PORT, host="127.0.0.1", backend="anthropic",
        service_name="headroom-" + PROFILE,
    )
    installed = service_path().exists() or port_open()
    if sys.platform.startswith("linux"):
        result = subprocess.run(
            ["systemctl", "--user", "show", deployment.service_name, "-p", "LoadState", "--value"],
            check=True, capture_output=True, text=True, timeout=5,
        )
        installed = installed or result.stdout.strip() != "not-found"
    # The service manager owns its process tree, including the proxy child.
    # Never pass a bare pidfile to upstream stop_runtime.
    if installed or sys.platform == "darwin":
        stop_supervisor(deployment)
    for _ in range(50):
        if not port_open():
            break
        time.sleep(0.1)
    if port_open():
        fail("Kit service did not stop; ownership and Python environment retained.")
    remove_supervisor(deployment)
    if service_path().exists():
        fail("Kit service artifact remains; ownership and Python environment retained.")
    if DEPLOY.exists():
        shutil.rmtree(DEPLOY)


def restore_thread_routing():
    from headroom.providers.codex.threads import retag_to_native
    retag_to_native(CONFIG.parent)


def check(quiet=False):
    if not STATE.is_file() or read_json(STATE).get("profile") != PROFILE:
        fail("No kit-owned persistent Headroom installation. Run install.sh.")
    manifest()
    status = headroom("install", "status", "--profile", PROFILE, capture=True).stdout
    health = probe("/health") or {}
    deployment = health.get("deployment") or {}
    if not (re.search(r"^Status:\s+running$", status, re.M)
            and re.search(r"^Healthy:\s+yes$", status, re.M)
            and probe("/readyz") is not None
            and deployment.get("profile") == PROFILE
            and deployment.get("preset") == "persistent-service"):
        fail("Headroom service is not running and ready with the kit profile. A healthy unrelated listener is not success.\n" + status)
    if health.get("version") != VERSION:
        fail("The running Headroom version differs from the pinned environment.")
    check_provider()
    if not quiet:
        print(status.rstrip())


def preflight():
    for name, expected in (("CODEX_HOME", HOME / ".codex"),
                           ("HEADROOM_WORKSPACE_DIR", HOME / ".headroom"),
                           ("HEADROOM_CONFIG_DIR", HOME / ".headroom/config")):
        if os.environ.get(name) and Path(os.environ[name]).expanduser() != expected:
            fail(f"{name} points outside the kit's supported host-local paths; unset it before installing.")
    for path in (STATE, CONFIG, DEPLOY, service_path(), HOME / ".claude.json"):
        safe_path(path)
    owned = STATE.is_file() and read_json(STATE).get("profile") == PROFILE
    if not owned and (DEPLOY.exists() or service_path().exists()):
        fail("An unowned Headroom profile/service uses the kit name. It was preserved; migrate it explicitly.")
    for path in (HOME / ".headroom/deploy").glob("*/manifest.json"):
        if path.parent != DEPLOY and read_json(path).get("port") == PORT:
            fail(f"Port {PORT} belongs to another Headroom profile: {path.parent.name}. Stop/remove or relocate that deployment yourself, then rerun.")
    if port_open():
        health = probe("/health") or {}
        if not owned or (health.get("deployment") or {}).get("profile") != PROFILE:
            fail(f"Port {PORT} is occupied by an unowned or ephemeral proxy/process. Nothing was stopped. Resolve the listener and rerun.")
    if sys.platform == "darwin":
        subprocess.run(["launchctl", "print", f"gui/{os.getuid()}"], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    elif sys.platform.startswith("linux"):
        subprocess.run(["systemctl", "--user", "show-environment"], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    else:
        fail("Persistent Headroom supports macOS and Linux with a user service manager.")


def install():
    preflight()
    if STATE.exists():
        repair_runner()
        sync_codex_auth()
        if not port_open():
            start_service()
        check()
        return
    text = CONFIG.read_text() if CONFIG.exists() else ""
    config = tomllib.loads(text)
    if START in text or "headroom" in config.get("model_providers", {}):
        fail("An existing Headroom provider has no kit ownership record. Preserve it and remove/migrate it with its original installer first.")
    if config.get("model_provider", "openai") != "openai":
        fail("A user-selected custom Codex provider is active. It was preserved; choose the native OpenAI provider before enabling kit routing.")
    saved = {key: config[key] for key in ("model_provider", "openai_base_url") if key in config}
    # Record ownership before apply so an interrupted activation is recoverable.
    write_json(STATE, {"profile": PROFILE, "port": PORT, "previous_provider": saved,
                       "python": sys.executable, "version": VERSION})
    try:
        headroom("install", "apply", "--profile", PROFILE, "--preset", "persistent-service",
                 "--runtime", "python", "--scope", "provider", "--providers", "manual",
                 "--target", "codex", "--port", str(PORT))
        sync_codex_auth()
        check()
    except BaseException:
        # Keep ownership when cleanup fails so shell rollback retains the
        # environment and the next --remove-headroom can retry the service.
        try:
            remove_service()
        finally:
            CONFIG.write_text(text)
        restore_thread_routing()
        STATE.unlink(missing_ok=True)
        raise


def remove():
    if not STATE.is_file():
        fail("No kit ownership record; no service or configuration was removed.")
    preflight()
    saved = read_json(STATE)["previous_provider"]
    if (DEPLOY / "manifest.json").exists():
        manifest(check_runner=False)
    original = CONFIG.read_text() if CONFIG.exists() else ""
    if START not in original and END not in original:
        # Failed upstream apply can already have reverted the provider block.
        without_provider = original
    elif original.count(START) == 1 and original.count(END) == 1:
        begin, end = original.index(START), original.index(END) + len(END)
        without_provider = original[:begin] + original[end:]
    else:
        fail("The owned provider markers are ambiguous; configuration was preserved.")
    remove_service()
    current = tomllib.loads(without_provider)
    restore = "".join(f"{key} = {json.dumps(value)}\n" for key, value in saved.items() if key not in current)
    CONFIG.write_text(restore + without_provider)
    restore_thread_routing()
    STATE.unlink()
    print("Removed kit Headroom service/provider; unrelated settings and tool environments preserved.")


def claude_direct_check():
    # The shell variable alone cannot override env saved in Claude settings.
    for path in (HOME / ".claude/settings.json", Path.cwd() / ".claude/settings.json",
                 Path.cwd() / ".claude/settings.local.json"):
        if path.is_file():
            value = read_json(path).get("env", {}).get("ANTHROPIC_BASE_URL", "")
            if value and value.rstrip("/") != "https://api.anthropic.com":
                fail(f"Claude Remote Control needs direct Anthropic. Remove ANTHROPIC_BASE_URL from {path}; the kit left your file unchanged.")


def require_no_install():
    if (KIT / ".lock").exists():
        fail("The kit installer is running. Wait for it to finish before starting a new Headroom session.")


def ensure_running():
    require_no_install()
    if not port_open():
        # Only the stopped-to-running transition needs serialization. Healthy
        # sessions share the service without holding a lock for their lifetime.
        with (KIT / "headroom-start.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            require_no_install()
            preflight()
            manifest()
            if not port_open():
                start_service()
    check(quiet=True)


def launch(tool, args):
    ensure_running()
    env = os.environ.copy()
    directory = Path.cwd()
    if tool == "codex":
        for index, arg in enumerate(args):
            if arg == "--":
                break
            if arg in ("-C", "--cd") and index + 1 < len(args):
                directory = Path(args[index + 1]).expanduser()
            elif arg.startswith("--cd="):
                directory = Path(arg.partition("=")[2]).expanduser()
    project = env.get("HEADROOM_PROJECT") or directory.resolve().name
    env["HEADROOM_PROJECT"] = project
    if tool == "codex":
        # A persistent headroom provider must not be treated as its own upstream.
        # CLI overrides preserve the durable CODEX_HOME and never edit config.
        args = ["--config", "model_providers.headroom.http_headers.X-Headroom-Project="
                + json.dumps(project), *args]
    else:
        env["ANTHROPIC_BASE_URL"] = BASE_URL
        env.setdefault("ENABLE_TOOL_SEARCH", "auto")
        header = "X-Headroom-Project: " + project.replace("\r", "").replace("\n", "")
        headers = env.get("ANTHROPIC_CUSTOM_HEADERS", "")
        if not re.search(r"(?im)^x-headroom-project\s*:", headers):
            env["ANTHROPIC_CUSTOM_HEADERS"] = (headers + "\n" + header).strip()
        # Session settings also reach workers without mutating settings.local.json.
        settings = {}
        clean = []
        index = 0
        while index < len(args):
            arg = args[index]
            if arg == "--":
                clean.extend(args[index:])
                break
            if arg == "--settings" or arg.startswith("--settings="):
                if arg == "--settings":
                    index += 1
                    if index == len(args):
                        fail("--settings requires a file or JSON value")
                    value = args[index]
                else:
                    value = arg.partition("=")[2]
                settings = json.loads(value) if value.lstrip().startswith("{") else read_json(Path(value).expanduser())
            else:
                clean.append(arg)
            index += 1
        settings["env"] = {**settings.get("env", {}), "ANTHROPIC_BASE_URL": BASE_URL,
                           "ENABLE_TOOL_SEARCH": settings.get("env", {}).get("ENABLE_TOOL_SEARCH", env["ENABLE_TOOL_SEARCH"])}
        headers = settings["env"].get("ANTHROPIC_CUSTOM_HEADERS", env.get("ANTHROPIC_CUSTOM_HEADERS", ""))
        if not re.search(r"(?im)^x-headroom-project\s*:", headers):
            headers = (headers + "\n" + header).strip()
        settings["env"]["ANTHROPIC_CUSTOM_HEADERS"] = headers
        args = ["--settings", json.dumps(settings), *clean]
    managed = KIT / "cli/bin" / tool
    if managed.exists() or managed.is_symlink():
        if not managed.is_file() or not os.access(managed, os.X_OK):
            fail(f"Managed {tool} is missing or not executable: {managed}; rerun install.sh.")
        binary = str(managed)
    else:
        binary = shutil.which(tool)
    if not binary:
        fail(f"{tool} is not on PATH")
    os.execvpe(binary, [binary, *args], env)


def main():
    action, *args = sys.argv[1:]
    if action not in ("dependencies", "environment", "migrate-legacy", "adopt-default") and STATE.exists():
        safe_path(STATE)
        select_profile(read_json(STATE).get("profile"))
    if action == "dependencies":
        dependencies(args[0])
    elif action == "environment":
        environment(*args)
    elif action == "migrate-legacy":
        migrate_legacy()
    elif action == "adopt-default":
        adopt_default(args[0])
    elif action == "install-mcp":
        install_mcp(args[0])
    elif action == "install":
        install()
    elif action == "check":
        check()
    elif action == "remove":
        remove()
    elif action == "preflight":
        preflight()
    elif action == "claude-direct-check":
        claude_direct_check()
    elif action == "launch":
        launch(args[0], args[1:])
    else:
        fail(f"Unknown runtime action: {action}")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, ImportError, subprocess.SubprocessError) as exc:
        print(f"Headroom: {exc}", file=sys.stderr)
        sys.exit(1)
