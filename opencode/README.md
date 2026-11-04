# OpenCode V2

`sh install.sh` installs or updates the official V2 CLI and applies this platform's global instructions, two read-only research roles, TUI defaults, context policy, and Headroom configuration. Use the V2 release channel and `@opencode/cli`; the repository-wide GitHub latest release can point to V1.

| Source | Installed location |
| --- | --- |
| AGENTS.md | `$XDG_CONFIG_HOME/opencode/AGENTS.md`, default `~/.config/opencode/AGENTS.md` |
| agents/ | The configuration directory's agents/ |
| cli.json | The configuration directory's cli.json |
| opencode.jsonc | The configuration directory's opencode.jsonc |
| plugins/research-context/ | The configuration directory's research-agent-kit/context/ |
| Shared research skills and Humanizer | `~/.agents/skills/`, discovered natively |
| Ponytail (default integration profile) | `~/.universal-research-agent-kit/marketplaces/ponytail-<revision>/ponytail/.opencode/plugins/` |

The installer edits only its JSONC keys and plugin entries, preserving comments, providers, credentials, other MCP servers, and user plugin order. It records absent keys separately from null and preserves subsequent user changes on reinstall/removal. User additions to global skill discovery directories are backed up and retired under the requested full skill replacement policy. Project-local skills and session/BTW data have a separate lifecycle.

## Defaults

The full-screen TUI uses low verbosity, automatic grouping, hidden reasoning display, working-directory tabs, quiet system notifications, and automatic responses to permission prompts. Explicit deny rules still apply. Hiding reasoning affects display, not model effort.

Native build/plan agents remain available. context-explorer and research-reviewer allow read/glob/grep, native skill loading, and sandboxed Code Mode over the permitted read tools. Shell, edits, network fetches, MCP/custom tools, and delegation remain denied. The configured inventory and effective permissions must be checked before claiming a role is read-only in a different environment. An inherited model is an independent session of that model, not cross-model or requested Astra review.

The context plugin sets chat-model context/input metadata to 1,000,000 tokens without replacing provider/model IDs, variants, output limits, or credentials. `compaction.auto=true` and `buffer="20%"` give an 800,000-token compaction ceiling. This is a harness policy; it does not expand a provider's actual supported context.

Ponytail uses the same downloaded revision as Codex and Claude Code. Its V2 plugin injects the rules on each turn and registers `/ponytail` and the companion commands and skills. The upstream default is `full`; an existing saved level or `off` is preserved. Use `/ponytail full` to enable it again. Installation and `--verify` check the V2 entrypoint and configuration registration. Reinstallation replaces an older Ponytail registration in place to avoid duplicate plugin IDs. `--integrations none` removes the kit registration and restores any registration that preceded it.

## LaTeX

The installer registers `opencode-latex@0.2.0` in `opencode.jsonc`; OpenCode downloads the package and loads its TUI companion on startup. The server plugin asks the model to use simple Unicode inline math and fenced `latex` blocks for longer formulas. Existing `\[...\]` expressions in conversation history are not converted.

````markdown
```latex
\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}
```
````

Kitty/SIXEL terminals support graphical output; other terminals use Unicode cells. `/latex-render-mode` selects the output mode. Installation and the command dialog were checked in OpenCode 2.2.5; graphical formula output in a supported terminal has not been visually verified.

## Headroom And Long Work

Headroom's official V2 plugin is read from the installed Python wheel and uses the kit's persistent proxy. Retrieval and the local Headroom MCP are configured through that same deployment. Configuration checks verify directory entrypoints, proxy and MCP paths. OpenAI chat/responses, Anthropic Messages, and the `claude-agent` subprocess are distinct request routes; report only the routes actually tested.

The installer registers [opencode-monitor](https://github.com/rndmcnlly/opencode-monitor) from its `main` branch by default; OpenCode downloads it on startup. Run a native `shell` command with `background: true, monitor: true` to deliver output lines to the agent while the command runs. Filter experiment logs to decisive events such as completion or failure so routine progress does not repeatedly interrupt the agent. Native background jobs also report completion. After a notification, verify the exit status and expected artifacts before continuing dependent work. Keep an experiment separate from any log-watching command whose timeout or cancellation stops its process tree.

Installation and server activation were checked with OpenCode 2.2.5 and upstream commit `6bdb284bcf983da82546d08d852e21005256ee80`. The upstream output-delivery tests passed; live experiment notifications have not been verified.

## BTW History

The CLI uses a local compatibility package built from `opencode-btw-plus@0.1.3`, with the built-in `opencode.btw` disabled. `/btw question` saves a new question/answer and `/btw` reopens the session's saved history. It does not import past built-in BTW answers. TUI-host storage is plain JSON and is preserved across kit updates, outside skill cleanup.

The upstream bundle failed with OpenTUI 0.8. The bounded [compatibility patch](plugins/btw-plus-compat/README.md) supplies the syntax-style resource owner and theme 2.2.5. The patched package passed host-matched headless UI checks; full-app/real-model execution is a separate scope. Unknown source hashes or host versions fail before activation.

## Crucible Research Loop

The shared [Crucible skill](../skills/crucible/SKILL.md) connects OpenCode to the separate [Crucible engine](https://github.com/reo91004/Crucible). Default installation reuses a checkout discovered under HOME or downloads it to `~/Crucible`, records its path, and installs the skill. Existing source checkouts are preserved. `CRUCIBLE_ROOT` and an installed CLI remain optional overrides; tooling-skip mode also skips engine setup.

Run the engine's `link-opencode --project <project>` to add its project-local V2 bridge, then reopen that project's session. The native `crucible` tool starts background execution, inspects state and explicitly delivers durable events. Linking does not alter global providers, permissions or other running projects. The engine README documents its configuration and actual validation scope.

After one-time experiment/evaluator/model/budget setup, `start` evaluates each result and automatically requests review for registered anomaly/regression/stagnation/theory-conflict events. To request discussion explicitly, use `/crucible-debate <question>` or the native tool with `action=debate`, `question`, and optional project-relative `evidence`. Manual cases preserve their own snapshots and bounded budgets; they do not start experiments or change an active loop's next decision. External jobs are not automatically discovered.

## Sources

- [V2 configuration](https://opencode.ai/v2/docs/config), [CLI settings](https://opencode.ai/v2/docs/cli/config), [permissions](https://opencode.ai/v2/docs/permissions).
- [V2 compaction](https://opencode.ai/v2/docs/compaction), [models](https://opencode.ai/v2/docs/models), [plugins](https://opencode.ai/v2/docs/plugins).
- [Headroom OpenCode integration](https://docs.headroomlabs.ai/docs/opencode).
