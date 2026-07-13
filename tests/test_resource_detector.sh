#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECTOR="$ROOT/codex/skills/resource-aware-orchestration/scripts/detect_resources.sh"
FIXTURES="$ROOT/tests/fixtures/resources"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/resource-detector.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

assert_line() {
  local text="$1"
  local expected="$2"
  printf '%s\n' "$text" | grep -Fqx "$expected" || {
    echo "missing output: $expected" >&2
    printf '%s\n' "$text" >&2
    exit 1
  }
}

assert_match() {
  local text="$1"
  local expected="$2"
  printf '%s\n' "$text" | grep -Eq "$expected" || {
    echo "missing output pattern: $expected" >&2
    printf '%s\n' "$text" >&2
    exit 1
  }
}

prepare_case() {
  local name="$1"
  local source="${2:-base}"
  mkdir "$TMP/$name"
  cp -R "$FIXTURES/$source/." "$TMP/$name/"
  date +%s > "$TMP/$name/captured_epoch"
}

set_signal() {
  printf '%s\n' "$3" > "$TMP/$1/$2"
}

run_fixture() {
  local expected_rc="$1"
  local name="$2"
  shift 2
  set +e
  output="$(env "$@" "$DETECTOR" --fixture "$TMP/$name" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -eq "$expected_rc" ] || {
    echo "$name: expected rc $expected_rc, got $rc" >&2
    printf '%s\n' "$output" >&2
    exit 1
  }
}

prepare_cgroup_system_root() {
  local root="$TMP/cgroup-system-root"
  local index=0
  mkdir -p \
    "$root/proc/pressure" \
    "$root/proc/self" \
    "$root/proc/sys/kernel" \
    "$root/sys/fs/cgroup/team/slice"
  printf '%s\n' \
    'MemTotal:       33554432 kB' \
    'MemAvailable:   16777216 kB' \
    'SwapTotal:              0 kB' \
    'SwapFree:               0 kB' > "$root/proc/meminfo"
  while [ "$index" -lt 12 ]; do
    printf 'processor : %s\n' "$index" >> "$root/proc/cpuinfo"
    index=$((index + 1))
  done
  printf '%s\n' 'Linux version synthetic' > "$root/proc/version"
  printf '%s\n' '6.8.0' > "$root/proc/sys/kernel/osrelease"
  printf '%s\n' 'pswpout 0' > "$root/proc/vmstat"
  printf '%s\n' \
    'some avg10=0.00 avg60=0.00 avg300=0.00 total=0' \
    'full avg10=0.00 avg60=0.00 avg300=0.00 total=0' > "$root/proc/pressure/memory"
  printf '%s\n' '0::/tenant/team/slice' > "$root/proc/self/cgroup"
  printf '%s\n' '29 23 0:26 /tenant /sys/fs/cgroup rw,nosuid,nodev,noexec,relatime - cgroup2 cgroup rw' > "$root/proc/self/mountinfo"
  printf '%s\n' max > "$root/sys/fs/cgroup/memory.max"
  printf '%s\n' 0 > "$root/sys/fs/cgroup/memory.current"
  printf '%s\n' 'oom 0' 'oom_kill 0' > "$root/sys/fs/cgroup/memory.events"
  printf '%s\n' 'max 100000' > "$root/sys/fs/cgroup/cpu.max"
  printf '%s\n' '0-11' > "$root/sys/fs/cgroup/cpuset.cpus.effective"
  printf '%s\n' 209715200 > "$root/sys/fs/cgroup/team/memory.max"
  printf '%s\n' 199229440 > "$root/sys/fs/cgroup/team/memory.current"
  printf '%s\n' '200000 100000' > "$root/sys/fs/cgroup/team/cpu.max"
  printf '%s\n' 104857600 > "$root/sys/fs/cgroup/team/slice/memory.max"
  printf '%s\n' 0 > "$root/sys/fs/cgroup/team/slice/memory.current"
  printf '%s\n' 'oom 0' 'oom_kill 0' > "$root/sys/fs/cgroup/team/slice/memory.events"
  echo "$root"
}

