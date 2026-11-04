#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TEST_NODE="$(command -v node)"
TEST_PYTHON="$(python3 -c 'import sys; print(sys.executable)')"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME" "$WORK/bin" "$WORK/node/bin"
"$TEST_PYTHON" - "$ROOT" <<'PY'
import os, pathlib, subprocess, sys, tempfile
for action in ([], ['--verify']):
    with tempfile.TemporaryDirectory() as directory:
        home = pathlib.Path(directory) / 'home'
        home.mkdir()
        custom = pathlib.Path(directory) / 'custom'
        custom.mkdir()
        result = subprocess.run(['bash', sys.argv[1] + '/install.sh', *action],
            env={**os.environ, 'HOME': str(home), 'CODEX_HOME': str(custom)}, capture_output=True, text=True)
        assert result.returncode and 'Custom CODEX_HOME' in result.stderr, result.stderr
        assert not list(home.iterdir()) and not list(custom.iterdir()), action
PY
for name in sh bash dirname basename mkdir mktemp date cp mv rm rmdir awk tar gzip shasum sha256sum uname chmod ln grep cat id sed cmp readlink jq; do
  binary="$(command -v "$name" || true)"
  [ -z "$binary" ] || ln -s "$binary" "$WORK/bin/$name"
done
for name in node npm npx; do
  printf '%s\n' '#!/bin/sh' 'if [ "${1:-}" = --version ]; then echo 24.21.0; else exec "$TEST_NODE" "$@"; fi' > "$WORK/node/bin/$name"
  chmod +x "$WORK/node/bin/$name"
done
tar -czf "$WORK/node.tar.gz" -C "$WORK" node
source "$ROOT/install.sh"
source "$ROOT/scripts/codex_remote.sh"
export PATH="$WORK/bin"
kit_init_state
KIT_HEADROOM_PYTHON="$TEST_PYTHON"
export BOOTSTRAP_CALLS="$WORK/calls"
export MOCK_CODEX_LATEST=0.153.4 MOCK_CLAUDE_LATEST=2.1.0 MOCK_OPENCODE_LATEST=2.2.5
printf '%s\n' '#!/bin/sh' 'echo v12.0.0' > "$WORK/bin/node"
chmod +x "$WORK/bin/node"

download_file() {
  # Record CLI metadata and payload requests; keep the Node fixture lookup quiet.
  if [ "$1" = https://nodejs.org/dist/index.json ]; then
    printf '%s\n' '[' '{"version":"v25.1.0","lts":false},' '{"version":"v24.21.0","lts":"Krypton"},' > "$2"
    return
  fi
  printf '%s\n' "$1" >> "$BOOTSTRAP_CALLS"
  case "$1" in
    https://releases.openai.com/codex/channels/latest)
      [ "${MOCK_CODEX_PRIMARY_DOWN:-0}" -ne 1 ] || return 22
      printf '{"tag_name":"rust-v%s","prerelease":false}\n' "$MOCK_CODEX_LATEST" > "$2" ;;
    https://api.github.com/repos/openai/codex/releases/latest)
      printf '{"tag_name":"rust-v%s","prerelease":false}\n' "$MOCK_CODEX_LATEST" > "$2" ;;
    https://downloads.claude.ai/claude-code-releases/latest)
      printf '%s\n' "$MOCK_CLAUDE_LATEST" > "$2" ;;
    https://opencode.ai/update/api/latest/cli/npm)
      printf '{"version":"%s","metadata":{"package":"@opencode/cli"},"active":true}\n' "$MOCK_OPENCODE_LATEST" > "$2" ;;
    https://registry.npmjs.org/@opencode%2fcli-*/*)
      mkdir -p "$WORK/opencode-package/package/bin"
      printf '%s\n' '#!/bin/sh' 'case "$*" in' "  --version) echo v${1##*/} ;;" '  "plugin --help") : ;;' '  *) exit 1 ;;' 'esac' \
        > "$WORK/opencode-package/package/bin/opencode"
      chmod +x "$WORK/opencode-package/package/bin/opencode"
      tar -czf "$WORK/opencode-package.tgz" -C "$WORK/opencode-package" package
      node -e 'const fs=require("fs"),c=require("crypto"),u=new URL(process.argv[1]),parts=decodeURIComponent(u.pathname.slice(1)).split("/"),v=parts.pop();
        console.log(JSON.stringify({name:parts.join("/"),version:v,dist:{tarball:"https://registry.npmjs.org/@opencode/cli-fixture/-/package.tgz",integrity:"sha512-"+c.createHash("sha512").update(fs.readFileSync(process.argv[2])).digest("base64")}}));' \
        "$1" "$WORK/opencode-package.tgz" > "$2" ;;
    https://registry.npmjs.org/@opencode/cli-fixture/-/package.tgz)
      cp "$WORK/opencode-package.tgz" "$2"
      [ "${MOCK_OPENCODE_CORRUPT:-0}" -ne 1 ] || printf 'corrupt' >> "$2" ;;
    *nodejs.org*tar.gz) cp "$WORK/node.tar.gz" "$2" ;;
    *nodejs.org*SHASUMS256.txt)
      if command -v shasum >/dev/null; then digest="$(shasum -a 256 "$WORK/node.tar.gz")"; else digest="$(sha256sum "$WORK/node.tar.gz")"; fi
      for platform in darwin linux; do
        for arch in arm64 x64; do printf '%s  node-v24.21.0-%s-%s.tar.gz\n' "${digest%% *}" "$platform" "$arch"; done
      done > "$2"
      ;;
    https://chatgpt.com/codex/install.sh)
      cat > "$2" <<'INSTALL'
