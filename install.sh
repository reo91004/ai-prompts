#!/bin/sh
# Re-exec before parsing Bash functions; works with dash and macOS Bash 3.2.
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRAPHIFY_VERSION=0.9.39
HEADROOM_VERSION=0.34.0
EXPECTED_GRAPHIFY_VERSION="$GRAPHIFY_VERSION"
EXPECTED_HEADROOM_VERSION="$HEADROOM_VERSION"
KIT_PYTHON_VERSION=3.13
KIT_UV_VERSION=0.12.10
GRAPHIFY_PACKAGE="graphifyy==$GRAPHIFY_VERSION"
HEADROOM_PACKAGE="headroom-ai[all]==$HEADROOM_VERSION"
source "$ROOT/scripts/bootstrap_cli.sh"


kit_die() {
  echo "Error: $*" >&2
  exit 1
}

download_file() {
  local url="$1" destination="$2"
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --silent --show-error --connect-timeout 15 --retry 2 "$url" --output "$destination" ||
      kit_die "Download failed: $url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=30 -O "$destination" "$url" || kit_die "Download failed: $url"
  else
    kit_die "curl or wget is required to download the managed runtimes."
  fi
}

kit_validate_home() {
  case "${HOME:-}" in
    ""|/) kit_die "HOME must be a non-root absolute directory." ;;
    /*) ;;
    *) kit_die "HOME must be an absolute directory: $HOME" ;;
  esac

  [ -d "$HOME" ] || kit_die "HOME does not exist: $HOME"
}

kit_require_real_dir() {
  local path="$1"

  [ ! -L "$path" ] || kit_die "Refusing to use a symlinked managed directory: $path"
  if [ -e "$path" ] && [ ! -d "$path" ]; then
    kit_die "Managed directory path is not a directory: $path"
  fi
  mkdir -p "$path"
}

kit_require_regular_or_absent() {
  local path="$1"

  [ ! -L "$path" ] || kit_die "Refusing to use a symlinked managed file: $path"
  if [ -e "$path" ] && [ ! -f "$path" ]; then
    kit_die "Managed file path is not a regular file: $path"
  fi
}

kit_tooling_idle() (
  # Isolate shell tracing so `bash -x install.sh` cannot log other processes'
  # complete command lines, while preserving the caller's tracing preference.
  set +x
  local snapshot pid command executable name argument remaining busy seen=0
  local root="$HOME/.universal-research-agent-kit/tooling" physical_home physical_root
  local local_headroom="$HOME/.local/bin/headroom" physical_headroom
  physical_home="$(cd "$HOME" && pwd -P)" || return 1
  physical_root="$physical_home/.universal-research-agent-kit/tooling"
  physical_headroom="$physical_home/.local/bin/headroom"
  # Keep command lines in memory: they can contain credentials. A failed
  # process inspection is not permission to replace a potentially active venv.
  if ! snapshot="$(ps -ww -u "$(id -u)" -o pid= -o args= 2>/dev/null)" || [ -z "$snapshot" ]; then
    echo "Cannot inspect running processes; managed environments were not cleared for modification." >&2
    return 1
  fi
  while read -r pid command; do
    [ -n "$command" ] || continue
    case "$pid" in *[!0-9]*|'') echo "Invalid process inspection; installation was not cleared to modify environments." >&2; return 1 ;; esac
    seen=1
    busy=0
    case "$command" in
      "$root/"*|"$physical_root/"*|"$local_headroom"|"$local_headroom"[[:space:]]*|"$physical_headroom"|"$physical_headroom"[[:space:]]*) busy=1 ;;
    esac
    executable="${command%%[[:space:]]*}"
    name="${executable##*/}"
    case "$name" in
      headroom) busy=1 ;;
      python|python[0-9]*|Python|Python[0-9]*|pypy|pypy[0-9]*|sh|bash|dash|zsh)
        # ps does not preserve argv boundaries. Recognize the interpreter's
        # module/script position, never words inside Python/shell -c source.
        remaining="${command#"$executable"}"
        while :; do
          remaining="${remaining#"${remaining%%[![:space:]]*}"}"
          [ -n "$remaining" ] || break
          case "$remaining" in
            "$root/"*|"$physical_root/"*|"$local_headroom"|"$local_headroom"[[:space:]]*|"$physical_headroom"|"$physical_headroom"[[:space:]]*) busy=1; break ;;
          esac
          argument="${remaining%%[[:space:]]*}"
          remaining="${remaining#"$argument"}"
          case "$argument" in
            -c|--command|-c?*) break ;;
            -m|-?*m)
              remaining="${remaining#"${remaining%%[![:space:]]*}"}"
              case "${remaining%%[[:space:]]*}" in headroom|headroom.*) busy=1 ;; esac
              break ;;
            -mheadroom|-mheadroom.*) busy=1; break ;;
            -W|-X)
              remaining="${remaining#"${remaining%%[![:space:]]*}"}"
              remaining="${remaining#"${remaining%%[[:space:]]*}"}" ;;
            --) ;;
            -*) ;;
            *)
              case "$argument" in headroom|*/headroom|"$root/"*|"$HOME/.config/headroom/runtime.py") busy=1 ;; esac
              break ;;
          esac
        done
        ;;
    esac
    if [ "$busy" -eq 1 ]; then
      echo "Headroom or a managed tool environment is in use (PID $pid). Finish its sessions and stop it yourself before installing; no process was stopped." >&2
      return 1
    fi
  done <<< "$snapshot"
  [ "$seen" -eq 1 ] || { echo "Empty process inspection; installation was not cleared to modify environments." >&2; return 1; }
)

kit_init_state() {
  kit_validate_home
  umask 077
  KIT_STATE_ROOT="$HOME/.universal-research-agent-kit"
  KIT_BACKUP_ROOT="$KIT_STATE_ROOT/backups"
  KIT_MANIFEST_ROOT="$KIT_STATE_ROOT/manifests"

  kit_require_real_dir "$KIT_STATE_ROOT"
  kit_require_real_dir "$KIT_BACKUP_ROOT"
  kit_require_real_dir "$KIT_MANIFEST_ROOT"

  KIT_LOCK_DIR="$KIT_STATE_ROOT/.lock"
  mkdir "$KIT_LOCK_DIR" 2>/dev/null || kit_die "Another kit install holds $KIT_LOCK_DIR"
  KIT_LOCK_OWNED=1
  KIT_BACKUP_DIR="$(mktemp -d "$KIT_BACKUP_ROOT/run.$(date +%Y%m%d_%H%M%S).XXXXXX")"
  KIT_JOURNAL="$KIT_BACKUP_DIR/journal.tsv"

}

# Record per-host outcomes for verification, including explicit skips.
kit_write_integrations_state() {
  local profile="$1"
  local codex_ponytail="$2"
  local claude_ponytail="$3"
  local codex_lazycodex="$4"
  local codex_seqthink="$5"
  local claude_seqthink="$6"
  local state_file="$KIT_STATE_ROOT/integrations.state"
  local tmp

  kit_require_regular_or_absent "$state_file"
  kit_backup_path "$state_file" "state/integrations.state"
  tmp="$(mktemp "$state_file.tmp.XXXXXX")"
  {
    printf 'requested_profile=%s\n' "$profile"
    printf 'codex_ponytail=%s\n' "$codex_ponytail"
    printf 'claude_ponytail=%s\n' "$claude_ponytail"
    printf 'codex_lazycodex=%s\n' "$codex_lazycodex"
    printf 'codex_sequential_thinking=%s\n' "$codex_seqthink"
    printf 'claude_sequential_thinking=%s\n' "$claude_seqthink"
  } > "$tmp"
  mv "$tmp" "$state_file"
}

kit_write_tooling_state() {
  local status="$1"
  local graphify="$2"
  local headroom="$3"
  local wrapper="$4"
  local graphify_version="$5"
  local headroom_version="$6"
  local tool_bin_dir="$7"
  local state_file="$KIT_STATE_ROOT/tooling.state"
  local tmp

  kit_require_regular_or_absent "$state_file"
  kit_backup_path "$state_file" "state/tooling.state"
  tmp="$(mktemp "$state_file.tmp.XXXXXX")"
  {
    printf 'status=%s\n' "$status"
    printf 'graphify=%s\n' "$graphify"
    printf 'graphify_version=%s\n' "$graphify_version"
    printf 'headroom=%s\n' "$headroom"
    printf 'headroom_version=%s\n' "$headroom_version"
    printf 'headroom_wrapper=%s\n' "$wrapper"
    printf 'tool_bin_dir=%s\n' "$tool_bin_dir"
  } > "$tmp"
  mv "$tmp" "$state_file"
}

kit_replace_managed_block() {
  local target="$1"
  local block="$2"
  local backup_relative="$3"
  local begin_marker="$4"
  local end_marker="$5"
  local tmp
  local begin_count
  local end_count
  local begin_line
  local end_line

  kit_require_real_dir "$(dirname "$target")"
  [ ! -L "$target" ] || kit_die "Refusing to replace a symlinked managed file: $target"
  if [ -e "$target" ] && [ ! -f "$target" ]; then
    kit_die "Managed block target is not a regular file: $target"
  fi
  if [ -e "$target" ]; then
    begin_count="$(grep -Fxc -- "$begin_marker" "$target" || true)"
    end_count="$(grep -Fxc -- "$end_marker" "$target" || true)"
  else
    begin_count=0
    end_count=0
  fi
  if [ "$begin_count" -ne 0 ] || [ "$end_count" -ne 0 ]; then
    if [ "$begin_count" -ne 1 ] || [ "$end_count" -ne 1 ]; then
      kit_die "Malformed kit marker pair in $target (begin=$begin_count end=$end_count); repair the markers before reinstalling."
    fi
    begin_line="$(grep -Fnx -- "$begin_marker" "$target" | cut -d: -f1)"
    end_line="$(grep -Fnx -- "$end_marker" "$target" | cut -d: -f1)"
    if [ "$begin_line" -ge "$end_line" ]; then
      kit_die "Kit end marker precedes the begin marker in $target; repair the markers before reinstalling."
    fi
  fi

  kit_backup_path "$target" "$backup_relative"
  if [ ! -e "$target" ]; then
    printf '' > "$target"
  fi
  tmp="$(mktemp "$target.tmp.XXXXXX")"

  if [ "$begin_count" -eq 1 ]; then
    awk -v block_file="$block" -v begin_marker="$begin_marker" -v end_marker="$end_marker" '
      BEGIN {
        while ((getline line < block_file) > 0) {
          managed = managed line ORS
        }
      }
      $0 == begin_marker {
        printf "%s", managed
        in_block = 1
        next
      }
      $0 == end_marker {
        in_block = 0
        next
      }
      !in_block { print }
    ' "$target" > "$tmp"
  else
    cat "$target" > "$tmp"
    if [ -s "$target" ]; then
      printf "\n" >> "$tmp"
    fi
    cat "$block" >> "$tmp"
  fi

  mv "$tmp" "$target"
}

kit_release_lock() {
  if [ "${KIT_LOCK_OWNED:-0}" = "1" ]; then
    rmdir "$KIT_LOCK_DIR" 2>/dev/null || true
    KIT_LOCK_OWNED=0
  fi
}

kit_journal_entry() {
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$KIT_JOURNAL"
}

# Roll back all journaled changes after a failure or signal.
kit_enable_rollback() {
  trap 'kit_handle_exit $?' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

kit_handle_exit() {
  local status="$1"
  trap - EXIT
  if [ "$status" -ne 0 ]; then
    if [ "${KIT_HEADROOM_CREATED:-0}" = 1 ] && [ -f "$KIT_STATE_ROOT/headroom.json" ]; then
      if ! "$KIT_HEADROOM_PYTHON" -I -B "$ROOT/headroom/runtime.py" remove; then
        echo "Warning: runtime cleanup failed. Kept its environment/configuration and journal at $KIT_BACKUP_DIR for recovery; inspect --headroom-status before retrying." >&2
        kit_release_lock
        exit "$status"
      fi
    fi
    echo "Install failed with status $status; rolling back journaled changes." >&2
    if kit_rollback_run; then
      echo "Rollback complete. Backups remain in $KIT_BACKUP_DIR" >&2
    else
      echo "Warning: automatic rollback incomplete; restore manually from $KIT_BACKUP_DIR" >&2
    fi
  fi
  kit_release_lock
  exit "$status"
}

# Restore into a sibling temp first; the original target is removed only
# after a complete copy of the backup exists next to it.
kit_restore_entry() {
  local target="$1"
  local backup="$2"
  local parent
  local name
  local temp

  if [ ! -e "$backup" ] && [ ! -L "$backup" ]; then
    return 1
  fi
  parent="$(dirname "$target")"
  name="$(basename "$target")"
  mkdir -p "$parent" || return 1
  if [ -L "$backup" ]; then
    temp="$(mktemp "$parent/.$name.restore.XXXXXX")" || return 1
    rm -f -- "$temp"
    cp -P "$backup" "$temp" || { rm -rf -- "$temp"; return 1; }
  elif [ -d "$backup" ]; then
    temp="$(mktemp -d "$parent/.$name.restore.XXXXXX")" || return 1
    cp -Rp "$backup/." "$temp/" || { rm -rf -- "$temp"; return 1; }
  elif [ -f "$backup" ]; then
    temp="$(mktemp "$parent/.$name.restore.XXXXXX")" || return 1
    cp -p "$backup" "$temp" || { rm -f -- "$temp"; return 1; }
  else
    return 1
  fi
  rm -rf -- "$target"
  mv "$temp" "$target"
}

kit_rollback_run() {
  local tab action source destination failed=0

  [ -f "$KIT_JOURNAL" ] || return 0
  tab="$(printf '\t')"
  # Do not restore/delete a venv that another process started using during
  # this run. Preserve the complete journal for explicit recovery instead.
  while IFS="$tab" read -r action source destination; do
    case "$source" in
      "$KIT_STATE_ROOT/tooling"|"$KIT_STATE_ROOT/tooling/"*)
        if ! kit_tooling_idle; then
          echo "Rollback left the managed environment and journal at $KIT_BACKUP_DIR intact because safe restoration could not be established." >&2
          return 1
        fi
        break ;;
    esac
  done < "$KIT_JOURNAL"
  # Newest-first replay so later changes are undone before earlier ones.
  while IFS="$tab" read -r action source destination; do
    case "$source" in
      "$KIT_STATE_ROOT/tooling"|"$KIT_STATE_ROOT/tooling/"*) kit_tooling_idle || return 1 ;;
    esac
    case "$action" in
      restore)
        kit_restore_entry "$source" "$destination" || failed=1
        ;;
      absent)
        rm -rf -- "$source" || failed=1
        ;;
      *)
        failed=1
        ;;
    esac
  done <<EOF
