#!/usr/bin/env bash
# Sourced by install.sh.

prepare_crucible() {
  local locator="$ROOT/skills/crucible/scripts/engine.py" source status target stage connection_file
  if source="$("$KIT_HEADROOM_PYTHON" -I -B "$locator" find)"; then
    printf 'Reusing Crucible: %s\n' "$source"
  else
    status=$?
    [ "$status" -eq 1 ] || kit_die "Crucible discovery failed; existing checkouts were preserved."
    target="$HOME/Crucible"
    [ ! -e "$target" ] && [ ! -L "$target" ] || kit_die "Crucible destination already exists: $target"
    stage="$KIT_WORK_DIR/crucible-source"
    git clone --depth 1 https://github.com/reo91004/Crucible.git "$stage" || kit_die "Crucible download failed."
    "$KIT_HEADROOM_PYTHON" -I -B "$locator" connect "$stage" "$KIT_WORK_DIR/crucible-stage.json" || kit_die "Downloaded Crucible is invalid."
    mkdir "$target" || kit_die "Crucible destination appeared during installation; preserved it."
    kit_journal_entry absent "$target"
    cp -Rp "$stage/." "$target/" || kit_die "Crucible installation failed."
    source="$target"
  fi
  connection_file="$KIT_STATE_ROOT/crucible.json"
  kit_require_regular_or_absent "$connection_file"
  kit_backup_path "$connection_file" "crucible/connection.json"
  "$KIT_HEADROOM_PYTHON" -I -B "$locator" connect "$source" "$KIT_WORK_DIR/crucible.next.json" || kit_die "Crucible connection failed."
  kit_replace_file "$KIT_WORK_DIR/crucible.next.json" "$connection_file"
}

prepare_shared_skills() {
  local source name
  KIT_SHARED_SKILLS="$KIT_WORK_DIR/shared-skills.next"
  kit_require_real_dir "$KIT_SHARED_SKILLS"
  for source in "$ROOT/skills"/*; do
    [ -d "$source" ] || continue
    [ -s "$source/SKILL.md" ] || kit_die "Missing source skill: $source"
    name="${source##*/}"
    kit_safe_name "$name"
    kit_replace_dir "$source" "$KIT_SHARED_SKILLS/$name"
  done
  if [ -n "${HUMANIZER_SKILL_SOURCE:-}" ]; then
    kit_replace_dir "$HUMANIZER_SKILL_SOURCE" "$KIT_SHARED_SKILLS/humanizer"
  fi
}

# Retire global user-skill paths while retaining CLI-managed builtins.
reset_legacy_skill_root() {
  local target="$1" preserve="${2:-}" label="$3" stage
  [ -e "$target" ] || [ -L "$target" ] || return 0
  stage="$KIT_WORK_DIR/$label.next"
  kit_require_real_dir "$stage"
  if [ -n "$preserve" ] && { [ -e "$target/$preserve" ] || [ -L "$target/$preserve" ]; }; then
    cp -Rp "$target/$preserve" "$stage/$preserve"
  fi
  kit_backup_path "$target" "$label"
  kit_replace_dir "$stage" "$target"
}

install_opencode_core() {
  local source name manifest block
  KIT_OPENCODE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  case "$KIT_OPENCODE_CONFIG_DIR" in /*) ;; *) kit_die "OpenCode config directory must be absolute" ;; esac
  kit_require_real_dir "$KIT_OPENCODE_CONFIG_DIR"
  kit_require_real_dir "$KIT_OPENCODE_CONFIG_DIR/agents"
  block="$KIT_WORK_DIR/opencode-agents.block"
  {
    printf '%s\n' '# BEGIN UNIVERSAL RESEARCH AGENT KIT'
    cat "$ROOT/opencode/AGENTS.md"
    printf '%s\n' '# END UNIVERSAL RESEARCH AGENT KIT'
  } > "$block"
  kit_replace_managed_block "$KIT_OPENCODE_CONFIG_DIR/AGENTS.md" "$block" "opencode/AGENTS.md" \
    '# BEGIN UNIVERSAL RESEARCH AGENT KIT' '# END UNIVERSAL RESEARCH AGENT KIT'
  kit_backup_path "$KIT_OPENCODE_CONFIG_DIR/agents" "opencode/agents"
  manifest="$KIT_WORK_DIR/opencode-agents.current"
  kit_create_empty_file "$manifest"
  for source in "$ROOT/opencode/agents"/*.md; do
    [ -f "$source" ] || continue
    printf '%s\n' "${source##*/}" >> "$manifest"
  done
  sort -o "$manifest" "$manifest"
  kit_prune_manifest "$KIT_OPENCODE_CONFIG_DIR/agents" "$KIT_MANIFEST_ROOT/opencode-agents" "$manifest"
  while IFS= read -r name; do
    kit_replace_file "$ROOT/opencode/agents/$name" "$KIT_OPENCODE_CONFIG_DIR/agents/$name"
  done < "$manifest"
  kit_commit_manifest "$manifest" "$KIT_MANIFEST_ROOT/opencode-agents"
  kit_require_real_dir "$KIT_OPENCODE_CONFIG_DIR/research-agent-kit"
  kit_backup_path "$KIT_OPENCODE_CONFIG_DIR/research-agent-kit/context" "opencode/context"
  kit_replace_dir "$ROOT/opencode/plugins/research-context" "$KIT_OPENCODE_CONFIG_DIR/research-agent-kit/context"
  reset_legacy_skill_root "$KIT_OPENCODE_CONFIG_DIR/skills" "" opencode-legacy-skills
  reset_legacy_skill_root "$HOME/.opencode/skills" "" opencode-v1-legacy-skills
}

