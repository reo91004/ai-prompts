import test from "node:test";
import assert from "node:assert/strict";
import plugin from "../opencode/plugins/openai-websocket/index.js";

test("OpenAI Responses gets a unique handshake per step and preserves other headers", async () => {
  let handshake, disposed = false;
  const cleanup = await plugin.setup({ session: { async hook(name, callback, options) {
    assert.equal(name, "experimental.ws.handshake");
    assert.deepEqual(options, { providerID: "openai" });
    handshake = callback;
    return { async dispose() { disposed = true; } };
  } } });
  const original = { authorization: "Bearer fixture", "x-client-request-id": "ses_fixture" };
  const first = { url: "wss://proxy.example/custom/v1/responses?mode=test", headers: { ...original } };
  const second = { ...first, headers: { ...original } };
  handshake(first);
  handshake(second);
  assert.match(first.headers["x-opencode-ws-step-id"], /^[0-9a-f-]{36}$/);
  assert.notEqual(first.headers["x-opencode-ws-step-id"], second.headers["x-opencode-ws-step-id"]);
  delete first.headers["x-opencode-ws-step-id"];
  assert.deepEqual(first.headers, original);
  const other = { url: "wss://proxy.example/v1/chat/completions", headers: { ...original } };
  handshake(other);
  assert.deepEqual(other.headers, original);
  await cleanup();
  assert.equal(disposed, true);
});