$(sed -n '1!G;h;$p' "$KIT_JOURNAL")
EOF
  mv "$KIT_JOURNAL" "$KIT_JOURNAL.rolled-back"
  [ "$failed" -eq 0 ]
}

# The journal entry is written only after the backup is complete and in its
# final location: a rollback must never see a restore entry whose backup does
# not exist, or it would delete the original with nothing to restore from.
kit_backup_path() {
  local source="$1"
  local relative="$2"
  local destination="$KIT_BACKUP_DIR/$relative"
  local parent
  local name
  local temp

  if [ ! -e "$source" ] && [ ! -L "$source" ]; then
    kit_journal_entry absent "$source"
    return
  fi

  parent="$(dirname "$destination")"
  name="$(basename "$destination")"
  kit_require_real_dir "$parent"
  if [ -e "$destination" ] || [ -L "$destination" ]; then
    kit_die "Backup destination already exists: $destination"
  fi
  if [ -L "$source" ]; then
    temp="$(mktemp "$parent/.$name.tmp.XXXXXX")"
    rm -f -- "$temp"
    cp -P "$source" "$temp" || { rm -rf -- "$temp"; kit_die "Backup copy failed: $source"; }
  elif [ -f "$source" ]; then
    temp="$(mktemp "$parent/.$name.tmp.XXXXXX")"
    cp -p "$source" "$temp" || { rm -f -- "$temp"; kit_die "Backup copy failed: $source"; }
  elif [ -d "$source" ]; then
    temp="$(mktemp -d "$parent/.$name.tmp.XXXXXX")"
    cp -Rp "$source/." "$temp/" || { rm -rf -- "$temp"; kit_die "Backup copy failed: $source"; }
  else
    kit_die "Unsupported managed path type: $source"
  fi
  mv "$temp" "$destination"
  kit_journal_entry restore "$source" "$destination"
  echo "Backed up $source -> $destination"
}

kit_create_empty_file() {
  local destination="$1"
  local parent
  local name
  local temp

  parent="$(dirname "$destination")"
  name="$(basename "$destination")"
  kit_safe_name "$name"
  kit_require_real_dir "$parent"
  if [ -e "$destination" ] || [ -L "$destination" ]; then
    kit_die "Refusing to reuse a run artifact: $destination"
  fi
  temp="$(mktemp "$parent/.$name.tmp.XXXXXX")"
  mv "$temp" "$destination"
}

kit_safe_name() {
  case "$1" in
    ""|.|..|*/*) kit_die "Unsafe managed entry name: $1" ;;
  esac
}

kit_remove_owned_entry() {
  local root="$1"
  local name="$2"
  local target

  kit_safe_name "$name"
  target="$root/$name"
  if [ -e "$target" ] || [ -L "$target" ]; then
    rm -rf -- "$target"
  fi
}

kit_replace_file() {
  local source="$1"
  local destination="$2"
  local parent
  local name
  local temp

  parent="$(dirname "$destination")"
  name="$(basename "$destination")"
  kit_safe_name "$name"
  kit_require_real_dir "$parent"
  temp="$(mktemp "$parent/.$name.tmp.XXXXXX")"
  if ! cp -p "$source" "$temp"; then
    rm -f -- "$temp"
    return 1
  fi
  kit_remove_owned_entry "$parent" "$name"
  mv "$temp" "$destination"
}

kit_replace_dir() {
  local source="$1"
  local destination="$2"
  local parent
  local name
  local temp

  parent="$(dirname "$destination")"
  name="$(basename "$destination")"
  kit_safe_name "$name"
  kit_require_real_dir "$parent"
  temp="$(mktemp -d "$parent/.$name.tmp.XXXXXX")"
  if ! cp -Rp "$source/." "$temp/"; then
    rm -rf -- "$temp"
    return 1
  fi
  kit_remove_owned_entry "$parent" "$name"
  mv "$temp" "$destination"
}

kit_prune_manifest() {
  local root="$1"
  local installed_manifest="$2"
  local current_manifest="$3"
  local checksum_file="$installed_manifest.cksum"
  local expected_checksum
  local actual_checksum
  local name

  if [ ! -f "$installed_manifest" ]; then
    return 0
  fi
  [ ! -L "$installed_manifest" ] || kit_die "Refusing a symlinked ownership manifest: $installed_manifest"
  if [ ! -f "$checksum_file" ]; then
    echo "Skipping prune from an unverified legacy manifest: $installed_manifest"
    return 0
  fi
  [ ! -L "$checksum_file" ] || kit_die "Refusing a symlinked manifest checksum: $checksum_file"
  expected_checksum="$(cat "$checksum_file")"
  actual_checksum="$(cksum "$installed_manifest" | awk '{ print $1 ":" $2 }')"
  [ "$expected_checksum" = "$actual_checksum" ] ||
    kit_die "Ownership manifest checksum mismatch: $installed_manifest"
  while IFS= read -r name || [ -n "$name" ]; do
    kit_safe_name "$name"
  done < "$installed_manifest"

  while IFS= read -r name || [ -n "$name" ]; do
    if ! grep -Fqx "$name" "$current_manifest"; then
      kit_remove_owned_entry "$root" "$name"
      echo "Removed obsolete kit entry: $root/$name"
    fi
  done < "$installed_manifest"
}

kit_commit_manifest() {
  local current_manifest="$1"
  local installed_manifest="$2"
  local checksum_file="$installed_manifest.cksum"
  local temp
  local checksum_temp

  kit_require_real_dir "$(dirname "$installed_manifest")"
  kit_backup_path "$installed_manifest" "manifests/$(basename "$installed_manifest")"
  kit_backup_path "$checksum_file" "manifests/$(basename "$checksum_file")"
  temp="$(mktemp "$installed_manifest.tmp.XXXXXX")"
  cp -p "$current_manifest" "$temp"
  mv "$temp" "$installed_manifest"
  checksum_temp="$(mktemp "$checksum_file.tmp.XXXXXX")"
  cksum "$installed_manifest" | awk '{ print $1 ":" $2 }' > "$checksum_temp"
  mv "$checksum_temp" "$checksum_file"
}

install_core() {
  local platform source_dir target prompt destination suffix group source name manifest
  kit_require_real_dir "$HOME/.codex"
  kit_require_real_dir "$HOME/.agents"
# Keep the user config intact except for this feature; unsupported TOML forms
# fail before replacement instead of risking a duplicate or misplaced key.
config="$HOME/.codex/config.toml"
kit_require_regular_or_absent "$config"
config_input="$config"
[ -f "$config_input" ] || config_input=/dev/null
config_next="$KIT_BACKUP_DIR/codex-config.next"
if ! awk '
  function finish_section() {
    if (target && !key_seen) print "experimental_mode = true"
  }
  {
    line = $0
    # Multiline strings can contain text that looks like table headers.
    if (index(line, "\"\"\"") || index(line, sprintf("%c%c%c", 39, 39, 39))) exit 1
    sub(/#.*/, "", line)
    gsub(/[[:space:]]/, "", line)
    normalized = line
    gsub(/[\"\047]/, "", normalized)
    if (target && line ~ /=\[/ && line !~ /]$/) exit 1
    if (line ~ /^\[/) {
      if (index(line, "\\")) exit 1
      finish_section()
      target = (line == "[features.context_management]")
      if ((normalized ~ /^\[features(\.|])/ && normalized != line) ||
          normalized ~ /^\[\[features(\.|])/ ||
          normalized ~ /^\[features\.context_management\.experimental_mode(\.|])/) exit 1
      if (target) {
        if (section_seen++) exit 1
        key_seen = 0
      }
      section = line
    } else if ((section == "" || section == "[features]" || target) &&
               line ~ /^[^=]*\\/) {
      exit 1
    } else if (target && line ~ /^experimental_mode=/) {
      if (key_seen++ || line !~ /^experimental_mode=(true|false)$/) exit 1
      sub(/=[[:space:]]*(true|false)/, "= true")
    } else if ((section == "" && normalized ~ /^features[.=]/) ||
               (section == "[features]" && normalized ~ /^context_management[.=]/) ||
               (target && (normalized ~ /^experimental_mode\./ ||
                           (normalized ~ /^experimental_mode=/ && normalized != line)))) {
      exit 1
    }
    print
  }
  END {
    finish_section()
    if (!section_seen) {
      if (NR) print ""
      print "[features.context_management]\nexperimental_mode = true"
    }
  }
' "$config_input" > "$config_next"; then
  kit_die "Cannot safely update $config. Use [features.context_management] with a boolean experimental_mode; quoted/dotted/inline feature settings and multiline values in this table are unsupported; multiline strings and escaped table headers or related keys are unsupported."
fi
kit_backup_path "$config" "codex/config.toml"
kit_replace_file "$config_next" "$config"


  for platform in claude codex; do
    if [ "$platform" = claude ]; then
      source_dir="$ROOT/claude-code"; target="$HOME/.claude"
      prompt=CLAUDE.md; destination="$target/skills"; suffix=.md
    else
      source_dir="$ROOT/codex"; target="$HOME/.codex"
      prompt=AGENTS.md; destination="$HOME/.agents/skills"; suffix=.toml
    fi
    kit_require_real_dir "$target"
    kit_require_real_dir "$target/agents"
    kit_require_real_dir "$destination"
    kit_backup_path "$target/$prompt" "$platform/$prompt"
    kit_backup_path "$target/agents" "$platform/agents"
    kit_backup_path "$destination" "$platform/skills"
    kit_replace_file "$source_dir/$prompt" "$target/$prompt"
    for group in agents skills; do
      manifest="$KIT_BACKUP_DIR/$platform-$group.current"
      kit_create_empty_file "$manifest"
      if [ "$group" = agents ]; then
        for source in "$source_dir/agents"/*"$suffix"; do
          [ -f "$source" ] || continue
          printf '%s\n' "${source##*/}" >> "$manifest"
        done
      else
        for source in "$ROOT/skills"/*; do
          [ -d "$source" ] || continue
          printf '%s\n' "${source##*/}" >> "$manifest"
        done
      fi
      [ -s "$manifest" ] || kit_die "No $platform $group sources found"
      sort -o "$manifest" "$manifest"
      if [ "$group" = agents ]; then
        kit_prune_manifest "$target/agents" "$KIT_MANIFEST_ROOT/$platform-$group" "$manifest"
        while IFS= read -r name; do
          kit_replace_file "$source_dir/agents/$name" "$target/agents/$name"
        done < "$manifest"
      else
        kit_prune_manifest "$destination" "$KIT_MANIFEST_ROOT/$platform-$group" "$manifest"
        while IFS= read -r name; do
          kit_replace_dir "$ROOT/skills/$name" "$destination/$name"
        done < "$manifest"
      fi
      kit_commit_manifest "$manifest" "$KIT_MANIFEST_ROOT/$platform-$group"
    done
  done
}

SEQUENTIAL_THINKING_PACKAGE="@modelcontextprotocol/server-sequential-thinking@latest"
PONYTAIL_REMOTE="https://github.com/DietrichGebert/ponytail.git"
PONYTAIL_SOURCE_ROOT="$HOME/.universal-research-agent-kit/sources"
PONYTAIL_MARKETPLACE_ROOT="$HOME/.universal-research-agent-kit/marketplaces"
# Resolved from the remote's current HEAD by prepare_ponytail_source, so an
# install always lands on the latest Ponytail. Every path and version check
# below is keyed on the resolved revision, never on a constant in this file.
PONYTAIL_REVISION=""
PONYTAIL_VERSION=""
PONYTAIL_SOURCE=""
PONYTAIL_MARKETPLACE=""


