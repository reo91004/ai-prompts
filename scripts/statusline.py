"""Prepare or verify the bundled statuslines without copying account settings."""

import json
import os
from pathlib import Path
import re
import stat
import sys
import tomllib


def merge_codex(text, items):
    original = tomllib.loads(text)
    expected = dict(original)
    expected["tui"] = dict(original.get("tui", {}), status_line=items)
    value = "status_line = " + json.dumps(items) + "\n"
    lines = text.splitlines(keepends=True)
    headers = [i for i, line in enumerate(lines)
               if re.fullmatch(r"[ \t]*\[tui\][ \t]*(?:#.*)?", line.rstrip("\r\n"))]
    if not headers:
        updated = text.rstrip("\n") + "\n\n[tui]\n" + value
    else:
        start = headers[0] + 1
        end = next((i for i in range(start, len(lines))
                    if re.match(r"\s*\[", lines[i])), len(lines))
        key = next((i for i in range(start, end)
                    if re.match(r"\s*status_line\s*=", lines[i])), None)
        if key is None:
            lines.insert(start, value)
        else:
            # A status_line array can span lines. Parse until its value is complete.
            stop = key + 1
            while True:
                try:
                    tomllib.loads("".join(lines[key:stop]))
                    break
                except tomllib.TOMLDecodeError:
                    if stop >= len(lines):
                        raise ValueError("Cannot locate the complete tui.status_line value")
                    stop += 1
            lines[key:stop] = [value]
        updated = "".join(lines)
    # Refuse unfamiliar dotted/inline/quoted forms or misleading string contents
    # rather than changing any other setting or emitting duplicate TOML keys.
    if tomllib.loads(updated) != expected:
        raise ValueError("Cannot safely merge status_line; use a [tui] table and status_line key")
    return updated


def main():
    action, root_arg, *outputs = sys.argv[1:]
    root = Path(root_arg)
    home = Path(os.environ["HOME"])
    config = home / ".codex/config.toml"
    settings_path = home / ".claude/settings.json"
    items = tomllib.loads((root / "codex/statusline.toml").read_text())["tui"]["status_line"]
    status = json.loads((root / "claude-code/statusline.settings.json").read_text())["statusLine"]
    text = config.read_text() if config.exists() else ""
    settings = json.loads(settings_path.read_text()) if settings_path.exists() else {}
    if action == "prepare":
        updated = merge_codex(text, items)
        settings["statusLine"] = status
        output = Path(outputs[0])
        for source, name, contents in [
            (config, "statusline-codex.next", updated),
            (settings_path, "statusline-claude.next", json.dumps(settings, indent=2) + "\n"),
        ]:
            destination = output / name
            destination.write_text(contents)
            destination.chmod(stat.S_IMODE(source.stat().st_mode) if source.exists() else 0o600)
    elif action == "check":
        if tomllib.loads(text).get("tui", {}).get("status_line") != items:
            raise ValueError("Codex status_line differs from the bundled configuration")
        if settings.get("statusLine") != status:
            raise ValueError("Claude statusLine differs from the bundled configuration")
        installed = home / ".claude/statusline.sh"
        if installed.read_bytes() != (root / "claude-code/statusline.sh").read_bytes():
            raise ValueError("Claude statusline script differs from the bundled script")
        if not os.access(installed, os.X_OK):
            raise ValueError("Claude statusline script is not executable")
    else:
        raise ValueError(f"Unknown action: {action}")


if __name__ == "__main__":
    main()
