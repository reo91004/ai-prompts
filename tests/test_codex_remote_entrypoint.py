"""Daily Remote Control commands against isolated CLI and service fixtures."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class RemoteEntrypointTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="kit-remote-")
        self.addCleanup(self.directory.cleanup)
        self.work = Path(self.directory.name)
        self.home = self.work / "home"
        self.home.mkdir()
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.calls = self.work / "calls"
        self.env = {**os.environ, "HOME": str(self.home), "CODEX_HOME": str(self.home / ".codex"),
                    "PATH": str(self.bin) + os.pathsep + os.environ["PATH"], "REMOTE_CALLS": str(self.calls)}
        for name in ("BASH_ENV", "KIT_HEADROOM_PYTHON"):
            self.env.pop(name, None)

    def executable(self, path, contents):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        path.chmod(0o755)

    def install_fixtures(self):
        self.state = self.home / ".universal-research-agent-kit"
        runtime = self.state / "tooling/uv-tools/headroom-ai/bin/python"
        runtime.parent.mkdir(parents=True)
        runtime.symlink_to(sys.executable)
        (self.state / "headroom.json").write_text('{"profile":"research-agent-kit"}')
        self.auth = self.home / ".codex/auth.json"
        self.auth.parent.mkdir()
        self.auth.write_text("auth sentinel")
        self.executable(self.home / ".codex/packages/standalone/current/bin/codex", """#!/bin/sh
printf 'codex %s\\n' "$*" >> "$REMOTE_CALLS"
case "$*" in
  --version) echo 'codex-cli 0.166.0' ;;
  *--help) : ;;
  'remote-control start --json')
    if [ "${REMOTE_UNMANAGED:-0}" = 1 ]; then
      echo 'Error: app server is running but is not managed by codex app-server daemon' >&2
      exit 42
    fi
    mkdir -p "$HOME/.codex/app-server-daemon"
    echo '{"remoteControlEnabled":true}' > "$HOME/.codex/app-server-daemon/settings.json"
    echo '{"status":"connected","environmentId":"PRIVATE_ENV"}' ;;
  'app-server daemon version')
    [ "${REMOTE_VERSION_FAILURE:-0}" = 0 ] || { echo 'inspection unavailable' >&2; exit 43; }
    echo '{"status":"running","backend":"pid","environmentId":"PRIVATE_ENV"}' ;;
  'app-server daemon disable-remote-control')
    echo '{"remoteControlEnabled":false}' > "$HOME/.codex/app-server-daemon/settings.json" ;;
  'remote-control pair') echo PAIR_TEST_CODE ;;
  *) echo "Unexpected Codex action: $*" >&2; exit 99 ;;
esac
""")
        manager = """#!/bin/sh
printf '%s %s\\n' "${0##*/}" "$*" >> "$REMOTE_CALLS"
case "${0##*/} $*" in
  'systemctl --user show codex-remote-control.service '*)
    unit="$HOME/.config/systemd/user/codex-remote-control.service"
    if [ -f "$unit" ]; then
      printf 'LoadState=loaded\\nFragmentPath=%s\\nDropInPaths=\\n' "$unit"
    else
      printf 'LoadState=not-found\\nFragmentPath=\\nDropInPaths=\\n'
      exit 1
    fi ;;
  'systemctl --user is-enabled headroom-'*) echo enabled ;;
  'systemctl --user is-enabled codex-remote-control.service')
    [ -f "$HOME/startup-enabled" ] || exit 1
    echo enabled ;;
  'systemctl --user enable codex-remote-control.service')
    [ "${STARTUP_FAILURE:-0}" = 0 ] || exit 44
    : > "$HOME/startup-enabled" ;;
  'systemctl --user disable codex-remote-control.service') rm -f "$HOME/startup-enabled" ;;
  'systemctl --user daemon-reload') : ;;
  'loginctl show-user '*) echo yes ;;
  'launchctl print-disabled '*) printf 'disabled services = {\\n}\\n' ;;
  'launchctl enable '*) [ "${STARTUP_FAILURE:-0}" = 0 ] || exit 44 ;;
  *) echo "Unexpected startup action: $*" >&2; exit 99 ;;