repair_duplicate_headroom_mcp() {
  local config="$HOME/.codex/config.toml"
  local expected_command="command = \"$HOME/.universal-research-agent-kit/tooling/bin/headroom\""
  local headroom_sections
  local managed_block
  local needs_repair=0
  local tmp

  [ -f "$config" ] || return 0
  headroom_sections="$(grep -Fxc '[mcp_servers.headroom]' "$config" || true)"
  if [ "$headroom_sections" -gt 0 ] && ! awk -v first="$expected_command" \
      -v second="command = \"$HOME/.universal-research-agent-kit/tooling/python-venv/bin/headroom\"" '
    /^\[/ {
      if (section && !owned) bad=1
      section=($0 == "[mcp_servers.headroom]"); owned=0
    }
    section && ($0 == first || $0 == second) { owned=1 }
    END { if (section && !owned) bad=1; exit bad }
  ' "$config"; then
    if [ "$headroom_sections" -gt 1 ] || [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" != 1 ]; then
      kit_die "Unowned Headroom MCP configuration was preserved; resolve its name/path conflict before kit installation."
    fi
    (cd "$HOME" && codex mcp list >/dev/null 2>&1) || kit_die "Invalid user MCP configuration was preserved."
    return 0
  fi
  if [ "$headroom_sections" -gt 1 ]; then
    needs_repair=1
  elif [ "$headroom_sections" -eq 1 ] &&
       grep -Fqx '# --- Headroom MCP server ---' "$config"; then
    managed_block="$(sed -n '/^# --- Headroom MCP server ---$/,/^# --- end Headroom MCP server ---$/p' "$config")"
    printf '%s\n' "$managed_block" | grep -Fqx "$expected_command" || needs_repair=1
  fi

  if [ "$needs_repair" -eq 0 ]; then
    (cd "$HOME" && codex mcp list >/dev/null 2>&1) ||
      kit_die "Codex config is invalid and is not a repairable Headroom MCP case: $config"
    return 0
  fi

  tmp="$(mktemp "$config.tmp.XXXXXX")"
  awk '
    $0 == "# --- Headroom MCP server ---" { next }
    $0 == "# --- end Headroom MCP server ---" { next }
    $0 == "[mcp_servers.headroom]" || $0 == "[mcp_servers.headroom.env]" {
      skip = 1
      next
    }
    skip && /^\[/ { skip = 0 }
    !skip { print }
  ' "$config" > "$tmp"
  mv "$tmp" "$config"

  (cd "$HOME" && codex mcp list >/dev/null 2>&1) ||
    kit_die "Removing duplicate Headroom MCP sections did not produce a valid Codex config: $config"
  echo "Removed $headroom_sections stale or duplicate Headroom MCP section(s) from ~/.codex/config.toml; Headroom installation will register one canonical entry."
}

# Sequential Thinking MCP is add-or-repin: a registration under the kit's own
# name is replaced when it does not carry the kit's @latest package spec, so
# install alone converges a registration frozen at an older version. A
# registration under any other name is never inspected, replaced, or removed.
mcp_package_matches() {
  local description
  description="$(cat)"
  printf '%s\n' "$description" | grep -Eq '(^|[^[:alnum:]_/@.-])@modelcontextprotocol/server-sequential-thinking@latest([^[:alnum:]_/@.-]|$)' &&
    printf '%s\n' "$description" | grep -Fq "$HOME/.universal-research-agent-kit/cli/bin/kit-npx"
}

ensure_codex_sequential_thinking() {
  local current
  if current="$(cd "$HOME" && codex mcp get sequential_thinking 2>/dev/null)"; then
    if printf '%s\n' "$current" | mcp_package_matches; then
      echo "Codex sequential_thinking MCP already has the package and host-local launcher; leaving it unchanged."
      CODEX_SEQTHINK_STATE="preexisting"
      return
    fi
    echo "Re-registering the Codex sequential_thinking MCP against the latest package."
    (cd "$HOME" && codex mcp remove sequential_thinking)
    (cd "$HOME" && codex mcp add sequential_thinking -- "$HOME/.universal-research-agent-kit/cli/bin/kit-npx" -y "$SEQUENTIAL_THINKING_PACKAGE")
    (cd "$HOME" && codex mcp get sequential_thinking >/dev/null 2>&1) ||
      kit_die "Failed to re-register the Codex sequential_thinking MCP."
    CODEX_SEQTHINK_STATE="repinned_kit"
    return
  fi
  echo "Registering the Sequential Thinking MCP (latest) for Codex."
  (cd "$HOME" && codex mcp add sequential_thinking -- "$HOME/.universal-research-agent-kit/cli/bin/kit-npx" -y "$SEQUENTIAL_THINKING_PACKAGE")
  (cd "$HOME" && codex mcp get sequential_thinking >/dev/null 2>&1) ||
    kit_die "Failed to register the Codex sequential_thinking MCP."
  CODEX_SEQTHINK_STATE="registered_kit"
}

ensure_claude_sequential_thinking() {
  local current
  if current="$(claude mcp get sequential-thinking 2>/dev/null)"; then
    if printf '%s\n' "$current" | mcp_package_matches; then
      echo "Claude sequential-thinking MCP already has the package and host-local launcher; leaving it unchanged."
      CLAUDE_SEQTHINK_STATE="preexisting"
      return
    fi
    echo "Re-registering the Claude sequential-thinking MCP against the latest package."
    claude mcp remove sequential-thinking -s user
    claude mcp add -s user sequential-thinking -- "$HOME/.universal-research-agent-kit/cli/bin/kit-npx" -y "$SEQUENTIAL_THINKING_PACKAGE"
    claude mcp get sequential-thinking >/dev/null 2>&1 ||
      kit_die "Failed to re-register the Claude sequential-thinking MCP."
    CLAUDE_SEQTHINK_STATE="repinned_kit"
    return
  fi
  echo "Registering the Sequential Thinking MCP (latest) for Claude Code."
  claude mcp add -s user sequential-thinking -- "$HOME/.universal-research-agent-kit/cli/bin/kit-npx" -y "$SEQUENTIAL_THINKING_PACKAGE"
  claude mcp get sequential-thinking >/dev/null 2>&1 ||
    kit_die "Failed to register the Claude sequential-thinking MCP."
  CLAUDE_SEQTHINK_STATE="registered_kit"
}

codex_plugin_installed() {
  local selector="$1"
  codex plugin list --json | node -e '
    const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const plugin = (data.installed || []).find((item) => item.pluginId === process.argv[1]);
    process.exit(plugin && plugin.installed === true ? 0 : 1);
  ' "$selector"
}

codex_plugin_kit_owned() {
  local selector="$1"
  codex plugin list --json | node -e '
    const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const plugin = (data.installed || []).find((item) => item.pluginId === process.argv[1]);
    const owned = plugin && plugin.source?.source === "local" &&
      typeof plugin.source.path === "string" &&
      plugin.source.path.startsWith(process.argv[2] + "/");
    process.exit(owned ? 0 : 1);
  ' "$selector" "$PONYTAIL_MARKETPLACE_ROOT"
}

codex_plugin_exact_enabled() {
  local selector="$1"
  local version="$2"
  local require_local="${3:-0}"
  local expected_path="${4:-}"
  codex plugin list --json | node -e '
    const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const plugin = (data.installed || []).find((item) => item.pluginId === process.argv[1]);
    const requireLocal = process.argv[3] === "1";
    const expectedPath = process.argv[4];
    const exact = plugin && (!process.argv[2] || plugin.version === process.argv[2]) &&
      plugin.installed === true && plugin.enabled === true;
    const local = plugin && plugin.source?.source === "local" &&
      (!expectedPath || plugin.source.path === expectedPath);
    process.exit(exact && (!requireLocal || local) ? 0 : 1);
  ' "$selector" "$version" "$require_local" "$expected_path"
}

# Prints "<version> enabled|disabled" for an installed plugin, or "absent".
codex_plugin_status() {
  local selector="$1"
  codex plugin list --json | node -e '
    const data = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const plugin = (data.installed || []).find((item) => item.pluginId === process.argv[1]);
    if (!plugin || plugin.installed !== true) { console.log("absent"); process.exit(0); }
    console.log((plugin.version || "unknown") + " " + (plugin.enabled === true ? "enabled" : "disabled"));
  ' "$selector"
}

claude_plugin_installed() {
  claude plugin list --json | node -e '
    const plugins = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const plugin = plugins.find((item) =>
      item.id === "ponytail@ponytail" && item.scope === "user");
    process.exit(plugin ? 0 : 1);
  '
}

claude_plugin_exact_enabled() {
  claude plugin list --json | node -e '
    const plugins = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const plugin = plugins.find((item) =>
      item.id === "ponytail@ponytail" && item.scope === "user");
    process.exit(plugin && (!process.argv[1] || plugin.version === process.argv[1]) && plugin.enabled === true ? 0 : 1);
  ' "${1-$PONYTAIL_VERSION}"
}

# Marketplace ownership: kit-owned means the registration path points into
# the kit state directory. Returns 0 kit-owned, 1 absent, 2 user-owned.
codex_ponytail_marketplace_ownership() {
  local marketplaces
  marketplaces="$(codex plugin marketplace list --json)"
  if ! printf '%s\n' "$marketplaces" | grep -Eq '"name"[[:space:]]*:[[:space:]]*"ponytail"'; then
    return 1
  fi
  if printf '%s\n' "$marketplaces" | grep -Fq "$PONYTAIL_MARKETPLACE_ROOT/"; then
    return 0
  fi
  return 2
}

claude_ponytail_marketplace_ownership() {
  local marketplaces
  marketplaces="$(claude plugin marketplace list --json)"
  if ! printf '%s\n' "$marketplaces" | grep -Eq '"name"[[:space:]]*:[[:space:]]*"ponytail"'; then
    return 1
  fi
  if printf '%s\n' "$marketplaces" | grep -Fq "$PONYTAIL_MARKETPLACE_ROOT/"; then
    return 0
  fi
  return 2
}

prepare_ponytail_source() {
  local temp
  local revision

  command -v git >/dev/null 2>&1 || {
    echo "Error: git is required to install the latest Ponytail release." >&2
    exit 1
  }
  kit_require_real_dir "$PONYTAIL_SOURCE_ROOT"

  PONYTAIL_REVISION="$(git ls-remote "$PONYTAIL_REMOTE" HEAD | awk 'NR == 1 { print $1 }')"
  case "$PONYTAIL_REVISION" in
    [0-9a-f][0-9a-f]*) ;;
    *) kit_die "Failed to resolve the latest Ponytail revision from $PONYTAIL_REMOTE" ;;
  esac
  PONYTAIL_SOURCE="$PONYTAIL_SOURCE_ROOT/ponytail-$PONYTAIL_REVISION"
  PONYTAIL_MARKETPLACE="$PONYTAIL_MARKETPLACE_ROOT/ponytail-$PONYTAIL_REVISION"

  if [ -e "$PONYTAIL_SOURCE" ]; then
    kit_require_real_dir "$PONYTAIL_SOURCE"
    kit_require_real_dir "$PONYTAIL_SOURCE/.git"
  else
    temp="$(mktemp -d "$PONYTAIL_SOURCE_ROOT/.ponytail.tmp.XXXXXX")"
    if ! git -C "$temp" init -q ||
       ! git -C "$temp" remote add origin "$PONYTAIL_REMOTE" ||
       ! git -C "$temp" fetch -q --depth=1 origin "$PONYTAIL_REVISION" ||
       ! git -C "$temp" checkout -q --detach FETCH_HEAD; then
      rm -rf -- "$temp"
      echo "Error: failed to fetch the latest Ponytail release." >&2
      exit 1
    fi
    mv "$temp" "$PONYTAIL_SOURCE"
  fi

  revision="$(git -C "$PONYTAIL_SOURCE" rev-parse HEAD)"
  [ "$revision" = "$PONYTAIL_REVISION" ] ||
    kit_die "Ponytail checkout has unexpected revision: $revision"
  [ -z "$(git -C "$PONYTAIL_SOURCE" status --porcelain --untracked-files=all)" ] ||
    kit_die "Ponytail checkout contains local modifications."

  # The version to verify after install comes from the checkout, so tracking
  # HEAD cannot leave a stale expected version behind in this script.
  PONYTAIL_VERSION="$(node -e '
    const fs = require("fs");
    const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    process.stdout.write(manifest.version || "");
  ' "$PONYTAIL_SOURCE/.claude-plugin/plugin.json")"
  [ -n "$PONYTAIL_VERSION" ] ||
    kit_die "Ponytail checkout $PONYTAIL_REVISION declares no plugin version."
}

prepare_ponytail_marketplace() {
  local temp
  local name

  kit_require_real_dir "$PONYTAIL_MARKETPLACE_ROOT"
  temp="$(mktemp -d "$PONYTAIL_MARKETPLACE_ROOT/.ponytail-market.tmp.XXXXXX")"
  mkdir -p "$temp/.agents/plugins" "$temp/.claude-plugin" "$temp/ponytail"
  if ! git -C "$PONYTAIL_SOURCE" archive HEAD | tar -xf - -C "$temp/ponytail"; then
    rm -rf -- "$temp"
    kit_die "Failed to materialize the pinned Ponytail marketplace."
  fi

  cat > "$temp/.agents/plugins/marketplace.json" <<'JSON'
{
  "name": "ponytail",
  "interface": { "displayName": "Ponytail" },
  "plugins": [
    {
      "name": "ponytail",
      "source": { "source": "local", "path": "./ponytail" },
      "policy": { "installation": "AVAILABLE", "authentication": "ON_INSTALL" },
      "category": "Productivity"
    }
  ]
}
JSON
  cat > "$temp/.claude-plugin/marketplace.json" <<'JSON'
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "ponytail",
  "description": "Pinned Ponytail marketplace for this kit.",
  "owner": { "name": "Dietrich Gebert", "url": "https://github.com/DietrichGebert" },
  "plugins": [
    {
      "name": "ponytail",
      "description": "Forces the smallest solution that works.",
      "source": "./ponytail",
      "category": "productivity"
    }
  ]
}
JSON

  name="${PONYTAIL_MARKETPLACE##*/}"
  kit_remove_owned_entry "$PONYTAIL_MARKETPLACE_ROOT" "$name"
  mv "$temp" "$PONYTAIL_MARKETPLACE"
}

