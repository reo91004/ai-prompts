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
  KIT_STATE_ROOT="$HOME/.universal-research-agent-kit"
  KIT_BACKUP_ROOT="$KIT_STATE_ROOT/backups"
  KIT_MANIFEST_ROOT="$KIT_STATE_ROOT/manifests"

  kit_require_real_dir "$KIT_STATE_ROOT"
  kit_require_real_dir "$KIT_BACKUP_ROOT"
  kit_require_real_dir "$KIT_MANIFEST_ROOT"

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
  else
    KIT_BACKUP_DIR="$(mktemp -d "$KIT_BACKUP_ROOT/run.$(date +%Y%m%d_%H%M%S).XXXXXX")"
  fi

  export KIT_STATE_ROOT KIT_BACKUP_ROOT KIT_MANIFEST_ROOT KIT_BACKUP_DIR
}

kit_backup_path() {
  local source="$1"
  local relative="$2"
  local destination="$KIT_BACKUP_DIR/$relative"

  if [ ! -e "$source" ] && [ ! -L "$source" ]; then
    return
  fi

  kit_require_real_dir "$(dirname "$destination")"
  if [ -e "$destination" ] || [ -L "$destination" ]; then
    kit_die "Backup destination already exists: $destination"
  fi
  if [ -L "$source" ]; then
    cp -P "$source" "$destination"
  elif [ -f "$source" ]; then
    cp -p "$source" "$destination"
  elif [ -d "$source" ]; then
    cp -Rp "$source" "$destination"
  else
    kit_die "Unsupported managed path type: $source"
  fi
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
