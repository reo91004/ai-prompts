# BTW Plus compatibility patch

The official `opencode-btw-plus@0.1.3` package uses `@opencode/theme@2.0.11` and calls `generateSyntax(theme)` without a resource owner. OpenTUI 0.8, used by OpenCode 2.2.5, requires a renderer-owned syntax style. The original package can load but fails when displaying stored answers.

`patch.mjs` accepts only the verified upstream version and bundle SHA256, applies one call-site change to pass `context.renderer.nativeScene`, and creates a local TUI package using `@opencode/theme@2.2.5`. It copies the upstream MIT license, a dependency lockfile, and source/hash/host provenance to `UPSTREAM.json`. Run `npm ci --ignore-scripts --no-audit --no-fund --prefix /path/to/staging` before registering the local package. It does not declare the old OpenTUI peer dependencies.

```sh
node patch.mjs /path/to/verified/upstream/package /path/to/empty/staging 2.2.5
```

Register the generated local directory in `cli.json` after `-opencode.btw`. Do not register the upstream package and patched package together. Keep its plugin ID `btw-plus` and OpenCode's plugin storage location stable during updates: history belongs to the TUI storage service and is not part of this configuration or skill directory. The patch does not import old built-in `/btw` exchanges.

Unknown upstream bundles and untested host versions fail before staging. A new release needs its own compatibility evidence rather than a blind textual patch.

The tested combination is Bun 1.4.4, OpenCode plugin SDK 2.2.5, OpenTUI 0.8.0, Solid 1.9.17, and the actual patched npm bundle. With the OpenCode 2.2.5 runtime-module initialization, the upstream `test/plugin.test.tsx` suite passed 18 tests and 955 assertions, including saved-answer reopening, session isolation, search, concurrent questions, errors, focus, scrolling, and resizing. `session.generate` and storage use the upstream controlled fixture; this is not a real model call or full OpenCode application test.

`tests/test_opencode_btw_patch.mjs` checks the prepared package against an extracted verified upstream package. `tests/test_opencode_btw_compat.sh` runs the packaged UI tests using explicit `BTWP_BUN`, `BTWP_SOURCE`, `BTWP_PACKAGE`, and `BTWP_EVIDENCE_DIR` paths. It requires the upstream source at the recorded commit, with test dependencies matching the host versions above, and keeps test configuration/data/cache outside the real home configuration.

Sources:

- [Upstream source at the packaged commit](https://github.com/Tarquinen/opencode-btw-plus/tree/872e7df67b8476ebc44626fd7b79178d854c3c41)
- [OpenCode 2.2.5 theme helper](https://github.com/anomalyco/opencode/blob/v2.2.5/packages/theme/src/tui/syntax.ts)
- [OpenCode 2.2.5 runtime-module setup](https://github.com/anomalyco/opencode/blob/v2.2.5/packages/tui/src/plugin/runtime-plugin-support.bun.ts)
