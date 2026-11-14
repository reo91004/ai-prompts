# BTW Plus compatibility patch

The official `opencode-btw-plus@0.1.3` package uses `@opencode/theme@2.0.11` and calls `generateSyntax(theme)` without a resource owner. OpenTUI 0.8, used by OpenCode 2.2.5 and 2.2.7, requires a renderer-owned syntax style. The original package can load but fails when displaying stored answers.

`patch.mjs` accepts the upstream version below, applies one call-site change to pass `context.renderer.nativeScene` (refusing if that call does not occur exactly once), and creates a local TUI package using the theme version and dependency lockfile for the selected host below. It copies the upstream MIT license and records the source and host versions in `UPSTREAM.json`. Run `npm ci --ignore-scripts --no-audit --no-fund --prefix /path/to/staging` before registering the local package. It does not declare the old OpenTUI peer dependencies.

```sh
node patch.mjs /path/to/verified/upstream/package /path/to/empty/staging 2.2.7
```

Register the generated local directory in `cli.json` after `-opencode.btw`. Do not register the upstream package and patched package together. Keep its plugin ID `btw-plus` and OpenCode's plugin storage location stable during updates: history belongs to the TUI storage service and is not part of this configuration or skill directory. The patch does not import old built-in `/btw` exchanges.

For an OpenCode version not in the table, the installer prints a warning, skips BTW Plus, and continues; add a row with its lockfile to support it.

Both combinations below were tested on Linux x86_64 with Bun 1.4.4, Solid 1.9.17, the actual patched npm bundle, and the host's runtime-module initialization. On 2026-11-13, the upstream `test/plugin.test.tsx` suite passed 18 tests and 955 assertions for each combination, including saved-answer reopening, session isolation, search, concurrent questions, errors, focus, scrolling, and resizing. `session.generate` and storage use the upstream controlled fixture; this is not a real model call or full OpenCode application test.

| OpenCode plugin SDK / theme | OpenTUI core / solid / keymap | Effect | Runtime lockfile |
| --- | --- | --- | --- |
| 2.2.5 | 0.8.0 | 4.0.6 | `runtime-package-lock.json` |
| 2.2.7 | 0.8.1 | 4.1.0 | `runtime-2.2.7-package-lock.json` |

`tests/test_opencode_btw_patch.mjs` checks both host versions against an extracted verified upstream package. `tests/test_opencode_btw_compat.sh` runs the packaged UI tests using explicit `BTWP_BUN`, `BTWP_SOURCE`, `BTWP_PACKAGE`, and `BTWP_EVIDENCE_DIR` paths. Set `BTWP_OPENCODE_VERSION=2.2.7` for the newer host; the default is 2.2.5. It verifies the prepared package and requires the upstream source at the recorded commit, with test dependencies matching the host versions above, and keeps test configuration/data/cache outside the real home configuration.

Sources:

- [Upstream source at the packaged commit](https://github.com/Tarquinen/opencode-btw-plus/tree/872e7df67b8476ebc44626fd7b79178d854c3c41)
- [OpenCode 2.2.5 theme helper](https://github.com/anomalyco/opencode/blob/v2.2.5/packages/theme/src/tui/syntax.ts)
- [OpenCode 2.2.5 runtime-module setup](https://github.com/anomalyco/opencode/blob/v2.2.5/packages/tui/src/plugin/runtime-plugin-support.bun.ts)
- [OpenCode 2.2.7 host dependency versions](https://github.com/anomalyco/opencode/blob/v2.2.7/package.json)
- [OpenCode 2.2.7 runtime-module setup](https://github.com/anomalyco/opencode/blob/v2.2.7/packages/tui/src/plugin/runtime-plugin-support.bun.ts)
