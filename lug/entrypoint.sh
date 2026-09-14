#!/usr/bin/env bash
set -uo pipefail

readonly cgroup_root=/sys/fs/cgroup
readonly supervisor_cgroup="$cgroup_root/supervisor"
readonly jobs_cgroup="$cgroup_root/jobs"
readonly lug_bin="${LUG_BIN:-/app/lug}"

prepare_cgroup_delegation() {
  [[ -f "$cgroup_root/cgroup.controllers" ]] || return 1
  mount -o remount,rw "$cgroup_root" || return 1
  mkdir -p "$supervisor_cgroup" || return 1

  # Keep the cgroup namespace root free of processes so v2 controllers can be
  # enabled for children. At container startup this normally moves only PID 1.
  local pid
  while read -r pid; do
    [[ -n "$pid" ]] || continue
    printf '%s' "$pid" >"$supervisor_cgroup/cgroup.procs" || return 1
  done <"$cgroup_root/cgroup.procs"

  printf '%s' '+memory +pids' >"$cgroup_root/cgroup.subtree_control" || return 1
  mkdir -p "$jobs_cgroup" || return 1
  printf '%s' '+memory +pids' >"$jobs_cgroup/cgroup.subtree_control" || return 1
  export LUG_CGROUP_JOBS_ROOT="$jobs_cgroup"
}

if prepare_cgroup_delegation; then
  printf 'lug-entrypoint: delegated cgroup jobs root at %s\n' "$jobs_cgroup" >&2
else
  printf 'lug-entrypoint: unable to delegate cgroups; using process-group fallback\n' >&2
fi

# SYS_ADMIN is needed only for the private cgroupfs remount and delegation
# above. Remove it from the bounding set before lug or any worker is executed.
exec setpriv \
  --bounding-set=-sys_admin \
  --inh-caps=-all \
  --ambient-caps=-all \
  --no-new-privs \
  -- "$lug_bin" "$@"