esac
"""
        for name in ("systemctl", "launchctl", "loginctl"):
            self.executable(self.bin / name, manager)
        for name in ("curl", "wget", "npm", "npx", "brew", "headroom"):
            self.executable(self.bin / name, '#!/bin/sh\necho "UNEXPECTED_UPDATE $0 $*" >> "$REMOTE_CALLS"\nexit 98\n')

    def run_remote(self, *args, **env):
        return subprocess.run(["sh", str(ROOT / "codex-remote.sh"), *args],
                              env={**self.env, **env}, capture_output=True, text=True)

    def snapshot(self):
        return {str(path.relative_to(self.home)): ("link", os.readlink(path)) if path.is_symlink()
                else ("file", hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mode)
                if path.is_file() else ("directory", path.stat().st_mode)
                for path in self.home.rglob("*")}

    def test_uninstalled_status_and_invalid_arguments_do_not_create_state(self):
        result = self.run_remote()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Managed Codex: unavailable", result.stdout)
        self.assertEqual(self.snapshot(), {})
        self.assertEqual(self.run_remote("unknown").returncode, 2)
        self.assertEqual(self.run_remote("status", "extra").returncode, 2)
        self.assertEqual(self.snapshot(), {})

    def test_daily_commands_use_installed_tools_and_status_is_read_only(self):
        self.install_fixtures()
        enabled = self.run_remote("enable")
        self.assertEqual(enabled.returncode, 0, enabled.stdout + enabled.stderr)
        self.assertNotIn("PRIVATE_ENV", enabled.stdout + enabled.stderr)
        before = self.snapshot()
        for args in ((), ("status",)):
            status = self.run_remote(*args)
            self.assertEqual(status.returncode, 0, status.stdout + status.stderr)
            self.assertIn("managed daemon running, Remote Control enabled", status.stdout)
            self.assertIn("pairing/relay not verified", status.stdout)
            self.assertEqual(self.snapshot(), before)
        paired = self.run_remote("pair")
        self.assertEqual(paired.returncode, 0, paired.stderr)
        self.assertEqual(paired.stdout.strip(), "PAIR_TEST_CODE")
        self.assertEqual(self.snapshot(), before)
        disabled = self.run_remote("disable")
        self.assertEqual(disabled.returncode, 0, disabled.stdout + disabled.stderr)
        self.assertEqual((self.state / "codex-remote-control.state").read_text(), "enabled=0\n")
        self.assertFalse(json.loads((self.home / ".codex/app-server-daemon/settings.json").read_text())["remoteControlEnabled"])
        calls = "\n".join(line for line in self.calls.read_text().splitlines() if not line.endswith(" --help"))
        for forbidden in ("UNEXPECTED_UPDATE", "daemon bootstrap", "daemon stop", "daemon restart", "daemon update", "--now", "bootout", "kickstart"):
            self.assertNotIn(forbidden, calls)
        self.assertEqual(self.auth.read_text(), "auth sentinel")

    def test_status_continues_after_daemon_failure(self):
        self.install_fixtures()
        self.assertEqual(self.run_remote("enable").returncode, 0)
        before = self.snapshot()
        self.calls.write_text("")
        result = self.run_remote("status", REMOTE_VERSION_FAILURE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Codex daemon: inspection failed", result.stdout)
        self.assertIn("Remote Control preference: enabled", result.stdout)
        self.assertIn("startup:", result.stdout)
        self.assertIn("launchctl" if sys.platform == "darwin" else "systemctl", self.calls.read_text())
        self.assertEqual(self.snapshot(), before)

    def test_unmanaged_enable_requests_explicit_repair(self):
        self.install_fixtures()
        result = self.run_remote("enable", REMOTE_UNMANAGED="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("codex-remote.sh repair", result.stderr)
        self.assertEqual(self.calls.read_text().count("remote-control start --json"), 1)
        self.assertFalse((self.state / "codex-remote-control.state").exists())
        self.assertFalse((self.state / ".lock").exists())
        self.assertEqual(self.auth.read_text(), "auth sentinel")

    def test_partial_startup_failure_is_not_recorded_as_complete(self):
        self.install_fixtures()
        result = self.run_remote("enable", STARTUP_FAILURE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Remote Control: connected", result.stdout)
        self.assertFalse((self.state / "codex-remote-control.state").exists())
        status = self.run_remote("status")
        self.assertNotEqual(status.returncode, 0)
        self.assertIn("No completed Remote Control setup is recorded", status.stdout)
        self.assertIn("Remote Control preference: enabled", status.stdout)
        self.assertFalse((self.state / ".lock").exists())

    def test_custom_codex_home_is_rejected_before_writing(self):
        result = self.run_remote("enable", CODEX_HOME=str(self.work / "custom"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Custom CODEX_HOME", result.stderr)
        self.assertEqual(self.snapshot(), {})


if __name__ == "__main__":
    unittest.main()
