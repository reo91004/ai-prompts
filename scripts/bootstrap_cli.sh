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
    opencode) printf '%s\n' "$version" | grep -Eq '^(opencode )?v?2\.[0-9]+\.[0-9]+([[:space:]]|$)' || return 1 ;;
    node)
      [[ "$version" =~ ^v?([0-9]+)\.[0-9]+\.[0-9]+ ]] && [ "${BASH_REMATCH[1]}" -ge 24 ] || return 1 ;;
    npx) printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+' || return 1 ;;
  esac
  case "$tool" in
    codex|claude)
      "$binary" mcp --help >/dev/null 2>&1 && "$binary" plugin --help >/dev/null 2>&1 || return 1 ;;
    opencode) "$binary" plugin --help >/dev/null 2>&1 || return 1 ;;
  esac
}

cli_version() {
  local version
  version="$("$1" --version 2>/dev/null)" || return 1
  [[ "$version" =~ ([0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?) ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

resolve_cli_versions() {
  [ "${KIT_CLI_VERSIONS_RESOLVED:-0}" -eq 0 ] || return 0
  KIT_CODEX_SOURCE=https://releases.openai.com/codex/channels/latest
  KIT_CLAUDE_SOURCE=https://downloads.claude.ai/claude-code-releases/latest
  KIT_OPENCODE_SOURCE=https://opencode.ai/update/api/latest/cli/npm
  if ! (download_file "$KIT_CODEX_SOURCE" "$KIT_WORK_DIR/codex-release.json") 2> "$KIT_WORK_DIR/codex-release-primary.log"; then
    echo "Codex release host unavailable; checking the official GitHub release metadata."
    KIT_CODEX_SOURCE=https://api.github.com/repos/openai/codex/releases/latest
    download_file "$KIT_CODEX_SOURCE" "$KIT_WORK_DIR/codex-release.json" || kit_die "Could not resolve the latest Codex release."
  fi
  download_file "$KIT_CLAUDE_SOURCE" "$KIT_WORK_DIR/claude-release.txt" || kit_die "Could not resolve the latest Claude Code release."
  download_file "$KIT_OPENCODE_SOURCE" "$KIT_WORK_DIR/opencode-release.json" || kit_die "Could not resolve the latest OpenCode V2 release."
  KIT_CODEX_VERSION="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    const v=(d.tag_name||"").replace(/^rust-v/,"");
    if(d.prerelease===true||!/^\d+\.\d+\.\d+$/.test(v))process.exit(1);console.log(v);' \
    "$KIT_WORK_DIR/codex-release.json")" || kit_die "Invalid stable Codex release metadata."
  KIT_CLAUDE_VERSION="$(node -e 'const v=require("fs").readFileSync(process.argv[1],"utf8").trim();
    if(!/^\d+\.\d+\.\d+$/.test(v))process.exit(1);console.log(v);' \
    "$KIT_WORK_DIR/claude-release.txt")" || kit_die "Invalid stable Claude Code release metadata."
  KIT_OPENCODE_VERSION="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    const p=d.metadata?.package||d.package;
    if(p!=="@opencode/cli"||d.active===false||!/^2\.\d+\.\d+$/.test(d.version))process.exit(1);console.log(d.version);' \
    "$KIT_WORK_DIR/opencode-release.json")" || kit_die "Invalid OpenCode V2 release metadata."
  KIT_CLI_VERSIONS_RESOLVED=1
  printf 'Selected CLI versions: Codex %s, Claude Code %s, OpenCode %s\n' \
    "$KIT_CODEX_VERSION" "$KIT_CLAUDE_VERSION" "$KIT_OPENCODE_VERSION"
}

find_usable_cli() {
  local tool="$1" candidate directory target
  local candidates=("$KIT_STATE_ROOT/cli/bin/$tool") directories=()
  case "$tool" in
    codex) candidates+=("$HOME/.codex/packages/standalone/current/bin/codex" "$HOME/.codex/packages/standalone/current/codex") ;;
    claude) candidates+=("$HOME/.local/bin/claude" "$HOME/.claude/local/claude") ;;
    opencode) candidates+=("$HOME/.opencode/bin/opencode") ;;
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
  resolve_cli_versions
  if binary="$(managed_codex)" && cli_usable codex "$binary" &&
      [ "$(cli_version "$binary")" = "$KIT_CODEX_VERSION" ]; then
    set_cli_launcher codex "$binary"
    return 0
  fi
  backup_vendor_profiles
  kit_require_real_dir "$KIT_STATE_ROOT/cli"
  kit_require_real_dir "$KIT_STATE_ROOT/cli/bin"
  KIT_CLI_UPDATE_INDEX=$((${KIT_CLI_UPDATE_INDEX:-0} + 1))
  kit_backup_path "$HOME/.codex/packages/standalone" "bootstrap/codex-payload-$KIT_CLI_UPDATE_INDEX"
  kit_backup_path "$KIT_STATE_ROOT/cli/bin/codex" "bootstrap/codex-vendor-launcher-$KIT_CLI_UPDATE_INDEX"
  download_file https://chatgpt.com/codex/install.sh "$KIT_WORK_DIR/install-codex.sh" || kit_die "Could not download the Codex installer."
  # Package-manager cleanup follows verification of all replacements.
  CODEX_INSTALL_DIR="$KIT_STATE_ROOT/cli/bin" CODEX_NON_INTERACTIVE=1 \
    sh "$KIT_WORK_DIR/install-codex.sh" --release "$KIT_CODEX_VERSION" || kit_die "Codex standalone installation failed."
  binary="$(managed_codex)" && cli_usable codex "$binary" &&
    [ "$(cli_version "$binary")" = "$KIT_CODEX_VERSION" ] ||
    kit_die "Official installer did not provide managed Codex $KIT_CODEX_VERSION."
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
  resolve_cli_versions
  if ! native_claude || [ "$(cli_version "$HOME/.local/bin/claude")" != "$KIT_CLAUDE_VERSION" ]; then
    backup_vendor_profiles
    kit_require_real_dir "$HOME/.local"
    kit_require_real_dir "$HOME/.local/bin"
    [ ! -e "$HOME/.local/bin/claude" ] || [ -f "$HOME/.local/bin/claude" ] || [ -L "$HOME/.local/bin/claude" ] ||
      kit_die "Claude launcher is not a file; its directory was preserved."
    KIT_CLI_UPDATE_INDEX=$((${KIT_CLI_UPDATE_INDEX:-0} + 1))
    kit_backup_path "$HOME/.local/share/claude" "bootstrap/claude-payload-$KIT_CLI_UPDATE_INDEX"
    kit_backup_path "$HOME/.local/bin/claude" "bootstrap/claude-native-launcher-$KIT_CLI_UPDATE_INDEX"
    rm -f "$HOME/.local/bin/claude"
    download_file https://claude.ai/install.sh "$KIT_WORK_DIR/install-claude.sh" || kit_die "Could not download the Claude Code installer."
    bash "$KIT_WORK_DIR/install-claude.sh" "$KIT_CLAUDE_VERSION" || kit_die "Claude Code native installation failed."
    native_claude && [ "$(cli_version "$HOME/.local/bin/claude")" = "$KIT_CLAUDE_VERSION" ] ||
      kit_die "Claude installer did not provide Claude Code $KIT_CLAUDE_VERSION."
  fi
  set_cli_launcher claude "$HOME/.local/bin/claude"
}

opencode_platform() {
  local platform architecture target
  case "$(uname -s)" in Darwin) platform=darwin ;; Linux) platform=linux ;; *) kit_die "OpenCode supports macOS and Linux in this kit." ;; esac
  case "$(uname -m)" in arm64|aarch64) architecture=arm64 ;; x86_64|amd64) architecture=x64 ;; *) kit_die "Unsupported OpenCode CPU architecture." ;; esac
  if [ "$platform-$architecture" = darwin-x64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" = 1 ]; then
    architecture=arm64
  fi
  target="$platform-$architecture"
  if [ "$architecture" = x64 ]; then
    if { [ "$platform" = linux ] && ! grep -qwi avx2 /proc/cpuinfo; } ||
        { [ "$platform" = darwin ] && [ "$(sysctl -n hw.optional.avx2_0 2>/dev/null || true)" != 1 ]; }; then
      target="$target-baseline"
    fi
  fi
  if [ "$platform" = linux ] && { [ -f /etc/alpine-release ] || ldd --version 2>&1 | grep -qi musl; }; then
    target="$target-musl"
  fi
  printf '%s\n' "$target"
}