kit_context_run() {
  local action="$1"
  shift
  "${KIT_HEADROOM_PYTHON:-$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python}" -I -B "$ROOT/scripts/context_defaults.py" "$action" \
    "$ROOT/codex/context.toml" "$HOME/.codex/config.toml" "$@"
}

opencode_config_run() {
  local action="$1"
  shift
  local args=(--config-dir "${KIT_OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}" \
    --state "$HOME/.universal-research-agent-kit/opencode-config.json" --templates "$ROOT/opencode" \
    --parser "$HOME/.universal-research-agent-kit/tooling/opencode-config/node_modules/jsonc-parser/lib/umd/main.js")
  [ -z "${KIT_HEADROOM_FRAGMENT:-}" ] || args+=(--extra-template "$KIT_HEADROOM_FRAGMENT")
  [ -z "${KIT_OPENCODE_CLI_FRAGMENT:-}" ] || args+=(--extra-cli-template "$KIT_OPENCODE_CLI_FRAGMENT")
  node "$ROOT/scripts/opencode_config.mjs" "$action" "${args[@]}" "$@"
}

prepare_btw_plugin() {
  local metadata="$KIT_WORK_DIR/btw-latest.json" archive="$KIT_WORK_DIR/btw-upstream.tgz" url source stage
  KIT_BTW_SOURCE=https://registry.npmjs.org/opencode-btw-plus/latest
  download_file "$KIT_BTW_SOURCE" "$metadata"
  KIT_BTW_VERSION="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));if(d.name!=="opencode-btw-plus"||!/^\d+\.\d+\.\d+$/.test(d.version)||!/^sha512-[A-Za-z0-9+/]+={0,2}$/.test(d.dist?.integrity||""))process.exit(1);console.log(d.version)' "$metadata")" || kit_die "Invalid BTW Plus release metadata."
  url="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")),u=new URL(d.dist.tarball);if(u.protocol!=="https:"||u.hostname!=="registry.npmjs.org")process.exit(1);console.log(u.href)' "$metadata")" || kit_die "Invalid BTW Plus package source."
  download_file "$url" "$archive"
  KIT_BTW_ARCHIVE_SHA256="$(node -e 'const fs=require("fs"),c=require("crypto"),m=JSON.parse(fs.readFileSync(process.argv[1],"utf8")),b=fs.readFileSync(process.argv[2]);if("sha512-"+c.createHash("sha512").update(b).digest("base64")!==m.dist.integrity)process.exit(1);console.log(c.createHash("sha256").update(b).digest("hex"))' "$metadata" "$archive")" || kit_die "BTW Plus archive integrity mismatch."
  source="$(mktemp -d "$KIT_WORK_DIR/btw-source.XXXXXX")"
  stage="$(mktemp -d "$KIT_WORK_DIR/btw-compatible.XXXXXX")"
  tar -xzf "$archive" -C "$source"
  node "$ROOT/opencode/plugins/btw-plus-compat/patch.mjs" "$source/package" "$stage" "$KIT_OPENCODE_VERSION" ||
    kit_die "This latest BTW Plus/OpenCode pair has not passed the bounded compatibility check."
  npm ci --prefix "$stage" --ignore-scripts --no-audit --no-fund || kit_die "BTW Plus compatibility dependencies failed."
  node "$ROOT/opencode/plugins/btw-plus-compat/patch.mjs" --check "$stage" "$KIT_OPENCODE_VERSION" || kit_die "BTW Plus staged package verification failed."
  KIT_BTW_DIRECTORY="$KIT_STATE_ROOT/tooling/opencode-btw-plus"
  kit_backup_path "$KIT_BTW_DIRECTORY" "opencode/btw-plugin"
  kit_replace_dir "$stage" "$KIT_BTW_DIRECTORY"
  KIT_OPENCODE_CLI_FRAGMENT="$KIT_WORK_DIR/opencode-cli-plugins.json"
  node -e 'require("fs").writeFileSync(process.argv[1],JSON.stringify({plugins:["-opencode.btw",process.argv[2]]})+"\n")' \
    "$KIT_OPENCODE_CLI_FRAGMENT" "$KIT_BTW_DIRECTORY"
}

