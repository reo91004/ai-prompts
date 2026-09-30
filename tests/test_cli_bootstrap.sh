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
for action in ([], ['--disable-codex-remote-control'], ['--remote-control-status'], ['--verify']):
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
  printf '%s\n' '#!/bin/sh' 'if [ "${1:-}" = --version ]; then echo 24.13.0; else exec "$TEST_NODE" "$@"; fi' > "$WORK/node/bin/$name"
  chmod +x "$WORK/node/bin/$name"
done
tar -czf "$WORK/node.tar.gz" -C "$WORK" node
source "$ROOT/install.sh"
export PATH="$WORK/bin"
kit_init_state
KIT_HEADROOM_PYTHON="$TEST_PYTHON"
export BOOTSTRAP_CALLS="$WORK/calls"
printf '%s\n' '#!/bin/sh' 'echo v12.0.0' > "$WORK/bin/node"
chmod +x "$WORK/bin/node"

download_file() {
  printf '%s\n' "$1" >> "$BOOTSTRAP_CALLS"
  case "$1" in
    *nodejs.org*tar.gz) cp "$WORK/node.tar.gz" "$2" ;;
    *nodejs.org*SHASUMS256.txt)
      if command -v shasum >/dev/null; then digest="$(shasum -a 256 "$WORK/node.tar.gz")"; else digest="$(sha256sum "$WORK/node.tar.gz")"; fi
      for platform in darwin linux; do
        for arch in arm64 x64; do printf '%s  node-v24.13.0-%s-%s.tar.gz\n' "${digest%% *}" "$platform" "$arch"; done
      done > "$2"
      ;;
    https://chatgpt.com/codex/install.sh)
      cat > "$2" <<'INSTALL'
#!/bin/sh
test "$CODEX_NON_INTERACTIVE" = 1
mkdir -p "$HOME/.codex/packages/standalone/current/bin" "$CODEX_INSTALL_DIR"
cat > "$HOME/.codex/packages/standalone/current/bin/codex" <<'CLI'
#!/bin/sh
case "$*" in
  --version) echo 'codex 0.146.1' ;;
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
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/claude/versions"
printf '%s\n' '#!/bin/sh' 'echo "2.1.0 (Claude Code)"' > "$HOME/.local/share/claude/versions/2.1.0"
ln -s "$HOME/.local/share/claude/versions/2.1.0" "$HOME/.local/bin/claude"
chmod +x "$HOME/.local/bin/claude"
INSTALL
      ;;
    *) echo "Unexpected download: $1" >&2; exit 1 ;;
  esac
}

bootstrap_cli
for name in codex claude node npx; do command -v "$name" >/dev/null; done
! grep -Fq remote-start "$BOOTSTRAP_CALLS"
[ ! -e "$KIT_STATE_ROOT/codex-remote-control.state" ]
before="$(cat "$BOOTSTRAP_CALLS")"
bootstrap_cli
[ "$before" = "$(cat "$BOOTSTRAP_CALLS")" ]
# Existing native payloads repair missing/dangling kit launchers without download.
rm "$KIT_STATE_ROOT/cli/bin/codex" "$KIT_STATE_ROOT/cli/bin/claude"
ln -s "$WORK/missing-codex" "$KIT_STATE_ROOT/cli/bin/codex"
ln -s "$WORK/missing-claude" "$KIT_STATE_ROOT/cli/bin/claude"
bootstrap_cli
verify_native_clis
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
  'list --cask --versions') [ -f "$HOME/brew-removed" ] || printf 'codex 0.1\nclaude-code 1.0\nother-tool 2.0\n' ;;
  'list --formula --versions') : ;;
  'uninstall --cask codex'|'uninstall --cask claude-code')
    printf 'brew-remove %s\n' "$3" >> "$BOOTSTRAP_CALLS"
    [ "$3" != claude-code ] || : > "$HOME/brew-removed"
    ;;
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
[ "$(grep -c '^brew-remove' "$BOOTSTRAP_CALLS")" -eq 2 ]
cleanup_legacy_clis
[ "$(grep -c '^npm-remove' "$BOOTSTRAP_CALLS")" -eq 2 ]

# Failed native verification must prevent package removal.
mv "$HOME/.codex/packages/standalone/current/bin/codex" "$WORK/native-codex"
if (cleanup_legacy_clis) > "$WORK/refused-cleanup.log" 2>&1; then exit 1; fi
grep -Fq 'Legacy packages were preserved' "$WORK/refused-cleanup.log"
mv "$WORK/native-codex" "$HOME/.codex/packages/standalone/current/bin/codex"
# A broken native payload triggers the official installer again, without RC.
printf '%s\n' '#!/bin/sh' 'exit 127' > "$HOME/.local/share/claude/versions/2.1.0"
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
verify_codex_remote > "$WORK/verify.log"
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
  if (REMOTE_TEST_VERSION_FAILURE="$failure" verify_codex_remote) > "$WORK/failed-version.log" 2>&1; then exit 1; fi
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
