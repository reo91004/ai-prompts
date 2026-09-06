# Ledger Format


`ledger.json` schema:

```json
{
  "schema_version": 1,
  "active_work_id": "2026-07-13-A-slug",
  "works": {
    "2026-07-13-A-slug": {
      "slug": "slug",
      "status": "active",
      "plan": "2026-07-13-A-slug/plan.md",
      "constraints": ["standing constraint stated by the user, verbatim"],
      "updated": "2026-07-13"
    }
  }
}
```

`status` is one of `active`, `paused`, `completed`, or `blocked`. `active_work_id` is a key in `works` or `null`. `constraints` holds only constraints the user stated; never record procedure rules the agent invented for itself. `plan` is relative to `.plans/`. Rewrite the whole file on every update so it always parses.

The day letter `<L>` is the first unused capital letter for that date (`A` for the day's first item, then `B`, `C`, …), so several plans opened on the same day keep a stable order. Create only the files the work actually needs; never scaffold empty templates. `.plans/` is local by default (the kit's global gitignore excludes it); a project that wants version-tracked plans adds `!.plans/` to its own `.gitignore`.
