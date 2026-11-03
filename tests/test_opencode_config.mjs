import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, cpSync, readdirSync, statSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { parseConfig, reconcile, mergeObjects } from "../scripts/opencode_config.mjs";
import contextPlugin from "../opencode/plugins/research-context/index.js";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const require = createRequire(new URL("../scripts/opencode-config/package.json", import.meta.url));
const parserPath = process.env.KIT_JSONC_PARSER_PATH || require.resolve("jsonc-parser");
const parser = require(parserPath);

test("JSONC edits preserve comments, unrelated credentials and trailing commas", () => {
  const source = '{\n  // keep the provider\n  "providers": {"custom": {"secret": "untouched"}},\n  "compaction": {"auto": false, "keep": {"tokens": 24000},},\n}\n';
  const result = reconcile(parser, source, { compaction: { auto: true, buffer: "20%" } });
  assert.match(result.text, /\/\/ keep the provider/);
  assert.match(result.text, /"providers": \{"custom": \{"secret": "untouched"\}\}/);
  assert.deepEqual(parseConfig(parser, result.text).compaction, { auto: true, keep: { tokens: 24000 }, buffer: "20%" });
  const repeated = reconcile(parser, result.text, { compaction: { auto: true, buffer: "20%" } }, result.state);
  assert.equal(repeated.text, result.text);
  assert.deepEqual(repeated.state, result.state);
});

test("initial global skill directory reset is owned and reversible", () => {
  const original = '{"skills":["/legacy/global-skills"],"providers":{"custom":{"settings":{"key":"keep"}}}}';
  const installed = reconcile(parser, original, { skills: [] });
  assert.deepEqual(parseConfig(parser, installed.text).skills, []);
  assert.equal(parseConfig(parser, installed.text).providers.custom.settings.key, "keep");
  const removed = reconcile(parser, installed.text, {}, installed.state);
  assert.deepEqual(parseConfig(parser, removed.text), JSON.parse(original));
});

test("ownership preserves absent versus null and restores original values", () => {
  const first = reconcile(parser, '{"nullable":null,"existing":false}', { nullable: 1, newKey: 2, existing: true });
  assert.deepEqual(first.state.keys['["nullable"]'].original, { exists: true, value: null });
  assert.deepEqual(first.state.keys['["newKey"]'].original, { exists: false });
  const removed = reconcile(parser, first.text, {}, first.state);
  assert.deepEqual(parseConfig(parser, removed.text), { nullable: null, existing: false });
});

test("reinstall and removal preserve later user edits and deletions", () => {
  const first = reconcile(parser, "{}", { choice: "first", deleted: true, owned: 1 });
  const text = '{"choice":null,"owned":1,"foreign":"keep"}';
  const update = reconcile(parser, text, { choice: "second", deleted: false, owned: 2 }, first.state);
  assert.deepEqual(parseConfig(parser, update.text), { choice: null, owned: 2, foreign: "keep" });
  assert.deepEqual(update.overrides.sort(), ["choice", "deleted"]);
  const removed = reconcile(parser, update.text, {}, update.state);
  assert.deepEqual(parseConfig(parser, removed.text), { choice: null, foreign: "keep" });
});

test("plugin ownership updates only kit entries while preserving user additions", () => {
  const source = '{"plugins":["user-plugin",{"package":"/kit/headroom","options":{"port":1}}]}';
  const first = reconcile(parser, source, { plugins: [{ package: "/kit/headroom", options: { port: 2 } }, "/kit/context"] });
  const data = parseConfig(parser, first.text);
  data.plugins.push("later-user-plugin");
  const second = reconcile(parser, JSON.stringify(data), { plugins: [{ package: "/kit/headroom", options: { port: 3 } }, "/kit/context"] }, first.state);
  assert.deepEqual(parseConfig(parser, second.text).plugins, ["user-plugin", { package: "/kit/headroom", options: { port: 3 } }, "/kit/context", "later-user-plugin"]);
  const removed = reconcile(parser, second.text, {}, second.state);
  assert.deepEqual(parseConfig(parser, removed.text).plugins, ["user-plugin", { package: "/kit/headroom", options: { port: 1 } }, "later-user-plugin"]);
});

test("a customized kit plugin survives reinstall and removal", () => {
  const first = reconcile(parser, "{}", { plugins: [{ package: "/kit/context", options: { value: 1 } }] });
  const custom = '{"plugins":[{"package":"/kit/context","options":{"value":7}},"user"]}';
  const second = reconcile(parser, custom, { plugins: [{ package: "/kit/context", options: { value: 2 } }] }, first.state);
  assert.equal(second.text, custom);
  assert.deepEqual(second.overrides, ["plugins:/kit/context"]);
  assert.equal(reconcile(parser, second.text, {}, second.state).text, custom);
});

