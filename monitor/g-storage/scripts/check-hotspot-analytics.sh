#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUNTIME=${CONTAINER_RUNTIME:-docker}
VECTOR_IMAGE=${VECTOR_IMAGE:-docker.io/timberio/vector:0.55.0-alpine}
CLICKHOUSE_IMAGE=${CLICKHOUSE_IMAGE:-docker.io/clickhouse/clickhouse-server:26.3}
TMP_DIR=$(mktemp -d)
CLICKHOUSE_CONTAINER="mirror-hotspot-check-$$"
cleanup() {
  "$RUNTIME" rm -f "$CLICKHOUSE_CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

command -v "$RUNTIME" >/dev/null 2>&1 || {
  echo "container runtime not found: $RUNTIME" >&2
  exit 1
}

"$RUNTIME" run --rm \
  -e HOTSPOT_CLICKHOUSE_INGEST_PASSWORD=check-ingest-password \
  -e HOTSPOT_CLIENT_HASH_KEY=check-client-hash-key-that-is-long-enough \
  -v "$ROOT/config/vector.toml:/etc/vector/vector.toml:ro" \
  -v "$ROOT/config/vector-tests.yaml:/etc/vector/tests.yaml:ro" \
  "$VECTOR_IMAGE" validate --no-environment /etc/vector/vector.toml

"$RUNTIME" run --rm \
  -e HOTSPOT_CLICKHOUSE_INGEST_PASSWORD=check-ingest-password \
  -e HOTSPOT_CLIENT_HASH_KEY=check-client-hash-key-that-is-long-enough \
  -v "$ROOT/config/vector.toml:/etc/vector/vector.toml:ro" \
  -v "$ROOT/config/vector-tests.yaml:/etc/vector/tests.yaml:ro" \
  "$VECTOR_IMAGE" test /etc/vector/vector.toml /etc/vector/tests.yaml

shellcheck "$ROOT/scripts/run-vector.sh"
python3 -m json.tool \
  "$ROOT/grafana/dashboards/hotspot/mirror-hotspot-analytics.json" >/dev/null

"$RUNTIME" run -d --name "$CLICKHOUSE_CONTAINER" \
  -v "$ROOT/config/clickhouse/server.xml:/etc/clickhouse-server/config.d/hotspot.xml:ro" \
  -v "$ROOT/config/clickhouse/schema.sql:/docker-entrypoint-initdb.d/00-hotspot-schema.sql:ro" \
  "$CLICKHOUSE_IMAGE" >/dev/null

ready=false
for _attempt in $(seq 1 60); do
  if "$RUNTIME" exec "$CLICKHOUSE_CONTAINER" sh -c \
      'grep -q clickhouse /proc/1/comm && clickhouse-client --query="EXISTS hotspot.repo_5m_totals" | grep -qx 1' \
      >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [ "$ready" != true ]; then
  "$RUNTIME" logs "$CLICKHOUSE_CONTAINER" >&2 || true
  echo "temporary ClickHouse did not become ready" >&2
  exit 1
fi

"$RUNTIME" exec -i "$CLICKHOUSE_CONTAINER" clickhouse-client --query \
  'INSERT INTO hotspot.requests_raw FORMAT JSONEachRow' <<'EOF_EVENT'
{"event_time":"2099-01-02 03:04:05.000","event_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","org":"sjtug","server":"siyuan","http_host":"mirror.sjtu.edu.cn","repo":"archlinux","path":"/archlinux/file.pkg","request_method":"GET","status":206,"status_class":"2xx","body_bytes_sent":1024,"request_time":0.25,"upstream_response_time":0.0,"content_type":"application/octet-stream","proxied":0,"range_requested":1,"client_key":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","referer_host":"","ua_browser":"curl","ua_os":"Other","ua_device_type":"Other","client_country_code":"","client_region":"","client_asn":0,"is_bot":0,"request_id":"fixture"}
EOF_EVENT

test "$("$RUNTIME" exec "$CLICKHOUSE_CONTAINER" clickhouse-client --query \
  "SELECT sum(requests) = 1 AND sum(bytes) = 1024 FROM hotspot.repo_5m_totals")" = 1
test "$("$RUNTIME" exec "$CLICKHOUSE_CONTAINER" clickhouse-client --query \
  "SELECT sum(requests) = 1 AND sum(range_requests) = 1 FROM hotspot.object_1h_totals")" = 1

HOTSPOT_CHECK_ROOT="$ROOT" python3 - <<'PY' >"$TMP_DIR/dashboard-queries.sql"
import json
import os
from pathlib import Path

root = Path(os.environ["HOTSPOT_CHECK_ROOT"])
dashboard = json.loads(
    (root / "grafana/dashboards/hotspot/mirror-hotspot-analytics.json").read_text()
)
queries = [
    target["rawSql"]
    for panel in dashboard["panels"]
    for target in panel.get("targets", [])
]
queries.extend(variable["query"] for variable in dashboard["templating"]["list"])
for query in queries:
    query = query.replace(
        "$__timeFilter(bucket)", "bucket >= now() - INTERVAL 1 DAY"
    )
    query = query.replace(
        "$__conditionalAll(server IN (${server:singlequote}), $server)", "1"
    )
    query = query.replace(
        "$__conditionalAll(repo IN (${repo:singlequote}), $repo)", "1"
    )
    query = query.replace(
        "$__conditionalAll(current.repo IN (${repo:singlequote}), $repo)", "1"
    )
    print(query.rstrip().rstrip(";") + " FORMAT Null;")
PY
"$RUNTIME" exec -i "$CLICKHOUSE_CONTAINER" \
  clickhouse-client --multiquery <"$TMP_DIR/dashboard-queries.sql"

echo "hotspot analytics configuration validated"