# Both required hosts have converged before superseded revision directories are pruned.
prune_old_ponytail_revisions() {
  local root entry name

  [ -n "$PONYTAIL_REVISION" ] || return 0
  for root in "$PONYTAIL_SOURCE_ROOT" "$PONYTAIL_MARKETPLACE_ROOT"; do
    for entry in "$root"/ponytail-*; do
      [ -d "$entry" ] || continue
      name="${entry##*/}"
      if [ "$name" != "ponytail-$PONYTAIL_REVISION" ]; then
        kit_remove_owned_entry "$root" "$name"
        echo "Removed superseded Ponytail revision directory: $entry"
      fi
    done
  done
}

# Returns 0 when the kit marketplace is registered and usable, 1 when a
# user-owned ponytail marketplace must be preserved (skip kit management).
configure_codex_marketplace() {
  local ownership_rc=0
  codex_ponytail_marketplace_ownership || ownership_rc=$?
  if [ "$ownership_rc" -eq 2 ]; then
    echo "Preserving user-owned ponytail marketplace in Codex; skipping kit Ponytail management."
    return 1
  fi
  if [ "$ownership_rc" -eq 0 ] &&
     ! codex plugin marketplace list --json | grep -Fq "$PONYTAIL_MARKETPLACE"; then
    codex plugin marketplace remove ponytail
  fi
  if ! codex plugin marketplace list --json | grep -Fq "$PONYTAIL_MARKETPLACE"; then
    codex plugin marketplace add "$PONYTAIL_MARKETPLACE"
  fi
}

configure_claude_marketplace() {
  local ownership_rc=0
  claude_ponytail_marketplace_ownership || ownership_rc=$?
  if [ "$ownership_rc" -eq 2 ]; then
    echo "Preserving user-owned ponytail marketplace in Claude Code; skipping kit Ponytail management."
    return 1
  fi
  if [ "$ownership_rc" -eq 0 ] &&
     ! claude plugin marketplace list --json | grep -Fq "$PONYTAIL_MARKETPLACE"; then
    claude plugin marketplace remove ponytail
  fi
  if ! claude plugin marketplace list --json | grep -Fq "$PONYTAIL_MARKETPLACE"; then
    claude plugin marketplace add "$PONYTAIL_MARKETPLACE"
  fi
}

# Remove the legacy plugin and only its recorded or lazycodex-* loose agents.
LAZYCODEX_AGENT_MANIFEST="$HOME/.codex/plugins/data/omo-sisyphuslabs/bootstrap/agents-stage/.installed-agents.json"

# Missing lazycodex-* registrations can outlive their files; unrelated entries stay.
broken_codex_agent_registrations() {
  local config="$HOME/.codex/config.toml"

  [ -f "$config" ] || return 0
  awk -v home="$HOME" '
    /^\[agents\./ {
      name = $0
      sub(/^\[agents\./, "", name)
      sub(/\]$/, "", name)
      gsub(/"/, "", name)
      if (index(name, ".") > 0) { current = ""; next }
      current = name
      next
    }
    /^\[/ { current = ""; next }
    current != "" && /^[ \t]*config_file[ \t]*=/ {
      path = $0
      sub(/^[ \t]*config_file[ \t]*=[ \t]*/, "", path)
      gsub(/^"|"$/, "", path)
      if (substr(path, 1, 2) == "~/") path = home substr(path, 2)
      print current "\t" path
    }
  ' "$config" | while IFS="$(printf '\t')" read -r name path; do
    case "$name" in lazycodex-*) ;; *) continue ;; esac
    [ -e "$path" ] || printf '%s\n' "$name"
  done
}

drop_codex_agent_registrations() {
  local names="$1"
  local config="$HOME/.codex/config.toml"
  local tmp

  [ -n "$names" ] || return 0
  [ -f "$config" ] || return 0
  kit_require_regular_or_absent "$config"
  kit_backup_path "$config" "integrations/codex-config-agents.toml"

  tmp="$(mktemp "$config.tmp.XXXXXX")"
  awk -v names="$names" '
    BEGIN {
      count = split(names, list, " ")
      for (i = 1; i <= count; i++) {
        drop["[agents." list[i] "]"] = 1
        drop["[agents.\"" list[i] "\"]"] = 1
        prefix[i] = "[agents." list[i] "."
        quoted[i] = "[agents.\"" list[i] "\"."
      }
      total = count
    }
    /^\[/ {
      skip = ($0 in drop)
      if (!skip) {
        for (i = 1; i <= total; i++) {
          if (index($0, prefix[i]) == 1 || index($0, quoted[i]) == 1) { skip = 1; break }
        }
      }
      if (skip) next
    }
    !skip { print }
  ' "$config" > "$tmp"
  mv "$tmp" "$config"

  if command -v codex >/dev/null 2>&1; then
    (cd "$HOME" && codex mcp list >/dev/null 2>&1) ||
      kit_die "Removing LazyCodex agent registrations produced an invalid Codex config: $config"
  fi
}

remove_lazycodex_planted_agents() {
  local agents_dir="$HOME/.codex/agents"
  local removed=0
  local removed_names=""
  local broken
  local name entry planted_agents

  if [ ! -d "$agents_dir" ]; then
    broken="$(broken_codex_agent_registrations | tr '\n' ' ')"
    drop_codex_agent_registrations "$broken"
    [ -z "${broken// /}" ] ||
      echo "Dropped Codex agent registration(s) pointing at missing files:${broken% }"
    return 0
  fi

  if [ -f "$LAZYCODEX_AGENT_MANIFEST" ] && command -v node >/dev/null 2>&1; then
    planted_agents="$(node -e '
  const fs = require("fs");
  const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  for (const p of data.agents || []) console.log(p);
' "$LAZYCODEX_AGENT_MANIFEST")"
    while IFS= read -r entry; do
      case "$entry" in "$agents_dir/"*.toml) ;; *) continue ;; esac
      name="${entry##*/}"
      case "$name" in
        */*|..|.|"") continue ;;
      esac
      [ -f "$ROOT/codex/agents/$name" ] && continue
      [ -f "$agents_dir/$name" ] || continue
      kit_backup_path "$agents_dir/$name" "integrations/lazycodex-agents/$name"
      kit_remove_owned_entry "$agents_dir" "$name"
      removed_names="$removed_names ${name%.toml}"
      removed=$((removed + 1))
    done <<EOF
$planted_agents
EOF
  fi

  for entry in "$agents_dir"/lazycodex-*.toml; do
    [ -f "$entry" ] || continue
    name="${entry##*/}"
    kit_backup_path "$entry" "integrations/lazycodex-agents/$name"
    kit_remove_owned_entry "$agents_dir" "$name"
    removed_names="$removed_names ${name%.toml}"
    removed=$((removed + 1))
  done

  broken="$(broken_codex_agent_registrations | tr '\n' ' ')"
  drop_codex_agent_registrations "$removed_names $broken"
  [ "$removed" -eq 0 ] ||
    echo "Removed $removed LazyCodex-planted agent file(s) from ~/.codex/agents (backed up)."
  [ -z "${broken// /}" ] ||
    echo "Dropped Codex agent registration(s) pointing at missing files:${broken% }"
}

reconcile_codex_lazycodex() {
  local status version

  status="$(codex_plugin_status "omo@sisyphuslabs")"
  if [ "$status" = "absent" ]; then
    remove_lazycodex_planted_agents
    CODEX_LAZYCODEX_STATE="not_requested"
    return
  fi
  version="${status%% *}"
  echo "Removing LazyCodex $version; this kit does not install it in any profile."
  codex plugin remove omo@sisyphuslabs
  [ "$(codex_plugin_status "omo@sisyphuslabs")" = "absent" ] ||
    kit_die "Failed to remove LazyCodex."
  # The sisyphuslabs marketplace exists only to serve LazyCodex, but it is not
  # kit-owned, so a failure to drop the registration is not an install failure.
  codex plugin marketplace remove sisyphuslabs 2>/dev/null ||
    echo "Left the sisyphuslabs marketplace registration in place."
  remove_lazycodex_planted_agents
  CODEX_LAZYCODEX_STATE="removed_legacy"
}

# Profile none removes only kit-owned Ponytail remnants; user-owned
# marketplaces and plugins are never touched.
reconcile_codex_ponytail_none() {
  local ownership_rc=0

  if codex_plugin_installed "ponytail@ponytail"; then
    if codex_plugin_kit_owned "ponytail@ponytail"; then
      echo "Removing kit-installed Ponytail plugin from Codex (profile: none)."
      codex plugin remove ponytail@ponytail
      CODEX_PONYTAIL_STATE="removed_legacy"
    else
      echo "Preserving user-owned Ponytail plugin in Codex."
      CODEX_PONYTAIL_STATE="preserved_user_owned"
      return
    fi
  else
    CODEX_PONYTAIL_STATE="not_requested"
  fi

  codex_ponytail_marketplace_ownership || ownership_rc=$?
  if [ "$ownership_rc" -eq 0 ]; then
    echo "Removing kit-owned ponytail marketplace registration from Codex."
    codex plugin marketplace remove ponytail
    CODEX_PONYTAIL_STATE="removed_legacy"
  fi
}

reconcile_claude_ponytail_none() {
  local ownership_rc=0

  claude_ponytail_marketplace_ownership || ownership_rc=$?
  case "$ownership_rc" in
    0)
      if claude_plugin_installed; then
        echo "Removing kit-installed Ponytail plugin from Claude Code (profile: none)."
        claude plugin uninstall ponytail@ponytail -s user
      fi
      echo "Removing kit-owned ponytail marketplace registration from Claude Code."
      claude plugin marketplace remove ponytail
      CLAUDE_PONYTAIL_STATE="removed_legacy"
      ;;
    1)
      if claude_plugin_installed; then
        echo "Preserving Ponytail plugin in Claude Code (no kit-owned marketplace; treating as user-owned)."
        CLAUDE_PONYTAIL_STATE="preserved_user_owned"
      else
        CLAUDE_PONYTAIL_STATE="not_requested"
      fi
      ;;
    2)
      echo "Preserving user-owned ponytail marketplace in Claude Code."
      CLAUDE_PONYTAIL_STATE="preserved_user_owned"
      ;;
  esac
}


ensure_user_codex_ponytail() {
    if ! codex_plugin_installed ponytail@ponytail; then
      codex plugin add ponytail@ponytail
    fi
    codex_plugin_exact_enabled ponytail@ponytail "" ||
      kit_die "User-owned Codex Ponytail is not enabled. Enable ponytail@ponytail in Codex plugin settings, then rerun; this CLI has no plugin-enable command. Its source was preserved."
}

# Parse outside a predicate: malformed CLI JSON must fail, not resemble absence.
validate_plugin_listings() {
  local host
  for host in codex claude; do
    "$host" plugin list --json | node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))'
    "$host" plugin marketplace list --json | node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))'
  done
}

