#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime="${CONTAINER_RUNTIME:-docker}"
image="${VECTOR_IMAGE:-docker.io/timberio/vector:0.55.0-alpine}"

command -v "$runtime" >/dev/null 2>&1 || {
  echo "container runtime not found: $runtime" >&2
  exit 1
}

vector_run() {
  "$runtime" run --rm \
    -e VECTOR_ORG=sjtug \
    -e VECTOR_SERVER=test-edge \
    -v "$root_dir/vector/vector.yaml:/etc/vector/vector.yaml:ro" \
    -v "$root_dir/vector/vector-tests.yaml:/etc/vector/tests.yaml:ro" \
    -v "$root_dir/caddy/repositories.siyuan.csv:/etc/vector/repositories.csv:ro" \
    "$image" "$@"
}

vector_run validate --no-environment /etc/vector/vector.yaml
vector_run test /etc/vector/vector.yaml /etc/vector/tests.yaml
