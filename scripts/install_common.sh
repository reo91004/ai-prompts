#!/usr/bin/env bash
# Sourced by install.sh.

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

# Installs always use the newest releases; tooling.state records what was installed.
latest_pypi_version() {
  local json="$KIT_WORK_DIR/pypi-$1.json" version
  download_file "https://pypi.org/pypi/$1/json" "$json"
  version="$(grep -o '"version":"[^"]*"' "$json" | sed -n '1s/^"version":"\(.*\)"$/\1/p')"
  [ -n "$version" ] || kit_die "Cannot read the latest $1 release from PyPI."
  printf '%s\n' "$version"
}

latest_node_lts() {
  local index="$KIT_WORK_DIR/node-index.json" version
  download_file "https://nodejs.org/dist/index.json" "$index"
  version="$(grep -m1 '"lts":"' "$index" | grep -o '"version":"v[^"]*"' | sed 's/^"version":"v\(.*\)"$/\1/')"
  [ -n "$version" ] || kit_die "Cannot read the latest Node.js LTS release."
  printf '%s\n' "$version"
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
  local node_root="$HOME/.universal-research-agent-kit/cli/node" physical_node_root
  physical_home="$(cd "$HOME" && pwd -P)" || return 1
  physical_root="$physical_home/.universal-research-agent-kit/tooling"
  physical_headroom="$physical_home/.local/bin/headroom"
  physical_node_root="$physical_home/.universal-research-agent-kit/cli/node"
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
      "$root/"*|"$physical_root/"*|"$node_root/"*|"$physical_node_root/"*|"$local_headroom"|"$local_headroom"[[:space:]]*|"$physical_headroom"|"$physical_headroom"[[:space:]]*) busy=1 ;;
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
            "$root/"*|"$physical_root/"*|"$node_root/"*|"$physical_node_root/"*|"$local_headroom"|"$local_headroom"[[:space:]]*|"$physical_headroom"|"$physical_headroom"[[:space:]]*) busy=1; break ;;
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
      echo "A tool environment is still in use (PID $pid). Close its owning client or job before retrying; environment changes are blocked." >&2
      return 1
    fi
  done <<< "$snapshot"
  [ "$seen" -eq 1 ] || { echo "Empty process inspection; installation was not cleared to modify environments." >&2; return 1; }
)

kit_maintenance_run() {
  local candidate
  # Maintenance must also work when Headroom's third-party dependencies or
  # venv links are broken. Probe only the stdlib helper, never install Python
  # into an environment that is still in use.
  for candidate in \
    "$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python" \
    "$HOME/.universal-research-agent-kit/tooling/python-venv/bin/python" \
    "$(command -v python3 2>/dev/null || true)" \
    "$HOME/.universal-research-agent-kit/tooling/python"/cpython-*/bin/python3; do
    [ -x "$candidate" ] || continue
    if "$candidate" -I -B "$ROOT/headroom/maintenance.py" probe >/dev/null 2>&1; then
      "$candidate" -I -B "$ROOT/headroom/maintenance.py" "$@"
      return $?
    fi
  done
  echo "No runnable Python 3.8+ is available for safe Headroom shutdown. Close its clients/service and retry; no environment was replaced." >&2
  return 1
}

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
  KIT_WORK_DIR="$KIT_BACKUP_DIR/work"
  mkdir "$KIT_WORK_DIR"
}