install_integrations() {
  kit_require_real_dir "$HOME/.codex"
  kit_require_real_dir "$HOME/.codex/plugins"
  kit_require_regular_or_absent "$HOME/.codex/config.toml"
  kit_backup_path "$HOME/.codex/config.toml" "integrations/codex-config.toml"
  repair_duplicate_headroom_mcp
  kit_require_real_dir "$HOME/.claude"
  kit_require_real_dir "$HOME/.claude/plugins"
  kit_require_regular_or_absent "$HOME/.claude.json"
  kit_require_regular_or_absent "$HOME/.claude/settings.json"
  kit_require_regular_or_absent "$HOME/.claude/plugins/known_marketplaces.json"
  kit_require_regular_or_absent "$HOME/.claude/plugins/installed_plugins.json"
  kit_backup_path "$HOME/.claude.json" "integrations/claude.json"
  kit_backup_path "$HOME/.claude/settings.json" "integrations/claude-settings.json"
  kit_backup_path "$HOME/.claude/plugins/known_marketplaces.json" "integrations/claude-known-marketplaces.json"
  kit_backup_path "$HOME/.claude/plugins/installed_plugins.json" "integrations/claude-installed-plugins.json"
  validate_plugin_listings

if [ "$PROFILE" != "none" ]; then
  prepare_ponytail_source
  prepare_ponytail_marketplace
fi

  reconcile_codex_lazycodex

  if [ "$PROFILE" = "none" ]; then
    reconcile_codex_ponytail_none
  elif codex_plugin_installed ponytail@ponytail && ! codex_plugin_kit_owned ponytail@ponytail; then
    ensure_user_codex_ponytail
    CODEX_PONYTAIL_STATE="preserved_user_owned"
  elif configure_codex_marketplace; then
    if codex_plugin_installed "ponytail@ponytail" &&
       ! codex_plugin_exact_enabled "ponytail@ponytail" "$PONYTAIL_VERSION" 1 "$PONYTAIL_MARKETPLACE/ponytail"; then
      if codex_plugin_kit_owned "ponytail@ponytail"; then
        codex plugin remove ponytail@ponytail
      else
        kit_die "Existing Codex ponytail plugin is not kit-owned; remove it manually or keep it and rerun with --integrations none."
      fi
    fi
    if ! codex_plugin_exact_enabled "ponytail@ponytail" "$PONYTAIL_VERSION" 1 "$PONYTAIL_MARKETPLACE/ponytail"; then
      codex plugin add ponytail@ponytail
    else
      echo "Ponytail for Codex is already installed and enabled."
    fi
    codex_plugin_exact_enabled "ponytail@ponytail" "$PONYTAIL_VERSION" 1 "$PONYTAIL_MARKETPLACE/ponytail" ||
      kit_die "Codex Ponytail $PONYTAIL_VERSION is not installed and enabled."
    CODEX_PONYTAIL_STATE="installed_kit_owned"
  else
    ensure_user_codex_ponytail
    CODEX_PONYTAIL_STATE="preserved_user_owned"
  fi


  if [ "$PROFILE" = "none" ]; then
    reconcile_claude_ponytail_none
  elif configure_claude_marketplace; then
    if claude_plugin_installed && ! claude_plugin_exact_enabled; then
      claude plugin uninstall ponytail@ponytail -s user
      claude plugin install ponytail@ponytail -s user
    elif ! claude_plugin_installed; then
      claude plugin install ponytail@ponytail -s user
    else
      echo "Ponytail for Claude Code is already installed and enabled."
    fi
    claude_plugin_exact_enabled ||
      kit_die "Claude Ponytail $PONYTAIL_VERSION is not installed and enabled."
    CLAUDE_PONYTAIL_STATE="installed_kit_owned"
  else
    if ! claude_plugin_installed; then
      claude plugin install ponytail@ponytail -s user
    fi
    if ! claude_plugin_exact_enabled ""; then
      claude plugin enable ponytail@ponytail -s user
    fi
    claude_plugin_exact_enabled "" || kit_die "User-owned Claude Ponytail is not installed and enabled; check its marketplace and rerun. Its source was preserved."
    CLAUDE_PONYTAIL_STATE="preserved_user_owned"
  fi


ensure_codex_sequential_thinking
ensure_claude_sequential_thinking

prune_old_ponytail_revisions

kit_write_integrations_state "$PROFILE" "$CODEX_PONYTAIL_STATE" "$CLAUDE_PONYTAIL_STATE" "$CODEX_LAZYCODEX_STATE" "$CODEX_SEQTHINK_STATE" "$CLAUDE_SEQTHINK_STATE"
echo "Recorded integrations state (profile: $PROFILE)."

}
tool_version_matches() {
  local command_name="$1"
  local expected_version="$2"
  local candidate
  local output

  output="$("$command_name" --version 2>&1)" || return 1
  while IFS= read -r candidate; do
    [ "$candidate" = "$expected_version" ] && return 0
  done <<EOF
$(printf '%s\n' "$output" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*' || true)
EOF
  return 1
}


prepare_tooling() {
[ "${KIT_TOOLING_PREPARED:-0}" -eq 0 ] || return 0
TOOL_ROOT="$KIT_STATE_ROOT/tooling"
TOOL_BIN_DIR="$TOOL_ROOT/bin"
TOOL_UV_DIR="$TOOL_ROOT/uv-tools"
TOOL_ROOT_PREPARED=0
KIT_UV_BIN="$TOOL_ROOT/uv-bin/uv"
KIT_UV_READY=0

validate_tool_path() {
  local path="$1"

  [ ! -L "$path" ] || kit_die "Refusing a symlinked managed tooling path: $path"
  if [ -e "$path" ] && [ ! -d "$path" ]; then
    kit_die "Managed tooling path is not a directory: $path"
  fi
}

validate_tool_path "$TOOL_ROOT"
validate_tool_path "$TOOL_BIN_DIR"
validate_tool_path "$TOOL_UV_DIR"

prepare_managed_tool_root() {
  [ "$TOOL_ROOT_PREPARED" -eq 0 ] || return 0

  kit_tooling_idle || kit_die "Installation stopped before changing managed tooling."
  kit_backup_path "$TOOL_ROOT" "tooling/environment"
  if [ -d "$TOOL_ROOT" ]; then
    kit_tooling_idle || kit_die "Installation stopped before clearing the old managed environment."
    echo "Managed tooling failed validation; rebuilding from an empty directory. Backup: $KIT_BACKUP_DIR/tooling/environment"
    rm -rf -- "$TOOL_ROOT"
  fi
  kit_require_real_dir "$TOOL_ROOT"
  kit_require_real_dir "$TOOL_BIN_DIR"
  kit_require_real_dir "$TOOL_UV_DIR"
  TOOL_ROOT_PREPARED=1
}

ensure_uv() {
  [ "$KIT_UV_READY" -eq 0 ] || return 0
  prepare_managed_tool_root
  if [ ! -x "$KIT_UV_BIN" ]; then
    kit_require_real_dir "$TOOL_ROOT/uv-bin"
    if command -v uv >/dev/null 2>&1 && tool_version_matches uv "$KIT_UV_VERSION"; then
      cp "$(command -v uv)" "$KIT_UV_BIN"
    else
      echo "Preparing kit-local uv $KIT_UV_VERSION (no system Python required)."
      download_file "https://astral.sh/uv/$KIT_UV_VERSION/install.sh" "$KIT_BACKUP_DIR/install-uv.sh"
      UV_UNMANAGED_INSTALL="$TOOL_ROOT/uv-bin" sh "$KIT_BACKUP_DIR/install-uv.sh" || kit_die "uv bootstrap failed."
    fi
  fi
  tool_version_matches "$KIT_UV_BIN" "$KIT_UV_VERSION" || kit_die "Kit uv does not report $KIT_UV_VERSION."
  kit_require_real_dir "$TOOL_ROOT/python"
  export UV_PYTHON_INSTALL_DIR="$TOOL_ROOT/python"
  export UV_TOOL_DIR="$TOOL_UV_DIR"
  export UV_TOOL_BIN_DIR="$TOOL_BIN_DIR"
  export UV_PYTHON_DOWNLOADS=automatic
  kit_tooling_idle || kit_die "Installation stopped before provisioning managed Python."
  "$KIT_UV_BIN" --no-config python install --managed-python --no-bin "$KIT_PYTHON_VERSION" ||
    kit_die "Failed to provision kit Python $KIT_PYTHON_VERSION."
  KIT_UV_READY=1
}

tool_environment_ready() {
  local command_name="$1"
  local expected_version="$2"
  local distribution="$3"
  local command_path="$TOOL_BIN_DIR/$1"
  local python_path="$TOOL_UV_DIR/$distribution/bin/python"

  [ -x "$command_path" ] && [ -x "$python_path" ] || return 1
  tool_version_matches "$command_path" "$expected_version" || return 1
  "$python_path" -I -B "$ROOT/headroom/runtime.py" environment "$distribution" "$expected_version" || return 1
  "$KIT_UV_BIN" --no-config pip check --python "$python_path" || return 1
  if [ "$command_name" = headroom ]; then
    "$python_path" -I -B "$ROOT/headroom/runtime.py" dependencies "$expected_version" || return 1
  fi
}

ensure_tool() {
  local command_name="$1"
  local package="$2"
  local expected_version="$3"
  local install_state_var="$4"
  local distribution="$5"

  ensure_uv
  kit_tooling_idle || kit_die "Installation stopped before replacing $command_name."
  echo "Installing/repairing $command_name in its kit-managed Python environment."
  "$KIT_UV_BIN" --no-config tool install --managed-python --python "$KIT_PYTHON_VERSION" \
    --reinstall "$package" || kit_die "Failed to install $command_name with uv."
  hash -r 2>/dev/null || true
  tool_environment_ready "$command_name" "$expected_version" "$distribution" ||
    kit_die "Managed Python environment verification failed for $command_name."
  printf -v "$install_state_var" '%s' installed
}

# Always put the managed bin first. A previous run leaves this directory in the
# shell rc, and ~/.profile can prepend ~/.local/bin ahead of it, so testing for
# mere presence would let a stale copy there shadow the version installed here.
PATH="$TOOL_BIN_DIR:$PATH"
export PATH
hash -r 2>/dev/null || true

GRAPHIFY_STATE=""
HEADROOM_STATE=""
if [ -x "$KIT_UV_BIN" ] && tool_version_matches "$KIT_UV_BIN" "$KIT_UV_VERSION" &&
    tool_environment_ready graphify "$GRAPHIFY_VERSION" graphifyy &&
    tool_environment_ready headroom "$HEADROOM_VERSION" headroom-ai; then
  GRAPHIFY_STATE=present
  HEADROOM_STATE=present
else
  ensure_tool graphify "$GRAPHIFY_PACKAGE" "$GRAPHIFY_VERSION" GRAPHIFY_STATE graphifyy
  ensure_tool headroom "$HEADROOM_PACKAGE" "$HEADROOM_VERSION" HEADROOM_STATE headroom-ai
fi
GRAPHIFY_BIN="$(command -v graphify 2>/dev/null || true)"
[ -n "$GRAPHIFY_BIN" ] || kit_die "Graphify installation completed but its command is not on PATH: $TOOL_BIN_DIR"

HEADROOM_BIN="$(command -v headroom 2>/dev/null || true)"
[ -n "$HEADROOM_BIN" ] || kit_die "Headroom installation completed but its command is not on PATH: $TOOL_BIN_DIR"
KIT_HEADROOM_PYTHON="$TOOL_UV_DIR/headroom-ai/bin/python"
KIT_TOOLING_PREPARED=1
}

install_tooling() {
prepare_tooling

HEADROOM_WRAPPER="$HOME/.config/headroom/auto-wrap.sh"
kit_require_regular_or_absent "$HEADROOM_WRAPPER"
kit_backup_path "$HEADROOM_WRAPPER" "tooling/headroom-auto-wrap.sh"
kit_replace_file "$ROOT/headroom/auto-wrap.sh" "$HEADROOM_WRAPPER" || kit_die "Failed to install the Headroom wrapper."
kit_require_regular_or_absent "$HOME/.config/headroom/runtime.py"
kit_backup_path "$HOME/.config/headroom/runtime.py" "tooling/headroom-runtime.py"
kit_replace_file "$ROOT/headroom/runtime.py" "$HOME/.config/headroom/runtime.py"
KIT_HEADROOM_PYTHON="$TOOL_UV_DIR/headroom-ai/bin/python"


GRAPHIFY_CLAUDE_PROMPT="$HOME/.claude/CLAUDE.md"
GRAPHIFY_CLAUDE_SKILL="$HOME/.claude/skills/graphify"
GRAPHIFY_CODEX_SKILL="$HOME/.codex/skills/graphify"
for graphify_parent in "$HOME/.claude" "$HOME/.claude/skills" "$HOME/.codex" "$HOME/.codex/skills"; do
  [ ! -L "$graphify_parent" ] || kit_die "Refusing a symlinked Graphify parent: $graphify_parent"
  if [ -e "$graphify_parent" ] && [ ! -d "$graphify_parent" ]; then
    kit_die "Graphify parent is not a directory: $graphify_parent"
  fi
done
kit_require_regular_or_absent "$GRAPHIFY_CLAUDE_PROMPT"
for graphify_skill in "$GRAPHIFY_CLAUDE_SKILL" "$GRAPHIFY_CODEX_SKILL"; do
  [ ! -L "$graphify_skill" ] || kit_die "Refusing a symlinked Graphify skill: $graphify_skill"
  if [ -e "$graphify_skill" ] && [ ! -d "$graphify_skill" ]; then
    kit_die "Graphify skill path is not a directory: $graphify_skill"
  fi
done
kit_backup_path "$GRAPHIFY_CLAUDE_PROMPT" "tooling/graphify-claude-prompt"
kit_backup_path "$GRAPHIFY_CLAUDE_SKILL" "tooling/graphify-claude-skill"
kit_backup_path "$GRAPHIFY_CODEX_SKILL" "tooling/graphify-codex-skill"

CODEX_AGENTS="$HOME/.codex/AGENTS.md"
CODEX_GRAPHIFY_BLOCK="$KIT_BACKUP_DIR/graphify-codex-agents-block"
cat > "$CODEX_GRAPHIFY_BLOCK" <<'EOF'
# BEGIN UNIVERSAL RESEARCH AGENT KIT GRAPHIFY
## Graphify

For an explicit graph request or an existing useful project graph, use the installed Graphify skill and its scoped query/path/explain workflow. Do not build or query a graph as a prerequisite for ordinary code reading.

The global Graphify skill is installed at `~/.codex/skills/graphify/SKILL.md`.
# END UNIVERSAL RESEARCH AGENT KIT GRAPHIFY
EOF
kit_replace_managed_block "$CODEX_AGENTS" "$CODEX_GRAPHIFY_BLOCK" "tooling/graphify-codex-agents" '# BEGIN UNIVERSAL RESEARCH AGENT KIT GRAPHIFY' '# END UNIVERSAL RESEARCH AGENT KIT GRAPHIFY'

# Graphify updates all existing platform version stamps; include them in rollback.
GRAPHIFY_EXISTING_INDEX=0
for graphify_existing_skill in \
  "$HOME/.config/opencode/skills/graphify" \
  "$HOME/.config/kilo/skills/graphify" \
  "$HOME/.aider/graphify" \
  "$HOME/.copilot/skills/graphify" \
  "$HOME/.openclaw/skills/graphify" \
  "$HOME/.factory/skills/graphify" \
  "$HOME/.trae/skills/graphify" \
  "$HOME/.trae-cn/skills/graphify" \
  "$HOME/.hermes/skills/graphify" \
  "$HOME/.gemini/config/skills/graphify" \
  "$HOME/.kiro/skills/graphify" \
  "$HOME/.pi/agent/skills/graphify" \
  "$HOME/.codebuddy/skills/graphify" \
  "$HOME/.agents/skills/graphify" \
  "$HOME/.config/agents/skills/graphify" \
  "$HOME/.config/devin/skills/graphify" \
  "$HOME/.kimi/skills/graphify"; do
  [ "$graphify_existing_skill" = "$GRAPHIFY_CLAUDE_SKILL" ] && continue
  [ "$graphify_existing_skill" = "$GRAPHIFY_CODEX_SKILL" ] && continue
  [ ! -L "$graphify_existing_skill" ] || kit_die "Refusing a symlinked Graphify skill: $graphify_existing_skill"
  if [ -e "$graphify_existing_skill" ] && [ ! -d "$graphify_existing_skill" ]; then
    kit_die "Graphify skill path is not a directory: $graphify_existing_skill"
  fi
  if [ -e "$graphify_existing_skill" ]; then
    kit_backup_path "$graphify_existing_skill" "tooling/graphify-existing-$GRAPHIFY_EXISTING_INDEX"
    GRAPHIFY_EXISTING_INDEX=$((GRAPHIFY_EXISTING_INDEX + 1))
  fi
done

SHELL_BLOCK="$KIT_BACKUP_DIR/headroom-shell-block"
cat > "$SHELL_BLOCK" <<'EOF'
# BEGIN UNIVERSAL RESEARCH AGENT KIT HEADROOM
case ":$PATH:" in
  *:"$HOME/.local/bin":*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ; export PATH ;;
esac
case ":$PATH:" in
  *:"$HOME/.universal-research-agent-kit/cli/bin":*) ;;
  *) PATH="$HOME/.universal-research-agent-kit/cli/bin:$PATH" ; export PATH ;;
