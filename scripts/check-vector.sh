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
    -v "$root_dir/vector/central-sink.yaml:/etc/vector/central-sink.yaml:ro" \
    -v "$root_dir/vector/run.sh:/etc/vector/run.sh:ro" \
    -v "$root_dir/vector/vector-tests.yaml:/etc/vector/tests.yaml:ro" \
    -v "$root_dir/caddy/repositories.siyuan.csv:/etc/vector/repositories.csv:ro" \
    "$image" "$@"
}

vector_run validate --no-environment \
  /etc/vector/vector.yaml /etc/vector/central-sink.yaml
vector_run test /etc/vector/vector.yaml /etc/vector/tests.yaml
shellcheck "$root_dir/vector/run.sh"

# Missing optional central-forwarding credentials must not take down the local
# Prometheus exporter. A five-second timeout means Vector stayed running.
startup_log=$(mktemp)
cleanup() { rm -f "$startup_log"; }
trap cleanup EXIT
set +e
timeout 5 "$runtime" run --rm \
  -e VECTOR_ORG=sjtug \
  -e VECTOR_SERVER=test-edge \
  -v "$root_dir/vector/vector.yaml:/etc/vector/vector.yaml:ro" \
  -v "$root_dir/vector/run.sh:/etc/vector/run.sh:ro" \
  -v "$root_dir/caddy/repositories.siyuan.csv:/etc/vector/repositories.csv:ro" \
  --entrypoint /etc/vector/run.sh \
  "$image" >"$startup_log" 2>&1
startup_status=$?
set -e
if [ "$startup_status" -ne 124 ]; then
  cat "$startup_log" >&2
  echo "Vector did not remain active without central-forwarding TLS files" >&2
  exit 1
fi
grep -Fq 'MirrorZ forwarding disabled' "$startup_log"
grep -Fq 'Vector has started' "$startup_log"
