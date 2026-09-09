"""Exercise the real Bash/Zsh dispatcher with argv-recording CLI executables."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

WRAPPER = Path(__file__).resolve().parents[1] / "headroom/auto-wrap.sh"


class DispatchTests(unittest.TestCase):
    def test_dispatch_argv_environment_and_exit_status(self):
        cases = [
            ("codex", [], "headroom"),
            ("codex", ["exec", "a prompt with spaces"], "headroom"),
            ("codex", ["resume"], "headroom"),
            ("codex", ["remote-control", "start"], "codex"),
            ("codex", ["remote-control", "pair"], "codex"),
            ("codex", ["app-server", "daemon", "version"], "codex"),
            ("codex", ["--config", 'model="custom"', "remote-control", "start"], "codex"),
            ("codex", ["--model", "remote-control", "prompt"], "headroom"),
            ("codex", ["--", "remote-control"], "headroom"),
            ("claude", ["hello"], "headroom"),
            ("claude", ["remote-control", "--spawn", "worktree", "--capacity", "4"], "claude"),
            ("claude", ["--remote-control", "a name"], "claude"),
            ("claude", ["--rc"], "claude"),
            ("claude", ["--rc=a name"], "claude"),
            ("claude", ["--model", "test-model", "--rc"], "claude"),
            ("claude", ["--append-system-prompt", "--rc", "hello"], "headroom"),
            ("claude", ["--", "--rc"], "headroom"),
            ("claude", ["-p", "explain remote-control and --rc"], "headroom"),
            ("codex_raw", ["hello"], "codex"),
            ("claude_raw", ["hello"], "claude"),
        ]
        for shell in ("bash", "zsh"):
            if not shutil.which(shell):
                continue
            with tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                binary_dir = home / "bin"
                binary_dir.mkdir()
                record = home / "record.json"
                for name in ("codex", "claude", "headroom"):
                    path = binary_dir / name
                    path.write_text(f"#!{sys.executable}\n" + """import json, os, pathlib, sys
pathlib.Path(os.environ['RECORD']).write_text(json.dumps({'name': pathlib.Path(sys.argv[0]).name, 'args': sys.argv[1:], 'base': os.environ.get('ANTHROPIC_BASE_URL')}))
sys.exit(int(os.environ.get('CLI_EXIT', '0')))
""")
                    path.chmod(0o755)
                env = {**os.environ, "HOME": str(home), "PATH": str(binary_dir) + ":/usr/bin:/bin",
                       "RECORD": str(record), "ANTHROPIC_BASE_URL": "http://inherited-proxy"}
                for tool, args, expected in cases:
                    with self.subTest(shell=shell, tool=tool, args=args):
                        command = f'source "$1"; shift; {tool} "$@"'
                        result = subprocess.run([shell, "-c", command, "test", str(WRAPPER), *args], env=env, capture_output=True, text=True)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        data = json.loads(record.read_text())
                        self.assertEqual(data["name"], expected)
                        self.assertEqual(data["args"], (["wrap", tool, "--", *args] if expected == "headroom" else args))
                        if tool == "claude" and expected == "claude":
                            self.assertIsNone(data["base"])
                        else:
                            self.assertEqual(data["base"], "http://inherited-proxy")
                result = subprocess.run([shell, "-c", 'source "$1"; codex remote-control start', "test", str(WRAPPER)], env={**env, "CLI_EXIT": "37"})
                self.assertEqual(result.returncode, 37)


    def test_managed_launcher_wins_over_later_path_changes(self):
        for shell in ("bash", "zsh"):
            if not shutil.which(shell):
                continue
            with tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                managed = home / ".universal-research-agent-kit/cli/bin"
                shadow = home / "shadow"
                managed.mkdir(parents=True)
                shadow.mkdir()
                for tool in ("codex", "claude"):
                    for folder, message in ((managed, "managed"), (shadow, "wrong-path")):
                        executable = folder / tool
                        executable.write_text("#!/bin/sh\necho " + message + "\n")
                        executable.chmod(0o755)
                    env = {**os.environ, "HOME": str(home), "PATH": str(shadow) + ":/usr/bin:/bin"}
                    result = subprocess.run([shell, "-c", 'source "$1"; "$2" --version',
                                             "test", str(WRAPPER), tool], env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), "managed")
                    (managed / tool).unlink()
                    (managed / tool).symlink_to(home / "missing")
                    result = subprocess.run([shell, "-c", 'source "$1"; "$2" --version',
                                             "test", str(WRAPPER), tool], env=env, capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("wrong-path", result.stdout)


if __name__ == "__main__":
    unittest.main()
