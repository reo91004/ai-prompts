"""Register the native Codex starter without supervising or restarting its daemon."""

import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import tempfile


UNIT = "codex-remote-control.service"
LABEL = "com.research-agent-kit.codex-remote-control"
LAYOUTS = (".codex/packages/standalone/current/bin/codex", ".codex/packages/standalone/current/codex")
PROFILES = ("research-agent-kit", "default")


def command(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"{' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def startup_path(home):
    if sys.platform == "darwin":
        return home / "Library/LaunchAgents" / (LABEL + ".plist")
    if sys.platform == "linux":
        return home / ".config/systemd/user" / UNIT
    raise RuntimeError("Codex automatic startup supports macOS and Linux only.")


def unit_text(layout, profile, legacy=False):
    # Adopt the standard manual unit; managed registrations pin CODEX_HOME.
    environment = "" if legacy else "Environment=CODEX_HOME=%h/.codex\n"
    return f"""[Unit]
Description=Codex managed daemon boot startup
Wants=headroom-{profile}.service
After=headroom-{profile}.service

[Service]
{environment}Type=oneshot
RemainAfterExit=yes
ExecStart=%h/{layout} app-server daemon start
ExecStop=%h/{layout} app-server daemon stop
TimeoutStopSec=330
StandardOutput=null

[Install]
WantedBy=default.target
"""


def launch_agent(home, layout):
    return {
        "Label": LABEL,
        "ProgramArguments": [str(home / layout), "app-server", "daemon", "start"],
        "RunAtLoad": True,
        "AbandonProcessGroup": True,
        "EnvironmentVariables": {"HOME": str(home), "CODEX_HOME": str(home / ".codex")},
        "StandardOutPath": "/dev/null",
    }


def owned_file(home):
    path = startup_path(home)
    for parent in (path, *path.parents):
        if parent == home.parent:
            break
        if parent.is_symlink():
            raise RuntimeError(f"Refusing a symlinked startup path: {parent}")
    if not path.exists():
        return False
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
        raise RuntimeError(f"Startup file must be a regular file owned by this user: {path}")
    if sys.platform == "darwin":
        data = plistlib.loads(path.read_bytes())
        owned = any(data == launch_agent(home, layout) for layout in LAYOUTS)
    else:
        owned = path.read_text() in {unit_text(layout, profile, legacy) for layout in LAYOUTS
                                    for profile in PROFILES for legacy in (False, True)}
    if not owned:
        raise RuntimeError(f"The existing Codex startup file was customized; it was preserved: {path}")
    return True


def check(home, binary):
    if str(binary.relative_to(home)) not in LAYOUTS:
        raise RuntimeError("Automatic startup requires the stable standalone Codex current path.")
    owned_file(home)
    if sys.platform == "linux":
        result = subprocess.run(["systemctl", "--user", "show", UNIT, "-p", "LoadState",
                                 "-p", "FragmentPath", "-p", "DropInPaths"], capture_output=True, text=True)
        fields = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
        if (not {"LoadState", "FragmentPath", "DropInPaths"} <= fields.keys()
                or fields["LoadState"] not in ("loaded", "not-found")
                or (result.returncode and fields["LoadState"] != "not-found")):
            raise RuntimeError("Cannot inspect the Codex startup unit in user systemd: " + result.stderr.strip())
        if fields.get("DropInPaths") or fields.get("FragmentPath", "") not in ("", str(startup_path(home))):
            raise RuntimeError("A custom Codex startup unit or drop-in exists; it was preserved.")
    else:
        launchd_disabled()


def launchd_disabled():
    output = command("launchctl", "print-disabled", f"gui/{os.getuid()}")
    if not output.startswith("disabled services = {") or not output.endswith("}"):
        raise RuntimeError("Cannot read launchd's login startup overrides.")
    match = re.search(r'"' + re.escape(LABEL) + r'"\s*=>\s*(true|false)', output)
    if LABEL in output and not match:
        raise RuntimeError("Cannot read the Codex login startup override.")
    return bool(match and match[1] == "true")


def write_file(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(contents)
            stream.flush()
            temporary.chmod(0o644)
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


def linger():
    return command("loginctl", "show-user", str(os.getuid()), "-p", "Linger", "--value") == "yes"


def headroom_profile(home):
    state = json.loads((home / ".universal-research-agent-kit/headroom.json").read_text())
    profile = state.get("profile") if isinstance(state, dict) else None
    if profile not in PROFILES:
        raise RuntimeError("Cannot identify the installed Headroom service for Codex startup.")
    return profile


def install(home, binary):
    check(home, binary)
    layout = str(binary.relative_to(home))
    path = startup_path(home)
    if sys.platform == "linux":
        profile = headroom_profile(home)
        if command("systemctl", "--user", "is-enabled", "headroom-" + profile + ".service") != "enabled":
            raise RuntimeError("The installed Headroom service is not enabled for startup.")
        contents = unit_text(layout, profile).encode()
    else:
        contents = plistlib.dumps(launch_agent(home, layout))
    if not path.exists() or path.read_bytes() != contents or path.stat().st_mode & 0o022:
        write_file(path, contents)
    if sys.platform == "linux":
        command("systemctl", "--user", "daemon-reload")
        # No --now: enable() already verified the running native daemon.
        command("systemctl", "--user", "enable", UNIT)
        if not linger():
            result = subprocess.run(["loginctl", "--no-ask-password", "enable-linger", str(os.getuid())],
                                    capture_output=True, text=True)
            if result.returncode or not linger():
                raise RuntimeError('Codex startup is registered, but login-free boot startup still needs linger. '
                                   'Run: sudo loginctl enable-linger "$(id -un)"; then rerun '
                                   'sh install.sh --enable-codex-remote-control. No sudo command was run by the installer.')
    else:
        # LaunchAgents are read at GUI login. Do not bootstrap/kickstart the
        # current job or disturb the detached daemon that is already running.
        command("launchctl", "enable", f"gui/{os.getuid()}/{LABEL}")
    verify(home, binary)


def verify(home, binary):
    check(home, binary)
    if not owned_file(home):
        raise RuntimeError("Codex automatic startup is not registered; rerun sh install.sh --enable-codex-remote-control.")
    layout = str(binary.relative_to(home))
    path = startup_path(home)
    if path.stat().st_mode & 0o022:
        raise RuntimeError("Codex startup file is writable by other users; rerun the enable option to repair its permissions.")
    if sys.platform == "linux":
        if path.read_text() not in {unit_text(layout, headroom_profile(home), legacy) for legacy in (False, True)}:
            raise RuntimeError("Codex startup uses an older executable or Headroom profile; rerun the enable option.")
        if command("systemctl", "--user", "is-enabled", UNIT) != "enabled":
            raise RuntimeError("Codex automatic startup is not enabled.")
        if not linger():
            raise RuntimeError('Codex startup needs linger for login-free boot: sudo loginctl enable-linger "$(id -un)"')
        print("Codex startup: registered for boot without login (reboot/relay not tested).")
    else:
        if plistlib.loads(path.read_bytes()) != launch_agent(home, layout):
            raise RuntimeError("Codex login startup uses an older executable; rerun the enable option.")
        if launchd_disabled():
            raise RuntimeError("Codex login startup is disabled.")
        print("Codex startup: registered for GUI login; it does not run before login (login/relay not tested).")


def remove(home, binary):
    check(home, binary)
    path = startup_path(home)
    if not path.exists():
        return
    if sys.platform == "linux":
        # Disabling only removes startup links. Stopping this unit could stop
        # local Codex work via ExecStop; the caller disables RC separately.
        command("systemctl", "--user", "disable", UNIT)
    path.unlink()
    if sys.platform == "linux":
        command("systemctl", "--user", "daemon-reload")
    # Removing a one-shot LaunchAgent file prevents the next login launch;
    # no bootout is needed for its completed starter in the current session.
    print("Codex automatic startup removed; existing linger and Headroom settings were preserved.")


if __name__ == "__main__":
    try:
        action, binary, home = sys.argv[1], Path(sys.argv[2]), Path.home()
        if action == "check":
            check(home, binary)
            print(startup_path(home))
        elif action == "install":
            install(home, binary)
        elif action == "verify":
            verify(home, binary)
        elif action == "remove":
            remove(home, binary)
        else:
            raise RuntimeError("Expected check, install, verify or remove.")
    except (RuntimeError, OSError, ValueError, plistlib.InvalidFileException) as error:
        sys.exit(str(error))
