#!/usr/bin/env node
import { createHash } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, realpathSync, writeFileSync } from "node:fs";
import { isAbsolute, relative, resolve, join, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const UPSTREAM = {
  package: "opencode-btw-plus",
  version: "0.1.3",
  commit: "872e7df67b8476ebc44626fd7b79178d854c3c41",
  tarball: "https://registry.npmjs.org/opencode-btw-plus/-/opencode-btw-plus-0.1.3.tgz",
  integrity: "sha512-DCxG5prXRR9qjiCRXXl8ACJBxDKS/brg+h9BQAVTbb0cz5PEfkSkNf1VjPdU5vwUUvDKePGpUjUj4VnPfyy+vA==",
  sourceSha256: "7d46db4d10e6688e4e7215551041561a9c23941444a63424dc642766ad45ce88",
  patchedSha256: "5115c12c363a038eb4acfcd7c46dadb144d0a35a96be9d10b8ced0ed4c695ff3",
};

const sha256 = (text) => createHash("sha256").update(text).digest("hex");

export function verifyInstalled(directory, hostVersion) {
  if (hostVersion.replace(/^v/, "") !== "2.2.5") throw new Error("Unverified BTW host version");
  const provenance = JSON.parse(readFileSync(join(directory, "UPSTREAM.json"), "utf8"));
  for (const [key, value] of Object.entries(UPSTREAM)) {
    if (provenance[key] !== value) throw new Error(`BTW provenance differs: ${key}`);
  }
  if (provenance.host?.opencode !== "2.2.5" || provenance.host?.opentui !== "0.8.0") throw new Error("BTW host provenance differs");
  if (sha256(readFileSync(join(directory, "dist/tui.js"))) !== UPSTREAM.patchedSha256) throw new Error("BTW compatibility bundle differs");
  const manifest = JSON.parse(readFileSync(join(directory, "package.json"), "utf8"));
  const lock = JSON.parse(readFileSync(fileURLToPath(new URL("./runtime-package-lock.json", import.meta.url)), "utf8"));
  const expected = lock.packages[""].dependencies;
  if (manifest.name !== lock.name || manifest.version !== lock.version || manifest.exports?.["./tui"] !== "./dist/tui.js" ||
      Object.keys(manifest.dependencies ?? {}).length !== Object.keys(expected).length) throw new Error("BTW package identity differs");
  for (const [name, version] of Object.entries(expected)) {
    if (manifest.dependencies[name] !== version) throw new Error(`BTW dependency declaration differs: ${name}`);
    const installed = JSON.parse(readFileSync(join(directory, "node_modules", name, "package.json"), "utf8"));
    if (installed.version !== version) throw new Error(`BTW dependency differs: ${name}`);
  }
  return provenance;
}

export function prepare(sourceDirectory, outputDirectory, hostVersion) {
  if (hostVersion.replace(/^v/, "") !== "2.2.5") throw new Error("BTW compatibility patch is verified only for OpenCode 2.2.5");
  const source = realpathSync(sourceDirectory);
  const output = resolve(outputDirectory);
  const inside = relative(source, output);
  if (!inside || (inside !== ".." && !inside.startsWith(".." + sep) && !isAbsolute(inside))) throw new Error("Use a separate staging directory for the compatibility package");
  if (existsSync(output) && (lstatSync(output).isSymbolicLink() || !lstatSync(output).isDirectory() || readdirSync(output).length)) throw new Error("Compatibility staging directory must be empty and not symlinked");
  const manifest = JSON.parse(readFileSync(join(source, "package.json"), "utf8"));
  if (manifest.name !== UPSTREAM.package || manifest.version !== UPSTREAM.version) throw new Error("Unverified BTW package version");
  const original = readFileSync(join(source, "dist/tui.js"), "utf8");
  if (sha256(original) !== UPSTREAM.sourceSha256) throw new Error("BTW upstream bundle hash mismatch");
  const before = "generateSyntax(context.theme)";
  if (original.split(before).length !== 2) throw new Error("Unexpected upstream syntax-style call");
  const patched = original.replace(before, "generateSyntax(context.theme, context.renderer.nativeScene)");
  if (sha256(patched) !== UPSTREAM.patchedSha256) throw new Error("Unexpected compatibility bundle hash");
  const license = readFileSync(join(source, "LICENSE"));
  const lockfile = readFileSync(fileURLToPath(new URL("./runtime-package-lock.json", import.meta.url)));
  const generatedManifest = {
    name: "research-agent-kit-btw-plus-compat",
    version: "0.1.3-kit.1",
    private: true,
    type: "module",
    license: "MIT",
    exports: { "./tui": "./dist/tui.js" },
    dependencies: { "@opencode/theme": "2.2.5", "string-width": "7.2.0" },
  };
  const provenance = {
    ...UPSTREAM,
    host: { opencode: "2.2.5", opentui: "0.8.0" },
    change: "Pass the renderer nativeScene to the OpenCode 2.2.5 theme helper for owned syntax-style resources.",
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
  if (process.argv[2] === "--check") {
    if (process.argv.length !== 5) throw new Error("Usage: patch.mjs --check INSTALLED_DIRECTORY OPENCODE_VERSION");
    verifyInstalled(process.argv[3], process.argv[4]);
    process.exit(0);
  }
  if (process.argv.length !== 5) throw new Error("Usage: patch.mjs UPSTREAM_PACKAGE_DIRECTORY EMPTY_STAGING_DIRECTORY OPENCODE_VERSION");
  process.stdout.write(JSON.stringify(prepare(...process.argv.slice(2))) + "\n");
}