esac
case ":$PATH:" in
  *:"$HOME/.universal-research-agent-kit/tooling/bin":*) ;;
  *) PATH="$HOME/.universal-research-agent-kit/tooling/bin:$PATH" ; export PATH ;;
esac
[ -f "$HOME/.config/headroom/auto-wrap.sh" ] && source "$HOME/.config/headroom/auto-wrap.sh"
# END UNIVERSAL RESEARCH AGENT KIT HEADROOM
EOF
kit_replace_managed_block "$HOME/.zshrc" "$SHELL_BLOCK" "shell/zshrc" '# BEGIN UNIVERSAL RESEARCH AGENT KIT HEADROOM' '# END UNIVERSAL RESEARCH AGENT KIT HEADROOM'
kit_replace_managed_block "$HOME/.bashrc" "$SHELL_BLOCK" "shell/bashrc" '# BEGIN UNIVERSAL RESEARCH AGENT KIT HEADROOM' '# END UNIVERSAL RESEARCH AGENT KIT HEADROOM'

"$GRAPHIFY_BIN" install --platform claude || kit_die "Graphify Claude global installation failed."
"$GRAPHIFY_BIN" install --platform codex || kit_die "Graphify Codex global installation failed."

# Install shared MCP configuration once; normal sessions never rewrite it.
kit_backup_path "$HOME/.codex/config.toml" "tooling/headroom-codex-config"
for mcp_path in "$HOME/.claude.json" "$HOME/.claude/mcp.json"; do
  kit_require_regular_or_absent "$mcp_path"
done
kit_backup_path "$HOME/.claude.json" "tooling/headroom-claude-config"
kit_backup_path "$HOME/.claude/mcp.json" "tooling/headroom-claude-legacy-mcp"
"$HEADROOM_BIN" mcp install --agent codex || kit_die "Headroom Codex MCP registration failed."
"$HEADROOM_BIN" mcp install --agent claude || kit_die "Headroom Claude MCP registration failed."

kit_require_regular_or_absent "$KIT_STATE_ROOT/headroom.json"
kit_backup_path "$KIT_STATE_ROOT/headroom.json" "tooling/headroom-state"
KIT_HEADROOM_CREATED=0
[ -f "$KIT_STATE_ROOT/headroom.json" ] || KIT_HEADROOM_CREATED=1
"$KIT_HEADROOM_PYTHON" -I -B "$ROOT/headroom/runtime.py" install || kit_die "Persistent Headroom installation failed."
if [ "$(uname -s)" = Linux ]; then
  if ! command -v loginctl >/dev/null 2>&1 ||
      [ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)" != yes ]; then
    echo "Note: user systemd is ready, but SSH-logout/reboot persistence needs linger. Ask your administrator or run: loginctl enable-linger $(id -un)"
  fi
fi


kit_write_tooling_state "installed" "$GRAPHIFY_STATE" "$HEADROOM_STATE" "installed" \
  "$GRAPHIFY_VERSION" "$HEADROOM_VERSION" "$TOOL_BIN_DIR"
echo "Installed Graphify, Headroom MCP, process-local launchers and the host persistent proxy."

}
verify_install() {
TOOLING_STATE_FILE="$HOME/.universal-research-agent-kit/tooling.state"
read_tooling_state() {
  sed -n "s/^$1=//p" "$TOOLING_STATE_FILE" | sed -n '1p'
}

tooling_status_for_prompt=""
if [ -f "$TOOLING_STATE_FILE" ] && [ ! -L "$TOOLING_STATE_FILE" ]; then
  tooling_status_for_prompt="$(read_tooling_state status)"
fi

if command -v uv >/dev/null 2>&1; then
  uv_tool_bin="$(uv tool dir --bin 2>/dev/null || true)"
  case "$uv_tool_bin" in
    /*) PATH="$uv_tool_bin:$PATH"; export PATH ;;
  esac
fi
if command -v python3 >/dev/null 2>&1; then
  python_tool_bin="$(python3 -c 'import site; print(site.getuserbase() + "/bin")' 2>/dev/null || true)"
  case "$python_tool_bin" in
    /*) PATH="$python_tool_bin:$PATH"; export PATH ;;
  esac
fi
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH"; export PATH ;;
esac
# The managed bin goes on last so it wins. The three directories above can each
# hold an older same-named tool, and verifying one of those would report the
# wrong version for a correct install.
PATH="$HOME/.universal-research-agent-kit/tooling/bin:$HOME/.universal-research-agent-kit/cli/bin:$PATH"
export PATH
hash -r 2>/dev/null || true

bash "$ROOT/scripts/validate_harness.sh"

missing=0
scoped=0
check_file() {
  if [ ! -f "$1" ]; then
    echo "Missing: $1"
    missing=1
  else
    echo "OK: $1"
  fi
}
check_regular_file() {
  if [ ! -f "$1" ] || [ -L "$1" ]; then
    echo "Missing or unsafe regular file: $1"
    missing=1
  else
    echo "OK regular file: $1"
  fi
}
check_nonempty_file() {
  if [ ! -s "$1" ] || [ -L "$1" ]; then
    echo "Missing, empty, or unsafe file: $1"
    missing=1
  else
    echo "OK nonempty file: $1"
  fi
}
check_nonempty_dir() {
  local path="$1"
  if [ ! -d "$path" ] || [ -L "$path" ]; then
    echo "Missing or unsafe directory: $path"
    missing=1
  elif ! find "$path" -type f -print -quit | grep -q .; then
    echo "Empty directory: $path"
    missing=1
  else
    echo "OK nonempty directory: $path"
  fi
}
check_exact_file() {
  local path="$1"
  local expected="$2"
  local actual
  if [ ! -f "$path" ] || [ -L "$path" ]; then
    echo "Unexpected file content: $path"
    missing=1
  else
    actual="$(cat "$path")"
    if [ "$actual" != "$expected" ]; then
      echo "Unexpected file content: $path"
      missing=1
    else
      echo "OK exact file: $path"
    fi
  fi
}
check_dir() {
  if [ ! -d "$1" ]; then
    echo "Missing: $1"
    missing=1
  else
    echo "OK: $1"
  fi
}
check_executable() {
  if [ ! -x "$1" ]; then
    echo "Missing executable: $1"
    missing=1
  else
    echo "OK executable: $1"
  fi
}
check_contains() {
  local path="$1"
  local pattern="$2"
  if ! grep -q "$pattern" "$path"; then
    echo "Missing pattern in $path: $pattern"
    missing=1
  else
    echo "OK pattern in $path: $pattern"
  fi
}

check_contains_fixed() {
  local path="$1"
  local pattern="$2"
  if ! grep -Fq -- "$pattern" "$path"; then
    echo "Missing fixed pattern in $path: $pattern"
    missing=1
  else
    echo "OK fixed pattern in $path: $pattern"
  fi
}

check_same_file() {
  local source="$1"
  local installed="$2"
  if ! cmp -s "$source" "$installed"; then
    echo "Content mismatch: $installed"
    missing=1
  else
    echo "OK content: $installed"
  fi
}

check_claude_prompt() {
  local source="$1"
  local installed="$2"
  local require_graphify="${3:-}"
  local normalized

  if [ "$require_graphify" != "installed" ] && cmp -s "$source" "$installed"; then
    echo "OK content: $installed"
    return
  fi
  if [ ! -f "$installed" ]; then
    echo "Content mismatch: $installed"
    missing=1
    return
  fi

  if ! grep -Fqx -- '# graphify' "$installed" ||
    ! grep -Fqx -- '- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`' "$installed" ||
    ! grep -Fqx -- 'When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.' "$installed"; then
    echo "Missing or invalid Graphify registration: $installed"
    missing=1
    return
  fi

  normalized="$(mktemp "${TMPDIR:-/tmp}/claude-prompt.XXXXXX")"
  awk '$0 == "# graphify" { exit } { print }' "$installed" > "$normalized"
  if cmp -s "$source" "$normalized"; then
    echo "OK content with Graphify section: $installed"
  else
    echo "Content mismatch: $installed"
    missing=1
  fi
  rm -f "$normalized"
}

check_codex_agents() {
  local source="$1"
  local installed="$2"
  local require_graphify="${3:-}"
  local normalized

  if [ "$require_graphify" != "installed" ] && cmp -s "$source" "$installed"; then
    echo "OK content: $installed"
    return
  fi
  if [ ! -f "$installed" ]; then
    echo "Content mismatch: $installed"
    missing=1
    return
  fi

  if [ "$(grep -Fxc '# BEGIN UNIVERSAL RESEARCH AGENT KIT GRAPHIFY' "$installed" || true)" -ne 1 ] ||
    [ "$(grep -Fxc '# END UNIVERSAL RESEARCH AGENT KIT GRAPHIFY' "$installed" || true)" -ne 1 ] ||
    ! grep -Fqx -- '## Graphify' "$installed" ||
    ! grep -Fqx -- 'For an explicit graph request or an existing useful project graph, use the installed Graphify skill and its scoped query/path/explain workflow. Do not build or query a graph as a prerequisite for ordinary code reading.' "$installed" ||
    ! grep -Fqx -- 'The global Graphify skill is installed at `~/.codex/skills/graphify/SKILL.md`.' "$installed"; then
    echo "Missing or invalid Graphify Codex registration: $installed"
    missing=1
    return
  fi

  normalized="$(mktemp "${TMPDIR:-/tmp}/codex-agents.XXXXXX")"
  awk '
    { lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (lines[i] == "# BEGIN UNIVERSAL RESEARCH AGENT KIT GRAPHIFY" && start == 0) start = i
        if (lines[i] == "# END UNIVERSAL RESEARCH AGENT KIT GRAPHIFY" && start != 0) { stop = i; break }
      }
      for (i = 1; i <= NR; i++) {
        if (i >= start && i <= stop) continue
        if (i == start - 1 && lines[i] == "") continue
        print lines[i]
      }
    }
  ' "$installed" > "$normalized"
  if cmp -s "$source" "$normalized"; then
    echo "OK content with Graphify section: $installed"
  else
    echo "Content mismatch: $installed"
    missing=1
  fi
  rm -f "$normalized"
}

check_same_dir() {
  local source="$1"
  local installed="$2"
  if ! diff -qr "$source" "$installed" >/dev/null 2>&1; then
    echo "Directory content mismatch: $installed"
    missing=1
  else
    echo "OK directory content: $installed"
  fi
}

check_manifest() {
  local source_dir="$1"
  local suffix="$2"
  local manifest="$3"
  local checksum_file="$manifest.cksum"
  local expected_checksum actual_checksum
  local source name

  if [ ! -f "$manifest" ]; then
    echo "Missing ownership manifest: $manifest"
    missing=1
    return
  fi

  if [ -L "$manifest" ]; then
    echo "Unsafe ownership manifest: $manifest"
    missing=1
    return
  fi

  if [ ! -f "$checksum_file" ] || [ -L "$checksum_file" ]; then
    echo "Missing or unsafe manifest checksum: $checksum_file"
    missing=1
  else
    expected_checksum="$(cat "$checksum_file")"
    actual_checksum="$(cksum "$manifest" | awk '{ print $1 ":" $2 }')"
    if [ "$expected_checksum" != "$actual_checksum" ]; then
      echo "Manifest checksum mismatch: $manifest"
      missing=1
    fi
  fi

  for source in "$source_dir"/*"$suffix"; do
    [ -e "$source" ] || continue
    name="${source##*/}"
    if ! grep -Fqx "$name" "$manifest"; then
      echo "Missing manifest entry in $manifest: $name"
      missing=1
    fi
  done

  while IFS= read -r name || [ -n "$name" ]; do
    if [ -z "$name" ] || [ ! -e "$source_dir/$name" ]; then
      echo "Unexpected manifest entry in $manifest: $name"
      missing=1
    fi
  done < "$manifest"
}
check_file "$HOME/.claude/CLAUDE.md"
check_dir "$HOME/.claude/agents"
check_dir "$HOME/.claude/skills"

