import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, cpSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { prepare, supported, verifyInstalled, UPSTREAM } from "../opencode/plugins/btw-plus-compat/patch.mjs";

if (!process.argv[2]) throw new Error("Usage: node tests/test_opencode_btw_patch.mjs VERIFIED_UPSTREAM_PACKAGE_DIRECTORY");
const source = resolve(process.argv[2]);
const directory = mkdtempSync(join(tmpdir(), "research-btw-patch-"));
try {
  assert.equal(supported("v2.2.7"), true);
  assert.equal(supported("2.2.6"), false);
  for (const hostVersion of ["2.2.5", "2.2.7"]) {
    const output = join(directory, `patched-${hostVersion}`);
    const provenance = prepare(source, output, `v${hostVersion}`);
    const original = readFileSync(join(source, "dist/tui.js"), "utf8");
    assert.equal(readFileSync(join(output, "dist/tui.js"), "utf8"),
      original.replace("generateSyntax(context.theme)", "generateSyntax(context.theme, context.renderer.nativeScene)"));
    assert.deepEqual(readFileSync(join(output, "LICENSE")), readFileSync(join(source, "LICENSE")));
    const manifest = JSON.parse(readFileSync(join(output, "package.json"), "utf8"));
    assert.deepEqual(manifest.dependencies, { "@opencode/theme": hostVersion, "string-width": "7.2.0" });
    assert.deepEqual(provenance.host, { opencode: hostVersion, opentui: hostVersion === "2.2.5" ? "0.8.0" : "0.8.1" });
    const lock = JSON.parse(readFileSync(join(output, "package-lock.json"), "utf8"));
    assert.deepEqual(lock.packages[""].dependencies, manifest.dependencies);
    assert.equal(manifest.peerDependencies, undefined);
    assert.equal(manifest.exports["./tui"], "./dist/tui.js");
    assert.equal(provenance.commit, UPSTREAM.commit);
    for (const [name, version] of Object.entries(manifest.dependencies)) {
      const dependency = join(output, "node_modules", name);
      mkdirSync(dependency, { recursive: true });
      writeFileSync(join(dependency, "package.json"), JSON.stringify({ name, version }));
    }
    verifyInstalled(output, hostVersion);
    verifyInstalled(output, `v${hostVersion}`);
    assert.throws(() => verifyInstalled(output, hostVersion === "2.2.5" ? "2.2.7" : "2.2.5"), /dependency declaration differs/);
    assert.throws(() => verifyInstalled(output, "2.2.6"), /Unverified BTW host/);
    writeFileSync(join(output, "package.json"), JSON.stringify({ ...manifest, dependencies: {} }));
    assert.throws(() => verifyInstalled(output, hostVersion), /identity differs/);
    writeFileSync(join(output, "package.json"), JSON.stringify(manifest));
    assert.throws(() => prepare(source, output, hostVersion), /must be empty/);
    const rejected = join(directory, "rejected");
    assert.throws(() => prepare(source, rejected, "2.2.6"), /verified only/);
    assert.equal(existsSync(rejected), false);
    assert.throws(() => prepare(source, join(source, "unsafe"), hostVersion), /separate staging/);
    const changed = join(directory, `changed-${hostVersion}`);
    mkdirSync(join(changed, "dist"), { recursive: true });
    cpSync(join(source, "package.json"), join(changed, "package.json"));
    writeFileSync(join(changed, "dist/tui.js"), original + "\ngenerateSyntax(context.theme)\n");
    assert.throws(() => prepare(changed, rejected, hostVersion), /Unexpected upstream syntax-style call/);
    assert.equal(existsSync(rejected), false);
  }
  console.log("BTW compatibility patch: source, provenance, output and refusal checks passed.");
} finally {
  rmSync(directory, { recursive: true, force: true });
}