#!/bin/sh
test "$CODEX_NON_INTERACTIVE" = 1
test "$1" = --release
test "$2" = "$MOCK_CODEX_LATEST"
mkdir -p "$HOME/.codex/packages/standalone/current/bin" "$CODEX_INSTALL_DIR"
printf '%s\n' "$2" > "$HOME/.codex/packages/standalone/current/fixture-version"
cat > "$HOME/.codex/packages/standalone/current/bin/codex" <<'CLI'
#!/bin/sh
case "$*" in
  --version) printf 'codex %s\n' "$(cat "$HOME/.codex/packages/standalone/current/fixture-version")" ;;
  *--help) : ;;
  'remote-control start --json')
    case "${REMOTE_TEST_FAILURE:-}" in
      unmanaged) echo 'Error: app server is running but is not managed by codex app-server daemon' >&2; exit 42 ;;
      invalid_json) echo 'invalid-json DO_NOT_PERSIST'; exit 0 ;;
    esac
    mkdir -p "$HOME/.codex/app-server-daemon"
    echo '{"remoteControlEnabled":true}' > "$HOME/.codex/app-server-daemon/settings.json"
    echo 'remote-start' >> "$BOOTSTRAP_CALLS"
    printf '{"status":"%s","environmentId":"DO_NOT_PERSIST"}\n' "${REMOTE_TEST_STATUS:-connected}"
    ;;
  'app-server daemon version')
    case "${REMOTE_TEST_VERSION_FAILURE:-}" in
      failed) echo 'Error: daemon inspection failed' >&2; exit 43 ;;
      invalid_json) echo 'invalid-json DO_NOT_PERSIST'; exit 0 ;;
    esac
    printf '{"status":"running","backend":"%s"}\n' "${REMOTE_TEST_BACKEND:-pid}" ;;
  'app-server daemon disable-remote-control')
    echo '{"remoteControlEnabled":false}' > "$HOME/.codex/app-server-daemon/settings.json"
    echo 'remote-disabled' >> "$BOOTSTRAP_CALLS"
    ;;
  *) exit 1 ;;
esac
CLI
chmod +x "$HOME/.codex/packages/standalone/current/bin/codex"
ln -sf "$HOME/.codex/packages/standalone/current/bin/codex" "$CODEX_INSTALL_DIR/codex"
INSTALL
      ;;
    https://claude.ai/install.sh)
      cat > "$2" <<'INSTALL'