if ! awk '
  /^\[/ { section = ($0 == "[features.context_management]") }
  section && /^[[:space:]]*experimental_mode[[:space:]]*=[[:space:]]*true([[:space:]]*(#.*)?)$/ { found++ }
  END { exit found != 1 }
' "$HOME/.codex/config.toml"; then
  echo "Missing or disabled context_management.experimental_mode"
  missing=1
fi
check_file "$HOME/.codex/AGENTS.md"
check_dir "$HOME/.codex/agents"
check_dir "$HOME/.agents/skills"

for source in "$ROOT/claude-code/agents"/*.md; do
  check_same_file "$source" "$HOME/.claude/agents/${source##*/}"
done

for source in "$ROOT/codex/agents"/*.toml; do
  check_same_file "$source" "$HOME/.codex/agents/${source##*/}"
done

for source in "$ROOT/skills"/*; do
  [ -d "$source" ] || continue
  check_same_dir "$source" "$HOME/.claude/skills/${source##*/}"
done
for source in "$ROOT/skills"/*; do
  [ -d "$source" ] || continue
  check_same_dir "$source" "$HOME/.agents/skills/${source##*/}"
done

check_executable "$HOME/.claude/skills/resource-aware-orchestration/scripts/detect_resources.sh"
check_executable "$HOME/.agents/skills/resource-aware-orchestration/scripts/detect_resources.sh"
check_executable "$HOME/.claude/skills/resource-aware-orchestration/scripts/run_codex_agent.sh"
check_executable "$HOME/.agents/skills/resource-aware-orchestration/scripts/run_codex_agent.sh"

check_claude_prompt "$ROOT/claude-code/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "$tooling_status_for_prompt"
check_codex_agents "$ROOT/codex/AGENTS.md" "$HOME/.codex/AGENTS.md" "$tooling_status_for_prompt"

check_manifest "$ROOT/claude-code/agents" ".md" "$HOME/.universal-research-agent-kit/manifests/claude-agents"
check_manifest "$ROOT/codex/agents" ".toml" "$HOME/.universal-research-agent-kit/manifests/codex-agents"
check_manifest "$ROOT/skills" "" "$HOME/.universal-research-agent-kit/manifests/claude-skills"
check_manifest "$ROOT/skills" "" "$HOME/.universal-research-agent-kit/manifests/codex-skills"

check_file "$HOME/.config/git/ignore"
check_contains "$HOME/.config/git/ignore" "BEGIN UNIVERSAL RESEARCH AGENT KIT"
check_contains "$HOME/.config/git/ignore" "END UNIVERSAL RESEARCH AGENT KIT"

check_tool_command() {
  local command_name="$1"
  local command_path

  command_path="$(command -v "$command_name" 2>/dev/null || true)"
  if [ -n "$command_path" ]; then
    echo "OK command: $command_name ($command_path)"
  elif [ -x "$HOME/.universal-research-agent-kit/tooling/bin/$command_name" ]; then
    echo "OK command: $command_name ($HOME/.universal-research-agent-kit/tooling/bin/$command_name)"
  elif [ -x "$HOME/.local/bin/$command_name" ]; then
    echo "OK command: $command_name ($HOME/.local/bin/$command_name)"
  else
    echo "Missing command: $command_name"
    missing=1
  fi
}

check_tool_version() {
  tool_version_matches "$1" "$2" || { echo "Wrong version for $1; expected $2"; missing=1; }
}

check_graphify_skill_layout() {
  local skill_root="$1"

  check_regular_file "$skill_root/SKILL.md"
  check_nonempty_file "$skill_root/SKILL.md"
  check_contains_fixed "$skill_root/SKILL.md" "graphify"
  check_exact_file "$skill_root/.graphify_version" "$EXPECTED_GRAPHIFY_VERSION"
  check_nonempty_dir "$skill_root/references"
}

if [ ! -f "$TOOLING_STATE_FILE" ] || [ -L "$TOOLING_STATE_FILE" ]; then
  echo "Missing tooling state; run sh install.sh."
  missing=1
elif [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" = 1 ]; then
  echo "Scoped verification: tooling explicitly skipped by environment."
  scoped=1
else
  tooling_status="$(read_tooling_state status)"
  case "$tooling_status" in
    installed)
      graphify_state="$(read_tooling_state graphify)"
      headroom_state="$(read_tooling_state headroom)"
      wrapper_state="$(read_tooling_state headroom_wrapper)"
      case "$graphify_state" in
        present|installed) echo "Graphify: $graphify_state" ;;
        *) echo "Unknown Graphify state: $graphify_state"; missing=1 ;;
      esac
      case "$headroom_state" in
        present|installed) echo "Headroom: $headroom_state" ;;
        *) echo "Unknown Headroom state: $headroom_state"; missing=1 ;;
      esac
      [ "$wrapper_state" = "installed" ] || {
        echo "Unknown Headroom wrapper state: $wrapper_state"
        missing=1
      }
      graphify_version="$(read_tooling_state graphify_version)"
      headroom_version="$(read_tooling_state headroom_version)"
      tool_bin_dir="$(read_tooling_state tool_bin_dir)"
      [ "$graphify_version" = "$EXPECTED_GRAPHIFY_VERSION" ] || {
        echo "Unexpected Graphify state version: $graphify_version"
        missing=1
      }
      [ "$headroom_version" = "$EXPECTED_HEADROOM_VERSION" ] || {
        echo "Unexpected Headroom state version: $headroom_version"
        missing=1
      }
      [ "$tool_bin_dir" = "$HOME/.universal-research-agent-kit/tooling/bin" ] || {
        echo "Unexpected tooling bin directory: $tool_bin_dir"
        missing=1
      }
      check_tool_command graphify
      check_tool_command headroom
      check_tool_version graphify "$graphify_version"
      check_tool_version headroom "$headroom_version"
      "$HOME/.universal-research-agent-kit/tooling/uv-tools/graphifyy/bin/python" -I -B \
        "$ROOT/headroom/runtime.py" environment graphifyy "$EXPECTED_GRAPHIFY_VERSION" || missing=1
      check_graphify_skill_layout "$HOME/.claude/skills/graphify"
      check_graphify_skill_layout "$HOME/.codex/skills/graphify"
      check_same_file "$ROOT/headroom/auto-wrap.sh" "$HOME/.config/headroom/auto-wrap.sh"
      check_same_file "$ROOT/headroom/runtime.py" "$HOME/.config/headroom/runtime.py"
      runtime_python="$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python"
      if [ -x "$runtime_python" ]; then
        "$runtime_python" -I -B "$ROOT/headroom/runtime.py" dependencies "$EXPECTED_HEADROOM_VERSION" || missing=1
        "$runtime_python" -I -B "$ROOT/headroom/runtime.py" check || missing=1
      else
        echo "Missing kit Headroom interpreter: $runtime_python"; missing=1
      fi
      check_file "$HOME/.zshrc"
      check_file "$HOME/.bashrc"
      if [ -f "$HOME/.zshrc" ]; then
        check_contains_fixed "$HOME/.zshrc" '*:"$HOME/.universal-research-agent-kit/tooling/bin":*) ;;'
        check_contains_fixed "$HOME/.zshrc" '[ -f "$HOME/.config/headroom/auto-wrap.sh" ] && source "$HOME/.config/headroom/auto-wrap.sh"'
      fi
      if [ -f "$HOME/.bashrc" ]; then
        check_contains_fixed "$HOME/.bashrc" '*:"$HOME/.universal-research-agent-kit/tooling/bin":*) ;;'
        check_contains_fixed "$HOME/.bashrc" '[ -f "$HOME/.config/headroom/auto-wrap.sh" ] && source "$HOME/.config/headroom/auto-wrap.sh"'
      fi
      ;;
    skipped_env)
      echo "Scoped verification: Graphify and Headroom were explicitly skipped."
      scoped=1
      ;;
    *)
      echo "Unknown tooling state: $tooling_status"
      missing=1
      ;;
  esac
fi

# Verify each host against its recorded installation or preservation outcome.
STATE_FILE="$HOME/.universal-research-agent-kit/integrations.state"
KIT_MARKETPLACE_ROOT="$HOME/.universal-research-agent-kit/marketplaces"

# Kit-owned Ponytail requires the installed marketplace manifest's path and version.
KIT_PONYTAIL_MANIFEST=""
KIT_PONYTAIL_PATH=""
KIT_PONYTAIL_VERSION=""
for ponytail_manifest in "$KIT_MARKETPLACE_ROOT"/ponytail-*/ponytail/.claude-plugin/plugin.json; do
  [ -f "$ponytail_manifest" ] || continue
  if [ -z "$KIT_PONYTAIL_MANIFEST" ] || [ "$ponytail_manifest" -nt "$KIT_PONYTAIL_MANIFEST" ]; then
    KIT_PONYTAIL_MANIFEST="$ponytail_manifest"
  fi
done
if [ -n "$KIT_PONYTAIL_MANIFEST" ]; then
  KIT_PONYTAIL_PATH="${KIT_PONYTAIL_MANIFEST%/.claude-plugin/plugin.json}"
  if command -v node >/dev/null 2>&1; then
    KIT_PONYTAIL_VERSION="$(node -e '
      const fs = require("fs");
      const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      process.stdout.write(manifest.version || "");
    ' "$KIT_PONYTAIL_MANIFEST")"
  fi
fi

read_state() {
  sed -n "s/^$1=//p" "$STATE_FILE" | sed -n '1p'
}

codex_usable() { command -v codex >/dev/null 2>&1 && command -v node >/dev/null 2>&1; }
claude_usable() { command -v claude >/dev/null 2>&1 && command -v node >/dev/null 2>&1; }

PONYTAIL_MARKETPLACE_ROOT="$KIT_MARKETPLACE_ROOT"
PONYTAIL_VERSION="$KIT_PONYTAIL_VERSION"
codex_ponytail_kit_enabled() {
  [ -n "$KIT_PONYTAIL_VERSION" ] && [ -n "$KIT_PONYTAIL_PATH" ] &&
    codex_plugin_exact_enabled ponytail@ponytail "$KIT_PONYTAIL_VERSION" 1 "$KIT_PONYTAIL_PATH"
}
codex_ponytail_kit_owned_present() { codex_plugin_installed ponytail@ponytail && codex_plugin_kit_owned ponytail@ponytail; }
codex_lazycodex_installed() { codex_plugin_installed omo@sisyphuslabs; }
codex_lazycodex_enabled() { case "$(codex_plugin_status omo@sisyphuslabs)" in *' enabled') return 0;; *) return 1;; esac; }
claude_ponytail_kit_enabled() { [ -n "$KIT_PONYTAIL_VERSION" ] && claude_plugin_exact_enabled; }
claude_ponytail_pinned_installed() { claude_plugin_installed && claude_ponytail_marketplace_ownership; }
claude_ponytail_installed() { claude_plugin_installed; }

if [ ! -f "$STATE_FILE" ] || [ -L "$STATE_FILE" ]; then
  echo "Missing integrations state; run sh install.sh."
  missing=1
