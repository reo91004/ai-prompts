#!/usr/bin/env bash
set -u

fixture_dir=""
system_root=""
if [ "$#" -gt 0 ]; then
  if [ "$#" -eq 1 ] && [ "$1" = "--help" ]; then
    echo "usage: detect_resources.sh [--fixture DIRECTORY | --system-root DIRECTORY]"
    exit 0
  fi
  if [ "$#" -ne 2 ]; then
    echo "usage: detect_resources.sh [--fixture DIRECTORY | --system-root DIRECTORY]" >&2
    exit 2
  fi
  case $1 in
    --fixture) fixture_dir=$2 ;;
    --system-root) system_root=$2 ;;
    *)
      echo "usage: detect_resources.sh [--fixture DIRECTORY | --system-root DIRECTORY]" >&2
      exit 2
      ;;
  esac
  input_dir=${fixture_dir:-$system_root}
  if [ ! -d "$input_dir" ] || [ -L "$input_dir" ]; then
    echo "input directory is unavailable or unsafe: $input_dir" >&2
    exit 2
  fi
  input_dir=$(cd -P "$input_dir" 2>/dev/null && pwd) || exit 2
  if [ -n "$fixture_dir" ]; then fixture_dir=$input_dir; else system_root=$input_dir; fi
fi

is_uint() {
  case ${1-} in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

read_fixture() {
  if [ -f "$fixture_dir/$1" ]; then
    sed -n '1p' "$fixture_dir/$1"
  fi
}

rooted_path() {
  case $1 in
    /*/../*|*/..|/*/./*|*/.|*//*|*\\*) return 2 ;;
    /*) printf '%s%s\n' "$system_root" "$1" ;;
    *) return 2 ;;
  esac
}

min_value() {
  if [ "$1" -lt "$2" ]; then
    echo "$1"
  else
    echo "$2"
  fi
}

# Degraded detection is not evidence of resource shortage: report the
# configured ceiling, keep one heavy slot, and exit 3 so callers can see the
# structured status instead of a fake concurrency measurement.
emit_degraded() {
  echo "status=$1"
  echo "platform=${platform:-unknown}"
  echo "captured_epoch=${captured_epoch:-unavailable}"
  echo "snapshot_age_seconds=${snapshot_age_seconds:-unavailable}"
  echo "cgroup_v2=${cgroup_v2_state:-not_applicable}"
  echo "cgroup_path=${cgroup_path:-unavailable}"
  echo "agent_slots=$ceiling"
  echo "writer_slots=1"
  echo "heavy_command_slots=1"
  echo "concurrency=$ceiling"
  echo "warnings=none"
  echo "reason=$2"
  exit 3
}

ceiling=${HARNESS_MAX_THREADS:-6}
if ! is_uint "$ceiling" || [ "$ceiling" -eq 0 ] || [ "$ceiling" -gt 6 ]; then
  ceiling=6
fi

cpuset_count() {
  echo "$1" | awk -F, '
    function valid_int(value) { return value ~ /^[0-9]+$/ }
    {
      total = 0
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+-[0-9]+$/) {
          split($i, range, "-")
          if (range[2] < range[1]) exit 2
          total += range[2] - range[1] + 1
        } else if (valid_int($i)) {
          total++
        } else {
          exit 2
        }
      }
      if (total < 1) exit 2
      print total
    }'
}

bytes_from_unit() {
  echo "$1" | awk '
    /^[0-9]+([.][0-9]+)?[KMGT]$/ {
      unit = substr($0, length($0), 1)
      value = substr($0, 1, length($0) - 1)
      multiplier = 1
      if (unit == "K") multiplier = 1024
      if (unit == "M") multiplier = 1024 * 1024
      if (unit == "G") multiplier = 1024 * 1024 * 1024
      if (unit == "T") multiplier = 1024 * 1024 * 1024 * 1024
      printf "%.0f\n", value * multiplier
      found = 1
    }
    END { if (!found) exit 2 }'
}

valid_abs_path() {
  case ${1-} in
    ''|[!/]*) return 1 ;;
    /*/../*|*/..|/*/./*|*/.|*//*|*\\*|*' '*) return 1 ;;
    *) return 0 ;;
  esac
}

