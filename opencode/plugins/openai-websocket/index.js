import { randomUUID } from "node:crypto";

export default {
  id: "research-agent-kit.openai-websocket",
  async setup(ctx) {
    const registration = await ctx.session.hook("experimental.ws.handshake", (event) => {
      if (!new URL(event.url).pathname.endsWith("/responses")) return;
      // Handshake headers select the reusable socket; a new ID rotates it before each step.
      event.headers["x-opencode-ws-step-id"] = randomUUID();
    }, { providerID: "openai" });
    return () => registration.dispose();
  },
};