test("versioned CLI plugins upgrade in place and restore the original package", () => {
  const source = '{"plugins":["user-first","opencode-btw-plus@0.1.0","user-last"]}';
  const first = reconcile(parser, source, { plugins: ["-opencode.btw", "opencode-btw-plus@0.1.3"] });
  assert.deepEqual(parseConfig(parser, first.text).plugins, ["user-first", "-opencode.btw", "opencode-btw-plus@0.1.3", "user-last"]);
  const next = reconcile(parser, first.text, { plugins: ["-opencode.btw", "opencode-btw-plus@0.1.4"] }, first.state);
  assert.deepEqual(parseConfig(parser, next.text).plugins, ["user-first", "-opencode.btw", "opencode-btw-plus@0.1.4", "user-last"]);
  assert.deepEqual(parseConfig(parser, reconcile(parser, next.text, {}, next.state).text).plugins,
    ["user-first", "opencode-btw-plus@0.1.0", "user-last"]);
});

test("a user-selected package version and repeated enable directives survive", () => {
  const first = reconcile(parser, "{}", { plugins: ["-opencode.btw", "opencode-btw-plus@0.1.3"] });
  const source = '{"plugins":["user","-user","user","-opencode.btw","opencode-btw-plus@0.2.0"]}';
  const next = reconcile(parser, source, { plugins: ["-opencode.btw", "opencode-btw-plus@0.1.4"] }, first.state);
  assert.equal(next.text, source);
  assert.deepEqual(next.overrides, ["plugins:opencode-btw-plus"]);
  const removed = reconcile(parser, next.text, {}, next.state);
  assert.deepEqual(parseConfig(parser, removed.text).plugins, ["user", "-user", "user", "opencode-btw-plus@0.2.0"]);
});

test("reject malformed and duplicate configuration before editing", () => {
  for (const source of ['{"broken":', '{"same":1,"same":2}', '{"a":{"same":1,"same":2}}', "[]"]) {
    assert.throws(() => reconcile(parser, source, { valid: true }), /JSONC/);
  }
});

test("effective config replaces same-name MCP servers instead of fabricating inherited fields", () => {
  const merged = mergeObjects(
    { providers: { p: { models: { a: {} } } }, mcp: { servers: { same: { type: "local", command: ["old"] }, other: { type: "local", command: ["keep"] } } } },
    { providers: { p: { models: { b: {} } } }, mcp: { servers: { same: { type: "remote", url: "https://example.invalid" } } } },
  );
  assert.deepEqual(merged.providers.p.models, { a: {}, b: {} });
  assert.deepEqual(merged.mcp.servers.same, { type: "remote", url: "https://example.invalid" });
  assert.deepEqual(merged.mcp.servers.other.command, ["keep"]);
});

test("removal clears created empty MCP containers and preserves user siblings", () => {
  const desired = { mcp: { servers: { headroom: { type: "local", command: ["python", "-m", "headroom"] } } } };
  const first = reconcile(parser, "{}", desired);
  assert.deepEqual(parseConfig(parser, reconcile(parser, first.text, {}, first.state).text), {});
  const edited = parseConfig(parser, first.text);
  edited.mcp.servers.user = { type: "local", command: ["user-command"] };
  const removed = reconcile(parser, JSON.stringify(edited), {}, first.state);
  assert.deepEqual(parseConfig(parser, removed.text), { mcp: { servers: { user: edited.mcp.servers.user } } });
});

