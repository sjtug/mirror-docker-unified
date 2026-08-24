#!/usr/bin/env python3

import json
import os
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


def required_value(name: str, placeholder: str) -> str:
    value = env.get(name, "").strip()
    if not value or value == placeholder:
        raise SystemExit(f"{name} must be set to a non-placeholder value")
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

print("rendered runtime/alertmanager.yml and runtime/blackbox.yml")
print(f"telegram_enabled={str(telegram_enabled).lower()}")
