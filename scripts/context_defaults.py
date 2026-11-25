"""Prepare or check Codex context and TUI defaults while preserving the user's TOML.

Codex 0.166 normalizes an explicit empty fallback prompt to None. It prevents
model-owned fallback defaults and adds no fallback buffer, even when a positive
buffer value remains configured. This does not disable the token-budget feature.
"""

from collections.abc import MutableMapping
from pathlib import Path
import stat
import sys
import tomllib

import tomlkit


ROOT_KEYS = (
    "model_context_window",
    "model_auto_compact_token_limit",
    "model_auto_compact_token_limit_scope",
    "model_post_turn_compact_threshold_percent",
    "model_reasoning_effort",
)


def feature_table(features, name):
    if name not in features:
        features[name] = tomlkit.inline_table()
    elif isinstance(features[name], bool):
        replacement = tomlkit.inline_table()
        if name == "token_budget":
            replacement["enabled"] = features[name]
        features[name] = replacement
    value = features[name]
    if not isinstance(value, MutableMapping):
        raise ValueError(f"features.{name} must be a boolean or table")
    if "enabled" in value and not isinstance(value["enabled"], bool):
        raise ValueError(f"features.{name}.enabled must be a boolean")
    if name == "context_management" and "enabled" in value:
        comment = value.item("enabled").trivia.comment
        del value["enabled"]
        if comment:
            value.add(tomlkit.comment(comment.lstrip("# ")))
    return value


def check_config(text, defaults):
    config = tomllib.loads(text)
    for key in ROOT_KEYS:
        value = config.get(key)
        if type(value) is not type(defaults[key]) or value != defaults[key]:
            raise ValueError(f"Codex {key} differs from the bundled context default")
    features = config.get("features")
    if not isinstance(features, dict):
        raise ValueError("Codex features must be a table")
    context = features.get("context_management")
    if not isinstance(context, dict) or context.get("experimental_mode") is not True:
        raise ValueError("Codex experimental context management is not configured")
    if "enabled" in context:
        raise ValueError("Codex context_management does not support an enabled table key")
    budget = features.get("token_budget")
    if budget is not False and (not isinstance(budget, dict) or budget.get("auto_compact_fallback_prompt") != ""):
        raise ValueError("Codex token budget must be disabled or have an explicit empty fallback prompt")
    for name, value in (("context_management", context), ("token_budget", budget)):
        if isinstance(value, dict) and "enabled" in value and type(value["enabled"]) is not bool:
            raise ValueError(f"features.{name}.enabled must be a boolean")
    tui = config.get("tui")
    if not isinstance(tui, dict) or tui.get("collapse_turn_details") is not defaults["tui"]["collapse_turn_details"]:
        raise ValueError("Codex tui.collapse_turn_details differs from the bundled context default")


def merge_config(text, defaults):
    document = tomlkit.parse(text)
    for key in ROOT_KEYS:
        document[key] = defaults[key]
    if "features" not in document:
        document["features"] = tomlkit.table()
    features = document["features"]
    if not isinstance(features, MutableMapping):
        raise ValueError("Codex features must be a table")
    feature_table(features, "context_management")["experimental_mode"] = True
    if features.get("token_budget") is not False:
        feature_table(features, "token_budget")["auto_compact_fallback_prompt"] = ""
    if "tui" not in document:
        document["tui"] = tomlkit.table()
    if not isinstance(document["tui"], MutableMapping):
        raise ValueError("Codex tui must be a table")
    document["tui"]["collapse_turn_details"] = defaults["tui"]["collapse_turn_details"]
    updated = tomlkit.dumps(document)
    check_config(updated, defaults)
    return updated


def main():
    action, *args = sys.argv[1:]
    if action not in ("prepare", "check") or len(args) != (3 if action == "prepare" else 2):
        raise ValueError("Usage: context_defaults.py prepare <template> <config> <output> | check <template> <config>")
    template, config = map(Path, args[:2])
    defaults = tomllib.loads(template.read_text())
    text = config.read_text() if config.exists() else ""
    if action == "check":
        check_config(text, defaults)
        return
    output = Path(args[2])
    if output.is_symlink() or output.resolve() in (template.resolve(), config.resolve()):
        raise ValueError("Context defaults output must be a separate staging file")
    updated = merge_config(text, defaults)
    output.write_text(updated)
    output.chmod(stat.S_IMODE(config.stat().st_mode) if config.exists() else 0o600)


if __name__ == "__main__":
    main()