system_root="$(prepare_cgroup_system_root)"
set +e
output="$($DETECTOR --system-root "$system_root" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "system-root replay returned $rc" >&2; printf '%s\n' "$output" >&2; exit 1; }
assert_line "$output" 'cgroup_v2=detected'
assert_line "$output" 'cgroup_path=/sys/fs/cgroup/team/slice'
assert_line "$output" 'available_pct=10'
assert_line "$output" 'effective_cpu=2'
assert_line "$output" 'agent_slots=1'
assert_line "$output" 'concurrency=1'

printf '%s\n' '0::/tenant' > "$system_root/proc/self/cgroup"
root_output="$($DETECTOR --system-root "$system_root")"
assert_line "$root_output" 'cgroup_path=/sys/fs/cgroup'
assert_line "$root_output" 'agent_slots=6'
printf '%s\n' '0::/tenant/team/slice' > "$system_root/proc/self/cgroup"
slice_output="$($DETECTOR --system-root "$system_root")"
assert_line "$slice_output" 'cgroup_path=/sys/fs/cgroup/team/slice'
assert_line "$slice_output" 'agent_slots=1'

parser_failures=0
printf '%s\n' max > "$system_root/sys/fs/cgroup/team/slice/cpu.max"
set +e
malformed_cpu_output="$($DETECTOR --system-root "$system_root" 2>&1)"
malformed_cpu_rc=$?
set -e
if [ "$malformed_cpu_rc" -ne 3 ] || ! printf '%s\n' "$malformed_cpu_output" | grep -Fqx 'reason=malformed_cgroup_cpu'; then
  echo "single-token cpu.max was not rejected: rc=$malformed_cpu_rc" >&2
  printf '%s\n' "$malformed_cpu_output" >&2
  parser_failures=$((parser_failures + 1))
fi
printf '%s\n' 'max 100000' > "$system_root/sys/fs/cgroup/team/slice/cpu.max"
printf '%s\n' 'oom_kill 0' > "$system_root/sys/fs/cgroup/team/slice/memory.events"
set +e
malformed_events_output="$($DETECTOR --system-root "$system_root" 2>&1)"
malformed_events_rc=$?
set -e
if [ "$malformed_events_rc" -ne 3 ] || ! printf '%s\n' "$malformed_events_output" | grep -Fqx 'reason=malformed_cgroup_events'; then
  echo "memory.events without oom was not rejected: rc=$malformed_events_rc" >&2
  printf '%s\n' "$malformed_events_output" >&2
  parser_failures=$((parser_failures + 1))
fi
[ "$parser_failures" -eq 0 ] || exit 1
printf '%s\n' 'oom 0' 'oom_kill 0' > "$system_root/sys/fs/cgroup/team/slice/memory.events"

printf '%s\n' '0::/../../etc' > "$system_root/proc/self/cgroup"
set +e
unsafe_output="$($DETECTOR --system-root "$system_root" 2>&1)"
unsafe_rc=$?
set -e
[ "$unsafe_rc" -eq 3 ] || { echo "unsafe cgroup path returned $unsafe_rc" >&2; exit 1; }
assert_line "$unsafe_output" 'status=RESOURCE_UNKNOWN'
assert_line "$unsafe_output" 'reason=unsafe_cgroup_membership_path'