elif [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" = "1" ]; then
  echo "Scoped verification: integrations explicitly skipped by environment."
  scoped=1
else
  requested_profile="$(read_state requested_profile)"
  if ! verify_native_clis; then
    echo "Official native CLI installation or kit launcher is missing/broken; rerun sh install.sh."
    missing=1
  fi
  echo "Integrations profile: ${requested_profile:-unknown}"
  case "$requested_profile" in none|ponytail) ;; *) echo "Unknown requested integration profile"; missing=1 ;; esac

  if [ "$(read_state codex_ponytail)" != skipped_env ] || [ "$(read_state claude_ponytail)" != skipped_env ]; then
    if codex_usable && claude_usable; then
      validate_plugin_listings
    else
      echo "Required integration verification CLI unavailable (Codex, Claude or Node.js)"
      missing=1
    fi
  fi
  codex_ponytail_state="$(read_state codex_ponytail)"
  case "$codex_ponytail_state" in
    installed_kit_owned)
      if codex_usable && codex_ponytail_kit_enabled; then
        echo "OK Codex integration: Ponytail (kit-owned)"
      else
        echo "Missing Codex integration: Ponytail"
        missing=1
      fi
      ;;
    preserved_user_owned)
      if [ "$requested_profile" = ponytail ]; then
        codex_usable && codex_plugin_exact_enabled ponytail@ponytail "" || {
          echo "Required user-owned Codex Ponytail is missing or disabled"; missing=1;
        }
      fi
      echo "Codex integration: user-owned Ponytail source preserved"
      ;;
    removed_legacy|not_requested)
      [ "$requested_profile" != ponytail ] || { echo "Required Codex Ponytail was not installed"; missing=1; }
      if codex_usable && codex_ponytail_kit_owned_present; then
        echo "Kit-owned Codex Ponytail is still installed despite state '$codex_ponytail_state'."
        missing=1
      else
        echo "OK Codex integration: Ponytail $codex_ponytail_state"
      fi
      ;;
    skipped_env)
      scoped=1
      echo "Codex Ponytail: $codex_ponytail_state"
      ;;
    unverified_no_node)
      echo "Codex Ponytail state is unverified"; missing=1
      ;;
    *)
      echo "Unknown Codex Ponytail state: $codex_ponytail_state"
      missing=1
      ;;
  esac

  claude_ponytail_state="$(read_state claude_ponytail)"
  case "$claude_ponytail_state" in
    installed_kit_owned)
      if claude_usable && claude_ponytail_kit_enabled; then
        echo "OK Claude integration: Ponytail (kit-owned)"
      else
        echo "Missing Claude integration: Ponytail"
        missing=1
      fi
      ;;
    preserved_user_owned)
      if [ "$requested_profile" = ponytail ]; then
        claude_usable && claude_plugin_exact_enabled "" || {
          echo "Required user-owned Claude Ponytail is missing or disabled"; missing=1;
        }
      fi
      echo "Claude integration: user-owned Ponytail source preserved"
      ;;
    removed_legacy|not_requested)
      [ "$requested_profile" != ponytail ] || { echo "Required Claude Ponytail was not installed"; missing=1; }
      if claude_usable && claude_ponytail_pinned_installed; then
        echo "Kit-installed Claude Ponytail $KIT_PONYTAIL_VERSION is present despite state '$claude_ponytail_state'; run 'sh install.sh' to reconcile."
        missing=1
      elif claude_usable && claude_ponytail_installed; then
        echo "OK Claude integration: non-pinned user-owned Ponytail detected and preserved (state '$claude_ponytail_state')."
      else
        echo "OK Claude integration: Ponytail $claude_ponytail_state"
      fi
      ;;
    skipped_env)
      scoped=1
      echo "Claude Ponytail: $claude_ponytail_state"
      ;;
    unverified_no_node)
      echo "Claude Ponytail state is unverified"; missing=1
      ;;
    *)
      echo "Unknown Claude Ponytail state: $claude_ponytail_state"
      missing=1
      ;;
  esac

  codex_lazycodex_state="$(read_state codex_lazycodex)"
  case "$codex_lazycodex_state" in
    installed_kit_owned)
      echo "State records a kit-installed LazyCodex, which this kit no longer installs; run 'sh install.sh' to remove it."
      missing=1
      ;;
    removed_legacy)
      if codex_usable && codex_lazycodex_installed; then
        echo "LazyCodex is still installed but the profile is '$requested_profile'; run 'sh install.sh' to migrate."
        missing=1
      else
        echo "OK Codex integration: LazyCodex removed"
      fi
      ;;
    disabled_legacy|not_requested|user_owned_warned)
      if codex_usable && codex_lazycodex_enabled; then
        echo "LazyCodex is enabled but the profile is '$requested_profile'; run 'sh install.sh' to migrate."
        missing=1
      else
        echo "OK Codex integration: LazyCodex $codex_lazycodex_state"
      fi
      ;;
    skipped_env)
      scoped=1
      echo "Codex LazyCodex: $codex_lazycodex_state"
      ;;
    unverified_no_node)
      echo "Codex LazyCodex state is unverified"; missing=1
      ;;
    *)
      echo "Unknown Codex LazyCodex state: $codex_lazycodex_state"
      missing=1
      ;;
  esac

  codex_seqthink_state="$(read_state codex_sequential_thinking)"
  case "$codex_seqthink_state" in
    registered_kit|repinned_kit|preexisting)
      if ! command -v codex >/dev/null 2>&1 || ! (cd "$HOME" && codex mcp get sequential_thinking) | mcp_package_matches; then
        echo "Missing Codex MCP: sequential_thinking (state '$codex_seqthink_state')"
        missing=1
      else
        echo "OK Codex MCP: sequential_thinking ($codex_seqthink_state)"
      fi
      ;;
    skipped_env)
      scoped=1
      echo "Codex sequential_thinking MCP: ${codex_seqthink_state:-not_recorded}"
      ;;
    *)
      echo "Unknown Codex sequential_thinking state: $codex_seqthink_state"
      missing=1
      ;;
  esac

  claude_seqthink_state="$(read_state claude_sequential_thinking)"
  case "$claude_seqthink_state" in
    registered_kit|repinned_kit|preexisting)
      if ! command -v claude >/dev/null 2>&1 || ! claude mcp get sequential-thinking | mcp_package_matches; then
        echo "Missing Claude MCP: sequential-thinking (state '$claude_seqthink_state')"
        missing=1
      else
        echo "OK Claude MCP: sequential-thinking ($claude_seqthink_state)"
      fi
      ;;
    skipped_env)
      scoped=1
      echo "Claude sequential-thinking MCP: ${claude_seqthink_state:-not_recorded}"
      ;;
    *)
      echo "Unknown Claude sequential-thinking state: $claude_seqthink_state"
      missing=1
      ;;
  esac


fi

[ "${KIT_VERIFY_REMOTE:-1}" != 1 ] || verify_codex_remote || missing=1
if [ "$missing" -ne 0 ]; then
  echo "Install verification failed."
  exit 1
fi

if [ "$scoped" -eq 1 ]; then
  echo "Scoped verification passed; explicitly skipped components are not verified."
else
  echo "Full install verification passed. Restart Claude Code and Codex sessions."
fi

}
cleanup_backups() {
case "${HOME:-}" in
  ""|/) echo "Refusing to clean backups with an unsafe HOME." >&2; exit 1 ;;
  /*) ;;
  *) echo "HOME must be an absolute directory: $HOME" >&2; exit 1 ;;
esac

STATE_ROOT="$HOME/.universal-research-agent-kit"
BACKUP_ROOT="$STATE_ROOT/backups"

if [ -L "$STATE_ROOT" ] || [ -L "$BACKUP_ROOT" ]; then
  echo "Refusing to clean a symlinked kit state path." >&2
  exit 1
fi

# An active install depends on its run journal for automatic rollback.
if [ -d "$STATE_ROOT/.lock" ]; then
  echo "Refusing to clean backups while an install holds the kit lock: $STATE_ROOT/.lock" >&2
  exit 1
fi

if [ ! -d "$BACKUP_ROOT" ]; then
  echo "No kit backup snapshots found."
  return 0
fi

rm -rf -- "$BACKUP_ROOT"
echo "Kit backup snapshots deleted."

}
main() {
  PROFILE=ponytail
  ENABLE_CODEX_REMOTE=0
  action=install
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --integrations)
        [ "$#" -ge 2 ] || kit_die "--integrations requires none or ponytail"
        case "$2" in none|ponytail) PROFILE="$2" ;; *) kit_die "Unknown integration profile: $2" ;; esac
        shift 2 ;;
      --verify) [ "$action" = install ] || kit_die "Choose only one action"; action=verify; shift ;;
      --enable-codex-remote-control) ENABLE_CODEX_REMOTE=1; shift ;;
      --disable-codex-remote-control) [ "$action" = install ] || kit_die "Choose only one action"; action=remote_disable; shift ;;
      --remote-control-status) [ "$action" = install ] || kit_die "Choose only one action"; action=remote_status; shift ;;
      --headroom-status) [ "$action" = install ] || kit_die "Choose only one action"; action=headroom_status; shift ;;
      --remove-headroom) [ "$action" = install ] || kit_die "Choose only one action"; action=headroom_remove; shift ;;
      --cleanup-backups) [ "$action" = install ] || kit_die "Choose only one action"; action=cleanup; shift ;;
      -h|--help)
        cat <<'HELP'
Usage: sh install.sh [--integrations ponytail|none] [--verify | --cleanup-backups]
Default: install/update core, Ponytail, Sequential Thinking MCP, Graphify and Headroom.
Missing Codex, Claude and Node.js/npx are installed automatically; existing CLIs are preserved.
Python 3.13 and pinned uv are provisioned in the kit; no manual pip/system Python setup is needed.
Invalid managed tooling is backed up, cleared and rebuilt automatically; active environments block installation.
  --integrations none  Remove kit-owned Ponytail and legacy LazyCodex; keep MCP and tooling.
  --verify             Check source and installed files without installing or changing HOME.
  --enable-codex-remote-control  Opt this host into managed Codex Remote Control (pair separately).
  --disable-codex-remote-control Disable Remote Control on this host; preserve local tools.
  --remote-control-status       Read-only remote host status.
  --headroom-status    Check the kit service, readiness, interpreter and Codex routing.
  --remove-headroom    Remove only the kit persistent service/provider; restore prior root settings.
  --cleanup-backups    Delete backup snapshots only; refuse while an install holds the lock.
Environment: UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS=1 leaves integrations untouched;
UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING=1 leaves Graphify/Headroom untouched.
Explicit skips are recorded as skipped, not verified installations.
HELP
        return ;;
      *) kit_die "Unknown argument: $1" ;;
    esac
  done
  [ -z "${CODEX_HOME:-}" ] || [ "$CODEX_HOME" = "$HOME/.codex" ] ||
    kit_die "Custom CODEX_HOME is not supported; unset it before running this installer. No paths were changed."
  [ "$ENABLE_CODEX_REMOTE" -eq 0 ] || [ "$action" = install ] ||
    kit_die "--enable-codex-remote-control cannot be combined with a read-only/removal action."
  case "$action" in
    verify) verify_install; return ;;
    cleanup) cleanup_backups; return ;;
    remote_status) show_codex_remote; return ;;
    remote_disable)
      kit_init_state
      trap 'kit_release_lock' EXIT
      disable_codex_remote
      return ;;
    headroom_status)
      "$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python" -I -B "$ROOT/headroom/runtime.py" check
      return ;;
    headroom_remove)
      kit_init_state
      trap 'kit_release_lock' EXIT
      kit_backup_path "$HOME/.codex/config.toml" "headroom-remove/config.toml"
      "$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python" -I -B "$ROOT/headroom/runtime.py" remove
      return ;;
  esac
  [ -z "${CLAUDE_CONFIG_DIR:-}" ] || kit_die "CLAUDE_CONFIG_DIR is not supported by this installer; unset it and rerun."
  if [ "$ENABLE_CODEX_REMOTE" -eq 1 ] && [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" = 1 ]; then
    kit_die "Remote Control host setup requires the persistent Headroom tooling step."
  fi
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" != 1 ]; then
    kit_tooling_idle || kit_die "Installation stopped before changing this host."
  fi
  kit_init_state
  kit_enable_rollback
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" != 1 ]; then
    kit_tooling_idle || kit_die "Installation stopped after acquiring its lock."
  fi
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" != 1 ]; then
    bootstrap_cli
  fi
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" != 1 ]; then
    prepare_tooling
    kit_require_regular_or_absent "$HOME/.codex/config.toml"
    kit_backup_path "$HOME/.codex/config.toml" "legacy/config.toml"
    "$KIT_HEADROOM_PYTHON" -I -B "$ROOT/headroom/runtime.py" migrate-legacy || kit_die "Legacy Headroom migration failed."
  fi
  install_core
  kit_replace_managed_block "$HOME/.config/git/ignore" "$ROOT/global_research_agents.gitignore" git/ignore '# BEGIN UNIVERSAL RESEARCH AGENT KIT' '# END UNIVERSAL RESEARCH AGENT KIT'
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" = 1 ]; then
    kit_write_integrations_state "$PROFILE" skipped_env skipped_env skipped_env skipped_env skipped_env
  else
    install_integrations
  fi
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" = 1 ]; then
    kit_write_tooling_state skipped_env skipped_env skipped_env skipped_env - - "$HOME/.universal-research-agent-kit/tooling/bin"
  else
    install_tooling
  fi
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" != 1 ] &&
      [ -f "$KIT_STATE_ROOT/codex-remote-control.state" ] &&
      grep -Fqx 'enabled=1' "$KIT_STATE_ROOT/codex-remote-control.state"; then
    ENABLE_CODEX_REMOTE=1
  fi
  if [ "$ENABLE_CODEX_REMOTE" -eq 1 ] || [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" = 1 ]; then KIT_VERIFY_REMOTE=0; fi
  verify_install
  # Package manager removals cannot be rolled back by the file journal. Keep
  # the verified replacement installed if a manager reports a cleanup failure.
  trap 'kit_release_lock' EXIT
  if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_INTEGRATIONS:-0}" != 1 ]; then
    cleanup_legacy_clis
  fi
  if [ "$ENABLE_CODEX_REMOTE" -eq 1 ]; then
    # The validated kit remains installed if a host's auth/network prevents RC.
    trap 'kit_release_lock' EXIT
    KIT_HEADROOM_PYTHON="$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python"
    enable_codex_remote
    verify_codex_remote
  fi
  echo "Done for the verified scope. Restart Claude Code and Codex sessions."
}
[ "${BASH_SOURCE[0]}" != "$0" ] || main "$@"
