#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kit-release-fallback.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
source "$ROOT/install.sh"
KIT_BACKUP_DIR="$WORK/evidence"
KIT_WORK_DIR="$KIT_BACKUP_DIR/work"
mkdir -p "$KIT_WORK_DIR"
mkdir -p "$KIT_BACKUP_DIR" "$WORK/bin"
cp "$ROOT/tests/mock_latest_curl.sh" "$WORK/bin/curl"
chmod +x "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH"
export KIT_TEST_CURL_LOG="$WORK/downloads"
export KIT_TEST_CODEX_PRIMARY_FAIL=1

# Exercise production download_file, whose failure exits its shell. The primary
# metadata request must be isolated so the supported fallback can still run.
resolve_cli_versions
[ "$KIT_CODEX_SOURCE" = https://api.github.com/repos/openai/codex/releases/latest ]
[ "$KIT_CODEX_VERSION" = 0.153.4 ]
[ "$KIT_CLAUDE_VERSION" = 2.1.0 ]
[ "$KIT_OPENCODE_VERSION" = 2.2.5 ]
[ "$(grep -Fxc 'https://releases.openai.com/codex/channels/latest' "$WORK/downloads")" -eq 1 ]
[ "$(grep -Fxc 'https://api.github.com/repos/openai/codex/releases/latest' "$WORK/downloads")" -eq 1 ]
before="$(cksum "$WORK/downloads")"
resolve_cli_versions
[ "$before" = "$(cksum "$WORK/downloads")" ]
echo 'Production CLI metadata downloader falls back and resolves only once.'