# Absolute headroom buckets: one slot per 2 GiB available, clamped to 1-6.
for point in 1073741824:1 2147483648:1 4294967295:1 4294967296:2 6442450944:3 8589934592:4 10737418240:5 12884901888:6; do
  bytes=${point%%:*}
  expected=${point##*:}
  prepare_case "bucket-$expected-$bytes"
  set_signal "bucket-$expected-$bytes" available_bytes "$bytes"
  run_fixture 0 "bucket-$expected-$bytes"
  assert_line "$output" "memory_bucket=$expected"
  assert_line "$output" "agent_slots=$expected"
  assert_line "$output" "concurrency=$expected"
done

# Low absolute-percentage headroom warns without serializing.
prepare_case low-memory-pct
set_signal low-memory-pct available_bytes 1073741824
run_fixture 0 low-memory-pct
assert_line "$output" 'status=OK'
assert_line "$output" 'warnings=low_memory_pct'
assert_line "$output" 'agent_slots=1'

prepare_case cpu-cap
set_signal cpu-cap cpu_count 4
run_fixture 0 cpu-cap
assert_line "$output" 'agent_slots=2'

prepare_case thread-cap
run_fixture 0 thread-cap HARNESS_MAX_THREADS=4
assert_line "$output" 'agent_slots=4'

prepare_case task-cap
run_fixture 0 task-cap HARNESS_TASK_CAP=3
assert_line "$output" 'agent_slots=3'

prepare_case no-swap
run_fixture 0 no-swap
assert_line "$output" 'swap_free_pct=not_configured'
assert_line "$output" 'status=OK'
assert_line "$output" 'warnings=none'

# Low swap alone is a warning, never a serialization signal.
prepare_case low-swap
set_signal low-swap swap_total_bytes 100
set_signal low-swap swap_free_bytes 9
run_fixture 0 low-swap
assert_line "$output" 'status=OK'
assert_line "$output" 'warnings=low_swap'
assert_line "$output" 'agent_slots=6'
assert_line "$output" 'heavy_command_slots=1'
assert_line "$output" 'spawn_authorized=1'

prepare_case cgroup-memory
set_signal cgroup-memory cgroup_memory_max 4294967296
set_signal cgroup-memory cgroup_memory_current 2147483648
run_fixture 0 cgroup-memory
assert_line "$output" 'available_pct=50'
assert_line "$output" 'agent_slots=1'

prepare_case cgroup-cpu
set_signal cgroup-cpu cgroup_cpu_quota 200000
set_signal cgroup-cpu cgroup_cpu_period 100000
run_fixture 0 cgroup-cpu
assert_line "$output" 'effective_cpu=2'
assert_line "$output" 'agent_slots=1'

prepare_case cpuset
set_signal cpuset cpuset_cpus '0-3,6'
run_fixture 0 cpuset
assert_line "$output" 'effective_cpu=5'
assert_line "$output" 'agent_slots=2'

prepare_case psi-boundary
set_signal psi-boundary psi 'some avg10=19.99 avg60=0.00 avg300=0.00 total=0
full avg10=0.99 avg60=0.00 avg300=0.00 total=0'
run_fixture 0 psi-boundary
assert_line "$output" 'status=OK'
assert_line "$output" 'agent_slots=6'

# Critical PSI and swapout growth reduce slots one step and hold heavy work.
prepare_case psi-full-critical
set_signal psi-full-critical psi 'full avg10=1.00 avg60=0.00 avg300=0.00 total=0'
run_fixture 0 psi-full-critical
assert_line "$output" 'status=RESOURCE_CONSTRAINED'
assert_line "$output" 'agent_slots=5'
assert_line "$output" 'heavy_command_slots=0'
assert_line "$output" 'reason=critical_psi'

prepare_case psi-some-critical
set_signal psi-some-critical psi 'some avg10=20.00 avg60=0.00 avg300=0.00 total=0'
run_fixture 0 psi-some-critical
assert_line "$output" 'status=RESOURCE_CONSTRAINED'
assert_line "$output" 'agent_slots=5'
assert_line "$output" 'reason=critical_psi'

prepare_case swapout-growth
set_signal swapout-growth swapout_before 1
set_signal swapout-growth swapout_after 2
run_fixture 0 swapout-growth
assert_line "$output" 'status=RESOURCE_CONSTRAINED'
assert_line "$output" 'agent_slots=5'
assert_line "$output" 'heavy_command_slots=0'
assert_line "$output" 'reason=swapout_growth'

# The one-step reduction never drops below one slot.
prepare_case constrained-floor
set_signal constrained-floor available_bytes 1073741824
set_signal constrained-floor psi 'full avg10=1.00 avg60=0.00 avg300=0.00 total=0'
run_fixture 0 constrained-floor
assert_line "$output" 'status=RESOURCE_CONSTRAINED'
assert_line "$output" 'agent_slots=1'

# OOM growth is the only signal that forces a single slot.
prepare_case oom-growth
set_signal oom-growth oom_before 1
set_signal oom-growth oom_after 2
run_fixture 0 oom-growth
assert_line "$output" 'status=RESOURCE_CONSTRAINED'
assert_line "$output" 'agent_slots=1'
assert_line "$output" 'heavy_command_slots=0'
assert_line "$output" 'reason=oom_growth'

# Detection failure is RESOURCE_UNKNOWN at the configured ceiling, not a
# fake shortage measurement.
prepare_case malformed
set_signal malformed total_bytes invalid
run_fixture 3 malformed
assert_line "$output" 'status=RESOURCE_UNKNOWN'
assert_line "$output" 'agent_slots=6'
assert_line "$output" 'concurrency=6'
assert_line "$output" 'spawn_authorized=read_only'

prepare_case malformed-ceiling
set_signal malformed-ceiling total_bytes invalid
run_fixture 3 malformed-ceiling HARNESS_MAX_THREADS=2
assert_line "$output" 'status=RESOURCE_UNKNOWN'
assert_line "$output" 'agent_slots=2'

# The degraded ceiling honors HARNESS_TASK_CAP too, not just max threads.
prepare_case malformed-task-cap
set_signal malformed-task-cap total_bytes invalid
run_fixture 3 malformed-task-cap HARNESS_TASK_CAP=2
assert_line "$output" 'status=RESOURCE_UNKNOWN'
assert_line "$output" 'agent_slots=2'

prepare_case windows windows
run_fixture 3 windows
assert_line "$output" 'status=RESOURCE_UNKNOWN'
assert_line "$output" 'agent_slots=6'

prepare_case cgroup-zero cgroup-zero
run_fixture 3 cgroup-zero
assert_line "$output" 'status=RESOURCE_UNKNOWN'
assert_line "$output" 'reason=malformed_cgroup_memory'

prepare_case stale
now="$(date +%s)"
set_signal stale captured_epoch "$((now - 601))"
run_fixture 3 stale
assert_line "$output" 'status=RESOURCE_STALE'
snapshot_age="$(printf '%s\n' "$output" | sed -n 's/^snapshot_age_seconds=//p')"
[ "$snapshot_age" -ge 601 ] || { echo "stale snapshot age was $snapshot_age" >&2; exit 1; }
assert_line "$output" 'agent_slots=0'
assert_line "$output" 'concurrency=0'
assert_line "$output" 'spawn_authorized=0'
assert_line "$output" 'heavy_command_slots=0'

prepare_case fresh wsl
run_fixture 0 fresh
assert_line "$output" 'platform=wsl'
assert_match "$output" '^snapshot_age_seconds=[0-2]$'

set +e
help_output="$($DETECTOR --help 2>&1)"
help_rc=$?
unknown_output="$($DETECTOR --unknown 2>&1)"
unknown_rc=$?
set -e
[ "$help_rc" -eq 0 ] || { echo "--help returned $help_rc" >&2; exit 1; }
[ "$unknown_rc" -eq 2 ] || { echo "unknown option returned $unknown_rc" >&2; exit 1; }
assert_line "$help_output" 'usage: detect_resources.sh [--fixture DIRECTORY | --system-root DIRECTORY]'
assert_line "$unknown_output" 'usage: detect_resources.sh [--fixture DIRECTORY | --system-root DIRECTORY]'

echo "Resource detector tests passed."
