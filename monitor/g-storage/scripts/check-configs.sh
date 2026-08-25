#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(mktemp -d)
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

tar -C "$ROOT" \
  --exclude='./.env' \
  --exclude='./bot.env' \
  --exclude='./runtime' \
  --exclude='./.backup' \
  --exclude='./docker-compose.override.yml' \
  --exclude='./xray/config.json' \
  --exclude='./xray/dat' \
  --exclude='*.bak' \
  --exclude='*.swp' \
  --exclude='*.swo' \
  -cf - . | tar -C "$WORK_DIR" -xf -
chmod -R u+w "$WORK_DIR"
cp "$WORK_DIR/.env.example" "$WORK_DIR/.env"
cp "$WORK_DIR/xray/config.example.json" "$WORK_DIR/xray/config.json"

cd "$WORK_DIR"
if python3 ./scripts/render-monitor-configs.py >/dev/null 2>&1; then
  echo "Example credentials unexpectedly passed renderer validation" >&2
  exit 1
fi

CHECK_ENV=(
  GITHUB_CLIENT_ID=check-client-id
  GITHUB_CLIENT_SECRET=check-client-secret
  MONITOR_USERNAME=check-user
  MONITOR_PASSWORD=check-only-secret
)
env "${CHECK_ENV[@]}" python3 ./scripts/render-monitor-configs.py
env "${CHECK_ENV[@]}" python3 ./scripts/render-prometheus-config.py

if command -v nerdctl >/dev/null 2>&1 && nerdctl compose version >/dev/null 2>&1; then
  env "${CHECK_ENV[@]}" nerdctl \
    --address "${CONTAINERD_ADDRESS:-/run/containerd/containerd.sock}" \
    --namespace "${CONTAINERD_NAMESPACE:-default}" compose \
    --project-name docker-prometheus-grafana \
    --project-directory "$WORK_DIR" -f "$WORK_DIR/docker-compose.yml" config \
    >effective-compose.yml
elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  env "${CHECK_ENV[@]}" docker compose --project-name docker-prometheus-grafana \
    --project-directory "$WORK_DIR" -f "$WORK_DIR/docker-compose.yml" config \
    >effective-compose.yml
else
  echo "nerdctl compose and docker compose not found; skipping Compose model validation" >&2
fi

if [ -f effective-compose.yml ]; then
  if grep -Fq 'check-client-secret' effective-compose.yml; then
    echo "GitHub client secret was embedded in the Compose model" >&2
    exit 1
  fi
fi

