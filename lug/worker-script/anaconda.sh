#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

phase_retry="${LUG_anaconda_phase_retry:-3}"
phase_retry_interval="${LUG_anaconda_phase_retry_interval:-3600}"

if [[ ! "$phase_retry" =~ ^[1-9][0-9]*$ ]]; then
  printf 'invalid LUG_anaconda_phase_retry: %s\n' "$phase_retry" >&2
  exit 2
fi
if [[ ! "$phase_retry_interval" =~ ^[0-9]+$ ]]; then
  printf 'invalid LUG_anaconda_phase_retry_interval: %s\n' "$phase_retry_interval" >&2
  exit 2
fi

run_phase() {
  local name="$1"
  local prefix="$2"
  local config="$3"
  shift 3

  local attempt status
  for ((attempt = 1; attempt <= phase_retry; attempt++)); do
    printf 'anaconda phase %s: attempt %d/%d\n' "$name" "$attempt" "$phase_retry" >&2
    if "$DIR/mirror-clone-v2.sh" \
      --target-type s3 \
      --s3-prefix "$prefix" \
      "$@" conda "$config"; then
      return 0
    else
      status=$?
    fi

    if ((attempt == phase_retry)); then
      return "$status"
    fi
    printf 'anaconda phase %s failed (exit %d); retrying in %ss\n' \
      "$name" "$status" "$phase_retry_interval" >&2
    sleep "$phase_retry_interval"
  done
}

# Keep retries inside each independent target prefix. In particular, a cloud
# failure must not replay a successful pkgs phase and immediately overwrite
# metadata that jCloud still has temporarily locked.
run_phase pkgs anaconda/pkgs "$DIR/conda.pkgs.yaml" "$@"
run_phase cloud anaconda/cloud "$DIR/conda.cloud.yaml" "$@"