install_native_opencode() {
  local binary="$HOME/.opencode/bin/opencode" target metadata archive stage url
  resolve_cli_versions
  if cli_usable opencode "$binary" && [ "$(cli_version "$binary")" = "$KIT_OPENCODE_VERSION" ]; then
    set_cli_launcher opencode "$binary"
    return 0
  fi
  KIT_CLI_UPDATE_INDEX=$((${KIT_CLI_UPDATE_INDEX:-0} + 1))
  target="$(opencode_platform)"
  metadata="$KIT_WORK_DIR/opencode-package-$KIT_CLI_UPDATE_INDEX.json"
  archive="$KIT_WORK_DIR/opencode-package-$KIT_CLI_UPDATE_INDEX.tgz"
  stage="$(mktemp -d "$KIT_WORK_DIR/opencode-stage.XXXXXX")"
  download_file "https://registry.npmjs.org/@opencode%2fcli-$target/$KIT_OPENCODE_VERSION" "$metadata" || kit_die "Could not download OpenCode platform package metadata."
  url="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
    if(d.name!==process.argv[2]||d.version!==process.argv[3]||!/^sha512-[A-Za-z0-9+/]+={0,2}$/.test(d.dist?.integrity||""))process.exit(1);
    const u=new URL(d.dist.tarball);if(u.protocol!=="https:"||u.hostname!=="registry.npmjs.org")process.exit(1);console.log(u.href);' \
    "$metadata" "@opencode/cli-$target" "$KIT_OPENCODE_VERSION")" || kit_die "Invalid OpenCode platform package metadata."
  download_file "$url" "$archive" || kit_die "Could not download the OpenCode platform package."
  KIT_OPENCODE_ARCHIVE_SHA256="$(node -e 'const fs=require("fs"),c=require("crypto"),d=JSON.parse(fs.readFileSync(process.argv[1],"utf8")),b=fs.readFileSync(process.argv[2]);
    if("sha512-"+c.createHash("sha512").update(b).digest("base64")!==d.dist.integrity)process.exit(1);
    console.log(c.createHash("sha256").update(b).digest("hex"));' "$metadata" "$archive")" || kit_die "OpenCode archive integrity mismatch."
  tar -xzf "$archive" -C "$stage"
  cli_usable opencode "$stage/package/bin/opencode" &&
    [ "$(cli_version "$stage/package/bin/opencode")" = "$KIT_OPENCODE_VERSION" ] || kit_die "OpenCode package did not provide V2 $KIT_OPENCODE_VERSION."
  kit_require_real_dir "$HOME/.opencode"
  kit_require_real_dir "$HOME/.opencode/bin"
  kit_backup_path "$binary" "bootstrap/opencode-native-binary-$KIT_CLI_UPDATE_INDEX"
  kit_replace_file "$stage/package/bin/opencode" "$binary"
  set_cli_launcher opencode "$binary"
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
      # Name-only listing avoids loading unrelated cask definitions and taps.
      installed="$("$manager" list "--$kind" -1)" || kit_die "Cannot inspect Homebrew $kind packages."
      for name in codex claude-code; do
        printf '%s\n' "$installed" | grep -Fqx "$name" || continue
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
  for tool in codex claude opencode; do
    launcher="$HOME/.universal-research-agent-kit/cli/bin/$tool"
    [ -f "$launcher" ] && grep -Fqx '# research-agent-kit CLI launcher' "$launcher" || return 1
    target="$(sed -n 's/^# target: //p' "$launcher")"
    case "$tool" in
      codex) [ "$target" = "$(managed_codex)" ] || return 1 ;;
      claude) [ "$target" = "$HOME/.local/bin/claude" ] && native_claude || return 1 ;;
      opencode) [ "$target" = "$HOME/.opencode/bin/opencode" ] || return 1 ;;
    esac
    cli_usable "$tool" "$launcher" || return 1
    case "$tool" in
      codex) [ -z "${KIT_CODEX_VERSION:-}" ] || [ "$(cli_version "$launcher")" = "$KIT_CODEX_VERSION" ] || return 1 ;;
      claude) [ -z "${KIT_CLAUDE_VERSION:-}" ] || [ "$(cli_version "$launcher")" = "$KIT_CLAUDE_VERSION" ] || return 1 ;;
      opencode) [ -z "${KIT_OPENCODE_VERSION:-}" ] || [ "$(cli_version "$launcher")" = "$KIT_OPENCODE_VERSION" ] || return 1 ;;
    esac
  done
}

