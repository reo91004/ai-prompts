---
name: resource-aware-orchestration
description: Use when independent agent work is warranted, to select safe concurrency and define a bounded task and result.
---

## Delegation Gate

Actively delegate non-trivial work when a delegation trigger applies; assign each separable specialist deliverable to a subagent, and keep work in the main agent only for genuinely trivial or tightly coupled tasks. One child is valid and zero is right for trivial work; never create a child merely to satisfy a count. Child agents must not delegate.

Delegate by default for: a bounded implementation or refactoring slice with explicit ownership; exploration of an unfamiliar subsystem before acting; high-volume searches, tests, logs, traces, or document retrieval whose raw output would pollute parent context; domain-sensitive design, implementation change, evidence interpretation, or claim review; final acceptance of a material claim; and independent workstreams that can proceed concurrently. For high-volume work, keep raw output in an artifact and return only a concise synthesis with evidence pointers. Detected slots are a ceiling, not a target.

## Claude–Codex Cooperation

Claude collaborates with Codex across substantive phases, using an available connector or the installed `scripts/run_codex_agent.sh` with a matching role. Batch related small steps, reuse useful reviews, and produce concrete answers, artifacts, diagnoses, or decisions. A child never launches another agent; orchestration remains with the parent. If Codex is unavailable, report that once and continue authorized local work without claiming collaboration occurred.

## Dispatch Integrity

For native Codex delegation, set the exact `agent_type`; a task label does not select a role. In a spawn call that also sets role, model, or reasoning overrides, use `fork_turns = "none"` or a bounded positive turn count because current Multi-Agent V2 full-history mode rejects override-bearing calls. Without overrides, select the context range independently and allow `"all"` when full history is needed. Pass the agent's declared `model` and `reasoning_effort` when the tool exposes those fields. If this runtime hides the selector or model controls, run `scripts/run_codex_agent.sh <role> <task>` from this skill for an isolated Codex child, or report the limitation. Do not describe a generic child as the configured specialist.

For Claude Code, select the exact subagent type through the Agent tool or an explicit `@agent-name` mention. `CLAUDE_CODE_SUBAGENT_MODEL` and `CLAUDE_CODE_EFFORT_LEVEL` override the declared assignment when set, so mention them if they change what actually ran.

In both runtimes, never state that a child ran as a specific role, model, or effort unless the runtime showed it. Saying "unverified" is correct; asserting the declaration as fact is not.

## Completion-Driven Long Work

Parent agents must not repeatedly poll long training, synthesis, hardware capture, PIDs, logs, task lists, or mailboxes. Keep routine progress in durable logs and checkpoints; emit a model-visible event only for completion, failure, a permission request, confirmed sustained no-progress, a resource or equipment emergency, or required operator intervention. After an event, the parent verifies exit status and expected artifacts before continuing dependent work.

Run a long command in the foreground and block on it in one tool call — the whole run then costs a single turn. Background it only when there is declared independent work to do meanwhile, and block with one OS-level wait on the process (`wait "$pid"`, or `tail --pid="$pid" -f /dev/null`); a `sleep`/`tail`/status loop is the polling this rule forbids, whatever interval it uses. When a tool wait returns on timeout it carries no information: re-issue the wait and emit nothing. Repeated waits are free only when they are silent, so a per-minute status line is a defect, not progress reporting.

For a fully specified long-running experiment, training, synthesis, or hardware-capture command in Codex, use the pinned `experiment_monitor` through `scripts/run_codex_agent.sh`. This role is `gpt-6-astra` at low effort with `danger-full-access`; it may execute the declared command, block, and collect terminal evidence, but it must not design the experiment, construct a missing command, interpret results, accept claims, or choose an undeclared retry. Do not replace it with an unpinned native child merely to obtain device access. Use a domain specialist before launch when those judgment-bearing tasks remain.

In Claude Code, prefer `Monitor` with a watcher that emits only terminal events. Explicitly request a background subagent when parallel work is useful, but rely on its completion notification only when the running version documents reliable completion semantics. If `Monitor` is unavailable, use a foreground blocking subagent or report the limitation rather than creating an LLM polling loop.

In Codex, direct background terminals require a later session wait or `write_stdin` to surface completion. The parent may continue independent work, then block on the isolated runner session at the dependency boundary. The `experiment_monitor` uses a shell-native blocking wait or the longest policy-allowed tool wait and returns only after a terminal event. A runner-session wait timeout causes another wait without re-analysis and is not failure. Scheduled polling is opt-in only when the user accepts cadence-based checks or the original session cannot remain alive.

