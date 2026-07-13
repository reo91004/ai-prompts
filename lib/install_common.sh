#!/usr/bin/env bash

kit_die() {
  echo "Error: $*" >&2
  exit 1
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
  if [ "${KIT_LOCK_HELD:-0}" = "1" ]; then
    KIT_LOCK_OWNED=0
  elif mkdir "$KIT_LOCK_DIR" 2>/dev/null; then
    KIT_LOCK_OWNED=1
    export KIT_LOCK_HELD=1
  else
    kit_die "Another kit install appears to be running (lock: $KIT_LOCK_DIR). Remove the lock directory only after confirming no installer is active."
  fi

  if [ -n "${KIT_BACKUP_DIR:-}" ]; then
    if [ "$(dirname "$KIT_BACKUP_DIR")" != "$KIT_BACKUP_ROOT" ]; then
      kit_die "Invalid shared backup directory: $KIT_BACKUP_DIR"
    fi
    case "$(basename "$KIT_BACKUP_DIR")" in
      run.*) ;;
      *) kit_die "Invalid shared backup directory name: $KIT_BACKUP_DIR" ;;
    esac
    [ -d "$KIT_BACKUP_DIR" ] && [ ! -L "$KIT_BACKUP_DIR" ] ||
      kit_die "Shared backup directory is unavailable: $KIT_BACKUP_DIR"
    KIT_RUN_OWNER=0
  else
    KIT_BACKUP_DIR="$(mktemp -d "$KIT_BACKUP_ROOT/run.$(date +%Y%m%d_%H%M%S).XXXXXX")"
    KIT_RUN_OWNER=1
  fi
  KIT_JOURNAL="$KIT_BACKUP_DIR/journal.tsv"

  export KIT_STATE_ROOT KIT_BACKUP_ROOT KIT_MANIFEST_ROOT KIT_BACKUP_DIR KIT_JOURNAL
}

# Per-host integration outcomes; the verifier trusts these states instead of
# assuming one global profile matches every host.
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

kit_release_lock() {
  if [ "${KIT_LOCK_OWNED:-0}" = "1" ]; then
    rmdir "$KIT_LOCK_DIR" 2>/dev/null || true
    KIT_LOCK_OWNED=0
    export KIT_LOCK_HELD=0
  fi
}

kit_journal_entry() {
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$KIT_JOURNAL"
}

# The run owner rolls back every journaled change on any failure or signal so
# a partial install never leaves the home configuration half-replaced.
kit_enable_rollback() {
  [ "${KIT_RUN_OWNER:-0}" = "1" ] || return 0
  trap 'kit_handle_exit $?' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

kit_handle_exit() {
  local status="$1"
  trap - EXIT
  if [ "$status" -ne 0 ]; then
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
  # Newest-first replay so later changes are undone before earlier ones.
  while IFS="$tab" read -r action source destination; do
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
