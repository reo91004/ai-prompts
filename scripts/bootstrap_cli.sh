#!/usr/bin/env bash
# Sourced by install.sh; mutation functions run after its lock/journal are ready.

backup_vendor_profiles() {
  [ "${KIT_VENDOR_PROFILES_BACKED_UP:-0}" -eq 0 ] || return 0
  local profile
  for profile in .profile .bash_profile .bashrc .zprofile .zshrc; do
    kit_require_regular_or_absent "$HOME/$profile"
    kit_backup_path "$HOME/$profile" "bootstrap/$profile"
  done
  KIT_VENDOR_PROFILES_BACKED_UP=1
}

cli_usable() {
  local tool="$1" binary="$2" version
  [ -x "$binary" ] || return 1
  version="$("$binary" --version 2>/dev/null)" || return 1
  case "$tool" in
    codex) printf '%s\n' "$version" | grep -Eq '^codex(-cli)? [0-9]+\.[0-9]+\.[0-9]+' || return 1 ;;
    claude) printf '%s\n' "$version" | grep -Eq '[0-9]+\.[0-9]+\.[0-9]+.*Claude Code' || return 1 ;;
    node)
      [[ "$version" =~ ^v?([0-9]+)\.[0-9]+\.[0-9]+ ]] && [ "${BASH_REMATCH[1]}" -ge 20 ] || return 1 ;;
    npx) printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+' || return 1 ;;
  esac
  case "$tool" in
    codex|claude)
      "$binary" mcp --help >/dev/null 2>&1 && "$binary" plugin --help >/dev/null 2>&1 || return 1 ;;
  esac
}

find_usable_cli() {
  local tool="$1" candidate directory target
  local candidates=("$KIT_STATE_ROOT/cli/bin/$tool") directories=()
  case "$tool" in
    codex) candidates+=("$HOME/.codex/packages/standalone/current/bin/codex" "$HOME/.codex/packages/standalone/current/codex") ;;
    claude) candidates+=("$HOME/.local/bin/claude" "$HOME/.claude/local/claude") ;;
  esac
  IFS=: read -r -a directories <<< "$PATH"
  for directory in "${directories[@]}"; do candidates+=("${directory:-.}/$tool"); done
  for candidate in "${candidates[@]}"; do
    if [ "$candidate" = "$KIT_STATE_ROOT/cli/bin/$tool" ] && [ -f "$candidate" ] &&
        grep -Fqx '# research-agent-kit CLI launcher' "$candidate"; then
      candidate="$(sed -n 's/^# target: //p' "$candidate")"
    fi
    [ -n "$candidate" ] && cli_usable "$tool" "$candidate" || continue
    directory="$(cd "$(dirname "$candidate")" && pwd -P)"
    target="$directory/$(basename "$candidate")"
    printf '%s\n' "$target"
    return 0
  done
  return 1
}

set_cli_launcher() {
  local tool="$1" target="$2" destination="$KIT_STATE_ROOT/cli/bin/$1" temporary
  case "$target" in *$'\n'*|*$'\r'*) kit_die "CLI paths containing line breaks are not supported." ;; esac
  [ "$target" != "$destination" ] || return 0
  kit_require_real_dir "$KIT_STATE_ROOT/cli"
  kit_require_real_dir "$KIT_STATE_ROOT/cli/bin"
  [ ! -e "$destination" ] || [ -f "$destination" ] || [ -L "$destination" ] || kit_die "CLI launcher is not a file: $destination"
  temporary="$(mktemp "$destination.tmp.XXXXXX")"
  {
    printf '#!/bin/bash\n# research-agent-kit CLI launcher\n# target: %s\n' "$target"
    printf 'export PATH=%q:"$PATH"\n' "${KIT_NODE_DIR:-$KIT_STATE_ROOT/cli/node/bin}"
    printf 'exec %q "$@"\n' "$target"
  } > "$temporary"
  if [ -f "$destination" ] && [ ! -L "$destination" ] && cmp -s "$temporary" "$destination"; then
    rm -f "$temporary"
    return 0
  fi
  KIT_CLI_BACKUP_INDEX=$((${KIT_CLI_BACKUP_INDEX:-0} + 1))
  kit_backup_path "$destination" "bootstrap/$tool-launcher-$KIT_CLI_BACKUP_INDEX"
  chmod 755 "$temporary"
  mv -f "$temporary" "$destination"
  echo "$tool launcher now uses $target"
}

