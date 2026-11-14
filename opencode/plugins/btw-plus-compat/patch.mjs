#!/usr/bin/env node
import { existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, realpathSync, writeFileSync } from "node:fs";
import { isAbsolute, relative, resolve, join, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const UPSTREAM = {
  package: "opencode-btw-plus",
  version: "0.1.3",
  commit: "872e7df67b8476ebc44626fd7b79178d854c3c41",
  tarball: "https://registry.npmjs.org/opencode-btw-plus/-/opencode-btw-plus-0.1.3.tgz",
};

const HOSTS = {
  "2.2.5": { opentui: "0.8.0", lock: "runtime-package-lock.json" },
  "2.2.7": { opentui: "0.8.1", lock: "runtime-2.2.7-package-lock.json" },
};

export function supported(hostVersion) {
  return Object.hasOwn(HOSTS, hostVersion.replace(/^v/, ""));
}

export function verifyInstalled(directory, hostVersion) {
  hostVersion = hostVersion.replace(/^v/, "");
  if (!supported(hostVersion)) throw new Error("Unverified BTW host version");
  const manifest = JSON.parse(readFileSync(join(directory, "package.json"), "utf8"));
  const lock = JSON.parse(readFileSync(fileURLToPath(new URL(HOSTS[hostVersion].lock, import.meta.url)), "utf8"));
  const expected = lock.packages[""].dependencies;
  if (manifest.name !== lock.name || manifest.version !== lock.version || manifest.exports?.["./tui"] !== "./dist/tui.js" ||
      Object.keys(manifest.dependencies ?? {}).length !== Object.keys(expected).length) throw new Error("BTW package identity differs");
  for (const [name, version] of Object.entries(expected)) {
    if (manifest.dependencies[name] !== version) throw new Error(`BTW dependency declaration differs: ${name}`);
    const installed = JSON.parse(readFileSync(join(directory, "node_modules", name, "package.json"), "utf8"));
    if (installed.version !== version) throw new Error(`BTW dependency differs: ${name}`);
  }
}

export function prepare(sourceDirectory, outputDirectory, hostVersion) {
  hostVersion = hostVersion.replace(/^v/, "");
  if (!supported(hostVersion)) throw new Error("BTW compatibility patch is verified only for OpenCode 2.2.5 and 2.2.7");
  const source = realpathSync(sourceDirectory);
  const output = resolve(outputDirectory);
  const inside = relative(source, output);
  if (!inside || (inside !== ".." && !inside.startsWith(".." + sep) && !isAbsolute(inside))) throw new Error("Use a separate staging directory for the compatibility package");
  if (existsSync(output) && (lstatSync(output).isSymbolicLink() || !lstatSync(output).isDirectory() || readdirSync(output).length)) throw new Error("Compatibility staging directory must be empty and not symlinked");
  const manifest = JSON.parse(readFileSync(join(source, "package.json"), "utf8"));
  if (manifest.name !== UPSTREAM.package || manifest.version !== UPSTREAM.version) throw new Error("Unverified BTW package version");
  const original = readFileSync(join(source, "dist/tui.js"), "utf8");
  const before = "generateSyntax(context.theme)";
  if (original.split(before).length !== 2) throw new Error("Unexpected upstream syntax-style call");
  const patched = original.replace(before, "generateSyntax(context.theme, context.renderer.nativeScene)");
  const license = readFileSync(join(source, "LICENSE"));
  const lockfile = readFileSync(fileURLToPath(new URL(HOSTS[hostVersion].lock, import.meta.url)));
  const generatedManifest = {
    name: "research-agent-kit-btw-plus-compat",
    version: "0.1.3-kit.1",
    private: true,
    type: "module",
    license: "MIT",
    exports: { "./tui": "./dist/tui.js" },
    dependencies: JSON.parse(lockfile).packages[""].dependencies,
  };
  const provenance = {
    ...UPSTREAM,
    host: { opencode: hostVersion, opentui: HOSTS[hostVersion].opentui },
    change: "Pass the renderer nativeScene to the OpenCode theme helper for owned syntax-style resources.",
  };
  mkdirSync(join(output, "dist"), { recursive: true });
  writeFileSync(join(output, "dist/tui.js"), patched);
  writeFileSync(join(output, "package.json"), JSON.stringify(generatedManifest, null, 2) + "\n");
  writeFileSync(join(output, "package-lock.json"), lockfile);
  writeFileSync(join(output, "LICENSE"), license);
  writeFileSync(join(output, "UPSTREAM.json"), JSON.stringify(provenance, null, 2) + "\n");
  return provenance;
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  if (process.argv[2] === "--supports") {
    if (process.argv.length !== 4) throw new Error("Usage: patch.mjs --supports OPENCODE_VERSION");
    process.exit(supported(process.argv[3]) ? 0 : 1);
  }
  if (process.argv[2] === "--check") {
    if (process.argv.length !== 5) throw new Error("Usage: patch.mjs --check INSTALLED_DIRECTORY OPENCODE_VERSION");
    verifyInstalled(process.argv[3], process.argv[4]);
    process.exit(0);
  }
  if (process.argv.length !== 5) throw new Error("Usage: patch.mjs UPSTREAM_PACKAGE_DIRECTORY EMPTY_STAGING_DIRECTORY OPENCODE_VERSION");
  process.stdout.write(JSON.stringify(prepare(...process.argv.slice(2))) + "\n");
}
