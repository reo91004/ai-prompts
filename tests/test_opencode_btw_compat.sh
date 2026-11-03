#!/usr/bin/env bash
set -euo pipefail

: "${BTWP_BUN:?Set the path to the isolated Bun 1.4.4 binary}"
: "${BTWP_SOURCE:?Set the isolated upstream source checkout path}"
: "${BTWP_PACKAGE:?Set the prepared compatibility package path}"
: "${BTWP_EVIDENCE_DIR:?Set the test evidence output directory}"

[ "$("$BTWP_BUN" --version)" = 1.4.4 ] || { echo "Expected Bun 1.4.4" >&2; exit 1; }
[ "$(git -C "$BTWP_SOURCE" rev-parse HEAD)" = 872e7df67b8476ebc44626fd7b79178d854c3c41 ] || {
  echo "Expected the upstream source commit for opencode-btw-plus 0.1.3" >&2; exit 1;
}
[ -f "$BTWP_PACKAGE/dist/tui.js" ] || { echo "Missing prepared TUI bundle" >&2; exit 1; }
mkdir -p "$BTWP_EVIDENCE_DIR"
task_directory="$(mktemp -d "$BTWP_SOURCE/.research-kit-btw.XXXXXX")"
trap 'rm -rf -- "$task_directory"' EXIT

cat > "$task_directory/preload.ts" <<'PRELOAD'
import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { ensurePluginRuntime, provides } from "@opencode/plugin/runtime"
import { Plugin, PluginContextProvider, usePlugin } from "@opencode/plugin/tui"
import { ensureRuntimePluginSupport } from "@opentui/solid/runtime-plugin-support/configure"
for (const [name, expected] of [["@opencode/plugin", "2.2.5"], ["@opentui/core", "0.8.0"], ["@opentui/solid", "0.8.0"], ["solid-js", "1.9.17"]]) {
  const actual = JSON.parse(readFileSync(resolve(import.meta.dir, "../node_modules", name, "package.json"), "utf8")).version
  if (actual !== expected) throw new Error(`Expected ${name}@${expected}, found ${actual}`)
}
ensurePluginRuntime()
ensureRuntimePluginSupport({ additional: { "@opencode/plugin/tui": { Plugin, PluginContextProvider, usePlugin } }, preserve: provides })
PRELOAD

set +e
(
  cd "$BTWP_SOURCE"
  XDG_CONFIG_HOME="$task_directory/config" \
  XDG_DATA_HOME="$task_directory/data" \
  XDG_CACHE_HOME="$task_directory/cache" \
  OPENCODE_BTW_TEST_ENTRYPOINT="$BTWP_PACKAGE/dist/tui.js" \
    "$BTWP_BUN" test --conditions=browser --preload "$task_directory/preload.ts" \
      --preload @opentui/solid/preload test/plugin.test.tsx --timeout 30000
) > "$BTWP_EVIDENCE_DIR/btw-ui.log" 2>&1
status=$?
set -e
printf '%s\n' "$status" > "$BTWP_EVIDENCE_DIR/exit-code"
tail -n 5 "$BTWP_EVIDENCE_DIR/btw-ui.log"
exit "$status"