managed_codex() {
  local base="$HOME/.codex/packages/standalone/current"
  if [ -x "$base/bin/codex" ]; then printf '%s\n' "$base/bin/codex"
  elif [ -x "$base/codex" ]; then printf '%s\n' "$base/codex"
  else return 1
  fi
}

install_standalone_codex() {
  local binary
  if binary="$(managed_codex)" && cli_usable codex "$binary" && codex_remote_capability >/dev/null 2>&1; then
    set_cli_launcher codex "$binary"
    return 0
  fi
  backup_vendor_profiles
  kit_require_real_dir "$KIT_STATE_ROOT/cli"
  kit_require_real_dir "$KIT_STATE_ROOT/cli/bin"
  kit_backup_path "$KIT_STATE_ROOT/cli/bin/codex" "bootstrap/codex-vendor-launcher"
  download_file https://chatgpt.com/codex/install.sh "$KIT_BACKUP_DIR/install-codex.sh"
  # Defer package-manager cleanup until both native CLIs and the kit validate.
  CODEX_INSTALL_DIR="$KIT_STATE_ROOT/cli/bin" CODEX_NON_INTERACTIVE=1 \
    sh "$KIT_BACKUP_DIR/install-codex.sh" || kit_die "Codex standalone installation failed."
  binary="$(managed_codex)" && cli_usable codex "$binary" && codex_remote_capability >/dev/null 2>&1 ||
    kit_die "Official installer produced no usable managed Codex executable."
  set_cli_launcher codex "$binary"
}

native_claude() {
  local launcher="$HOME/.local/bin/claude"
  [ -L "$launcher" ] && [ -x "$launcher" ] || return 1
  node -e 'const fs=require("fs"),p=require("path");
    const target=fs.realpathSync(process.argv[1]),root=fs.realpathSync(process.argv[2]);
    if(!target.startsWith(root+p.sep))process.exit(1);' \
    "$launcher" "$HOME/.local/share/claude/versions" || return 1
  cli_usable claude "$launcher"
}

install_native_claude() {
  if ! native_claude; then
    backup_vendor_profiles
    kit_require_real_dir "$HOME/.local"
    kit_require_real_dir "$HOME/.local/bin"
    [ ! -e "$HOME/.local/bin/claude" ] || [ -f "$HOME/.local/bin/claude" ] || [ -L "$HOME/.local/bin/claude" ] ||
      kit_die "Claude launcher is not a file; its directory was preserved."
    kit_backup_path "$HOME/.local/bin/claude" "bootstrap/claude-launcher"
    rm -f "$HOME/.local/bin/claude"
    download_file https://claude.ai/install.sh "$KIT_BACKUP_DIR/install-claude.sh"
    bash "$KIT_BACKUP_DIR/install-claude.sh" || kit_die "Claude Code native installation failed."
    native_claude || kit_die "Claude installer did not provide a working native CLI."
  fi
  set_cli_launcher claude "$HOME/.local/bin/claude"
}

cleanup_legacy_clis() {
  local directory manager root prefix package kind name native_target
  local managers=() seen=':'
  verify_native_clis || kit_die "Legacy packages were preserved because native CLI verification failed."
  native_target="$(node -e 'console.log(require("fs").realpathSync(process.argv[1]))' "$HOME/.local/bin/claude")"
  manager="$(command -v npm || true)"
  [ -z "$manager" ] || managers+=("$manager")
  for directory in "$HOME"/.nvm/versions/node/*/bin; do
    [ ! -x "$directory/npm" ] || managers+=("$directory/npm")
  done
  for manager in "${managers[@]}"; do
    directory="$(dirname "$manager")"
    root="$(PATH="$directory:$PATH" "$manager" root --global)" || kit_die "Cannot inspect npm packages with $manager."
    case "$root" in /*/lib/node_modules) prefix="${root%/lib/node_modules}" ;; *) continue ;; esac
    case "$seen" in *":$root:"*) continue ;; esac
    seen="$seen$root:"
    for package in @openai/codex @anthropic-ai/claude-code; do
      [ -f "$root/$package/package.json" ] || continue
      node -e 'if(require(process.argv[1]).name!==process.argv[2])process.exit(1)' "$root/$package/package.json" "$package" ||
        kit_die "Unexpected package identity at $root/$package; preserved."
      echo "Removing legacy npm package $package from $prefix (native replacement verified)."
      local remove_status=0
      PATH="$directory:$PATH" "$manager" uninstall --global --prefix "$prefix" "$package" || remove_status=$?
      # npm with prefix ~/.local can unlink the newly installed native launcher.
      if [ ! -e "$HOME/.local/bin/claude" ] && [ ! -L "$HOME/.local/bin/claude" ]; then
        ln -s "$native_target" "$HOME/.local/bin/claude"
      fi
      [ "$remove_status" -eq 0 ] || kit_die "Native CLIs are installed, but legacy npm cleanup failed for $prefix/$package."
    done
  done
  managers=()
  manager="$(command -v brew || true)"
  [ -z "$manager" ] || managers+=("$manager")
  seen=':'
  for manager in "${managers[@]}"; do
    prefix="$("$manager" --prefix)" || kit_die "Cannot inspect Homebrew prefix with $manager."
    case "$seen" in *":$prefix:"*) continue ;; esac
    seen="$seen$prefix:"
    for kind in cask formula; do
      local installed
      installed="$("$manager" list "--$kind" --versions)" || kit_die "Cannot inspect Homebrew $kind packages."
      for name in codex claude-code; do
        printf '%s\n' "$installed" | awk '{print $1}' | grep -Fqx "$name" || continue
        echo "Removing legacy Homebrew $kind $name (native replacement verified)."
        "$manager" uninstall "--$kind" "$name" || kit_die "Native CLIs are installed, but Homebrew cleanup failed for $name."
      done
    done
  done
  # npm with prefix ~/.local can unlink the new native launcher during removal.
  if [ ! -e "$HOME/.local/bin/claude" ] && [ ! -L "$HOME/.local/bin/claude" ]; then
    ln -s "$native_target" "$HOME/.local/bin/claude"
  fi
  verify_native_clis || kit_die "Native CLI verification failed after legacy package cleanup."
}