Run `scripts/detect_resources.sh` before a spawn wave, when the previous snapshot is older than 600 seconds, after a heavy command, after `RESOURCE_*`, after exit 137 or SIGKILL, and after a cgroup OOM counter increase. A new snapshot applies to new spawns only; do not cancel healthy running work because the recommendation decreased. Allow one writer per shared worktree and one heavy command at a time. After pressure clears, restore slots one step per fresh snapshot rather than jumping straight back to the ceiling.

## Detector Contract

The detector supports macOS, Linux, and WSL and emits `key=value` records. A valid snapshot has exactly one normalized `platform` value (`macos`, `linux`, or `wsl`), a `captured_epoch`, a computed `snapshot_age_seconds`, `agent_slots`, `writer_slots=1`, `heavy_command_slots`, and `spawn_authorized` (`1`, `read_only`, or `0`). `concurrency` mirrors `agent_slots` for backward compatibility.

`agent_slots` starts from absolute memory headroom — one slot per 2 GiB of effective available memory, clamped to 1–6 — then takes the minimum with `floor(effective_cpu/2)` (floor of one), `HARNESS_MAX_THREADS`, and `HARNESS_TASK_CAP`. Both caps default to six and cannot raise slots above six. `available_pct` is diagnostic output.

Signals are graded, not collapsed into one clamp:

- `warnings` (status stays `OK`, slots unchanged): swap free below 10% (`low_swap`), available memory below 10% of effective total (`low_memory_pct`). A warning alone never serializes agents.
- `RESOURCE_CONSTRAINED`: sampled swapout growth or critical PSI (`full avg10 >= 1.00` or `some avg10 >= 20.00`) reduces `agent_slots` by one step (floor one) and sets `heavy_command_slots=0`. Cgroup OOM growth forces `agent_slots=1` and `heavy_command_slots=0`.
- `RESOURCE_UNKNOWN` (exit 3): malformed or unsupported input. Detection failure is not evidence of shortage: `agent_slots` stays at the configured ceiling (the minimum of `HARNESS_MAX_THREADS` and `HARNESS_TASK_CAP`), `spawn_authorized=read_only`, and new writing, GPU, or physical-instrument work is deferred until a valid snapshot exists.
- `RESOURCE_STALE` (exit 3): snapshot older than 600 seconds. `spawn_authorized=0` and `agent_slots=0`: the stale snapshot authorizes nothing; re-run the detector before spawning.

CLI usage errors exit 2; `--help` exits 0.

For deterministic tests, pass `--fixture <directory>`. A fixture contains normalized one-line files: `platform`, `captured_epoch`, `total_bytes`, `available_bytes`, `cpu_count`, and optionally `swap_total_bytes`, `swap_free_bytes`, `psi`, `swapout_before`, `swapout_after`, `oom_before`, `oom_after`, `cgroup_memory_max`, `cgroup_memory_current`, `cgroup_cpu_quota`, `cgroup_cpu_period`, and `cpuset_cpus`.

For read-only Linux collector diagnosis, pass `--system-root <directory>` to replay a captured `/proc` and cgroup filesystem rooted at that directory. This mode does not infer success values: it runs the same collector against the supplied system tree and fails on unsafe paths or malformed required signals. The cgroup v2 collector maps the process membership from `/proc/self/cgroup` through the cgroup2 mount root and mountpoint in `/proc/self/mountinfo`, rejects traversal and filesystem escape, then applies the strictest available `memory.max/current`, `cpu.max`, `cpuset.cpus.effective`, and OOM signal from the process directory through the mount root. Missing optional controller files add no constraint; malformed present constraints produce a structured detection failure. Normal Linux output reports `cgroup_v2=detected|unavailable` and the resolved `cgroup_path` when detected.

## Task Packet

Read `references/task_result_contract.md`. Each child receives objective, agent role, allowed scope, forbidden scope, write permission, acceptance criteria, and return mode. Long-running commands additionally declare command, expected artifacts, checkpoint, and resume. Distinct children must own distinct deliverables. Keep the packet to those fields; process bookkeeping that catches no mistake does not belong in it.

## Result Contract

Each child returns status (`PASS`, `FAIL`, `BLOCKED`, or `RESOURCE_*`), evidence with inspectable paths, commands and exit codes, artifact paths, and remaining risks. A resource failure blocks dependent work but does not erase completed evidence.
