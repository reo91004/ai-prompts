export const CONTEXT_TOKENS = 1_000_000;

export default {
  id: "research-agent-kit.context",
  async setup(ctx) {
    const registration = await ctx.model.transform((models) => {
      for (const model of models.list()) {
        if (model.type && model.type !== "chat") continue;
        models.update(model.providerID, model.id, (draft) => {
          // Both limits feed V2's compaction window; provider capacity is unchanged.
          draft.limit = { ...draft.limit, context: CONTEXT_TOKENS, input: CONTEXT_TOKENS };
        });
      }
    });
    return () => registration.dispose();
  },
};
