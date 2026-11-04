#!/usr/bin/env bash
# Sourced by install.sh after its lock, journal, and Node runtime are ready.

humanizer_content_hash() {
  node - "$1" <<'NODE'
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const root = process.argv[2];
const fail = message => { console.error(message); process.exit(1); };
if (!fs.lstatSync(root).isDirectory()) fail('Humanizer bundle must be a regular directory.');
for (const name of ['SKILL.md', 'LICENSE']) {
  if (!fs.lstatSync(path.join(root, name)).isFile()) fail(`Humanizer ${name} must be a regular file.`);
}
const skill = fs.readFileSync(path.join(root, 'SKILL.md'), 'utf8');
const header = skill.match(/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/);
if (!header) fail('Humanizer SKILL.md has no YAML frontmatter.');
const names = header[1].split(/\r?\n/).filter(line => /^name:/.test(line));
if (names.length !== 1 || !/^name:\s*(?:humanizer|"humanizer"|'humanizer')\s*$/.test(names[0])) {
  fail('Humanizer SKILL.md must declare name: humanizer.');
}
const mit = `MIT License
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.`;
const normalize = value => value.replace(/\s+/g, ' ').trim();
const license = fs.readFileSync(path.join(root, 'LICENSE'), 'utf8')
  .split(/\r?\n/).filter(line => !/^Copyright\b/i.test(line)).join('\n');
if (normalize(license) !== normalize(mit)) fail('Humanizer must retain the MIT LICENSE.');
const hash = crypto.createHash('sha256');
function walk(relative) {
  for (const name of fs.readdirSync(path.join(root, relative)).sort()) {
    if (name === '.git') fail('Humanizer skill bundle must not contain .git.');
    const child = path.join(relative, name), full = path.join(root, child), stat = fs.lstatSync(full);
    if (stat.isDirectory()) {
      hash.update(`D\0${child}\0`);
      walk(child);
    } else if (stat.isFile()) {
      const data = fs.readFileSync(full);
      hash.update(`F\0${child}\0${stat.mode & 0o111 ? '755' : '644'}\0${data.length}\0`);
      hash.update(data);
    } else fail(`Unsupported Humanizer bundle entry: ${child}`);
  }
}
walk('');
console.log(hash.digest('hex'));
NODE
}

humanizer_record_hash() {
  node - "$1" "$2" "$3" <<'NODE'
const fs = require('fs');
const [file, source, revision] = process.argv.slice(2), record = JSON.parse(fs.readFileSync(file, 'utf8'));
if (record.source !== source || record.revision !== revision || !/^[0-9a-f]{40}$/.test(revision) || record.license !== 'MIT' ||
    !/^[0-9a-f]{64}$/.test(record.content_sha256)) process.exit(1);
console.log(record.content_sha256);
NODE
}

verify_humanizer_skill() {
  local actual
  actual="$(humanizer_content_hash "$1")" || return 1
  [ "$actual" = "$2" ]
}

