// Run with Bun and an official, unmodified OpenCode V2 binary; only localhost fixtures are used.
import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import { fileURLToPath } from "node:url";

if (process.argv.length !== 3) throw new Error("Usage: bun tests/smoke_opencode_websocket.mjs OPENCODE_BINARY");
const binary = resolve(process.argv[2]);
const plugin = fileURLToPath(new URL("../opencode/plugins/openai-websocket", import.meta.url));
const root = await mkdtemp(join(tmpdir(), "kit-websocket-smoke-"));

async function check(enabled) {
  const home = join(root, enabled ? "enabled" : "baseline");
  const project = join(home, "project");
  await mkdir(project, { recursive: true });
  const requests = [];
  let opens = 0, http = 0;
  const provider = Bun.serve({
    hostname: "127.0.0.1", port: 0,
    fetch(request, server) {
      if (server.upgrade(request, { data: { id: ++opens, step: request.headers.get("x-opencode-ws-step-id") } })) return;
      http++;
      return new Response("Unexpected HTTP provider request", { status: 500 });
    },
    websocket: { message(socket, data) {
      const input = JSON.parse(String(data));
      requests.push({ connection: socket.data.id, step: socket.data.step, ...input });
      const id = `msg_${requests.length}`;
      const item = { type: "message", id, status: "completed", role: "assistant",
        content: [{ type: "output_text", text: "fixture OK", annotations: [], logprobs: [] }] };
      for (const event of [
        { type: "response.created", response: { id: `resp_${requests.length}` } },
        { type: "response.output_item.added", item: { type: "message", id } },
        { type: "response.output_text.delta", item_id: id, delta: "fixture OK" },
        { type: "response.output_text.done", item_id: id, text: "fixture OK" },
        { type: "response.output_item.done", item },
        { type: "response.completed", response: { id: `resp_${requests.length}`, output: [item] } },
      ]) socket.send(JSON.stringify(event));
    } },
  });
  const env = {
    ...process.env, HOME: home, BUN_BE_BUN: undefined, NODE_OPTIONS: undefined,
    XDG_CONFIG_HOME: join(home, "config"), XDG_DATA_HOME: join(home, "data"),
    XDG_CACHE_HOME: join(home, "cache"), XDG_STATE_HOME: join(home, "state"),
    OPENCODE_TEST_HOME: home, OPENCODE_CONFIG_DIR: join(home, "config/opencode"),
    OPENCODE_DB: join(home, "opencode.db"), OPENCODE_DISABLE_FILEWATCHER: "true",
    OPENCODE_DISABLE_MODELS_FETCH: "true", OPENCODE_CLI_CONFIG_CONTENT: undefined,
    OPENCODE_PASSWORD: "local-fixture",
    OPENCODE_CONFIG_CONTENT: JSON.stringify({
      update: "disable", snapshots: false, plugins: enabled ? [plugin] : [],
      providers: { openai: { settings: { apiKey: "fixture", baseURL: `${provider.url}v1`, transport: "websocket" } } },
    }),
  };
  for (const name of Object.keys(env)) {
    if (name !== "OPENCODE_PASSWORD" && /(?:^|_)(?:API_KEY|AUTHORIZATION|TOKEN|SECRET|PASSWORD|CREDENTIALS?)$/i.test(name)) delete env[name];
  }
  const child = Bun.spawn([binary, "serve", "--hostname", "127.0.0.1", "--port", "0"], {
    cwd: project, env, stdin: "ignore", stdout: "pipe", stderr: Bun.file(join(home, "stderr.log")),
  });
  const ready = Promise.withResolvers();
  const output = (async () => {
    let text = "";
    for await (const chunk of child.stdout) {
      text += new TextDecoder().decode(chunk);
      const match = text.match(/server listening on (http:\/\/127\.0\.0\.1:\d+)/);
      if (match) ready.resolve(match[1]);
    }
    ready.reject(new Error(`Fixture server exited before startup; see ${home}/stderr.log`));
  })();
  const timeout = setTimeout(() => ready.reject(new Error(`Fixture startup timed out; see ${home}/stderr.log`)), 30000);
  try {
    const server = await ready.promise;
    clearTimeout(timeout);
    const api = async (route, body) => {
      const response = await fetch(server + route, {
        method: body === undefined ? "GET" : "POST",
        headers: { authorization: `Basic ${btoa("opencode:local-fixture")}`, "content-type": "application/json" },
        body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000),
      });
      assert.equal(response.status, 200, route);
      return response.json();
    };
    const session = (await api("/api/session", {
      title: "WebSocket fixture", location: { directory: project },
      model: { providerID: "openai", id: "gpt-6-astra", variant: "max" },
    })).data;
    for (const text of ["ws-fixture-first", "ws-fixture-second"]) {
      const previous = requests.length;
      await api(`/api/session/${session.id}/prompt`, { text });
      const deadline = Date.now() + 15000;
      while (true) {
        const messages = (await api(`/api/session/${session.id}/message?type=assistant&limit=10`)).data;
        assert.deepEqual(messages.filter((message) => message.error), [], "Fixture response failed");
        if (messages.filter((message) => message.finish === "stop").length > previous) break;
        assert.ok(Date.now() < deadline, "Fixture response timed out");
        await Bun.sleep(25);
      }
    }
    assert.equal(requests.length, 2);
    assert.equal(http, 0);
    assert.equal(opens, enabled ? 2 : 1, "Use an unmodified official binary for the baseline");
    assert.deepEqual(requests.map((request) => request.connection), enabled ? [1, 2] : [1, 1]);
    if (enabled) {
      assert.notEqual(requests[0].step, requests[1].step);
      assert.ok(requests.every((request) => request.step && request.previous_response_id === undefined));
      assert.match(JSON.stringify(requests[1].input), /ws-fixture-first/);
      assert.match(JSON.stringify(requests[1].input), /ws-fixture-second/);
      assert.match(JSON.stringify(requests[1].input), /fixture OK/);
    }
    console.log(JSON.stringify({ enabled, requests: requests.length, opens, http, passed: true }));
  } finally {
    clearTimeout(timeout);
    child.kill("SIGTERM");
    await child.exited;
    await output;
    provider.stop(true);
  }
}

try {
  await check(false);
  await check(true);
  await rm(root, { recursive: true });
} catch (error) {
  console.error(`Fixture artifacts retained: ${root}`);
  throw error;
}
