---
name: resource-aware-orchestration
description: Use before delegation to select safe concurrency on macOS, Linux, or WSL and enforce task/result contracts.
---

## Delegation Gate

Keep small local work in the main agent. Delegate only when at least two non-overlapping child deliverables exist. Once delegation is selected, run at least two children. A detected concurrency of one requires sequential child execution; it does not permit a one-child delegation. Child agents must not delegate.

Run `scripts/detect_resources.sh` before every spawn wave, when the previous snapshot is older than 600 seconds, after a heavy command, after `RESOURCE_*`, after exit 137 or SIGKILL, and after a cgroup OOM counter increase. Allow only one writing child and one heavy command at a time.

## Detector Contract

The detector supports macOS, Linux, and WSL and emits `key=value` records. A valid snapshot has exactly one normalized `platform` value (`macos`, `linux`, or `wsl`), a `captured_epoch`, a computed `snapshot_age_seconds`, `writer_slots=1`, and `heavy_command_slots=1`. `concurrency` is the minimum of the memory bucket, `floor(effective_cpu/2)` with a floor of one, `HARNESS_MAX_THREADS`, and `HARNESS_TASK_CAP`. Both caps default to six and cannot raise concurrency above six.

Memory buckets are `<20%=1`, `20–34%=2`, `35–49%=3`, `50–64%=4`, and `≥65%=6`. No configured swap adds no penalty. Swap free below 10%, any sampled swapout growth, cgroup OOM growth, or critical PSI (`full avg10 >= 1.00` or `some avg10 >= 20.00`) forces concurrency one and an explicit constrained status. A snapshot older than 600 seconds or any malformed/unsupported normalized input forces concurrency one and exits 3 with a structured `RESOURCE_*` status. CLI usage errors exit 2; `--help` exits 0.

For deterministic tests, pass `--fixture <directory>`. A fixture contains normalized one-line files: `platform`, `captured_epoch`, `total_bytes`, `available_bytes`, `cpu_count`, and optionally `swap_total_bytes`, `swap_free_bytes`, `psi`, `swapout_before`, `swapout_after`, `oom_before`, `oom_after`, `cgroup_memory_max`, `cgroup_memory_current`, `cgroup_cpu_quota`, `cgroup_cpu_period`, and `cpuset_cpus`.

For read-only Linux collector diagnosis, pass `--system-root <directory>` to replay a captured `/proc` and cgroup filesystem rooted at that directory. This mode does not infer success values: it runs the same collector against the supplied system tree and fails on unsafe paths or malformed required signals. The cgroup v2 collector maps the process membership from `/proc/self/cgroup` through the cgroup2 mount root and mountpoint in `/proc/self/mountinfo`, rejects traversal and filesystem escape, then applies the strictest available `memory.max/current`, `cpu.max`, `cpuset.cpus.effective`, and OOM signal from the process directory through the mount root. Missing optional controller files add no constraint; malformed present constraints produce a structured detection failure. Normal Linux output reports `cgroup_v2=detected|unavailable` and the resolved `cgroup_path` when detected.

## Task Packet

Read `references/task_result_contract.md`. Each child receives objective, allowed scope, forbidden scope, write permission, acceptance criteria, resource budget, review budget, stop condition, and output schema. Distinct children must own distinct deliverables.

## Result Contract

Each child returns status (`PASS`, `FAIL`, `BLOCKED`, or `RESOURCE_*`), evidence, commands and exit codes, artifact paths, deviations, and remaining risks. A resource failure blocks dependent work but does not erase completed evidence.
