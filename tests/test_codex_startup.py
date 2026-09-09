"""Exercise real startup files with fake OS managers; never register a user job."""

from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("codex_startup", Path(__file__).resolve().parents[1] / "scripts/codex_startup.py")
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)


class StartupTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="codex-startup-")
        self.addCleanup(directory.cleanup)
        self.home = Path(directory.name)
        self.binary = self.home / startup.LAYOUTS[0]
        self.binary.parent.mkdir(parents=True)
        self.binary.write_text("native executable fixture")
        self.state = self.home / ".universal-research-agent-kit/headroom.json"
        self.state.parent.mkdir()
        self.state.write_text('{"profile":"research-agent-kit"}')
        self.auth = self.home / ".codex/auth.json"
        self.auth.write_text("unchanged authentication")
        self.calls = []
        self.enabled = False
        self.lingering = False
        self.deny_linger = False
        self.disabled_agent = True
        self.fragment = None
        self.dropins = ""
        self.launchd_output = None
        self.addCleanup(lambda: self.assertEqual(self.auth.read_text(), "unchanged authentication"))
        self.run_patch = patch.object(startup.subprocess, "run", side_effect=self.run_command)
        self.run_patch.start()
        self.addCleanup(self.run_patch.stop)
        self.output_patch = redirect_stdout(io.StringIO())
        self.output_patch.__enter__()
        self.addCleanup(self.output_patch.__exit__, None, None, None)

    def run_command(self, args, **kwargs):
        args = tuple(args)
        self.calls.append(args)
        stdout, code = "", 0
        if args[:3] == ("systemctl", "--user", "show"):
            path = startup.startup_path(self.home)
            fragment = self.fragment if self.fragment is not None else (str(path) if path.exists() else "")
            stdout = f"LoadState={'loaded' if fragment else 'not-found'}\nFragmentPath={fragment}\nDropInPaths={self.dropins}\n"
            code = 0 if fragment else 1
        elif args[:3] == ("systemctl", "--user", "is-enabled"):
            enabled = self.enabled if args[3] == startup.UNIT else True
            stdout, code = ("enabled", 0) if enabled else ("disabled", 1)
        elif args == ("systemctl", "--user", "enable", startup.UNIT):
            self.enabled = True
        elif args == ("systemctl", "--user", "disable", startup.UNIT):
            self.enabled = False
        elif args == ("systemctl", "--user", "daemon-reload"):
            pass
        elif args[:2] == ("loginctl", "show-user"):
            stdout = "yes" if self.lingering else "no"
        elif args[:3] == ("loginctl", "--no-ask-password", "enable-linger"):
            self.lingering = not self.deny_linger
            code = 1 if self.deny_linger else 0
        elif args[:2] == ("launchctl", "print-disabled"):
            disabled = "true" if self.disabled_agent else "false"
            stdout = self.launchd_output or f'disabled services = {{\n "{startup.LABEL}" => {disabled}\n}}'
        elif args[:2] == ("launchctl", "enable"):
            self.assertEqual(args[2], f"gui/{os.getuid()}/{startup.LABEL}")
            self.disabled_agent = False
        else:
            raise AssertionError(f"Unexpected manager action (no daemon stop/start is allowed): {args}")
        return subprocess.CompletedProcess(args, code, stdout, "permission denied" if code else "")

    @patch.object(startup.sys, "platform", "linux")
    def test_linux_install_repeat_verify_and_remove_preserve_other_services(self):
        startup.install(self.home, self.binary)
        path = startup.startup_path(self.home)
        contents = path.read_text()
        self.assertIn("After=headroom-research-agent-kit.service", contents)
        self.assertIn("Environment=CODEX_HOME=%h/.codex", contents)
        self.assertIn("codex app-server daemon start", contents)
        self.assertNotIn("remote-control start", contents)
        self.assertTrue(self.enabled and self.lingering)
        modified = path.stat().st_mtime_ns
        startup.install(self.home, self.binary)
        self.assertEqual(path.stat().st_mtime_ns, modified)
        self.assertEqual(sum(call[:3] == ("loginctl", "--no-ask-password", "enable-linger") for call in self.calls), 1)
        startup.verify(self.home, self.binary)
        startup.remove(self.home, self.binary)
        self.assertFalse(path.exists() or self.enabled)
        self.assertTrue(self.lingering)
        self.assertNotIn("--now", {arg for call in self.calls for arg in call})
        self.assertFalse(any(call[0] == "sudo" or "disable-linger" in call for call in self.calls))

    @patch.object(startup.sys, "platform", "linux")
    def test_manual_registration_is_adopted_for_the_default_profile(self):
        self.state.write_text('{"profile":"default"}')
        path = startup.startup_path(self.home)
        path.parent.mkdir(parents=True)
        path.write_text(startup.unit_text(startup.LAYOUTS[0], "default", legacy=True))
        startup.install(self.home, self.binary)
        self.assertEqual(path.read_text(), startup.unit_text(startup.LAYOUTS[0], "default"))
        self.assertEqual(path.stat().st_mode & 0o777, 0o644)

    @patch.object(startup.sys, "platform", "linux")
    def test_linger_denial_does_not_claim_boot_success_or_run_sudo(self):
        self.deny_linger = True
        with self.assertRaisesRegex(RuntimeError, "login-free boot startup still needs linger"):
            startup.install(self.home, self.binary)
        self.assertTrue(self.enabled)
        with self.assertRaisesRegex(RuntimeError, "needs linger"):
            startup.verify(self.home, self.binary)
        self.assertFalse(any(call[0] == "sudo" for call in self.calls))

    @patch.object(startup.sys, "platform", "linux")
    def test_custom_files_dropins_and_units_elsewhere_are_preserved(self):
        path = startup.startup_path(self.home)
        path.parent.mkdir(parents=True)
        path.write_text("[Service]\nExecStart=/my/custom/command\n")
        for action in (startup.install, startup.remove):
            with self.assertRaisesRegex(RuntimeError, "customized"):
                action(self.home, self.binary)
        self.assertEqual(path.read_text(), "[Service]\nExecStart=/my/custom/command\n")
        path.unlink()
        self.dropins = "/custom/override.conf"
        with self.assertRaisesRegex(RuntimeError, "drop-in"):
            startup.install(self.home, self.binary)
        self.dropins = ""
        self.fragment = "/etc/systemd/user/codex-remote-control.service"
        with self.assertRaisesRegex(RuntimeError, "custom Codex startup"):
            startup.install(self.home, self.binary)
        self.assertFalse(path.exists() or self.enabled or self.lingering)

    @patch.object(startup.sys, "platform", "linux")
    def test_symlink_is_refused_and_owned_file_permissions_are_repaired(self):
        path = startup.startup_path(self.home)
        path.parent.mkdir(parents=True)
        target = self.home / "outside.service"
        original = startup.unit_text(startup.LAYOUTS[0], "research-agent-kit")
        target.write_text(original)
        path.symlink_to(target)
        with self.assertRaisesRegex(RuntimeError, "symlinked"):
            startup.install(self.home, self.binary)
        self.assertEqual(target.read_text(), original)
        path.unlink()
        path.write_text(original)
        path.chmod(0o666)
        with self.assertRaisesRegex(RuntimeError, "writable by other users"):
            startup.verify(self.home, self.binary)
        startup.install(self.home, self.binary)
        self.assertEqual(path.stat().st_mode & 0o777, 0o644)

    @patch.object(startup.sys, "platform", "linux")
    def test_verification_rejects_a_stale_binary_or_profile(self):
        startup.install(self.home, self.binary)
        path = startup.startup_path(self.home)
        for layout, profile in ((startup.LAYOUTS[1], "research-agent-kit"), (startup.LAYOUTS[0], "default")):
            path.write_text(startup.unit_text(layout, profile))
            with self.assertRaisesRegex(RuntimeError, "older executable or Headroom profile"):
                startup.verify(self.home, self.binary)

    @patch.object(startup.sys, "platform", "darwin")
    def test_macos_registers_login_once_without_loading_or_stopping_daemon(self):
        startup.install(self.home, self.binary)
        path = startup.startup_path(self.home)
        data = plistlib.loads(path.read_bytes())
        self.assertEqual(data["ProgramArguments"], [str(self.binary), "app-server", "daemon", "start"])
        self.assertIs(data["RunAtLoad"], True)
        self.assertIs(data["AbandonProcessGroup"], True)
        self.assertNotIn("KeepAlive", data)
        self.assertFalse(self.disabled_agent)
        startup.verify(self.home, self.binary)
        self.disabled_agent = True
        with self.assertRaisesRegex(RuntimeError, "startup is disabled"):
            startup.verify(self.home, self.binary)
        startup.remove(self.home, self.binary)
        self.assertFalse(path.exists())
        self.assertFalse(any(call[1] in ("bootout", "bootstrap", "kickstart") for call in self.calls))

    @patch.object(startup.sys, "platform", "darwin")
    def test_macos_custom_plist_and_unreadable_overrides_refuse_changes(self):
        path = startup.startup_path(self.home)
        path.parent.mkdir(parents=True)
        data = startup.launch_agent(self.home, startup.LAYOUTS[0])
        data["KeepAlive"] = True
        path.write_bytes(plistlib.dumps(data))
        with self.assertRaisesRegex(RuntimeError, "customized"):
            startup.install(self.home, self.binary)
        self.assertIs(plistlib.loads(path.read_bytes())["KeepAlive"], True)
        path.unlink()
        self.launchd_output = "an unrecognized output format"
        with self.assertRaisesRegex(RuntimeError, "Cannot read launchd"):
            startup.install(self.home, self.binary)
        self.assertFalse(path.exists())


if __name__ == "__main__":
    unittest.main()
