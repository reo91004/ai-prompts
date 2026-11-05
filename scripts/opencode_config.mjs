#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, mkdirSync, statSync } from "node:fs";
import { resolve, join } from "node:path";
import { pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";

const own = (object, key) => Object.prototype.hasOwnProperty.call(object, key);
const object = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const clone = (value) => structuredClone(value);

export function parseConfig(parser, text, filename = "configuration") {
  const errors = [];
  const tree = parser.parseTree(text, errors, { allowTrailingComma: true });
  if (errors.length || tree?.type !== "object") throw new Error(`Invalid JSONC object: ${filename}`);
  function check(node) {
    if (node.type === "object") {
      const keys = new Set();
      for (const property of node.children ?? []) {
        const key = property.children[0].value;
        if (keys.has(key)) throw new Error(`Duplicate JSONC key in ${filename}: ${key}`);
        keys.add(key);
      }
    }
    for (const child of node.children ?? []) check(child);
  }
  check(tree);
  return clone(parser.getNodeValue(tree));
}

export function lookup(value, path) {
  for (const key of path) {
    if (!object(value) || !own(value, key)) return { exists: false };
    value = value[key];
  }
  return { exists: true, value: clone(value) };
}

function leaves(value, path = []) {
  if (!object(value) || Object.keys(value).length === 0) return [[path, value]];
  return Object.entries(value).flatMap(([key, child]) => leaves(child, [...path, key]));
}

function edit(parser, text, path, snapshot) {
  return parser.applyEdits(text, parser.modify(text, path, snapshot.exists ? snapshot.value : undefined, {
    formattingOptions: { insertSpaces: true, tabSize: 2, eol: text.includes("\r\n") ? "\r\n" : "\n" },
  }));
}

function packageID(entry) {
  const id = typeof entry === "string" ? entry : entry?.package;
  if (typeof id !== "string" || !id) throw new Error("Plugin entries must have a package string");
  // V2 rejects duplicate plugin IDs, including Ponytail registered from an older local checkout.
  if (/(?:^|\/)ponytail(?:-[^/]+)?\/\.opencode\/plugins\/?$/.test(id)) return "@dietrichgebert/ponytail";
  const npm = /^((?:@[a-z0-9._-]+\/)?[a-z0-9._-]+)(?:@[^/]+)?$/i.exec(id);
  return npm?.[1] ?? id;
}

function pluginArray(value) {
  if (value === undefined) return [];
  if (!Array.isArray(value)) throw new Error("plugins must be an array");
  for (const entry of value) packageID(entry);
  return clone(value);
}

export function reconcile(parser, text, desired, previous = { keys: {}, plugins: {} }) {
  let data = parseConfig(parser, text);
  const expected = clone(desired);
  const plugins = pluginArray(expected.plugins);
  delete expected.plugins;
  const requested = new Map(leaves(expected).filter(([path]) => path.length).map(([path, value]) => [JSON.stringify(path), value]));
  const state = { keys: {}, plugins: {}, containers: [] };
  const containers = new Set(previous.containers ?? []);
  const overrides = [];
  for (const id of new Set([...Object.keys(previous.keys), ...requested.keys()])) {
    const path = JSON.parse(id);
    const current = lookup(data, path);
    const prior = previous.keys[id];
    if (prior && !isDeepStrictEqual(current, prior.installed)) {
      state.keys[id] = prior;
      overrides.push(path.join("."));
      continue;
    }
    const wanted = requested.has(id) ? { exists: true, value: requested.get(id) } : prior.original;
    if (!isDeepStrictEqual(current, wanted)) {
      if (wanted.exists) {
        for (let length = 1; length < path.length; length++) {
          const prefix = path.slice(0, length);
          if (!lookup(data, prefix).exists) containers.add(JSON.stringify(prefix));
        }
      }
      text = edit(parser, text, path, wanted);
      data = parseConfig(parser, text);
    }
    if (requested.has(id)) state.keys[id] = { original: prior?.original ?? current, installed: wanted };
  }

  // Empty MCP server objects shadow lower-precedence servers, so remove only containers we created.
  for (const id of [...containers].sort((a, b) => JSON.parse(b).length - JSON.parse(a).length)) {
    const path = JSON.parse(id);
    const needed = [...requested.keys()].some((key) => {
      const requestedPath = JSON.parse(key);
      return path.every((part, index) => requestedPath[index] === part);
    });
    const current = lookup(data, path);
    if (!needed && current.exists && object(current.value) && !Object.keys(current.value).length) {
      text = edit(parser, text, path, { exists: false });
      data = parseConfig(parser, text);
      containers.delete(id);
    }
  }
  state.containers = [...containers];

  const currentPlugins = pluginArray(data.plugins);
  let nextPlugins = [...currentPlugins];
  const requestedPlugins = new Map(plugins.map((entry) => [packageID(entry), entry]));
  for (const id of new Set([...Object.keys(previous.plugins), ...requestedPlugins.keys()])) {
    const index = nextPlugins.findLastIndex((entry) => packageID(entry) === id);
    const current = index < 0 ? { exists: false } : { exists: true, value: nextPlugins[index] };
    const prior = previous.plugins[id];
    if (prior && !isDeepStrictEqual(current, prior.installed)) {
      state.plugins[id] = prior;
      overrides.push(`plugins:${id}`);
      continue;
    }
    const wanted = requestedPlugins.has(id) ? { exists: true, value: requestedPlugins.get(id) } : prior.original;
    if (index >= 0) nextPlugins.splice(index, 1);
    if (wanted.exists) {
      const order = [...requestedPlugins.keys()];
      const later = order.slice(order.indexOf(id) + 1);
      const before = nextPlugins.findIndex((entry) => later.includes(packageID(entry)));
      const insertion = index >= 0 ? index : before >= 0 ? before : nextPlugins.length;
      nextPlugins.splice(insertion, 0, wanted.value);
    }
    if (requestedPlugins.has(id)) state.plugins[id] = { original: prior?.original ?? current, installed: wanted };
  }
  if (!isDeepStrictEqual(currentPlugins, nextPlugins)) {
    text = edit(parser, text, ["plugins"], { exists: true, value: nextPlugins });
  }
  parseConfig(parser, text);
  return { text, state, overrides };
}

export function mergeObjects(base, overlay, path = []) {
  const result = { ...base };
  for (const [key, value] of Object.entries(overlay)) {
    const replaceServer = path.length === 2 && path[0] === "mcp" && path[1] === "servers";
    const merged = !replaceServer && object(value) && object(base[key]) ? mergeObjects(base[key], value, [...path, key]) : clone(value);
    Object.defineProperty(result, key, { value: merged, enumerable: true, configurable: true, writable: true });
  }
  return result;
}

function readConfig(parser, path) {
  const text = existsSync(path) ? readFileSync(path, "utf8") : "{}\n";
  return { text, data: parseConfig(parser, text, path) };
}

function assertState(state, configDir) {
  if (state.version !== 1 || state.configDir !== configDir || !object(state.files)) {
    throw new Error("OpenCode ownership state does not match this configuration directory");
  }
  for (const file of Object.values(state.files)) {
    if (!object(file.keys) || !object(file.plugins)) throw new Error("Invalid OpenCode ownership entries");
    for (const [id, entry] of Object.entries(file.keys)) {
      const path = JSON.parse(id);
      if (!Array.isArray(path) || !path.length || path.some((part) => typeof part !== "string")) throw new Error("Invalid owned configuration path");
      if (typeof entry.original?.exists !== "boolean" || typeof entry.installed?.exists !== "boolean") throw new Error("Invalid owned configuration snapshot");
    }
  }
}

export async function main(args) {
  const [action, ...rest] = args;
  if (!["prepare", "check", "remove", "effective"].includes(action)) throw new Error("Usage: opencode_config.mjs prepare|check|remove|effective --config-dir PATH --parser PATH [--state PATH --templates PATH --extra-template PATH --extra-cli-template PATH --output-dir PATH]");
  const options = {};
  for (let i = 0; i < rest.length; i += 2) {
    if (!["--config-dir", "--state", "--templates", "--parser", "--output-dir", "--extra-template", "--extra-cli-template"].includes(rest[i]) || !rest[i + 1] || own(options, rest[i])) throw new Error(`Invalid argument: ${rest[i]}`);
    options[rest[i]] = resolve(rest[i + 1]);
  }
  for (const key of ["--config-dir", "--parser", ...(action === "effective" ? [] : ["--state", "--templates"])]) if (!options[key]) throw new Error(`Missing ${key}`);
  if (["prepare", "remove"].includes(action) && !options["--output-dir"]) throw new Error("Missing --output-dir");
  const module = await import(pathToFileURL(options["--parser"]).href);
  const parser = module.default ?? module;
  const configDir = options["--config-dir"];
  const base = readConfig(parser, join(configDir, "opencode.json")).data;
  if (action === "effective") {
    const overlay = readConfig(parser, join(configDir, "opencode.jsonc")).data;
    const effective = mergeObjects(base, overlay);
    if (own(base, "plugins") || own(overlay, "plugins")) effective.plugins = [...pluginArray(base.plugins), ...pluginArray(overlay.plugins)];
    process.stdout.write(JSON.stringify(effective) + "\n");
    return effective;
  }
  const statePath = options["--state"];
  const state = existsSync(statePath) ? JSON.parse(readFileSync(statePath, "utf8")) : { version: 1, configDir, files: {} };
  assertState(state, configDir);
  if (action === "check" && !existsSync(statePath)) throw new Error("OpenCode configuration has not been installed");

  let desiredCli = parseConfig(parser, readFileSync(join(options["--templates"], "cli.json"), "utf8"));
  if (options["--extra-cli-template"]) desiredCli = mergeObjects(desiredCli, parseConfig(parser, readFileSync(options["--extra-cli-template"], "utf8")));
  let desiredServer = parseConfig(parser, readFileSync(join(options["--templates"], "opencode.jsonc"), "utf8"));
  if (options["--extra-template"]) {
    const extra = parseConfig(parser, readFileSync(options["--extra-template"], "utf8"));
    const plugins = [...pluginArray(desiredServer.plugins), ...pluginArray(extra.plugins)];
    desiredServer = { ...mergeObjects(desiredServer, extra), plugins };
  }
  desiredServer.plugins = [join(configDir, "research-agent-kit/context"), join(configDir, "research-agent-kit/openai-websocket"), ...pluginArray(desiredServer.plugins)];
  const result = { status: "configured", overrides: [], prepared: {} };
  const nextState = { version: 1, configDir, files: {} };
  for (const [filename, desired, label] of [["cli.json", desiredCli, "cli"], ["opencode.jsonc", desiredServer, "server"]]) {
    const target = join(configDir, filename);
    const current = readConfig(parser, target);
    const previous = state.files[filename] ?? { keys: {}, plugins: {} };
    if (action === "check") {
      const effective = filename === "opencode.jsonc" ? mergeObjects(base, current.data) : current.data;
      for (const [path, value] of leaves(desired).filter(([path]) => path[0] !== "plugins")) {
        if (!isDeepStrictEqual(lookup(effective, path), { exists: true, value })) result.overrides.push(`${filename}:${path.join(".")}`);
      }
      const effectivePlugins = [...(filename === "opencode.jsonc" ? pluginArray(base.plugins) : []), ...pluginArray(current.data.plugins)];
      for (const expected of pluginArray(desired.plugins)) {
        const match = effectivePlugins.filter((entry) => packageID(entry) === packageID(expected)).at(-1);
        if (!isDeepStrictEqual(match, expected)) result.overrides.push(`${filename}:plugins:${packageID(expected)}`);
      }
      continue;
    }
    const updated = reconcile(parser, current.text, action === "remove" ? {} : desired, previous);
    result.overrides.push(...updated.overrides.map((key) => `${filename}:${key}`));
    nextState.files[filename] = updated.state;
    const output = join(options["--output-dir"], `opencode-${label}.next`);
    mkdirSync(options["--output-dir"], { recursive: true });
    writeFileSync(output, updated.text, { mode: existsSync(target) ? statSync(target).mode & 0o777 : 0o600 });
    result.prepared[filename] = output;
  }
  if (action !== "check") {
    const output = join(options["--output-dir"], "opencode-state.next");
    writeFileSync(output, JSON.stringify(nextState, null, 2) + "\n", { mode: 0o600 });
    result.prepared.state = output;
  }
  if (result.overrides.length) result.status = "customized";
  process.stdout.write(JSON.stringify(result) + "\n");
  return result;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  await main(process.argv.slice(2));
}
