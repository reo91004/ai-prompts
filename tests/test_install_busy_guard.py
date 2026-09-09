"""Busy-environment installation barriers; no real packages or services change."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class BusyInstallTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.home = self.work / "home with spaces"
        self.home.mkdir()
        self.kit = self.home / ".universal-research-agent-kit"
        self.darwin_proxy = "/Library/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python -m headroom.cli proxy"
        self.spaced_mcp = "/usr/bin/python3 " + str(self.home / ".local/bin/headroom") + " mcp serve"
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.snapshots = self.work / "snapshots.json"
        self.counter = self.work / "ps-count"
        self.events = self.work / "events"
        self.env = {**os.environ, "HOME": str(self.home), "PATH": str(self.bin) + ":" + os.environ["PATH"],
                    "GUARD_SNAPSHOTS": str(self.snapshots), "GUARD_COUNTER": str(self.counter),
                    "GUARD_EVENTS": str(self.events)}
        for key in ("CODEX_HOME", "CLAUDE_CONFIG_DIR", "HEADROOM_WORKSPACE_DIR", "HEADROOM_CONFIG_DIR",
                    "UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS", "UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING"):
            self.env.pop(key, None)
        self.executable(self.bin / "ps", f"#!{sys.executable}\n" + '''import json, os, pathlib, sys
assert sys.argv[1:] == ['-ww', '-u', str(os.getuid()), '-o', 'pid=', '-o', 'args=']
counter = pathlib.Path(os.environ['GUARD_COUNTER'])
index = int(counter.read_text()) if counter.exists() else 0
counter.write_text(str(index + 1))
rows = json.loads(pathlib.Path(os.environ['GUARD_SNAPSHOTS']).read_text())
row = rows[min(index, len(rows) - 1)]
sys.stdout.write(row['text'])
sys.exit(row.get('exit', 0))
''')
        self.set_snapshots("42 /usr/bin/idle-fixture\n")

    def executable(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        path.chmod(0o755)

    def set_snapshots(self, *snapshots):
        self.counter.unlink(missing_ok=True)
        self.snapshots.write_text(json.dumps([row if isinstance(row, dict) else {"text": row} for row in snapshots]))

    def run_shell(self, script):
        return subprocess.run(["bash", "-c", 'source "$1"\n' + script, "guard-test", str(ROOT / "install.sh")],
                              env=self.env, capture_output=True, text=True)

    def test_recognized_live_tools_and_interpreters(self):
        commands = [
            "/outside/bin/headroom proxy", "headroom mcp serve",
            self.darwin_proxy, self.spaced_mcp,
            "/usr/bin/python3 " + str((self.home / ".local/bin/headroom").resolve()) + " mcp serve",
            str(self.home / ".local/bin/headroom") + " proxy",
            "/usr/bin/python3 -m headroom.cli install agent run --profile research-agent-kit",
            "/usr/bin/python3 -I -B -X utf8 -W ignore -m headroom.cli proxy",
            "/usr/bin/python3 -Im headroom.cli proxy", "/usr/bin/python3 -mheadroom.cli proxy",
            "/usr/bin/python3 /outside/bin/headroom mcp serve",
            "/bin/bash /outside/bin/headroom mcp serve",
            str(self.kit / "tooling/uv-tools/headroom-ai/bin/python") + " -m headroom.cli proxy",
            str(self.kit / "tooling/python-venv/bin/python") + " /old/graphify",
            str(self.kit / "tooling/uv-tools/graphifyy/bin/python") + " /old/graphify",
            str(self.kit / "tooling/python/cpython-3.13/bin/python3") + " -c pass",
            str((self.kit / "tooling/python/cpython-3.13/bin/python3").resolve()) + " -c pass",
            "/usr/bin/python3 -B " + str(self.kit / "tooling/python-venv/bin/headroom") + " proxy",
        ]
        for command in commands:
            with self.subTest(command=command):
                self.set_snapshots("246 " + command + " SECRET_ARG_MUST_NOT_BE_LOGGED\n")
                result = self.run_shell("kit_tooling_idle")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("PID 246", result.stderr)
                self.assertNotIn("SECRET_ARG", result.stdout + result.stderr)
                self.assertEqual(list(self.home.iterdir()), [])

    def test_words_in_prompts_or_code_are_not_processes(self):
        commands = ["/usr/bin/rg headroom", "/bin/bash -c 'python -m headroom.cli'",
                    "/usr/bin/python3 -c 'print(\"headroom proxy\")'",
                    "/usr/bin/python3 tests/test_headroom_runtime.py",
                    "/usr/bin/node /app/codex.js 'headroom mcp serve'",
                    "/outside/bin/headroom-helper", "/usr/bin/python3 -m unittest tests.test_headroom_runtime",
                    str(self.home / ".local/bin/headroom-helper") + " proxy",
                    "/usr/bin/python3 " + str(self.home / ".local/bin/headroom-helper") + " mcp serve"]
        for command in commands:
            with self.subTest(command=command):
                self.set_snapshots("246 " + command + "\n")
                result = self.run_shell("kit_tooling_idle")
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_shell_tracing_does_not_expose_process_arguments(self):
        self.set_snapshots("246 /outside/bin/headroom proxy --key SECRET_ARG_MUST_NOT_BE_LOGGED\n")
        result = self.run_shell("set -x\nkit_tooling_idle")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PID 246", result.stderr)
        self.assertNotIn("SECRET_ARG", result.stdout + result.stderr)

    def test_blocked_install_never_reaches_bootstrap_or_changes_home(self):
        sentinel = self.home / "existing-settings"
        sentinel.write_text("keep")
        for row in ("246 /outside/bin/headroom proxy\n", "246 " + self.darwin_proxy + "\n",
                    "246 " + self.spaced_mcp + "\n", "", "  \n", "not-a-pid /bin/program\n",
                    {"text": "", "exit": 42}):
            with self.subTest(row=row):
                self.set_snapshots(row)
                result = self.run_shell('bootstrap_cli() { echo unexpected > "$GUARD_EVENTS"; return 99; }\nmain')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("stopped before changing this host", result.stderr)
                self.assertFalse(self.events.exists())
                self.assertEqual(list(self.home.iterdir()), [sentinel])
                self.assertEqual(sentinel.read_text(), "keep")

    def test_process_appearing_during_lock_acquisition_blocks_bootstrap(self):
        self.set_snapshots("42 /usr/bin/idle-fixture\n", "246 /outside/bin/headroom mcp serve\n")
        result = self.run_shell('bootstrap_cli() { echo unexpected > "$GUARD_EVENTS"; return 99; }\nmain')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stopped after acquiring its lock", result.stderr)
        self.assertFalse(self.events.exists())
        self.assertFalse((self.kit / "tooling").exists())
        self.assertFalse((self.kit / "cli").exists())
        self.assertFalse((self.kit / ".lock").exists())

    def test_checks_precede_tool_root_python_and_package_mutations(self):
        uv = self.bin / "uv"
        self.executable(uv, '''#!/bin/sh
case "$*" in
  --version) echo 'uv 0.12.10' ;;
  *'python install'*) echo python-provision >> "$GUARD_EVENTS" ;;
  *) echo unexpected-package-write >> "$GUARD_EVENTS"; exit 99 ;;
esac
''')
        sentinel = self.kit / "tooling/existing-environment"
        for scan in (1, 2, 3, 4):
            with self.subTest(scan=scan):
                sentinel.parent.mkdir(parents=True, exist_ok=True)
                sentinel.write_text("keep")
                self.events.unlink(missing_ok=True)
                self.set_snapshots(*(["42 /usr/bin/idle-fixture\n"] * (scan - 1)),
                                   "246 /outside/bin/headroom proxy\n")
                result = self.run_shell("kit_init_state\ntrap kit_release_lock EXIT\nprepare_tooling")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("PID 246", result.stderr)
                if scan <= 2:
                    self.assertEqual(sentinel.read_text(), "keep")
                else:
                    self.assertFalse(sentinel.exists())
                    backups = list((self.kit / "backups").glob("run.*/tooling/environment/existing-environment"))
                    self.assertTrue(backups)
                    self.assertTrue(all(path.read_text() == "keep" for path in backups))
                events = self.events.read_text() if self.events.exists() else ""
                self.assertEqual(events, "python-provision\n" if scan == 4 else "")

    def test_failed_backup_never_clears_the_old_environment(self):
        sentinel = self.kit / "tooling/existing-environment"
        sentinel.parent.mkdir(parents=True)
        sentinel.write_text("keep")
        result = self.run_shell('''kit_init_state
trap kit_release_lock EXIT
kit_backup_path() { return 42; }
prepare_tooling
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(sentinel.read_text(), "keep")

    def test_symlinked_tool_root_does_not_clear_an_external_environment(self):
        external = self.home / "custom-venv"
        external.mkdir()
        sentinel = external / "keep"
        sentinel.write_text("external environment")
        self.kit.mkdir()
        (self.kit / "tooling").symlink_to(external, target_is_directory=True)
        result = self.run_shell("kit_init_state\ntrap kit_release_lock EXIT\nprepare_tooling")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlinked managed tooling", result.stderr)
        self.assertEqual(sentinel.read_text(), "external environment")

    def test_busy_or_uninspectable_environment_prevents_rollback(self):
        for row in ("246 /outside/bin/headroom mcp serve\n", "246 " + self.darwin_proxy + "\n",
                    "246 " + self.spaced_mcp + "\n", {"text": "", "exit": 42}):
            with self.subTest(row=row):
                self.set_snapshots(row)
                self.kit.joinpath("tooling").mkdir(parents=True, exist_ok=True)
                sentinel = self.kit / "tooling/sentinel"
                sentinel.write_text("original")
                result = self.run_shell('''kit_init_state
trap kit_release_lock EXIT
kit_backup_path "$KIT_STATE_ROOT/tooling" tooling/environment
echo current > "$KIT_STATE_ROOT/tooling/sentinel"
kit_rollback_run
''')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("journal", result.stderr)
                self.assertEqual(sentinel.read_text(), "current\n")
                self.assertTrue(list((self.kit / "backups").glob("run.*/journal.tsv")))
                self.assertFalse(list((self.kit / "backups").glob("run.*/journal.tsv.rolled-back")))

    def test_idle_rollback_restores_environment(self):
        self.kit.joinpath("tooling").mkdir(parents=True)
        sentinel = self.kit / "tooling/sentinel"
        sentinel.write_text("original")
        result = self.run_shell('''kit_init_state
trap kit_release_lock EXIT
kit_backup_path "$KIT_STATE_ROOT/tooling" tooling/environment
echo current > "$KIT_STATE_ROOT/tooling/sentinel"
kit_rollback_run
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sentinel.read_text(), "original")
        self.assertTrue(list((self.kit / "backups").glob("run.*/journal.tsv.rolled-back")))

    def test_real_ps_snapshot_of_a_harmless_headroom_named_process(self):
        program = self.work / "headroom"
        self.executable(program, "#!/bin/bash\necho ready\nread -r finish\n")
        process = subprocess.Popen(["bash", str(program), "mcp", "serve"], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(process.stdout.readline().strip(), "ready")
            snapshot = subprocess.check_output([shutil.which("ps"), "-ww", "-u", str(os.getuid()),
                                                "-o", "pid=", "-o", "args="], text=True)
            # Keep unrelated command lines out of fixtures and failure output.
            own = next((line for line in snapshot.splitlines() if line.split(maxsplit=1)[0] == str(process.pid)), None)
            self.assertIsNotNone(own)
            self.set_snapshots(own + "\n")
            result = self.run_shell("kit_tooling_idle")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("PID " + str(process.pid), result.stderr)
            self.assertIsNone(process.poll())
        finally:
            process.communicate("finished\n", timeout=5)


if __name__ == "__main__":
    unittest.main()
