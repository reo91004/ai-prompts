import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("statusline", ROOT / "scripts/statusline.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ITEMS = tomllib.loads((ROOT / "codex/statusline.toml").read_text())["tui"]["status_line"]


class StatuslineTests(unittest.TestCase):
    def test_toml_merge(self):
        for text in ["", 'model = "custom"\n',
                     '[tui]\ntheme = "dark"\n[tui.other]\nkeep = true\n',
                     '[tui] # comment\nstatus_line = [\n "old",\n]\ntheme = "dark"\n']:
            before = tomllib.loads(text)
            updated = module.merge_codex(text, ITEMS)
            before.setdefault("tui", {})["status_line"] = ITEMS
            self.assertEqual(tomllib.loads(updated), before)
            self.assertEqual(module.merge_codex(updated, ITEMS), updated)
        for text in ['tui = { status_line = ["old"] }\n',
                     '[tui]\n"status_line" = ["old"]\n',
                     'notes = """\n[tui]\nstatus_line = ["old"]\n"""\n']:
            with self.assertRaises((ValueError, tomllib.TOMLDecodeError)):
                module.merge_codex(text, ITEMS)

    def test_install_and_rollback(self):
        with tempfile.TemporaryDirectory(prefix="statusline-") as tmp:
            home = Path(tmp)
            env = dict(os.environ, HOME=tmp,
                       UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING="1",
                       UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS="1")
            env.pop("CODEX_HOME", None)
            env.pop("CLAUDE_CONFIG_DIR", None)
            codex = home / ".codex/config.toml"
            claude = home / ".claude/settings.json"
            script = home / ".claude/statusline.sh"
            codex.parent.mkdir()
            claude.parent.mkdir()
            codex.write_text('model = "custom"\n[tui]\nstatus_line = ["old"]\ntheme = "dark"\n')
            original = {"env": {"KEEP": "yes"}, "statusLine": {"type": "command", "command": "old"}}
            claude.write_text(json.dumps(original))
            claude.chmod(0o600)
            codex.chmod(0o640)
            script.write_text("old script\n")

            def run(*args, success=True):
                result = subprocess.run(["bash", str(ROOT / "install.sh"), *args],
                                        env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)

            run("--without-statusline")
            self.assertEqual(json.loads(claude.read_text()), original)
            self.assertEqual(tomllib.loads(codex.read_text())["tui"]["status_line"], ["old"])
            run()
            module_data = tomllib.loads(codex.read_text())
            self.assertEqual(module_data["model"], "custom")
            self.assertEqual(module_data["tui"], {"theme": "dark", "status_line": ITEMS})
            self.assertEqual(json.loads(claude.read_text())["env"], original["env"])
            self.assertEqual(claude.stat().st_mode & 0o777, 0o600)
            self.assertEqual(codex.stat().st_mode & 0o777, 0o640)
            self.assertEqual(script.read_bytes(), (ROOT / "claude-code/statusline.sh").read_bytes())
            backups = home / ".universal-research-agent-kit/backups"
            self.assertTrue(any(p.read_text() == "old script\n" for p in backups.glob("*/statusline/statusline.sh")))
            installed = (codex.read_bytes(), claude.read_bytes(), script.read_bytes())
            run()
            self.assertEqual((codex.read_bytes(), claude.read_bytes(), script.read_bytes()), installed)
            self.assertEqual(claude.stat().st_mode & 0o777, 0o600)
            self.assertEqual(codex.stat().st_mode & 0o777, 0o640)
            run("--verify")
            script.write_text("user custom statusline\n")
            run("--verify", success=False)
            run("--without-statusline")
            self.assertEqual(script.read_text(), "user custom statusline\n")
            run()

            # A failure after all statusline replacements must restore every file.
            for path, data in [(codex, installed[0]), (claude, installed[1]), (script, b"custom\n")]:
                path.write_bytes(data)
            result = subprocess.run(["bash", "-c", 'source "$1/install.sh"; kit_init_state; '
                                     'kit_enable_rollback; install_statusline; exit 42', "test", str(ROOT)],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
            self.assertEqual((codex.read_bytes(), claude.read_bytes(), script.read_bytes()),
                             (installed[0], installed[1], b"custom\n"))
            claude.write_text("invalid json\n")
            run(success=False)
            self.assertEqual(claude.read_text(), "invalid json\n")
            self.assertEqual(script.read_bytes(), b"custom\n")
            self.assertEqual(codex.read_bytes(), installed[0])
            claude.write_bytes(installed[1])
            script.unlink()
            victim = home / "user-script"
            victim.write_text("do not replace\n")
            script.symlink_to(victim)
            run(success=False)
            self.assertTrue(script.is_symlink())
            self.assertEqual(victim.read_text(), "do not replace\n")

    def test_script_output(self):
        with tempfile.TemporaryDirectory(prefix="statusline-output-") as tmp:
            home = Path(tmp)
            (home / ".claude").mkdir()
            (home / ".claude/.ponytail-active").write_text("full\n")
            subprocess.run(["git", "init", "-q", "-b", "statusline-test", tmp], check=True)
            payload = {"model": {"display_name": "Test Model"}, "workspace": {"current_dir": tmp},
                       "context_window": {"used_percentage": 65.9, "context_window_size": 200000},
                       "effort": {"level": "high"}}
            env = dict(os.environ, HOME=tmp)
            env.pop("CLAUDE_CONFIG_DIR", None)
            result = subprocess.run(["bash", str(ROOT / "claude-code/statusline.sh")], env=env,
                                    input=json.dumps(payload), text=True, capture_output=True, check=True)
            for expected in ["Test Model", "statusline-test", "65% of 200k", "effort:high", "[PONYTAIL:FULL]"]:
                self.assertIn(expected, result.stdout)

    def test_missing_jq_preflight(self):
        with tempfile.TemporaryDirectory(prefix="statusline-no-jq-") as tmp:
            home = Path(tmp)
            bindir = home / "bin"
            bindir.mkdir()
            for name in ["bash", "dirname"]:
                (bindir / name).symlink_to(shutil.which(name))
            env = dict(os.environ, HOME=tmp, PATH=str(bindir))
            env.pop("CODEX_HOME", None)
            env.pop("CLAUDE_CONFIG_DIR", None)
            result = subprocess.run([str(bindir / "bash"), str(ROOT / "install.sh")],
                                    env=env, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("requires jq", result.stderr)
            self.assertFalse((home / ".universal-research-agent-kit").exists())


if __name__ == "__main__":
    unittest.main()
