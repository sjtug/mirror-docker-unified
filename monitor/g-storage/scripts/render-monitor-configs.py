#!/usr/bin/env python3

import hashlib
import json
import os
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME_DIR = ROOT / "runtime"


def read_env(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    if not path.exists():
        return env
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip().strip('"').strip("'")
    return env


def write(path: Path, content: str, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.parent.chmod(0o700)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content)
    temporary.chmod(mode)
    temporary.replace(path)


env = {
    **read_env(ROOT / ".env"),
    **read_env(ROOT / "bot.env"),
    **os.environ,
}


def required_value(name: str, placeholder: str, *, minimum_length: int = 1) -> str:
    value = env.get(name, "").strip()
    if not value or value == placeholder:
        raise SystemExit(f"{name} must be set to a non-placeholder value")
    if len(value) < minimum_length:
        raise SystemExit(f"{name} must be at least {minimum_length} characters")
    return value


required_value("GITHUB_CLIENT_ID", "github_client_id")
github_client_secret = required_value("GITHUB_CLIENT_SECRET", "github_client_secret")
monitor_user = required_value("MONITOR_USERNAME", "monitor_username")
monitor_password = required_value("MONITOR_PASSWORD", "monitor_password")

telegram_token = env.get("TELEGRAM_BOT_TOKEN", "").strip()
telegram_chat_id = env.get("TELEGRAM_CHAT_ID", "").strip()
telegram_api_url = (
    env.get("TELEGRAM_API_URL", "https://api.telegram.org").strip()
    or "https://api.telegram.org"
)
telegram_thread_id = env.get("TELEGRAM_MESSAGE_THREAD_ID", "").strip()
telegram_proxy_url = env.get("TELEGRAM_PROXY_URL", "http://metacubexd:1081").strip()
telegram_enabled = bool(
    telegram_token
    and telegram_token != "replace_me"
    and telegram_chat_id
    and telegram_chat_id != "0"
)

if telegram_enabled:
    try:
        int(telegram_chat_id)
    except ValueError as exc:
        raise SystemExit("TELEGRAM_CHAT_ID must be an integer") from exc

    thread_line = ""
    if telegram_thread_id:
        try:
            int(telegram_thread_id)
        except ValueError as exc:
            raise SystemExit("TELEGRAM_MESSAGE_THREAD_ID must be an integer") from exc
        thread_line = f"        message_thread_id: {telegram_thread_id}\n"

    alertmanager = f"""global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'job', 'instance', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: telegram

receivers:
  - name: telegram
    telegram_configs:
      - api_url: {json.dumps(telegram_api_url)}
        bot_token_file: /run/secrets/telegram_bot_token
        chat_id: {telegram_chat_id}
{thread_line}        http_config:
          proxy_url: {json.dumps(telegram_proxy_url)}
        send_resolved: true
        message: |-
          {{{{ if eq .Status "firing" }}}}FIRING{{{{ else }}}}RESOLVED{{{{ end }}}} {{{{ len .Alerts }}}} alert(s)
          {{{{ range .Alerts }}}}
          {{{{ .Labels.alertname }}}}{{{{ if .Labels.severity }}}} [{{{{ .Labels.severity }}}}]{{{{ end }}}}
          {{{{ if .Labels.host }}}}host={{{{ .Labels.host }}}} {{{{ end }}}}{{{{ if .Labels.instance }}}}instance={{{{ .Labels.instance }}}}{{{{ end }}}}
          {{{{ if .Annotations.summary }}}}{{{{ .Annotations.summary }}}}{{{{ end }}}}
          {{{{ if .Annotations.description }}}}{{{{ .Annotations.description }}}}{{{{ end }}}}
          {{{{ end }}}}
"""
else:
    alertmanager = """global:
  resolve_timeout: 5m

route:
  receiver: "null"
  group_by: ['alertname', 'job', 'instance', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

receivers:
  - name: "null"
"""


blackbox = f"""modules:
  http_2xx_3xx:
    prober: http
    timeout: 10s
    http:
      method: GET
      preferred_ip_protocol: ip4
      valid_status_codes: [200, 204, 301, 302, 303, 307, 308]
      follow_redirects: true
      fail_if_ssl: false
      fail_if_not_ssl: false

  http_2xx_monitor_auth:
    prober: http
    timeout: 10s
    http:
      method: GET
      preferred_ip_protocol: ip4
      valid_status_codes: [200]
      follow_redirects: true
      basic_auth:
        username: {json.dumps(monitor_user)}
        password_file: /run/secrets/monitor_password
"""

write(RUNTIME_DIR / "alertmanager.yml", alertmanager)
write(RUNTIME_DIR / "blackbox.yml", blackbox)
# Docker bind-mounts these files into non-root containers. The parent runtime
# directory is mode 0700, while the mounted files must be readable in-container.
write(RUNTIME_DIR / "telegram_bot_token", telegram_token + "\n")
write(RUNTIME_DIR / "monitor_password", monitor_password + "\n")
write(RUNTIME_DIR / "github_client_secret", github_client_secret + "\n")

hotspot_dashboard_dir = RUNTIME_DIR / "hotspot-dashboards"
hotspot_dashboard_dir.mkdir(parents=True, exist_ok=True, mode=0o755)
hotspot_dashboard_dir.chmod(0o755)
for old_dashboard in hotspot_dashboard_dir.glob("*.json"):
    old_dashboard.unlink()

hotspot_datasource_path = RUNTIME_DIR / "hotspot-clickhouse-datasource.yml"
ingest_password = required_value(
    "HOTSPOT_CLICKHOUSE_INGEST_PASSWORD",
    "hotspot_ingest_password",
    minimum_length=16,
)
grafana_password = required_value(
    "HOTSPOT_CLICKHOUSE_GRAFANA_PASSWORD",
    "hotspot_grafana_password",
    minimum_length=16,
)
client_hash_key = required_value(
    "HOTSPOT_CLIENT_HASH_KEY", "hotspot_client_hash_key", minimum_length=32
)

ingest_hash = hashlib.sha256(ingest_password.encode()).hexdigest()
grafana_hash = hashlib.sha256(grafana_password.encode()).hexdigest()
clickhouse_users = f"""<clickhouse>
  <profiles>
    <hotspot_ingest>
      <max_threads>4</max_threads>
      <max_memory_usage>4294967296</max_memory_usage>
    </hotspot_ingest>
    <hotspot_readonly>
      <!-- Mode 2 permits query-scoped settings while still rejecting writes. -->
      <readonly>2</readonly>
      <max_threads>8</max_threads>
      <max_execution_time>60</max_execution_time>
      <max_memory_usage>8589934592</max_memory_usage>
      <max_result_rows>100000</max_result_rows>
      <result_overflow_mode>throw</result_overflow_mode>
    </hotspot_readonly>
  </profiles>
  <users>
    <default>
      <networks replace=\"replace\"><ip>127.0.0.1</ip><ip>::1</ip></networks>
    </default>
    <hotspot_ingest>
      <password_sha256_hex>{ingest_hash}</password_sha256_hex>
      <networks><ip>0.0.0.0/0</ip><ip>::/0</ip></networks>
      <profile>hotspot_ingest</profile>
      <quota>default</quota>
      <grants>
        <query>GRANT SELECT, INSERT ON hotspot.requests_raw</query>
      </grants>
    </hotspot_ingest>
    <hotspot_grafana>
      <password_sha256_hex>{grafana_hash}</password_sha256_hex>
      <networks><ip>0.0.0.0/0</ip><ip>::/0</ip></networks>
      <profile>hotspot_readonly</profile>
      <quota>default</quota>
      <grants>
        <query>GRANT SELECT ON hotspot.repo_5m</query>
        <query>GRANT SELECT ON hotspot.repo_5m_totals</query>
        <query>GRANT SELECT ON hotspot.repo_5m_state</query>
        <query>GRANT SELECT ON hotspot.object_1h</query>
        <query>GRANT SELECT ON hotspot.object_1h_totals</query>
        <query>GRANT SELECT ON hotspot.object_1h_state</query>
        <query>GRANT SELECT ON system.columns</query>
        <query>GRANT SELECT ON system.databases</query>
        <query>GRANT SELECT ON system.tables</query>
      </grants>
    </hotspot_grafana>
  </users>
</clickhouse>
"""
write(RUNTIME_DIR / "clickhouse-users.xml", clickhouse_users)
write(
    RUNTIME_DIR / "hotspot_clickhouse_ingest_password",
    ingest_password + "\n",
    mode=0o600,
)
write(RUNTIME_DIR / "hotspot_client_hash_key", client_hash_key + "\n", mode=0o600)

hotspot_datasource = f"""apiVersion: 1

datasources:
  - name: Hotspot ClickHouse
    uid: hotspot-clickhouse
    type: grafana-clickhouse-datasource
    access: proxy
    isDefault: false
    editable: false
    jsonData:
      host: clickhouse
      port: 9000
      protocol: native
      defaultDatabase: hotspot
      username: hotspot_grafana
      tlsSkipVerify: false
      queryTimeout: \"60\"
    secureJsonData:
      password: {json.dumps(grafana_password)}
"""
# The host runtime directory is 0700. The bind-mounted file must remain
# readable by Grafana's non-root container user.
write(hotspot_datasource_path, hotspot_datasource)
shutil.copyfile(
    ROOT / "grafana/dashboards/hotspot/mirror-hotspot-analytics.json",
    hotspot_dashboard_dir / "mirror-hotspot-analytics.json",
)
(hotspot_dashboard_dir / "mirror-hotspot-analytics.json").chmod(0o644)

print("rendered runtime/alertmanager.yml and runtime/blackbox.yml")
print(f"telegram_enabled={str(telegram_enabled).lower()}")
