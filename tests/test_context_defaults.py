"""Context policy and TOML-preserving staging; no real account configuration."""

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest

from tomlkit.exceptions import TOMLKitError


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "codex/context.toml"
SCRIPT = ROOT / "scripts/context_defaults.py"
spec = importlib.util.spec_from_file_location("context_defaults", SCRIPT)
context = importlib.util.module_from_spec(spec)
spec.loader.exec_module(context)


class ContextDefaultsTests(unittest.TestCase):
    def setUp(self):
        self.defaults = context.read_defaults(TEMPLATE)

    def test_bundled_policy_is_one_million_with_an_800k_total_boundary(self):
        self.assertEqual(self.defaults["model_context_window"], 1_000_000)
        self.assertEqual(self.defaults["model_auto_compact_token_limit"], 800_000)
        self.assertEqual(self.defaults["model_auto_compact_token_limit_scope"], "total")
        self.assertEqual(self.defaults["model_post_turn_compact_threshold_percent"], 0)
        self.assertEqual(self.defaults["features"]["token_budget"], {"auto_compact_fallback_prompt": ""})

    def test_empty_config_and_repeated_merge(self):
        updated = context.merge_config("", self.defaults)
        context.check_config(updated, self.defaults)
        self.assertEqual(updated, context.merge_config(updated, self.defaults))

    def test_existing_budget_settings_comments_and_account_fields_are_preserved(self):
        original = '''# account comment
model = "user-model"
model_context_window = 200000 # window comment
model_auto_compact_token_limit = 150000
model_auto_compact_token_limit_scope = "input"
model_post_turn_compact_threshold_percent = 90
notes = """Do not interpret this as a header:
[features.token_budget]
auto_compact_fallback_prompt = "inside notes"
"""

[features]
user_feature = true

[features.context_management]
enabled = true # context preference
experimental_mode = false

[features.token_budget] # token budget comment
enabled = true
auto_compact_fallback_prompt = "old fallback" # prompt comment
auto_compact_fallback_buffer_tokens = 64000
reminder_threshold_tokens = 40000
reminder_message_template = "Keep {n_remaining} tokens."
guidance_message = "user guidance"
use_history_notes_extension = false

[model_providers."user provider"]
base_url = "https://private.example"
env_key = "PRIVATE_ACCOUNT_SENTINEL"

[agents]
max_threads = 4
'''
        updated = context.merge_config(original, self.defaults)
        before, after = tomllib.loads(original), tomllib.loads(updated)
        self.assertEqual(after["model_providers"], before["model_providers"])
        self.assertEqual(after["agents"], before["agents"])
        self.assertEqual(after["notes"], before["notes"])
        self.assertEqual(after["model"], before["model"])
        self.assertTrue(after["features"]["user_feature"])
        expected_budget = {**before["features"]["token_budget"], "auto_compact_fallback_prompt": ""}
        self.assertEqual(after["features"]["token_budget"], expected_budget)
        for comment in ("# account comment", "# window comment", "# context preference", "# token budget comment", "# prompt comment"):
            self.assertIn(comment, updated)
        self.assertEqual(updated, context.merge_config(updated, self.defaults))
        context.check_config(updated, self.defaults)

    def test_quoted_dotted_inline_and_out_of_order_tables(self):
        texts = [
            '"features"."context_management".experimental_mode = false\n'
            'features.token_budget.enabled = true\nfeatures.user_feature = false\n',
            'features = {context_management = {enabled=true, experimental_mode=false}, '
            'token_budget = {enabled=true, auto_compact_fallback_buffer_tokens=12345}, user_feature=false} # inline\n',
            '["features"."token_budget"]\nenabled=true\n["features"."context_management"]\nexperimental_mode=false\n',
            '[features]\ntoken_budget=true # keep boolean comment\n'
            '[model_providers.test]\nbase_url="https://private.example"\n'
            '[features.context_management]\nenabled=true\nexperimental_mode=false\n',
        ]
        for text in texts:
            with self.subTest(text=text):
                before = tomllib.loads(text)
                updated = context.merge_config(text, self.defaults)
                after = tomllib.loads(updated)
                context.check_config(updated, self.defaults)
                self.assertEqual(after.get("model_providers"), before.get("model_providers"))
                self.assertEqual(after["features"].get("user_feature"), before["features"].get("user_feature"))
                if "# inline" in text:
                    self.assertIn("# inline", updated)
                if "# keep boolean comment" in text:
                    self.assertIn("token_budget={", updated)
                    self.assertIn("# keep boolean comment", updated)
                self.assertEqual(updated, context.merge_config(updated, self.defaults))

    def test_boolean_token_budget_false_stays_false(self):
        original = '[features]\ntoken_budget = false # intentionally disabled\ncontext_management = true\n'
        updated = context.merge_config(original, self.defaults)
        features = tomllib.loads(updated)["features"]
        self.assertIs(features["token_budget"], False)
        self.assertEqual(features["context_management"], {"experimental_mode": True})
        self.assertIn("token_budget = false # intentionally disabled", updated)
        context.check_config(updated, self.defaults)

    def test_boolean_true_keeps_enabled_and_inline_comment(self):
        for original in (
            '[features]\ntoken_budget = true # budget enabled\ncontext_management = false # context disabled\n',
            'features = { token_budget = true, context_management = false } # inline features\n',
        ):
            with self.subTest(original=original):
                updated = context.merge_config(original, self.defaults)
                features = tomllib.loads(updated)["features"]
                self.assertEqual(features["token_budget"], {"enabled": True, "auto_compact_fallback_prompt": ""})
                self.assertEqual(features["context_management"], {"experimental_mode": True})
                for line in original.splitlines():
                    if "#" in line:
                        self.assertIn("#" + line.split("#", 1)[1], updated)

    def test_disabled_table_and_positive_buffer_are_preserved(self):
        original = '[features.token_budget]\nenabled=false\nauto_compact_fallback_buffer_tokens=90000\n'
        updated = context.merge_config(original, self.defaults)
        budget = tomllib.loads(updated)["features"]["token_budget"]
        self.assertEqual(budget, {"enabled": False, "auto_compact_fallback_buffer_tokens": 90000,
                                  "auto_compact_fallback_prompt": ""})
        context.check_config(updated, self.defaults)

    def test_invalid_feature_types_and_null_are_rejected(self):
        for text in (
            'features = null\n', 'features = false\n', 'features = []\n',
            'features = "PRIVATE_ACCOUNT_SENTINEL"\n',
            '[features]\ncontext_management = []\n',
            '[features]\ntoken_budget = 3\n',
            '[features.token_budget]\nenabled = "false"\n',
            '[features.context_management]\nenabled = 1\n',
        ):
            with self.subTest(text=text), self.assertRaises((ValueError, TOMLKitError)):
                context.merge_config(text, self.defaults)

    def test_check_requires_explicit_fallback_choice_and_exact_threshold_semantics(self):
        valid = context.merge_config('[features.token_budget]\nauto_compact_fallback_buffer_tokens=90000\n', self.defaults)
        invalid = [
            valid.replace('auto_compact_fallback_prompt = ""', 'auto_compact_fallback_prompt = "take notes"'),
            valid.replace('auto_compact_fallback_prompt = ""\n', ''),
            valid.replace('model_auto_compact_token_limit_scope = "total"', 'model_auto_compact_token_limit_scope = "input"'),
            valid.replace('model_auto_compact_token_limit = 800000', 'model_auto_compact_token_limit = 800001'),
            valid.replace('model_post_turn_compact_threshold_percent = 0', 'model_post_turn_compact_threshold_percent = false'),
            valid.replace('model_post_turn_compact_threshold_percent = 0', 'model_post_turn_compact_threshold_percent = 80'),
        ]
        for text in invalid:
            with self.subTest(text=text), self.assertRaises(ValueError):
                context.check_config(text, self.defaults)

    def test_template_rejects_invalid_types_and_unrelated_fields(self):
        original = TEMPLATE.read_text()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "template.toml"
            for text in (
                original.replace('1000000', '"1000000"'),
                original.replace('800000', '1200000'),
                original.replace('experimental_mode = true', 'experimental_mode = 1'),
                original.replace('auto_compact_fallback_prompt = ""', 'auto_compact_fallback_prompt = "notes"'),
                'model_provider = "PRIVATE_ACCOUNT_SENTINEL"\n' + original,
            ):
                path.write_text(text)
                with self.subTest(text=text), self.assertRaises(ValueError):
                    context.read_defaults(path)

    def test_cli_stages_without_touching_source_and_check_is_read_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config, output = root / "config.toml", root / "prepared.toml"
            config.write_text('model="custom"\n[model_providers.test]\nenv_key="PRIVATE_ACCOUNT_SENTINEL"\n')
            config.chmod(0o640)
            original = config.read_bytes()
            result = subprocess.run([sys.executable, "-B", str(SCRIPT), "prepare", str(TEMPLATE), str(config), str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(config.read_bytes(), original)
            self.assertEqual(output.stat().st_mode & 0o777, 0o640)
            self.assertNotIn("PRIVATE_ACCOUNT_SENTINEL", result.stdout + result.stderr)
            before = {path.name: path.read_bytes() for path in root.iterdir()}
            result = subprocess.run([sys.executable, "-B", str(SCRIPT), "check", str(TEMPLATE), str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(before, {path.name: path.read_bytes() for path in root.iterdir()})
            self.assertEqual(result.stdout, "")
            self.assertEqual(result.stderr, "")

    def test_cli_handles_absent_config_and_preserves_output_on_invalid_input(self):
        with tempfile.TemporaryDirectory() as directory:
            config, output = Path(directory) / "missing.toml", Path(directory) / "prepared.toml"
            command = [sys.executable, "-B", str(SCRIPT), "prepare", str(TEMPLATE), str(config), str(output)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(config.exists())
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            original_output = output.read_bytes()
            config.write_text('features = "PRIVATE_ACCOUNT_SENTINEL"\n')
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("PRIVATE_ACCOUNT_SENTINEL", result.stdout + result.stderr)
            self.assertEqual(output.read_bytes(), original_output)
            self.assertEqual(config.read_text(), 'features = "PRIVATE_ACCOUNT_SENTINEL"\n')

    def test_cli_refuses_source_and_symlink_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            config, output = Path(directory) / "config.toml", Path(directory) / "link.toml"
            config.write_text('model="custom"\n')
            output.symlink_to(config)
            for destination in (config, output):
                result = subprocess.run([sys.executable, "-B", str(SCRIPT), "prepare", str(TEMPLATE), str(config), str(destination)], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(config.read_text(), 'model="custom"\n')
            self.assertTrue(output.is_symlink())


if __name__ == "__main__":
    unittest.main()