#!/bin/sh
test "$1" = "$MOCK_CLAUDE_LATEST"
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/claude/versions"
printf '%s\n' '#!/bin/sh' "echo '$1 (Claude Code)'" > "$HOME/.local/share/claude/versions/$1"
ln -s "$HOME/.local/share/claude/versions/$1" "$HOME/.local/bin/claude"
chmod +x "$HOME/.local/bin/claude"
INSTALL
      ;;
    *) echo "Unexpected download: $1" >&2; exit 1 ;;
  esac
}

bootstrap_cli
for name in codex claude opencode node npx; do command -v "$name" >/dev/null; done
! grep -Fq remote-start "$BOOTSTRAP_CALLS"
[ ! -e "$KIT_STATE_ROOT/codex-remote-control.state" ]
before="$(cat "$BOOTSTRAP_CALLS")"
bootstrap_cli
[ "$before" = "$(cat "$BOOTSTRAP_CALLS")" ]
# Existing native payloads repair missing/dangling kit launchers without download.
rm "$KIT_STATE_ROOT/cli/bin/codex" "$KIT_STATE_ROOT/cli/bin/claude" "$KIT_STATE_ROOT/cli/bin/opencode"
ln -s "$WORK/missing-codex" "$KIT_STATE_ROOT/cli/bin/codex"
ln -s "$WORK/missing-claude" "$KIT_STATE_ROOT/cli/bin/claude"
ln -s "$WORK/missing-opencode" "$KIT_STATE_ROOT/cli/bin/opencode"
bootstrap_cli
verify_native_clis
[ "$before" = "$(cat "$BOOTSTRAP_CALLS")" ]

# A new install resolves new release metadata even when all old CLIs still work.
export MOCK_CODEX_LATEST=0.154.0 MOCK_CLAUDE_LATEST=2.1.1 MOCK_OPENCODE_LATEST=2.2.6
unset KIT_CLI_VERSIONS_RESOLVED
bootstrap_cli
verify_native_clis
[ "$(cli_version "$(managed_codex)")" = 0.154.0 ]
[ "$(cli_version "$HOME/.local/bin/claude")" = 2.1.1 ]
[ "$(cli_version "$HOME/.opencode/bin/opencode")" = 2.2.6 ]
for endpoint in codex/channels/latest claude-code-releases/latest latest/cli/npm; do
  [ "$(grep -c "$endpoint" "$BOOTSTRAP_CALLS")" -eq 2 ]
done