bootstrap_cli() {
  local cli_root="$KIT_STATE_ROOT/cli" node_version
  local platform architecture archive expected actual node_bin npx_bin
  PATH="$cli_root/bin:$HOME/.local/bin:$PATH"
  export PATH
  # Sequential Thinking 2 requires Node 24+; otherwise install the latest LTS.
  local replace_node=0
  if ! node_bin="$(find_usable_cli node)" || ! npx_bin="$(find_usable_cli npx)"; then
    replace_node=1
  else
    case "$node_bin" in
      "$cli_root/bin/node"|"$cli_root/node/bin/node")
        node_version="$(latest_node_lts)"
        [ "$(cli_version "$node_bin")" = "$node_version" ] || replace_node=1 ;;
    esac
  fi
  if [ "$replace_node" -eq 1 ]; then
    [ -n "${node_version:-}" ] || node_version="$(latest_node_lts)"
    kit_require_real_dir "$cli_root"
    kit_require_real_dir "$cli_root/bin"
    kit_backup_path "$cli_root/node" "bootstrap/node"
    rm -rf -- "$cli_root/node"
    kit_require_real_dir "$cli_root/node"
    case "$(uname -s)" in Darwin) platform=darwin ;; Linux) platform=linux ;; *) kit_die "CLI bootstrap supports macOS and Linux." ;; esac
    case "$(uname -m)" in arm64|aarch64) architecture=arm64 ;; x86_64|amd64) architecture=x64 ;; *) kit_die "Unsupported CPU architecture: $(uname -m)" ;; esac
    archive="node-v$node_version-$platform-$architecture.tar.gz"
    download_file "https://nodejs.org/dist/v$node_version/$archive" "$KIT_WORK_DIR/$archive"
    download_file "https://nodejs.org/dist/v$node_version/SHASUMS256.txt" "$KIT_WORK_DIR/node-shasums.txt"
    expected="$(awk -v name="$archive" '$2 == name { print $1 }' "$KIT_WORK_DIR/node-shasums.txt")"
    if command -v shasum >/dev/null 2>&1; then
      actual="$(shasum -a 256 "$KIT_WORK_DIR/$archive" | awk '{print $1}')"
    else
      actual="$(sha256sum "$KIT_WORK_DIR/$archive" | awk '{print $1}')"
    fi
    [ -n "$expected" ] && [ "$actual" = "$expected" ] || kit_die "Node.js archive checksum mismatch."
    tar -xzf "$KIT_WORK_DIR/$archive" --strip-components 1 -C "$cli_root/node"
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
  install_native_opencode
  hash -r 2>/dev/null || true
  local prerequisite
  for prerequisite in codex claude opencode node npx; do
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