verify_humanizer_source() {
  local revision="$1" expected="$2" source="${3:-https://github.com/blader/humanizer.git}" recorded
  local cache="$KIT_STATE_ROOT/sources/humanizer"
  [ ! -L "$KIT_STATE_ROOT/sources" ] && [ ! -L "$cache" ] || return 1
  if [ "$source" != https://github.com/blader/humanizer.git ]; then
    [ "${KIT_TEST_FIXTURES_ONLY:-0}" = 1 ] && [ -d "$source/.git" ] || return 1
  fi
  recorded="$(humanizer_record_hash "$cache/source.json" "$source" "$revision")" || return 1
  [ "$recorded" = "$expected" ] && verify_humanizer_skill "$cache/skill" "$expected"
}

prepare_humanizer() {
  local remote=https://github.com/blader/humanizer.git revision cached_hash stage checkout prepared
  local cache="$KIT_STATE_ROOT/sources/humanizer"
  if [ "$#" -ne 0 ]; then
    [ "$#" -eq 2 ] && [ "$1" = --fixture-repository ] && [ "${KIT_TEST_FIXTURES_ONLY:-0}" = 1 ] ||
      kit_die "Humanizer source overrides are only available to explicit local fixtures."
    case "$2" in /*) ;; *) kit_die "Humanizer fixture repository must be an absolute local path." ;; esac
    [ -d "$2/.git" ] || kit_die "Humanizer fixture repository is not a local Git checkout."
    remote="$2"
  fi
  if [ "${HUMANIZER_PREPARED:-0}" = 1 ]; then
    [ "$remote" = "$HUMANIZER_SOURCE" ] &&
      verify_humanizer_source "$HUMANIZER_REVISION" "$HUMANIZER_CONTENT_SHA256" "$remote" ||
      kit_die "Prepared Humanizer source changed during this install."
    return 0
  fi
  revision="$(git ls-remote --exit-code "$remote" HEAD | awk '$2 == "HEAD" {print $1}')" ||
    kit_die "Could not resolve the Humanizer repository HEAD."
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || kit_die "Invalid Humanizer HEAD revision."
  HUMANIZER_SOURCE="$remote"
  HUMANIZER_REVISION="$revision"
  HUMANIZER_LICENSE=MIT
  HUMANIZER_SKILL_SOURCE="$cache/skill"
  if cached_hash="$(humanizer_record_hash "$cache/source.json" "$remote" "$revision" 2>/dev/null)" &&
      verify_humanizer_source "$revision" "$cached_hash" "$remote" 2>/dev/null; then
    HUMANIZER_CONTENT_SHA256="$cached_hash"
    HUMANIZER_PREPARED=1
    return 0
  fi
  stage="$(mktemp -d "$KIT_WORK_DIR/humanizer.XXXXXX")" || kit_die "Could not create the Humanizer staging directory."
  checkout="$stage/repository"
  prepared="$stage/prepared"
  mkdir -p "$prepared/skill" || kit_die "Could not create the Humanizer bundle directory."
  git init --bare --quiet "$checkout" || kit_die "Could not prepare the Humanizer fetch directory."
  git -C "$checkout" fetch --quiet --depth=1 --no-tags "$remote" "$revision" ||
    kit_die "Could not fetch Humanizer revision $revision."
  [ "$(git -C "$checkout" rev-parse FETCH_HEAD)" = "$revision" ] || kit_die "Humanizer fetch returned another revision."
  git -C "$checkout" ls-tree -r "$revision" | awk '$1 != "100644" && $1 != "100755" {bad=1} END {exit bad}' ||
    kit_die "Humanizer source contains a symlink or submodule; its complete bundle was not installed."
  git -C "$checkout" archive --format=tar "$revision" > "$stage/source.tar" || kit_die "Could not archive the Humanizer revision."
  tar -xf "$stage/source.tar" -C "$prepared/skill" || kit_die "Could not extract the complete Humanizer bundle."
  HUMANIZER_CONTENT_SHA256="$(humanizer_content_hash "$prepared/skill")" || kit_die "Humanizer source validation failed."
  node - "$prepared/source.json" "$remote" "$revision" "$HUMANIZER_CONTENT_SHA256" <<'NODE' || kit_die "Could not record Humanizer provenance."
const fs = require('fs'), [file, source, revision, content_sha256] = process.argv.slice(2);
fs.writeFileSync(file, JSON.stringify({source, revision, content_sha256, license: 'MIT'}, null, 2) + '\n');
NODE
  kit_require_real_dir "$KIT_STATE_ROOT/sources"
  [ ! -L "$cache" ] || kit_die "Refusing a symlinked Humanizer source cache."
  KIT_HUMANIZER_BACKUP_INDEX=$((${KIT_HUMANIZER_BACKUP_INDEX:-0} + 1))
  kit_backup_path "$cache" "humanizer/source-$KIT_HUMANIZER_BACKUP_INDEX"
  kit_replace_dir "$prepared" "$cache"
  verify_humanizer_source "$revision" "$HUMANIZER_CONTENT_SHA256" "$remote" || kit_die "Prepared Humanizer source verification failed."
  HUMANIZER_PREPARED=1
}
