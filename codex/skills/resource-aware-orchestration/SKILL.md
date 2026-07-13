---
name: resource-aware-orchestration
description: Use before delegation to select safe concurrency on macOS, Linux, or WSL and enforce task/result contracts.
---

## Delegation Gate

Keep small local work in the main agent. Delegate only when a child owns one bounded specialist deliverable and delegation has a clear net benefit. One child is valid; never create a second child merely to satisfy a minimum agent count. Detected slots are a ceiling, not a target. Child agents must not delegate.

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

Read `references/task_result_contract.md`. Each child receives objective, allowed scope, forbidden scope, write permission, acceptance criteria, resource budget, review budget, stop condition, and output schema. Long-running commands additionally declare their progress probe, checkpoint, resume, cancel, and cleanup contract. Distinct children must own distinct deliverables.

## Result Contract

Each child returns status (`PASS`, `FAIL`, `BLOCKED`, or `RESOURCE_*`), evidence, commands and exit codes, artifact paths, deviations, and remaining risks. A resource failure blocks dependent work but does not erase completed evidence.