verify_native_clis() {
  local tool launcher target
  for tool in codex claude; do
    launcher="$HOME/.universal-research-agent-kit/cli/bin/$tool"
    [ -f "$launcher" ] && grep -Fqx '# research-agent-kit CLI launcher' "$launcher" || return 1
    target="$(sed -n 's/^# target: //p' "$launcher")"
    case "$tool" in
      codex) [ "$target" = "$(managed_codex)" ] && codex_remote_capability >/dev/null 2>&1 || return 1 ;;
      claude) [ "$target" = "$HOME/.local/bin/claude" ] && native_claude || return 1 ;;
    esac
    cli_usable "$tool" "$launcher" || return 1
  done
}

bootstrap_cli() {
  local cli_root="$KIT_STATE_ROOT/cli" node_version=24.13.0
  local platform architecture archive expected actual node_bin npx_bin
  PATH="$cli_root/bin:$HOME/.local/bin:$PATH"
  export PATH
  if ! node_bin="$(find_usable_cli node)" || ! npx_bin="$(find_usable_cli npx)"; then
    kit_require_real_dir "$cli_root"
    kit_require_real_dir "$cli_root/bin"
    kit_backup_path "$cli_root/node" "bootstrap/node"
    kit_require_real_dir "$cli_root/node"
    case "$(uname -s)" in Darwin) platform=darwin ;; Linux) platform=linux ;; *) kit_die "CLI bootstrap supports macOS and Linux." ;; esac
    case "$(uname -m)" in arm64|aarch64) architecture=arm64 ;; x86_64|amd64) architecture=x64 ;; *) kit_die "Unsupported CPU architecture: $(uname -m)" ;; esac
    archive="node-v$node_version-$platform-$architecture.tar.gz"
    download_file "https://nodejs.org/dist/v$node_version/$archive" "$KIT_BACKUP_DIR/$archive"
    download_file "https://nodejs.org/dist/v$node_version/SHASUMS256.txt" "$KIT_BACKUP_DIR/node-shasums.txt"
    expected="$(awk -v name="$archive" '$2 == name { print $1 }' "$KIT_BACKUP_DIR/node-shasums.txt")"
    if command -v shasum >/dev/null 2>&1; then
      actual="$(shasum -a 256 "$KIT_BACKUP_DIR/$archive" | awk '{print $1}')"
    else
      actual="$(sha256sum "$KIT_BACKUP_DIR/$archive" | awk '{print $1}')"
    fi
    [ -n "$expected" ] && [ "$actual" = "$expected" ] || kit_die "Node.js archive checksum mismatch."
    tar -xzf "$KIT_BACKUP_DIR/$archive" --strip-components 1 -C "$cli_root/node"
    local name
    for name in node npm npx; do
      kit_backup_path "$cli_root/bin/$name" "bootstrap/$name-launcher"
      ln -sf "$cli_root/node/bin/$name" "$cli_root/bin/$name"
    done
    node_bin="$cli_root/node/bin/node"
    npx_bin="$cli_root/node/bin/npx"
  fi
  KIT_NODE_DIR="$(dirname "$node_bin")"
  PATH="$cli_root/bin:$KIT_NODE_DIR:$PATH"
  export PATH
  install_standalone_codex
  install_native_claude
  hash -r 2>/dev/null || true
  local prerequisite
  for prerequisite in codex claude node npx; do
    command -v "$prerequisite" >/dev/null 2>&1 || kit_die "CLI bootstrap did not provide $prerequisite."
  done
  # Desktop/daemon MCP launches do not source shell rc or nvm initialization.
  KIT_NPX="$cli_root/bin/kit-npx"
  if [ "${KIT_NPX_PREPARED:-0}" -eq 0 ]; then
    kit_require_real_dir "$cli_root"
    kit_require_real_dir "$cli_root/bin"
    kit_require_regular_or_absent "$KIT_NPX"
    kit_backup_path "$KIT_NPX" "bootstrap/kit-npx"
    {
      printf '#!/bin/bash\nexport PATH=%q:"$PATH"\n' "$KIT_NODE_DIR"
      printf 'exec %q "$@"\n' "$npx_bin"
    } > "$KIT_NPX"
    chmod 755 "$KIT_NPX"
    KIT_NPX_PREPARED=1
  fi
}