prepare_opencode_fragments() {
  local output="$1" npx="${KIT_NPX:-$KIT_STATE_ROOT/cli/bin/kit-npx}"
  KIT_HEADROOM_FRAGMENT="$output/opencode-headroom.json"
  "${KIT_HEADROOM_PYTHON:-$HOME/.universal-research-agent-kit/tooling/uv-tools/headroom-ai/bin/python}" -I -B "$ROOT/headroom/runtime.py" opencode-config > "$KIT_HEADROOM_FRAGMENT" ||
    kit_die "Cannot prepare the official Headroom OpenCode integration."
  node -e 'const fs=require("fs"),f=process.argv[1],d=JSON.parse(fs.readFileSync(f,"utf8"));d.mcp.servers["sequential-thinking"]={type:"local",command:[process.argv[2],"-y",process.argv[3]],environment:{}};fs.writeFileSync(f,JSON.stringify(d)+"\n")' \
    "$KIT_HEADROOM_FRAGMENT" "$npx" "$SEQUENTIAL_THINKING_PACKAGE"
  KIT_OPENCODE_CLI_FRAGMENT="$output/opencode-cli-plugins.json"
  node -e 'require("fs").writeFileSync(process.argv[1],JSON.stringify({plugins:["-opencode.btw",process.argv[2]]})+"\n")' "$KIT_OPENCODE_CLI_FRAGMENT" "$KIT_STATE_ROOT/tooling/opencode-btw-plus"
}

install_opencode_configuration() {
  local dependencies="$KIT_STATE_ROOT/tooling/opencode-config" target name
  kit_backup_path "$dependencies" "opencode/dependencies"
  kit_require_real_dir "$dependencies"
  cp "$ROOT/scripts/opencode-config/package.json" "$ROOT/scripts/opencode-config/package-lock.json" "$dependencies/"
  npm ci --prefix "$dependencies" --ignore-scripts --no-audit --no-fund || kit_die "OpenCode configuration dependencies failed."
  prepare_btw_plugin
  prepare_opencode_fragments "$KIT_WORK_DIR"
  opencode_config_run prepare --output-dir "$KIT_WORK_DIR" > "$KIT_WORK_DIR/opencode-prepare.json" ||
    kit_die "OpenCode JSONC preparation failed."
  for name in cli server state; do
    case "$name" in
      cli) target="$KIT_OPENCODE_CONFIG_DIR/cli.json" ;;
      server) target="$KIT_OPENCODE_CONFIG_DIR/opencode.jsonc" ;;
      state) target="$KIT_STATE_ROOT/opencode-config.json" ;;
    esac
    kit_require_regular_or_absent "$target"
    kit_backup_path "$target" "opencode/config-$name"
    kit_replace_file "$KIT_WORK_DIR/opencode-$name.next" "$target"
  done
  opencode_config_run check > "$KIT_WORK_DIR/opencode-check.json" || kit_die "OpenCode configuration verification failed."
  node "$ROOT/scripts/opencode_config.mjs" effective --config-dir "$KIT_OPENCODE_CONFIG_DIR" \
    --parser "$dependencies/node_modules/jsonc-parser/lib/umd/main.js" |
    "$KIT_HEADROOM_PYTHON" -I -B "$ROOT/headroom/runtime.py" check-opencode-config ||
    kit_die "OpenCode Headroom configuration is not effective."
}

install_core() {
  local platform source_dir target prompt destination suffix group source name manifest
  kit_require_real_dir "$HOME/.codex"
  kit_require_real_dir "$HOME/.agents"
  prepare_shared_skills
# Keep the user config intact except for this feature; unsupported TOML forms
# fail before replacement instead of risking a duplicate or misplaced key.
config="$HOME/.codex/config.toml"
kit_require_regular_or_absent "$config"
config_input="$config"
[ -f "$config_input" ] || config_input=/dev/null
config_next="$KIT_WORK_DIR/codex-config.next"
if [ -f "$config" ]; then
  cp -p "$config" "$config_next"
else
  (umask 077; : > "$config_next")
fi
if [ "${UNIVERSAL_RESEARCH_AGENT_KIT_SKIP_TOOLING:-0}" != 1 ]; then
  kit_context_run prepare "$config_next" || kit_die "Cannot safely apply Codex context defaults."
else
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
    kit_backup_path "$target/$prompt" "$platform/$prompt"
    kit_backup_path "$target/agents" "$platform/agents"
    kit_backup_path "$destination" "$platform/skills"
    kit_replace_file "$source_dir/$prompt" "$target/$prompt"
    for group in agents skills; do
      manifest="$KIT_WORK_DIR/$platform-$group.current"
      kit_create_empty_file "$manifest"
      if [ "$group" = agents ]; then
        for source in "$source_dir/agents"/*"$suffix"; do
          [ -f "$source" ] || continue
          printf '%s\n' "${source##*/}" >> "$manifest"
        done
      else
        for source in "$KIT_SHARED_SKILLS"/*; do
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
        kit_replace_dir "$KIT_SHARED_SKILLS" "$destination"
      fi
      kit_commit_manifest "$manifest" "$KIT_MANIFEST_ROOT/$platform-$group"
    done
  done
  reset_legacy_skill_root "$HOME/.codex/skills" .system codex-legacy-user-skills
  install_opencode_core
}
