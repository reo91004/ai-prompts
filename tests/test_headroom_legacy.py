"""Legacy kit migration fixtures; no accounts, SQLite edits or service calls."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("legacy_runtime", Path(__file__).resolve().parents[1] / "headroom/runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


def block(content):
    return runtime.LEGACY_START + "\n" + content + runtime.LEGACY_END + "\n"


PROVIDER = block('[model_providers.headroom]\nname = "OpenAI via Headroom proxy"\n'
                 'base_url = "http://127.0.0.1:8787/v1"\nsupports_websockets = true\n'
                 'env_http_headers = { "X-Headroom-Project" = "HEADROOM_PROJECT" }\n')
WRAPPER = ('_universal_research_agent_kit_headroom_command() {\n  command headroom "$@"\n}\n'
           'codex() {\n  _universal_research_agent_kit_headroom_command wrap codex -- "$@"\n}\n')


class LegacyTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        home = Path(temporary.name)
        for name, value in {"HOME": home, "KIT": home / ".universal-research-agent-kit",
                            "CONFIG": home / ".codex/config.toml"}.items():
            self.enterContext(patch.object(runtime, name, value))
        self.enterContext(patch.dict(os.environ, {"HOME": str(home)}, clear=True))
        self.enterContext(patch("subprocess.run", side_effect=AssertionError("No service commands")))
        self.enterContext(patch("os.kill", side_effect=AssertionError("No PID signals")))
        runtime.KIT.mkdir()
        runtime.CONFIG.parent.mkdir()
        self.state = runtime.KIT / "tooling.state"
        self.state.write_text("headroom_wrapper=installed\n")
        self.wrapper = home / ".config/headroom/auto-wrap.sh"
        self.wrapper.parent.mkdir(parents=True)
        self.wrapper.write_text(WRAPPER)
        self.backup = runtime.CONFIG.with_name("config.toml.headroom-backup")
        (runtime.CONFIG.parent / "auth.json").write_text("synthetic untouched auth sentinel")
        (runtime.CONFIG.parent / "state_5.sqlite").write_bytes(b"synthetic untouched DB sentinel")

    def migrate(self, original, backup=None):
        runtime.CONFIG.write_text(original)
        if backup is not None:
            self.backup.write_text(backup)
        other_files = {p: p.read_bytes() for p in runtime.HOME.rglob("*") if p.is_file() and p != runtime.CONFIG}
        runtime.migrate_legacy()
        self.assertEqual(other_files, {p: p.read_bytes() for p in runtime.HOME.rglob("*") if p.is_file() and p != runtime.CONFIG})
        result = runtime.CONFIG.read_text()
        runtime.migrate_legacy()
        self.assertEqual(result, runtime.CONFIG.read_text())
        return result

    def test_two_spans_native_and_new_mcp(self):
        user = 'model = "new-model"\n[features]\nkeep = true\n'
        mcp = '[mcp_servers.new]\ncommand = "new-tool"\n'
        result = self.migrate(block('model_provider = "headroom"\nopenai_base_url = "http://127.0.0.1:8787/v1"\n')
                              + user + PROVIDER + mcp)
        self.assertEqual(result, user + mcp)

    def test_was_restores_custom_and_ignores_old_backup_other_content(self):
        root = ('model_provider = "headroom"  # was: personal\n'
                'openai_base_url = "http://127.0.0.1:8787/v1"  # was: https://gateway.example/v1\n')
        user = ('model = "new-model"\n[model_providers.personal]\nbase_url = "https://gateway.example/v1"\n'
                '[profiles.saved]\nmodel_provider = "headroom" # was: table-personal\n'
                'openai_base_url = "http://127.0.0.1:8787/v1"\n'
                '[mcp_servers.new]\ncommand = "new-tool"\n')
        result = self.migrate(root + user + PROVIDER,
                              'model_provider = "old-personal"\nmodel = "old-model"\n[mcp_servers.old]\ncommand = "old"\n')
        self.assertEqual(result, 'model_provider = "personal"\nopenai_base_url = "https://gateway.example/v1"\n' + user)

    def test_root_backup_only_and_preserve_new_selection(self):
        for selection in ('"headroom"', '"new-personal" # was: older'):
            with self.subTest(selection=selection):
                original = 'model_provider = ' + selection + '\n[profiles.saved]\nmodel_provider = "headroom"\n' + PROVIDER
                result = self.migrate(original, 'model_provider = "personal"\n[profiles.saved]\nmodel_provider = "backup-only"\n')
                config = runtime.tomllib.loads(result)
                self.assertEqual(config["model_provider"], "personal" if selection == '"headroom"' else "new-personal")
                self.assertEqual(config["profiles"]["saved"]["model_provider"], "headroom")

    def test_backup_table_key_is_not_restored_as_root(self):
        result = self.migrate(block('model_provider = "headroom"\n') + PROVIDER,
                              '[profiles.saved]\nmodel_provider = "personal"\n')
        self.assertNotIn("model_provider", runtime.tomllib.loads(result))

    def test_multiline_strings_with_marker_text_are_preserved(self):
        for delimiter in ('"""', "'''" ):
            with self.subTest(delimiter=delimiter):
                user = 'instructions = ' + delimiter + '\n' + runtime.LEGACY_START + '\n[not.a.table]\n' + runtime.LEGACY_END + '\n' + delimiter + '\n'
                result = self.migrate(block('model_provider = "headroom"\n') + user + PROVIDER)
                self.assertEqual(result, user)

    def test_escaped_original_string_is_restored(self):
        result = self.migrate('model_provider = "headroom" # was: personal\\\\name\n' + PROVIDER)
        self.assertEqual(runtime.tomllib.loads(result)["model_provider"], "personal\\name")

    def test_no_ownership_or_new_wrapper_leaves_config_untouched(self):
        original = block('model_provider = "headroom"\n') + PROVIDER
        self.state.write_text("headroom_wrapper=skipped\n")
        self.assertEqual(self.migrate(original), original)
        self.state.write_text("headroom_wrapper=installed\n")
        self.wrapper.write_text("codex() { command codex; }\n")
        self.assertEqual(self.migrate(original), original)

    def test_malformed_ambiguous_and_custom_spans_do_not_write(self):
        cases = [
            'model = [\n' + PROVIDER,
            runtime.LEGACY_START + '\nmodel_provider = "headroom"\n',
            runtime.LEGACY_END + '\n',
            runtime.LEGACY_START + '\n' + PROVIDER + runtime.LEGACY_END + '\n',
            'model_provider = "headroom"\n' + PROVIDER,
            '"model_provider" = "headroom" # was: openai\n' + PROVIDER,
            block('[model_providers.personal]\nbase_url = "https://personal.example"\n'),
            block('model_provider = "new-personal"\n') + PROVIDER,
        ]
        for original in cases:
            with self.subTest(original=original):
                runtime.CONFIG.write_text(original)
                with self.assertRaises((RuntimeError, ValueError)):
                    runtime.migrate_legacy()
                self.assertEqual(runtime.CONFIG.read_text(), original)

    def test_customized_provider_fields_are_preserved(self):
        generated = {'name': 'OpenAI via Headroom proxy', 'base_url': runtime.BASE_URL + '/v1',
                     'supports_websockets': True}
        changes = ({'name': 'User Gateway'}, {'base_url': 'https://gateway.example/v1'},
                   {'http_headers': {'X-User-Route': 'keep'}}, {'supports_websockets': False},
                   {'env_http_headers': {'X-Headroom-Project': 'USER_PROJECT'}},
                   {'env_http_headers': {'X-Other': 'CUSTOM'}})
        import json
        for change in changes:
            with self.subTest(change=change):
                fields = []
                for key, value in {**generated, **change}.items():
                    encoded = ('{' + ', '.join(json.dumps(k) + ' = ' + json.dumps(v) for k, v in value.items()) + '}') if isinstance(value, dict) else json.dumps(value)
                    fields.append(key + ' = ' + encoded + '\n')
                original = block('model_provider = "headroom"\n') + block('[model_providers.headroom]\n' + ''.join(fields))
                runtime.CONFIG.write_text(original)
                with self.assertRaisesRegex(RuntimeError, 'customized'):
                    runtime.migrate_legacy()
                self.assertEqual(runtime.CONFIG.read_text(), original)

    def test_known_duplicate_mcp_blocks_precede_toml_validation(self):
        for old_path in ("tooling/bin/headroom", "tooling/python-venv/bin/headroom"):
            with self.subTest(old_path=old_path):
                known = str(runtime.KIT / old_path)
                mcp = ('# --- Headroom MCP server ---\n[mcp_servers.headroom]\n'
                       'command = "' + known + '"\nargs = ["mcp"]\n# --- end Headroom MCP server ---\n')
                user = 'model = "new-model"\n[mcp_servers.new]\ncommand = "keep"\n'
                original = block('model_provider = "headroom"\n') + user + PROVIDER + mcp + mcp
                self.assertEqual(self.migrate(original), user)

    def test_standalone_known_mcp_and_custom_single_server(self):
        self.wrapper.unlink()
        for command in (str(runtime.KIT / "tooling/bin/headroom"), "/custom/headroom"):
            with self.subTest(command=command):
                mcp = ('# --- Headroom MCP server ---\n[mcp_servers.headroom]\n'
                       'command = "' + command + '"\n# --- end Headroom MCP server ---\n')
                original = 'model = "keep"\n' + mcp
                result = self.migrate(original)
                self.assertEqual(result, 'model = "keep"\n' if command.startswith(str(runtime.KIT)) else original)

    def test_custom_duplicate_mcp_and_other_malformed_data_are_not_modified(self):
        known = ('# --- Headroom MCP server ---\n[mcp_servers.headroom]\n'
                 'command = "' + str(runtime.KIT / "tooling/bin/headroom")
                 + '"\n# --- end Headroom MCP server ---\n')
        for extra in ('[mcp_servers.headroom]\ncommand = "/custom/headroom"\n',
                      'model = "duplicate"\nmodel = "invalid"\n'):
            original = extra + known
            runtime.CONFIG.write_text(original)
            with self.assertRaises((RuntimeError, ValueError)):
                runtime.migrate_legacy()
            self.assertEqual(runtime.CONFIG.read_text(), original)

    def test_malformed_backup_does_not_write(self):
        original = 'model_provider = "headroom"\n' + PROVIDER
        runtime.CONFIG.write_text(original)
        self.backup.write_text('model_provider = [\n')
        with self.assertRaises(ValueError):
            runtime.migrate_legacy()
        self.assertEqual(runtime.CONFIG.read_text(), original)


if __name__ == "__main__":
    unittest.main()
