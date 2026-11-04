#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
source "$ROOT/install.sh"
source "$ROOT/scripts/humanizer.sh"
KIT_STATE_ROOT="$WORK/state"
KIT_BACKUP_DIR="$WORK/backups"
KIT_WORK_DIR="$KIT_BACKUP_DIR/work"
mkdir -p "$KIT_WORK_DIR"
KIT_JOURNAL="$KIT_BACKUP_DIR/journal.tsv"
mkdir -p "$KIT_STATE_ROOT" "$KIT_BACKUP_DIR"
REAL_GIT="$(command -v git)"
git() {
  printf '%s\n' "$*" >> "$WORK/git-calls.log"
  "$REAL_GIT" "$@"
}
fixture="$WORK/upstream"
git -c init.defaultBranch=main init --quiet "$fixture"
mkdir -p "$fixture/references" "$fixture/scripts"
cat > "$fixture/SKILL.md" <<'SKILL'
---
name: humanizer
description: Rewrite prose while preserving its meaning.
license: MIT
---
Use references/rules.md and scripts/check.sh when relevant.
SKILL
cat > "$fixture/LICENSE" <<'LICENSE'
MIT License

Copyright (c) 2026 Test Fixture

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
SOFTWARE.
LICENSE
printf '%s\n' 'Preserve numbers and citations.' > "$fixture/references/rules.md"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$fixture/scripts/check.sh"
chmod +x "$fixture/scripts/check.sh"
commit_fixture() {
  git -C "$fixture" add .
  git -C "$fixture" -c user.name=Fixture -c user.email=fixture@example.invalid \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null commit --quiet -m "$1"
}
commit_fixture first
if (prepare_humanizer --fixture-repository "$fixture") > "$WORK/override.log" 2>&1; then exit 1; fi
grep -Fq 'only available to explicit local fixtures' "$WORK/override.log"
[ ! -e "$KIT_STATE_ROOT/sources" ]
KIT_TEST_FIXTURES_ONLY=1
prepare_humanizer --fixture-repository "$fixture"
first_revision="$HUMANIZER_REVISION"
first_hash="$HUMANIZER_CONTENT_SHA256"
[ "$first_revision" = "$(git -C "$fixture" rev-parse HEAD)" ]
verify_humanizer_source "$first_revision" "$first_hash" "$fixture"
cmp "$fixture/LICENSE" "$HUMANIZER_SKILL_SOURCE/LICENSE"
cmp "$fixture/references/rules.md" "$HUMANIZER_SKILL_SOURCE/references/rules.md"
[ -x "$HUMANIZER_SKILL_SOURCE/scripts/check.sh" ]
[ ! -e "$HUMANIZER_SKILL_SOURCE/.git" ]
grep -Fq "fetch --quiet --depth=1 --no-tags $fixture $first_revision" "$WORK/git-calls.log"

printf '%s\n' 'Preserve numbers, citations, and uncertainty.' > "$fixture/references/rules.md"
commit_fixture second
prepare_humanizer --fixture-repository "$fixture"
[ "$HUMANIZER_REVISION" = "$first_revision" ]
[ "$(grep -c '^ls-remote ' "$WORK/git-calls.log")" -eq 1 ]
HUMANIZER_PREPARED=0
prepare_humanizer --fixture-repository "$fixture"
second_revision="$HUMANIZER_REVISION"
second_hash="$HUMANIZER_CONTENT_SHA256"
[ "$second_revision" != "$first_revision" ] && [ "$second_hash" != "$first_hash" ]
verify_humanizer_source "$second_revision" "$second_hash" "$fixture"
node - "$KIT_STATE_ROOT/sources/humanizer/source.json" "$fixture" "$second_revision" "$second_hash" <<'NODE'
const assert = require('assert'), fs = require('fs'), [file, source, revision, hash] = process.argv.slice(2);
assert.deepStrictEqual(JSON.parse(fs.readFileSync(file, 'utf8')), {source, revision, content_sha256: hash, license: 'MIT'});
NODE
cp -Rp "$HUMANIZER_SKILL_SOURCE" "$WORK/installed"
verify_humanizer_skill "$WORK/installed" "$second_hash"
printf '\nChanged after installation.\n' >> "$WORK/installed/SKILL.md"
if verify_humanizer_skill "$WORK/installed" "$second_hash"; then exit 1; fi
if verify_humanizer_source "$first_revision" "$second_hash" "$fixture"; then exit 1; fi

# Cached content is revalidated; the next install repairs it from the pinned commit.
printf '\nChanged cache.\n' >> "$HUMANIZER_SKILL_SOURCE/SKILL.md"
if verify_humanizer_source "$second_revision" "$second_hash" "$fixture"; then exit 1; fi
HUMANIZER_PREPARED=0
prepare_humanizer --fixture-repository "$fixture"
verify_humanizer_source "$second_revision" "$second_hash" "$fixture"

cp "$fixture/SKILL.md" "$WORK/good-skill"
printf '%s\n' '---' 'name: another-skill' '---' 'Wrong bundle.' > "$fixture/SKILL.md"
commit_fixture wrong-name
if (HUMANIZER_PREPARED=0 prepare_humanizer --fixture-repository "$fixture") > "$WORK/name.log" 2>&1; then exit 1; fi
grep -Fq 'must declare name: humanizer' "$WORK/name.log"
verify_humanizer_source "$second_revision" "$second_hash" "$fixture"
cp "$WORK/good-skill" "$fixture/SKILL.md"
printf '%s\n' 'MIT License' 'Additional restrictions apply.' > "$fixture/LICENSE"
commit_fixture wrong-license
if (HUMANIZER_PREPARED=0 prepare_humanizer --fixture-repository "$fixture") > "$WORK/license.log" 2>&1; then exit 1; fi
grep -Fq 'must retain the MIT LICENSE' "$WORK/license.log"
verify_humanizer_source "$second_revision" "$second_hash" "$fixture"
cp "$HUMANIZER_SKILL_SOURCE/LICENSE" "$fixture/LICENSE"
ln -s "$WORK/installed" "$fixture/external"
commit_fixture external-link
if (HUMANIZER_PREPARED=0 prepare_humanizer --fixture-repository "$fixture") > "$WORK/link.log" 2>&1; then exit 1; fi
grep -Fq 'contains a symlink or submodule' "$WORK/link.log"
verify_humanizer_source "$second_revision" "$second_hash" "$fixture"
kit_rollback_run
[ ! -e "$KIT_STATE_ROOT/sources/humanizer" ]
echo 'Humanizer preparation, update, provenance, rejection, and rollback tests passed.'