path_within() {
  if [ "$2" = "/" ] || [ "$1" = "$2" ]; then
    return 0
  fi
  case $1 in
    "$2"/*) return 0 ;;
    *) return 1 ;;
  esac
}

safe_system_dir() {
  local resolved
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  resolved=$(cd -P "$1" 2>/dev/null && pwd) || return 1
  [ -z "$system_root" ] || path_within "$resolved" "$system_root"
}

safe_cgroup_file() {
  local parent
  [ -e "$1" ] || return 1
  [ -f "$1" ] && [ ! -L "$1" ] || return 2
  parent=${1%/*}
  safe_system_dir "$parent" || return 2
}

discover_cgroup_v2() {
  local cgroup_file mountinfo_file cgroup_relative mount_record
  local mount_root mount_point suffix target current parent host_target

  cgroup_file=$(rooted_path /proc/self/cgroup) || { collector_error=unsafe_cgroup_proc_path; return; }
  mountinfo_file=$(rooted_path /proc/self/mountinfo) || { collector_error=unsafe_cgroup_proc_path; return; }
  if [ -L "$cgroup_file" ] || [ -L "$mountinfo_file" ]; then
    collector_error=unsafe_cgroup_proc_file
    return
  fi
  if [ ! -f "$cgroup_file" ] || [ ! -f "$mountinfo_file" ]; then
    cgroup_v2_state=unavailable
    return
  fi
  cgroup_relative=$(awk -F: '$1 == "0" && $2 == "" { print $3; count++ } END { if (count != 1) exit 2 }' "$cgroup_file" 2>/dev/null || true)
  if [ -z "$cgroup_relative" ]; then
    cgroup_v2_state=unavailable
    return
  fi
  if ! valid_abs_path "$cgroup_relative"; then
    collector_error=unsafe_cgroup_membership_path
    return
  fi
  mount_record=$(awk -v cg="$cgroup_relative" '
    index($0, " - cgroup2 ") {
      root = $4
      mount = $5
      matches = (root == "/" || cg == root || index(cg, root "/") == 1)
      if (matches && length(root) > best_length) {
        best_length = length(root)
        best_root = root
        best_mount = mount
      }
    }
    END {
      if (!best_length) exit 2
      print best_root "|" best_mount
    }' "$mountinfo_file" 2>/dev/null || true)
  if [ -z "$mount_record" ]; then
    cgroup_v2_state=unavailable
    return
  fi
  mount_root=${mount_record%%|*}
  mount_point=${mount_record#*|}
  if ! valid_abs_path "$mount_root" || ! valid_abs_path "$mount_point" || ! path_within "$cgroup_relative" "$mount_root"; then
    collector_error=unsafe_cgroup_mount_path
    return
  fi
  if [ "$cgroup_relative" = "$mount_root" ]; then
    suffix=""
  elif [ "$mount_root" = "/" ]; then
    suffix=$cgroup_relative
  else
    suffix=${cgroup_relative#"$mount_root"}
  fi
  if [ "$mount_point" = "/" ]; then
    target=${suffix:-/}
  else
    target="$mount_point$suffix"
  fi
  if ! valid_abs_path "$target" || ! path_within "$target" "$mount_point"; then
    collector_error=unsafe_cgroup_resolved_path
    return
  fi
  host_target=$(rooted_path "$target") || { collector_error=unsafe_cgroup_resolved_path; return; }
  if ! safe_system_dir "$host_target"; then
    collector_error=missing_process_cgroup
    return
  fi

  cgroup_dirs=""
  current=$target
  while :; do
    cgroup_dirs="${cgroup_dirs}${cgroup_dirs:+
}$current"
    [ "$current" = "$mount_point" ] && break
    parent=${current%/*}
    [ -n "$parent" ] || parent=/
    if [ "$parent" = "$current" ] || ! path_within "$parent" "$mount_point"; then
      collector_error=unsafe_cgroup_ancestor_path
      return
    fi
    current=$parent
  done
  cgroup_v2_state=detected
  cgroup_path=$target
}

collect_cgroup_limits() {
  local old_ifs dir host_dir value current available quota period quota_cpu count field_count file_rc
  local memory_limit="" available_limit="" cpu_limit="" cpuset_limit="" cpuset_limit_count=""

  [ "$cgroup_v2_state" = "detected" ] || return
  old_ifs=$IFS
  IFS='
'
  for dir in $cgroup_dirs; do
    host_dir=$(rooted_path "$dir") || { collector_error=unsafe_cgroup_ancestor_path; break; }
    if safe_cgroup_file "$host_dir/memory.max"; then
      value=$(sed -n '1p' "$host_dir/memory.max" 2>/dev/null || true)
      if [ "$value" != "max" ]; then
        if ! safe_cgroup_file "$host_dir/memory.current"; then
          collector_error=malformed_cgroup_memory
          break
        fi
        current=$(sed -n '1p' "$host_dir/memory.current" 2>/dev/null || true)
        if ! is_uint "$value" || ! is_uint "$current" || [ "$value" -eq 0 ]; then
          collector_error=malformed_cgroup_memory
          break
        fi
        if [ "$current" -ge "$value" ]; then available=0; else available=$((value - current)); fi
        if [ -z "$memory_limit" ] || [ "$value" -lt "$memory_limit" ]; then memory_limit=$value; fi
        if [ -z "$available_limit" ] || [ "$available" -lt "$available_limit" ]; then available_limit=$available; fi
      fi
    else
      file_rc=$?
      if [ "$file_rc" -eq 2 ]; then collector_error=unsafe_cgroup_file; break; fi
    fi
    if safe_cgroup_file "$host_dir/cpu.max"; then
      value=$(sed -n '1p' "$host_dir/cpu.max" 2>/dev/null || true)
      field_count=$(printf '%s\n' "$value" | awk '{ print NF }')
      quota=${value%% *}
      period=${value#* }
      if [ "$field_count" -ne 2 ] || ! is_uint "$period" || [ "$period" -eq 0 ]; then
        collector_error=malformed_cgroup_cpu
        break
      fi
      if [ "$quota" != "max" ]; then
        if ! is_uint "$quota"; then
          collector_error=malformed_cgroup_cpu
          break
        fi
        quota_cpu=$((quota / period))
        [ "$quota_cpu" -ge 1 ] || quota_cpu=1
        if [ -z "$cpu_limit" ] || [ "$quota_cpu" -lt "$cpu_limit" ]; then cpu_limit=$quota_cpu; fi
      fi
    else
      file_rc=$?
      if [ "$file_rc" -eq 2 ]; then collector_error=unsafe_cgroup_file; break; fi
    fi
    if safe_cgroup_file "$host_dir/cpuset.cpus.effective"; then
      value=$(sed -n '1p' "$host_dir/cpuset.cpus.effective" 2>/dev/null || true)
      if [ -n "$value" ]; then
        count=$(cpuset_count "$value" || true)
        if ! is_uint "$count" || [ "$count" -eq 0 ]; then
          collector_error=malformed_cpuset
          break
        fi
        if [ -z "$cpuset_limit_count" ] || [ "$count" -lt "$cpuset_limit_count" ]; then
          cpuset_limit=$value
          cpuset_limit_count=$count
        fi
      fi
    else
      file_rc=$?
      if [ "$file_rc" -eq 2 ]; then collector_error=unsafe_cgroup_file; break; fi
    fi
  done
  IFS=$old_ifs
  [ -z "$collector_error" ] || return
  if [ -n "$memory_limit" ]; then
    cgroup_memory_max=$memory_limit
    cgroup_memory_current=$((memory_limit - available_limit))
  fi
  if [ -n "$cpu_limit" ]; then
    cgroup_cpu_quota=$cpu_limit
    cgroup_cpu_period=1
  fi
  cpuset_cpus=$cpuset_limit
}

collect_cgroup_oom() {
  local phase="$1"
  local old_ifs dir host_dir value event_rc file_rc total=0

  [ "$cgroup_v2_state" = "detected" ] || return
  old_ifs=$IFS
  IFS='
'
  for dir in $cgroup_dirs; do
    host_dir=$(rooted_path "$dir") || { collector_error=unsafe_cgroup_ancestor_path; break; }
    if safe_cgroup_file "$host_dir/memory.events"; then
      value=$(awk '
        $1 == "oom" {
          oom_count++
          if (NF != 2 || $2 !~ /^[0-9]+$/) invalid = 1
          oom = $2
        }
        $1 == "oom_kill" {
          oom_kill_count++
          if (NF != 2 || $2 !~ /^[0-9]+$/) invalid = 1
        }
        END {
          if (invalid || oom_count != 1 || oom_kill_count != 1) exit 2
          print oom
        }' "$host_dir/memory.events" 2>/dev/null)
      event_rc=$?
      if [ "$event_rc" -ne 0 ] || ! is_uint "$value"; then
        collector_error=malformed_cgroup_events
        break
      fi
      total=$((total + value))
    else
      file_rc=$?
      if [ "$file_rc" -eq 2 ]; then collector_error=unsafe_cgroup_file; break; fi
    fi
  done
  IFS=$old_ifs
  if [ "$phase" = "before" ]; then oom_before=$total; else oom_after=$total; fi
}

status="OK"
reasons="none"
platform=""
total_bytes=""
available_bytes=""
cpu_count=""
swap_total_bytes=0
swap_free_bytes=0
swapout_before=0
swapout_after=0
oom_before=0
oom_after=0
psi_text=""
cgroup_memory_max=""
cgroup_memory_current=""
cgroup_cpu_quota=""
cgroup_cpu_period=""
cpuset_cpus=""
captured_epoch=""
cgroup_v2_state=not_applicable
cgroup_path=unavailable
cgroup_dirs=""
collector_error=""

if [ -n "$fixture_dir" ]; then
  platform=$(read_fixture platform)
  captured_epoch=$(read_fixture captured_epoch)
  total_bytes=$(read_fixture total_bytes)
  available_bytes=$(read_fixture available_bytes)
  cpu_count=$(read_fixture cpu_count)
  swap_total_bytes=$(read_fixture swap_total_bytes)
  swap_free_bytes=$(read_fixture swap_free_bytes)
  swapout_before=$(read_fixture swapout_before)
  swapout_after=$(read_fixture swapout_after)
  oom_before=$(read_fixture oom_before)
  oom_after=$(read_fixture oom_after)
  psi_text=$(read_fixture psi)
  cgroup_memory_max=$(read_fixture cgroup_memory_max)
  cgroup_memory_current=$(read_fixture cgroup_memory_current)
  cgroup_cpu_quota=$(read_fixture cgroup_cpu_quota)
  cgroup_cpu_period=$(read_fixture cgroup_cpu_period)
  cpuset_cpus=$(read_fixture cpuset_cpus)
  swap_total_bytes=${swap_total_bytes:-0}
  swap_free_bytes=${swap_free_bytes:-0}
  swapout_before=${swapout_before:-0}
  swapout_after=${swapout_after:-0}
  oom_before=${oom_before:-0}
  oom_after=${oom_after:-0}
else
  if [ -n "$system_root" ]; then
    detected_platform=Linux
  else
    detected_platform=$(uname -s 2>/dev/null || true)
  fi
  case $detected_platform in
    Darwin)
      platform=macos
      total_bytes=$(sysctl -n hw.memsize 2>/dev/null || true)
      cpu_count=$(sysctl -n hw.logicalcpu 2>/dev/null || true)
      memory_free_pct=$(memory_pressure 2>/dev/null | awk '/System-wide memory free percentage:/ { gsub(/%/, "", $5); print $5; found = 1 } END { if (!found) exit 2 }' || true)
      if is_uint "$total_bytes" && is_uint "$memory_free_pct"; then
        available_bytes=$((total_bytes * memory_free_pct / 100))
      fi
      swap_line=$(sysctl -n vm.swapusage 2>/dev/null || true)
      swap_total_raw=$(echo "$swap_line" | awk '{ for (i = 1; i <= NF; i++) if ($i == "total" && $(i + 1) == "=") { print $(i + 2); exit } }')
      swap_free_raw=$(echo "$swap_line" | awk '{ for (i = 1; i <= NF; i++) if ($i == "free" && $(i + 1) == "=") { print $(i + 2); exit } }')
      if [ -n "$swap_total_raw" ] && [ -n "$swap_free_raw" ]; then
        swap_total_bytes=$(bytes_from_unit "$swap_total_raw" || echo 0)
        swap_free_bytes=$(bytes_from_unit "$swap_free_raw" || echo 0)
      fi
      swapout_before=$(vm_stat 2>/dev/null | awk '/Swapouts/ { gsub(/\./, "", $2); print $2 }' || echo 0)
      sleep 1
      swapout_after=$(vm_stat 2>/dev/null | awk '/Swapouts/ { gsub(/\./, "", $2); print $2 }' || echo 0)
      swapout_before=${swapout_before:-0}
      swapout_after=${swapout_after:-0}
      ;;
    Linux)
      platform=linux
      proc_osrelease=$(rooted_path /proc/sys/kernel/osrelease)
      proc_version=$(rooted_path /proc/version)
      proc_meminfo=$(rooted_path /proc/meminfo)
      proc_vmstat=$(rooted_path /proc/vmstat)
      proc_pressure=$(rooted_path /proc/pressure/memory)
      if grep -Eqi 'microsoft|wsl' "$proc_osrelease" "$proc_version" 2>/dev/null; then
        platform=wsl
      fi
      total_kib=$(awk '/^MemTotal:/ { print $2 }' "$proc_meminfo" 2>/dev/null || true)
      available_kib=$(awk '/^MemAvailable:/ { print $2 }' "$proc_meminfo" 2>/dev/null || true)
      if is_uint "$total_kib"; then total_bytes=$((total_kib * 1024)); fi
      if is_uint "$available_kib"; then available_bytes=$((available_kib * 1024)); fi
      if [ -n "$system_root" ]; then
        proc_cpuinfo=$(rooted_path /proc/cpuinfo)
        cpu_count=$(awk '/^processor[[:space:]]*:/ { count++ } END { if (count) print count }' "$proc_cpuinfo" 2>/dev/null || true)
      else
        cpu_count=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
      fi
      swap_total_kib=$(awk '/^SwapTotal:/ { print $2 }' "$proc_meminfo" 2>/dev/null || true)
      swap_free_kib=$(awk '/^SwapFree:/ { print $2 }' "$proc_meminfo" 2>/dev/null || true)
      if is_uint "$swap_total_kib"; then swap_total_bytes=$((swap_total_kib * 1024)); fi
      if is_uint "$swap_free_kib"; then swap_free_bytes=$((swap_free_kib * 1024)); fi
      psi_text=$(sed -n '1,2p' "$proc_pressure" 2>/dev/null || true)
      swapout_before=$(awk '/^pswpout / { print $2 }' "$proc_vmstat" 2>/dev/null || echo 0)
      discover_cgroup_v2
      collect_cgroup_limits
      collect_cgroup_oom before
      sleep 1
      swapout_after=$(awk '/^pswpout / { print $2 }' "$proc_vmstat" 2>/dev/null || echo 0)
      collect_cgroup_oom after
      swapout_before=${swapout_before:-0}
      swapout_after=${swapout_after:-0}
      oom_before=${oom_before:-0}
      oom_after=${oom_after:-0}
      ;;
    *)
      emit_degraded RESOURCE_UNKNOWN unsupported_platform
      ;;
  esac
  captured_epoch=$(date +%s 2>/dev/null || true)
fi

if [ -n "$collector_error" ]; then
  emit_degraded RESOURCE_UNKNOWN "$collector_error"
fi

case $platform in
  macos|linux|wsl) ;;
  *)
    emit_degraded RESOURCE_UNKNOWN unsupported_platform
    ;;
esac

current_epoch=$(date +%s 2>/dev/null || true)
if ! is_uint "$captured_epoch" || ! is_uint "$current_epoch" || [ "$captured_epoch" -gt "$current_epoch" ]; then
  emit_degraded RESOURCE_UNKNOWN malformed_capture_time
fi
snapshot_age_seconds=$((current_epoch - captured_epoch))
if [ "$snapshot_age_seconds" -gt 600 ]; then
  emit_degraded RESOURCE_STALE stale_snapshot
fi

if ! is_uint "$total_bytes" || ! is_uint "$available_bytes" || ! is_uint "$cpu_count" || [ "$total_bytes" -eq 0 ] || [ "$cpu_count" -eq 0 ]; then
  emit_degraded RESOURCE_UNKNOWN malformed_primary_signal
fi

if [ "$available_bytes" -gt "$total_bytes" ]; then
  emit_degraded RESOURCE_UNKNOWN inconsistent_memory_signal
fi

if ! is_uint "$swap_total_bytes" || ! is_uint "$swap_free_bytes" || ! is_uint "$swapout_before" || ! is_uint "$swapout_after" || ! is_uint "$oom_before" || ! is_uint "$oom_after"; then
  emit_degraded RESOURCE_UNKNOWN malformed_pressure_signal
fi

if [ "$swap_total_bytes" -eq 0 ] && [ "$swap_free_bytes" -ne 0 ] || [ "$swap_total_bytes" -gt 0 ] && [ "$swap_free_bytes" -gt "$swap_total_bytes" ]; then
  emit_degraded RESOURCE_UNKNOWN inconsistent_swap_signal
fi

effective_total=$total_bytes
effective_available=$available_bytes
if [ -n "$cgroup_memory_max" ] && [ "$cgroup_memory_max" != "max" ]; then
  if ! is_uint "$cgroup_memory_max" || ! is_uint "$cgroup_memory_current" || [ "$cgroup_memory_max" -eq 0 ]; then
    emit_degraded RESOURCE_UNKNOWN malformed_cgroup_memory
  fi
  if [ "$cgroup_memory_max" -lt "$effective_total" ]; then
    effective_total=$cgroup_memory_max
    if [ "$cgroup_memory_current" -ge "$cgroup_memory_max" ]; then
      effective_available=0
    else
      cgroup_available=$((cgroup_memory_max - cgroup_memory_current))
      effective_available=$(min_value "$effective_available" "$cgroup_available")
    fi
  fi
fi

effective_cpu=$cpu_count
if [ -n "$cgroup_cpu_quota" ] && [ "$cgroup_cpu_quota" != "max" ]; then
  if ! is_uint "$cgroup_cpu_quota" || ! is_uint "$cgroup_cpu_period" || [ "$cgroup_cpu_period" -eq 0 ]; then
    emit_degraded RESOURCE_UNKNOWN malformed_cgroup_cpu
  fi
  quota_cpu=$((cgroup_cpu_quota / cgroup_cpu_period))
  if [ "$quota_cpu" -lt 1 ]; then quota_cpu=1; fi
  effective_cpu=$(min_value "$effective_cpu" "$quota_cpu")
fi
if [ -n "$cpuset_cpus" ]; then
  cpuset_cpu=$(cpuset_count "$cpuset_cpus" || true)
  if ! is_uint "$cpuset_cpu" || [ "$cpuset_cpu" -eq 0 ]; then
    emit_degraded RESOURCE_UNKNOWN malformed_cpuset
  fi
  effective_cpu=$(min_value "$effective_cpu" "$cpuset_cpu")
fi

available_pct=$((effective_available * 100 / effective_total))
# One agent slot per 2 GiB of absolute headroom, clamped to 1-6. The percent
# value stays diagnostic: a large host with a small free ratio can still hold
# several agents, and a tiny host with a large ratio cannot.
memory_bucket=$((effective_available / 2147483648))
if [ "$memory_bucket" -lt 1 ]; then memory_bucket=1; fi
if [ "$memory_bucket" -gt 6 ]; then memory_bucket=6; fi

cpu_cap=$((effective_cpu / 2))
if [ "$cpu_cap" -lt 1 ]; then cpu_cap=1; fi
max_threads=${HARNESS_MAX_THREADS:-6}
task_cap=${HARNESS_TASK_CAP:-6}
if ! is_uint "$max_threads" || ! is_uint "$task_cap" || [ "$max_threads" -eq 0 ] || [ "$task_cap" -eq 0 ]; then
  emit_degraded RESOURCE_UNKNOWN malformed_concurrency_cap
fi
if [ "$max_threads" -gt 6 ]; then max_threads=6; fi
if [ "$task_cap" -gt 6 ]; then task_cap=6; fi
agent_slots=$(min_value "$memory_bucket" "$cpu_cap")
agent_slots=$(min_value "$agent_slots" "$max_threads")
agent_slots=$(min_value "$agent_slots" "$task_cap")
heavy_command_slots=1

# Warnings never serialize agents; only sampled pressure growth or critical
# PSI does, and OOM growth is the only signal that forces one slot.
warnings=""
if [ "$swap_total_bytes" -gt 0 ]; then
  swap_free_pct=$((swap_free_bytes * 100 / swap_total_bytes))
  if [ "$swap_free_pct" -lt 10 ]; then warnings="low_swap"; fi
else
  swap_free_pct="not_configured"
fi
if [ "$available_pct" -lt 10 ]; then warnings="${warnings:+$warnings,}low_memory_pct"; fi

constrained=""
if [ "$swapout_after" -gt "$swapout_before" ]; then constrained="swapout_growth"; fi
if [ "$oom_after" -gt "$oom_before" ]; then constrained="${constrained:+$constrained,}oom_growth"; fi
if [ -n "$psi_text" ]; then
  if echo "$psi_text" | awk '
    /^(full|some) / {
      found = 1
      line_has_avg10 = 0
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^avg10=[0-9]+([.][0-9]+)?$/) {
          line_has_avg10 = 1
          split($i, value, "=")
          if ($1 == "full" && value[2] + 0 >= 1.00) critical = 1
          if ($1 == "some" && value[2] + 0 >= 20.00) critical = 1
        }
      }
      if (!line_has_avg10) invalid = 1
    }
    END {
      if (!found || invalid) exit 2
      if (critical) exit 3
      exit 0
    }'; then
    :
  else
    psi_code=$?
    if [ "$psi_code" -eq 3 ]; then
      constrained="${constrained:+$constrained,}critical_psi"
    else
      emit_degraded RESOURCE_UNKNOWN malformed_psi
    fi
  fi
fi
if [ -n "$constrained" ]; then
  status="RESOURCE_CONSTRAINED"
  reasons=$constrained
  heavy_command_slots=0
  case ",$constrained," in
    *,oom_growth,*)
      agent_slots=1
      ;;
    *)
      agent_slots=$((agent_slots - 1))
      if [ "$agent_slots" -lt 1 ]; then agent_slots=1; fi
      ;;
  esac
fi
if [ -z "$warnings" ]; then warnings="none"; fi

echo "status=$status"
echo "platform=$platform"
echo "captured_epoch=$captured_epoch"
echo "snapshot_age_seconds=$snapshot_age_seconds"
echo "effective_total_bytes=$effective_total"
echo "effective_available_bytes=$effective_available"
echo "available_pct=$available_pct"
echo "effective_cpu=$effective_cpu"
echo "memory_bucket=$memory_bucket"
echo "cpu_cap=$cpu_cap"
echo "max_threads=$max_threads"
echo "task_cap=$task_cap"
echo "swap_free_pct=$swap_free_pct"
echo "cgroup_v2=$cgroup_v2_state"
echo "cgroup_path=$cgroup_path"
echo "agent_slots=$agent_slots"
echo "writer_slots=1"
echo "heavy_command_slots=$heavy_command_slots"
echo "concurrency=$agent_slots"
echo "warnings=$warnings"
echo "reason=$reasons"