test("prepare stages files; check reports effective customizations without mutation", () => {
  const directory = mkdtempSync(join(tmpdir(), "research-opencode-"));
  try {
    const configDir = join(directory, "config");
    const outputDir = join(directory, "prepared");
    const statePath = join(directory, "ownership.json");
    const extraPath = join(directory, "headroom.json");
    mkdirSync(configDir);
    writeFileSync(extraPath, JSON.stringify({ plugins: [{ package: "/kit/headroom", options: { proxyUrl: "http://127.0.0.1:8787" } }] }));
    const original = '{\n// original\n"providers":{"custom":{"models":{"one":{}}}},"plugins":["user-base"]\n}';
    writeFileSync(join(configDir, "opencode.json"), original);
    const args = ["--config-dir", configDir, "--state", statePath, "--templates", join(root, "opencode"), "--parser", parserPath, "--extra-template", extraPath];
    const run = (action, extra = []) => JSON.parse(execFileSync(process.execPath, [join(root, "scripts/opencode_config.mjs"), action, ...args, ...extra], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }));
    const prepared = run("prepare", ["--output-dir", outputDir]);
    assert.equal(prepared.status, "configured");
    assert.deepEqual(readdirSync(configDir), ["opencode.json"]);
    assert.equal(readFileSync(join(configDir, "opencode.json"), "utf8"), original);
    for (const name of ["cli.json", "opencode.jsonc"]) cpSync(prepared.prepared[name], join(configDir, name));
    cpSync(prepared.prepared.state, statePath);
    assert.equal(statSync(statePath).mode & 0o777, 0o600);
    assert.equal(run("check").status, "configured");
    const cli = parseConfig(parser, readFileSync(join(configDir, "cli.json"), "utf8"));
    cli.session.thinking = "show";
    writeFileSync(join(configDir, "cli.json"), JSON.stringify(cli));
    const before = readdirSync(configDir).map((name) => [name, readFileSync(join(configDir, name), "utf8")]);
    const checked = run("check");
    assert.equal(checked.status, "customized");
    assert.deepEqual(checked.overrides, ["cli.json:session.thinking"]);
    assert.deepEqual(readdirSync(configDir).map((name) => [name, readFileSync(join(configDir, name), "utf8")]), before);
    const effective = run("effective");
    assert.ok(effective.providers.custom.models.one);
    assert.deepEqual(effective.plugins, ["user-base", join(configDir, "research-agent-kit/context"), "opencode-latex@0.2.0",
      { package: "/kit/headroom", options: { proxyUrl: "http://127.0.0.1:8787" } }]);
    assert.equal(effective.compaction.buffer, "20%");
    writeFileSync(extraPath, "invalid");
    assert.throws(() => run("prepare", ["--output-dir", outputDir]), /Invalid JSONC/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("context plugin changes chat context/input only and disposes its registration", async () => {
  const models = [
    { id: "chat", providerID: "custom", type: "chat", limit: { context: 200000, input: 180000, output: 32000 }, variants: [{ id: "high" }], settings: { effort: "high" } },
    { id: "default", providerID: "custom", limit: { context: 128000, output: 8000 } },
    { id: "image", providerID: "custom", type: "image", limit: { context: 2000, output: 4000 } },
  ];
  const images = structuredClone(models[2]);
  let disposed = false;
  const cleanup = await contextPlugin.setup({ model: { async transform(callback) {
    callback({ list: () => models, update(providerID, id, update) { update(models.find((m) => m.providerID === providerID && m.id === id)); } });
    return { async dispose() { disposed = true; } };
  } } });
  assert.deepEqual(models[0].limit, { context: 1000000, input: 1000000, output: 32000 });
  assert.deepEqual(models[0].variants, [{ id: "high" }]);
  assert.deepEqual(models[0].settings, { effort: "high" });
  assert.equal(models[1].limit.input, 1000000);
  assert.deepEqual(models[2], images);
  const buffer = parseConfig(parser, readFileSync(join(root, "opencode/opencode.jsonc"), "utf8")).compaction.buffer;
  assert.equal(models[0].limit.context * (1 - Number.parseFloat(buffer) / 100), 800000);
  await cleanup();
  assert.equal(disposed, true);
});

test("extra CLI template installs ordered plugins and checks only CLI plugin scope", () => {
  const directory = mkdtempSync(join(tmpdir(), "research-opencode-cli-"));
  try {
    const configDir = join(directory, "config");
    const outputDir = join(directory, "prepared");
    const statePath = join(directory, "ownership.json");
    const extraPath = join(directory, "cli-extra.json");
    mkdirSync(configDir);
    writeFileSync(join(configDir, "cli.json"), '{\n// user CLI plugin\n"plugins":["user-cli"]\n}');
    writeFileSync(join(configDir, "opencode.json"), '{"plugins":["opencode-btw-plus@0.1.3"]}');
    writeFileSync(extraPath, JSON.stringify({ plugins: ["-opencode.btw", "opencode-btw-plus@0.1.3"] }));
    const args = ["--config-dir", configDir, "--state", statePath, "--templates", join(root, "opencode"), "--parser", parserPath, "--extra-cli-template", extraPath];
    const run = (action, extra = []) => JSON.parse(execFileSync(process.execPath,
      [join(root, "scripts/opencode_config.mjs"), action, ...args, ...extra], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }));
    const prepared = run("prepare", ["--output-dir", outputDir]);
    const staged = readFileSync(prepared.prepared["cli.json"], "utf8");
    assert.match(staged, /\/\/ user CLI plugin/);
    assert.deepEqual(parseConfig(parser, staged).plugins, ["user-cli", "-opencode.btw", "opencode-btw-plus@0.1.3"]);
    for (const name of ["cli.json", "opencode.jsonc"]) cpSync(prepared.prepared[name], join(configDir, name));
    cpSync(prepared.prepared.state, statePath);
    assert.equal(run("check").status, "configured");
    const cli = parseConfig(parser, staged);
    cli.plugins.pop();
    writeFileSync(join(configDir, "cli.json"), JSON.stringify(cli));
    assert.deepEqual(run("check").overrides, ["cli.json:plugins:opencode-btw-plus"]);
    assert.throws(() => run("prepare", ["--output-dir", outputDir, "--extra-cli-template", extraPath]), /Invalid argument/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