codex_remote_capability() {
  local binary
  binary="$(managed_codex)" || { echo "Managed standalone Codex is unavailable." >&2; return 1; }
  "$binary" --version &&
    "$binary" app-server daemon version --help >/dev/null &&
    "$binary" app-server daemon bootstrap --help >/dev/null &&
    "$binary" remote-control start --help >/dev/null
}

enable_codex_remote() {
  local binary
  kit_require_regular_or_absent "$KIT_STATE_ROOT/codex-remote-control.state"
  install_standalone_codex
  codex_remote_capability || kit_die "Installed Codex does not support the required managed Remote Control commands."
  binary="$(managed_codex)"
  # Parse in memory: never put environment IDs or pairing output in kit logs/state.
  "$binary" remote-control start --json | "$KIT_HEADROOM_PYTHON" -I -B -c '
import json, sys
data = json.load(sys.stdin)
status = data.get("status")
if status not in ("connected", "connecting"):
    sys.exit("Codex did not report connected/connecting Remote Control.")
print("Codex Remote Control: " + status)
if status == "connecting":
    print("Daemon started; relay connection is pending. Check authentication/network before pairing.")
'
  printf '%s\n' 'enabled=1' > "$KIT_STATE_ROOT/codex-remote-control.state"
  echo "Pair separately on this host: codex remote-control pair"
}

verify_codex_remote() {
  [ -f "$HOME/.universal-research-agent-kit/codex-remote-control.state" ] || return 0
  grep -Fqx 'enabled=1' "$HOME/.universal-research-agent-kit/codex-remote-control.state" || return 0
  codex_remote_capability || return 1
  local binary
  binary="$(managed_codex)"
  "$binary" app-server daemon version | \
    "$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python" -I -B -c '
import json, pathlib, sys
data = json.load(sys.stdin)
if data.get("status") != "running":
    sys.exit("Codex managed daemon is not running; run codex remote-control start.")
settings = pathlib.Path.home() / ".codex/app-server-daemon/settings.json"
if not settings.is_file() or not json.loads(settings.read_text()).get("remoteControlEnabled"):
    sys.exit("Codex daemon remote-control preference is disabled.")
print("Codex remote host: daemon running, Remote Control enabled (pairing/relay not verified).")
'
}

disable_codex_remote() {
  local binary
  binary="$(managed_codex)" || kit_die "No managed Codex installation; no remote host was changed."
  "$binary" app-server daemon disable-remote-control >/dev/null || kit_die "Could not disable Codex Remote Control."
  kit_require_regular_or_absent "$KIT_STATE_ROOT/codex-remote-control.state"
  printf '%s\n' 'enabled=0' > "$KIT_STATE_ROOT/codex-remote-control.state"
  echo "Codex Remote Control disabled on this host. Local Codex/Headroom remain available."
}

show_codex_remote() {
  if [ -f "$HOME/.universal-research-agent-kit/codex-remote-control.state" ] &&
      grep -Fqx 'enabled=1' "$HOME/.universal-research-agent-kit/codex-remote-control.state"; then
    verify_codex_remote
  else
    echo "This kit has not enabled Codex Remote Control on this host."
    echo "Enable when wanted: sh install.sh --enable-codex-remote-control"
  fi
}