# Installed runtimes and journaled backups outlive the disposable build/downloads.
kit_cleanup_work() {
  [ "$KIT_WORK_DIR" = "$KIT_BACKUP_DIR/work" ] && [ ! -L "$KIT_WORK_DIR" ] ||
    kit_die "Refusing to clean an unexpected installation workspace."
  rm -rf -- "$KIT_WORK_DIR"
  echo "Removed installation downloads, staging files and kit uv cache. Backups: $KIT_BACKUP_DIR"
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
    printf 'codex_version=%s\n' "${KIT_CODEX_VERSION:--}"
    printf 'claude_version=%s\n' "${KIT_CLAUDE_VERSION:--}"
    printf 'opencode_version=%s\n' "${KIT_OPENCODE_VERSION:--}"
    printf 'codex_source=%s\n' "${KIT_CODEX_SOURCE:--}"
    printf 'claude_source=%s\n' "${KIT_CLAUDE_SOURCE:--}"
    printf 'opencode_source=%s\n' "${KIT_OPENCODE_SOURCE:--}"
    printf 'opencode_archive_sha256=%s\n' "${KIT_OPENCODE_ARCHIVE_SHA256:--}"
    printf 'node_dir=%s\n' "${KIT_NODE_DIR:--}"
    printf 'humanizer_source=%s\n' "${HUMANIZER_SOURCE:--}"
    printf 'humanizer_revision=%s\n' "${HUMANIZER_REVISION:--}"
    printf 'humanizer_content_sha256=%s\n' "${HUMANIZER_CONTENT_SHA256:--}"
    printf 'humanizer_license=%s\n' "${HUMANIZER_LICENSE:--}"
    printf 'sequential_thinking_version=%s\n' "${SEQUENTIAL_THINKING_VERSION:--}"
    printf 'sequential_thinking_integrity=%s\n' "${SEQUENTIAL_THINKING_INTEGRITY:--}"
    printf 'btw_version=%s\n' "${KIT_BTW_VERSION:--}"
    printf 'btw_source=%s\n' "${KIT_BTW_SOURCE:--}"
    printf 'btw_archive_sha256=%s\n' "${KIT_BTW_ARCHIVE_SHA256:--}"
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
    if [ "${KIT_HEADROOM_ACTIVATION_STARTED:-0}" = 1 ] || [ "${TOOL_ROOT_PREPARED:-0}" = 1 ]; then
      if ! kit_maintenance_run quiesce "$KIT_BACKUP_DIR/rollback-maintenance.json"; then
        echo "Warning: Headroom service/MCP shutdown failed. Kept its environment and journal at $KIT_BACKUP_DIR for recovery." >&2
        kit_release_lock
        exit "$status"
      fi
    fi
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
      if [ -f "${KIT_MAINTENANCE_RECORD:-}" ] && ! kit_maintenance_run resume "$KIT_MAINTENANCE_RECORD"; then
        echo "Warning: files were restored, but Headroom could not resume. Recovery record: $KIT_MAINTENANCE_RECORD" >&2
      fi
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

kit_statusline_run() {
  local candidate action="$1"
  shift
  for candidate in \
    "${KIT_HEADROOM_PYTHON:-$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python}" \
    "$(command -v python3 2>/dev/null || true)"; do
    [ -x "$candidate" ] || continue
    if "$candidate" -I -B -c 'import tomllib' >/dev/null 2>&1; then
      "$candidate" -I -B "$ROOT/scripts/statusline.py" "$action" "$ROOT" "$@"
      return $?
    fi
  done
  echo "Statusline installation/verification requires Python 3.11+ (provided by the normal tooling installation)." >&2
  return 1
}

install_statusline() {
  command -v jq >/dev/null 2>&1 || kit_die "Claude statusline requires jq. Install jq (brew install jq or sudo apt install jq) and rerun --with-statusline."
  kit_require_real_dir "$HOME/.claude"
  kit_require_regular_or_absent "$HOME/.claude/settings.json"
  kit_require_regular_or_absent "$HOME/.claude/statusline.sh"
  # Prepare both merges before replacing either user configuration.
  kit_statusline_run prepare "$KIT_WORK_DIR" || kit_die "Statusline configuration merge failed."
  kit_backup_path "$HOME/.codex/config.toml" "statusline/codex-config.toml"
  kit_backup_path "$HOME/.claude/settings.json" "statusline/claude-settings.json"
  kit_backup_path "$HOME/.claude/statusline.sh" "statusline/statusline.sh"
  kit_require_regular_or_absent "$KIT_STATE_ROOT/statusline.state"
  kit_backup_path "$KIT_STATE_ROOT/statusline.state" "statusline/state"
  kit_replace_file "$KIT_WORK_DIR/statusline-codex.next" "$HOME/.codex/config.toml"
  kit_replace_file "$KIT_WORK_DIR/statusline-claude.next" "$HOME/.claude/settings.json"
  kit_replace_file "$ROOT/claude-code/statusline.sh" "$HOME/.claude/statusline.sh"
  chmod 755 "$HOME/.claude/statusline.sh"
  printf 'enabled=1\n' > "$KIT_WORK_DIR/statusline.state.next"
  kit_replace_file "$KIT_WORK_DIR/statusline.state.next" "$KIT_STATE_ROOT/statusline.state"
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