# Preserve the official installer's GitHub fallback when its primary host is unavailable.
(
  MOCK_CODEX_PRIMARY_DOWN=1 KIT_CLI_VERSIONS_RESOLVED=0 bootstrap_cli
  [ "$KIT_CODEX_SOURCE" = https://api.github.com/repos/openai/codex/releases/latest ]
) > "$WORK/codex-fallback.log" 2>&1

# Bad V2 metadata and corrupt packages must leave the selected binary intact.
if (MOCK_OPENCODE_LATEST=1.19.5 KIT_CLI_VERSIONS_RESOLVED=0 bootstrap_cli) > "$WORK/v1-refused.log" 2>&1; then exit 1; fi
grep -Fq 'Invalid OpenCode V2 release metadata' "$WORK/v1-refused.log"
if (MOCK_OPENCODE_LATEST=2.2.7 MOCK_OPENCODE_CORRUPT=1 KIT_CLI_VERSIONS_RESOLVED=0 bootstrap_cli) > "$WORK/corrupt-opencode.log" 2>&1; then exit 1; fi
grep -Fq 'OpenCode archive integrity mismatch' "$WORK/corrupt-opencode.log"
[ "$(cli_version "$HOME/.opencode/bin/opencode")" = 2.2.6 ]
# A kit Node too old for the CLIs is replaced cleanly with the latest LTS.
printf '%s\n' '#!/bin/sh' 'if [ "${1:-}" = --version ]; then echo v22.0.0; else exec "$TEST_NODE" "$@"; fi' > "$KIT_STATE_ROOT/cli/node/bin/node"
: > "$KIT_STATE_ROOT/cli/node/stale-file"
bootstrap_cli
[ "$(grep -c 'nodejs.org.*tar.gz$' "$BOOTSTRAP_CALLS")" -eq 2 ]
[ "$("$KIT_STATE_ROOT/cli/node/bin/node" --version)" = 24.21.0 ] && [ ! -e "$KIT_STATE_ROOT/cli/node/stale-file" ]
before="$(cat "$BOOTSTRAP_CALLS")"
bootstrap_cli
[ "$before" = "$(cat "$BOOTSTRAP_CALLS")" ]

# Package-manager fixtures own only this temporary HOME. They assert that the
# native replacements work before removing a legacy package or its launcher.
export CLEANUP_PREFIX="$HOME/.local"
mkdir -p "$CLEANUP_PREFIX/lib/node_modules/@openai/codex" "$CLEANUP_PREFIX/lib/node_modules/@anthropic-ai/claude-code"
printf '%s\n' '{"name":"@openai/codex"}' > "$CLEANUP_PREFIX/lib/node_modules/@openai/codex/package.json"
printf '%s\n' '{"name":"@anthropic-ai/claude-code"}' > "$CLEANUP_PREFIX/lib/node_modules/@anthropic-ai/claude-code/package.json"
cat > "$KIT_STATE_ROOT/cli/node/bin/npm" <<'MOCK'
#!/bin/bash
set -euo pipefail
case "$*" in
  'root --global') echo "$CLEANUP_PREFIX/lib/node_modules" ;;
  'uninstall --global --prefix '*)
    [ "$4" = "$CLEANUP_PREFIX" ]
    "$HOME/.universal-research-agent-kit/cli/bin/codex" --version >/dev/null
    "$HOME/.universal-research-agent-kit/cli/bin/claude" --version >/dev/null
    printf 'npm-remove %s\n' "$5" >> "$BOOTSTRAP_CALLS"
    rm -r "$CLEANUP_PREFIX/lib/node_modules/$5"
    [ "$5" != @anthropic-ai/claude-code ] || rm "$HOME/.local/bin/claude"
    ;;
  *) exit 99 ;;
esac
MOCK
cat > "$WORK/bin/brew" <<'MOCK'
#!/bin/bash
set -euo pipefail
case "$*" in
  --prefix) echo "$HOME/brew" ;;
  'list --cask --versions')
    echo 'Error: Refusing to load cask fif7y/tap/dimble from untrusted tap fif7y/tap.' >&2
    exit 1 ;;
  'list --cask -1')
    [ "${MOCK_BREW_LIST_FAILURE:-0}" -ne 1 ] || exit 42
    [ -f "$HOME/brew-removed" ] || printf 'codex\nclaude-code\nother-tool\ncodex-helper\n' ;;
  'list --formula -1')
    [ -f "$HOME/brew-formula-removed" ] || printf 'codex\nother-formula\n' ;;
  'uninstall --cask codex'|'uninstall --cask claude-code')
    printf 'brew-remove %s\n' "$3" >> "$BOOTSTRAP_CALLS"
    [ "$3" != claude-code ] || : > "$HOME/brew-removed"
    ;;
  'uninstall --formula codex')
    printf 'brew-remove formula %s\n' "$3" >> "$BOOTSTRAP_CALLS"
    : > "$HOME/brew-formula-removed" ;;
  *) exit 99 ;;
esac
MOCK
chmod +x "$WORK/bin/brew"
printf '%s\n' 'fixture-auth' > "$HOME/.codex/auth.json"
cleanup_legacy_clis
verify_native_clis
grep -Fqx fixture-auth "$HOME/.codex/auth.json"
[ ! -e "$CLEANUP_PREFIX/lib/node_modules/@openai/codex" ]
[ ! -e "$CLEANUP_PREFIX/lib/node_modules/@anthropic-ai/claude-code" ]
[ "$(grep -c '^npm-remove' "$BOOTSTRAP_CALLS")" -eq 2 ]
[ "$(grep -c '^brew-remove' "$BOOTSTRAP_CALLS")" -eq 3 ]
cleanup_legacy_clis
[ "$(grep -c '^npm-remove' "$BOOTSTRAP_CALLS")" -eq 2 ]
[ "$(grep -c '^brew-remove' "$BOOTSTRAP_CALLS")" -eq 3 ]