if grep -q 'check-only-secret' runtime/*.yml; then
  echo "Monitor password was embedded in generated configuration" >&2
  exit 1
fi
grep -Fqx 'check-client-secret' runtime/github_client_secret
grep -Fq "client_secret = \$__file{/run/secrets/github_client_secret}" grafana/grafana.ini

if [ "$(grep -c '^    honor_labels: true$' runtime/prometheus.yml || true)" -ne 2 ]; then
  echo "node-exporter and Caddy scrapes must preserve their sample host labels" >&2
  exit 1
fi

promtool check config runtime/prometheus.yml
promtool check rules prometheus/rules/*.yml
amtool check-config runtime/alertmanager.yml
blackbox_exporter --config.file=runtime/blackbox.yml --config.check
python3 -m json.tool grafana/dashboards/json/mirror-monitor-overview.json >/dev/null
python3 -m json.tool grafana/dashboards/json/mirror-repository-traffic.json >/dev/null
python3 - <<'PY'
import json

with open("grafana/dashboards/json/caddy-hosts.json") as dashboard_file:
    dashboard = json.load(dashboard_file)
variables = {
    variable["name"]: variable for variable in dashboard["templating"]["list"]
}
assert variables["datasource"]["current"]["value"] == "Prometheus"
assert variables["job"]["current"]["value"] == "caddy_mirrors"
assert variables["instance"]["current"]["value"] == "mirror.sjtu.edu.cn"
assert variables["host"]["current"]["value"] == ".*"
PY
grep -Fq 'mirror_intel_cache_size_bytes{job=\"mirror_intel_mirrors\",host=~\"mirror-siyuan|mirror-zhiyuan\"}' \
  grafana/dashboards/json/mirror-monitor-overview.json
grep -Fq 'mirror_repo_size_bytes{job=\"node_exporter_mirrors\"}' \
  grafana/dashboards/json/mirror-monitor-overview.json
grep -Fq 'mirror_repo_download_bytes_total{job=\"vector_mirrors\"' \
  grafana/dashboards/json/mirror-monitor-overview.json
for metric in \
  mirror_repo_requests_total \
  mirror_repo_download_bytes_total \
  mirror_repo_response_time_seconds_bucket \
  mirror_repo_size_bytes; do
  grep -Fq "$metric" grafana/dashboards/json/mirror-repository-traffic.json
done
grep -Fq 'mirror_intel_cache_size_scan_success' \
  prometheus/rules/mirror-alerts.yml
grep -Fq 'job_name: vector_mirrors' runtime/prometheus.yml
grep -Fq 'mirror_repo_size_collector_success' \
  prometheus/rules/mirror-alerts.yml
grep -Fq 'mirror_siyuan_data55t_mount_ok' \
  scripts/remote/mirror-siyuan-iscsi-metrics
grep -Fq 'mirror_siyuan_data55t_mount_ok' \
  prometheus/rules/mirror-alerts.yml
grep -Fq 'mirror_siyuan_data55t_mount_ok' \
  grafana/dashboards/json/mirror-monitor-overview.json
if grep -Eq 'MirrorSiyuanData55TMountMissing|MirrorSiyuanISCSIExt4Degraded' \
  prometheus/rules/mirror-alerts.yml; then
  echo "Legacy duplicate mirror-siyuan mount alerts are still present" >&2
  exit 1
fi
shellcheck scripts/*.sh scripts/remote/mirror-siyuan-iscsi-metrics
python3 -m py_compile \
  scripts/render-monitor-configs.py \
  scripts/render-prometheus-config.py \
  scripts/remote/mirror-repo-size-collector.py

mkdir -p fixture/mount/bin fixture/mount/output
cat >fixture/mount/bin/findmnt <<'EOF'
#!/usr/bin/env bash
case "${FINDMNT_TEST_STATE:?}" in
  rw) printf '/dev/sda ext4 rw,relatime\n' ;;
  ro) printf '/dev/sda ext4 ro,relatime\n' ;;
  missing) exit 1 ;;
  *) exit 2 ;;
esac
EOF
chmod +x fixture/mount/bin/findmnt
for state_and_expected in rw:1 ro:0 missing:0; do
  state=${state_and_expected%%:*}
  expected=${state_and_expected##*:}
  PATH="$WORK_DIR/fixture/mount/bin:$PATH" \
    FINDMNT_TEST_STATE="$state" \
    MIRROR_SIYUAN_TEXTFILE_DIR="$WORK_DIR/fixture/mount/output" \
    bash scripts/remote/mirror-siyuan-iscsi-metrics
  grep -Fqx \
    "mirror_siyuan_data55t_mount_ok{host=\"mirror-siyuan\",mountpoint=\"/mnt/data55T\"} $expected" \
    fixture/mount/output/mirror_siyuan_iscsi.prom
done

mkdir -p fixture/data/repo-a fixture/data/repo-b fixture/data/internal-cache
printf 'repository data\n' >fixture/data/repo-a/file.iso
ln -s repo-a fixture/data/repo-link
printf 'repo-a\nrepo-b\nrepo-link\n' >fixture/repositories.txt
ruff check scripts/remote/mirror-repo-size-collector.py
ruff format --check scripts/remote/mirror-repo-size-collector.py
for site in siyuan zhiyuan; do
  mkdir -p "fixture/repo-size-$site"
  python3 scripts/remote/mirror-repo-size-collector.py \
    --site "$site" \
    --data-dir "$WORK_DIR/fixture/data" \
    --output-dir "$WORK_DIR/fixture/repo-size-$site" \
    --repositories-file "$WORK_DIR/fixture/repositories.txt" \
    --lock-dir "$WORK_DIR/fixture"
  promtool check metrics <"fixture/repo-size-$site/mirror_repo_sizes.prom"
  promtool check metrics <"fixture/repo-size-$site/mirror_repo_size_collector.prom"
  grep -Fqx \
    "mirror_repo_size_repositories{host=\"mirror-$site\"} 3" \
    "fixture/repo-size-$site/mirror_repo_sizes.prom"
done
cp fixture/repo-size-siyuan/mirror_repo_sizes.prom fixture/siyuan-sizes-before-failure.prom
if python3 scripts/remote/mirror-repo-size-collector.py \
  --site siyuan \
  --data-dir "$WORK_DIR/fixture/missing" \
  --output-dir "$WORK_DIR/fixture/repo-size-siyuan" \
  --repositories-file "$WORK_DIR/fixture/repositories.txt" \
  --lock-dir "$WORK_DIR/fixture"; then
  echo "Repository size collector unexpectedly accepted a missing data directory" >&2
  exit 1
fi
cmp fixture/siyuan-sizes-before-failure.prom fixture/repo-size-siyuan/mirror_repo_sizes.prom
grep -Fqx \
  'mirror_repo_size_collector_success{host="mirror-siyuan"} 0' \
  fixture/repo-size-siyuan/mirror_repo_size_collector.prom

env "${CHECK_ENV[@]}" TELEGRAM_BOT_TOKEN=test-token TELEGRAM_CHAT_ID=-1 \
  python3 ./scripts/render-monitor-configs.py
amtool check-config runtime/alertmanager.yml
grep -q 'bot_token_file: /run/secrets/telegram_bot_token' runtime/alertmanager.yml
if grep -q 'bot_token:' runtime/alertmanager.yml; then
  echo "Telegram token was embedded in Alertmanager configuration" >&2
  exit 1
fi

echo "g-storage monitoring configuration validated"
