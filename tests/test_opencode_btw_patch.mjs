import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, cpSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createHash } from "node:crypto";
import { prepare, verifyInstalled, UPSTREAM } from "../opencode/plugins/btw-plus-compat/patch.mjs";

if (!process.argv[2]) throw new Error("Usage: node tests/test_opencode_btw_patch.mjs VERIFIED_UPSTREAM_PACKAGE_DIRECTORY");
const source = resolve(process.argv[2]);
const directory = mkdtempSync(join(tmpdir(), "research-btw-patch-"));
const hash = (file) => createHash("sha256").update(readFileSync(file)).digest("hex");
try {
  const output = join(directory, "patched");
  const provenance = prepare(source, output, "2.2.5");
  assert.equal(hash(join(source, "dist/tui.js")), UPSTREAM.sourceSha256);
  assert.equal(hash(join(output, "dist/tui.js")), UPSTREAM.patchedSha256);
  assert.deepEqual(readFileSync(join(output, "LICENSE")), readFileSync(join(source, "LICENSE")));
  const manifest = JSON.parse(readFileSync(join(output, "package.json"), "utf8"));
  assert.deepEqual(manifest.dependencies, { "@opencode/theme": "2.2.5", "string-width": "7.2.0" });
  assert.equal(manifest.peerDependencies, undefined);
  assert.equal(manifest.exports["./tui"], "./dist/tui.js");
  assert.equal(provenance.commit, UPSTREAM.commit);
  for (const [name, version] of Object.entries(manifest.dependencies)) {
    const dependency = join(output, "node_modules", name);
    mkdirSync(dependency, { recursive: true });
    writeFileSync(join(dependency, "package.json"), JSON.stringify({ name, version }));
  }
  verifyInstalled(output, "2.2.5");
  writeFileSync(join(output, "package.json"), JSON.stringify({ ...manifest, dependencies: {} }));
  assert.throws(() => verifyInstalled(output, "2.2.5"), /identity differs/);
  writeFileSync(join(output, "package.json"), JSON.stringify(manifest));
  writeFileSync(join(output, "dist/tui.js"), "corrupt");
  assert.throws(() => verifyInstalled(output, "2.2.5"), /bundle differs/);
  assert.throws(() => prepare(source, output, "2.2.5"), /must be empty/);
  const rejected = join(directory, "rejected");
  assert.throws(() => prepare(source, rejected, "2.2.6"), /verified only/);
  assert.equal(existsSync(rejected), false);
  assert.throws(() => prepare(source, join(source, "unsafe"), "2.2.5"), /separate staging/);
  const changed = join(directory, "changed");
  mkdirSync(join(changed, "dist"), { recursive: true });
  cpSync(join(source, "package.json"), join(changed, "package.json"));
  writeFileSync(join(changed, "dist/tui.js"), readFileSync(join(source, "dist/tui.js"), "utf8") + "\n");
  assert.throws(() => prepare(changed, rejected, "2.2.5"), /hash mismatch/);
  assert.equal(existsSync(rejected), false);
  console.log("BTW compatibility patch: source, provenance, output and refusal checks passed.");
} finally {
  rmSync(directory, { recursive: true, force: true });
}