# A failed name listing must still stop cleanup rather than hide inspection errors.
if (MOCK_BREW_LIST_FAILURE=1 cleanup_legacy_clis) > "$WORK/failed-brew-list.log" 2>&1; then exit 1; fi
grep -Fq 'Cannot inspect Homebrew cask packages' "$WORK/failed-brew-list.log"
[ "$(grep -c '^brew-remove' "$BOOTSTRAP_CALLS")" -eq 3 ]

# Failed native verification must prevent package removal.
mv "$HOME/.codex/packages/standalone/current/bin/codex" "$WORK/native-codex"
if (cleanup_legacy_clis) > "$WORK/refused-cleanup.log" 2>&1; then exit 1; fi
grep -Fq 'Legacy packages were preserved' "$WORK/refused-cleanup.log"
mv "$WORK/native-codex" "$HOME/.codex/packages/standalone/current/bin/codex"
# A broken native payload triggers the official installer again, without RC.
printf '%s\n' '#!/bin/sh' 'exit 127' > "$HOME/.local/bin/claude"
bootstrap_cli
verify_native_clis
printf '%s\n' '#!/bin/sh' 'echo codex 0.100.0' 'exit 1' > "$HOME/.codex/packages/standalone/current/bin/codex"
bootstrap_cli
verify_native_clis
! grep -Fq remote-start "$BOOTSTRAP_CALLS"
printf '%s\n' '{"profile":"research-agent-kit"}' > "$KIT_STATE_ROOT/headroom.json"
cat > "$WORK/bin/startup-manager" <<'MOCK'
#!/bin/sh
printf 'startup %s %s\n' "${0##*/}" "$*" >> "$BOOTSTRAP_CALLS"
case "${0##*/} $*" in
  'systemctl --user show codex-remote-control.service '*)
    unit="$HOME/.config/systemd/user/codex-remote-control.service"
    if [ -f "$unit" ]; then
      printf 'LoadState=loaded\nFragmentPath=%s\nDropInPaths=\n' "$unit"
    else
      printf 'LoadState=not-found\nFragmentPath=\nDropInPaths=\n'
      exit 1
    fi ;;
  'systemctl --user is-enabled headroom-'*) echo enabled ;;
  'systemctl --user is-enabled codex-remote-control.service')
    [ -f "$HOME/startup-enabled" ] || exit 1
    echo enabled ;;
  'systemctl --user enable codex-remote-control.service')
    [ "${STARTUP_TEST_FAILURE:-}" != enable ] || exit 44
    : > "$HOME/startup-enabled" ;;
  'systemctl --user disable codex-remote-control.service') rm -f "$HOME/startup-enabled" ;;
  'systemctl --user daemon-reload') : ;;
  'loginctl show-user '*)
    if [ -f "$HOME/linger-enabled" ]; then echo yes; else echo no; fi ;;
  'loginctl --no-ask-password enable-linger '*) : > "$HOME/linger-enabled" ;;
  'launchctl print-disabled '*) printf 'disabled services = {\n}\n' ;;
  'launchctl enable '*) [ "${STARTUP_TEST_FAILURE:-}" != enable ] || exit 44 ;;
  *) echo "Unexpected startup command: ${0##*/} $*" >&2; exit 99 ;;
esac
MOCK
chmod +x "$WORK/bin/startup-manager"
for manager in systemctl loginctl launchctl; do ln -s startup-manager "$WORK/bin/$manager"; done
enable_codex_remote > "$WORK/enable.log"
grep -Fq 'Remote Control: connected' "$WORK/enable.log"
! grep -RFq DO_NOT_PERSIST "$KIT_STATE_ROOT" "$WORK/enable.log"
mkdir -p "$KIT_STATE_ROOT/tooling/uv-tools/headroom-ai/bin"
ln -s "$TEST_PYTHON" "$KIT_STATE_ROOT/tooling/uv-tools/headroom-ai/bin/python"
show_codex_remote > "$WORK/verify.log"
disable_codex_remote
grep -Fqx enabled=0 "$KIT_STATE_ROOT/codex-remote-control.state"
for failure in unmanaged invalid_json; do
  if (REMOTE_TEST_FAILURE="$failure" enable_codex_remote) > "$WORK/failed-enable.log" 2>&1; then exit 1; fi
  grep -Fqx enabled=0 "$KIT_STATE_ROOT/codex-remote-control.state"
  ! grep -Eq 'Traceback|JSONDecodeError|DO_NOT_PERSIST' "$WORK/failed-enable.log"
  grep -Fqx fixture-auth "$HOME/.codex/auth.json"
done
if (STARTUP_TEST_FAILURE=enable enable_codex_remote) > "$WORK/failed-startup.log" 2>&1; then exit 1; fi
grep -Fqx enabled=0 "$KIT_STATE_ROOT/codex-remote-control.state"
! grep -Eq 'Traceback|DO_NOT_PERSIST' "$WORK/failed-startup.log"
if show_codex_remote > "$WORK/partial-status.log" 2>&1; then exit 1; fi
grep -Fq 'No completed Remote Control setup is recorded' "$WORK/partial-status.log"
grep -Fq 'managed daemon running, Remote Control enabled' "$WORK/partial-status.log"
! grep -Fq 'This kit has not enabled' "$WORK/partial-status.log"
REMOTE_TEST_STATUS=connecting enable_codex_remote > "$WORK/pending.log"
grep -Fq 'relay connection is pending' "$WORK/pending.log"
! grep -Fq DO_NOT_PERSIST "$WORK/pending.log"
# Activation must not write enabled=1 until managed ownership is confirmed.
disable_codex_remote
if (REMOTE_TEST_BACKEND=unmanaged enable_codex_remote) > "$WORK/unmanaged-version.log" 2>&1; then exit 1; fi
grep -Fqx enabled=0 "$KIT_STATE_ROOT/codex-remote-control.state"
enable_codex_remote > "$WORK/re-enable.log"
for failure in failed invalid_json; do
  if (REMOTE_TEST_VERSION_FAILURE="$failure" show_codex_remote) > "$WORK/failed-version.log" 2>&1; then exit 1; fi
  ! grep -Eq 'Traceback|JSONDecodeError|DO_NOT_PERSIST' "$WORK/failed-version.log"
  grep -Fqx enabled=1 "$KIT_STATE_ROOT/codex-remote-control.state"
done
# Unknown startup files are refused before the native activation command.
startup_path="$(codex_startup_command check "$(managed_codex)")"
disable_codex_remote > "$WORK/disabled.log"
[ ! -e "$startup_path" ]
if show_codex_remote > "$WORK/disabled-status.log" 2>&1; then exit 1; fi
grep -Fq 'remote-control preference is disabled' "$WORK/disabled-status.log"
printf '%s\n' 'user-custom-startup' > "$startup_path"
starts="$(grep -c '^remote-start$' "$BOOTSTRAP_CALLS")"
if (enable_codex_remote) > "$WORK/custom-startup.log" 2>&1; then exit 1; fi
[ "$(grep -c '^remote-start$' "$BOOTSTRAP_CALLS")" -eq "$starts" ]
grep -Fqx user-custom-startup "$startup_path"
grep -Fqx enabled=0 "$KIT_STATE_ROOT/codex-remote-control.state"
! grep -Eq 'startup .*--now|startup .* (stop|restart|bootout|kickstart)' "$BOOTSTRAP_CALLS"
kit_release_lock
echo 'CLI bootstrap and explicit Remote Control tests passed.'
