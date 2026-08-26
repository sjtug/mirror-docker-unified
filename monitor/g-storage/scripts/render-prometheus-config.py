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


env = {**read_env(ROOT / ".env"), **os.environ}
user = env.get("MONITOR_USERNAME", "").strip()
password = env.get("MONITOR_PASSWORD", "").strip()
if not user or user == "monitor_username":
    raise SystemExit("MONITOR_USERNAME must be set to a non-placeholder value")
if not password or password == "monitor_password":
    raise SystemExit("MONITOR_PASSWORD must be set to a non-placeholder value")


def quote(value: str) -> str:
    return json.dumps(value)


mirror_hosts = [
    ("mirror.sjtu.edu.cn", "mirror-siyuan", "siyuan"),
    ("mirrors.sjtug.sjtu.edu.cn", "mirror-zhiyuan", "zhiyuan"),
]
public_targets = [
    "https://mirror.sjtu.edu.cn/",
    "https://mirror.sjtu.edu.cn/archlinux/",
    "https://mirror.sjtu.edu.cn/ubuntu/",
    # "https://mirror.sjtu.edu.cn/github-release/prometheus/",
    "https://mirrors.sjtug.sjtu.edu.cn/",
    "https://mirrors.sjtug.sjtu.edu.cn/archlinux/",
    "https://mirrors.sjtug.sjtu.edu.cn/ubuntu/",
    # "https://mirrors.sjtug.sjtu.edu.cn/github-release/prometheus/",
]
monitor_paths = [
    "/monitor/node_exporter/metrics",
    "/monitor/cadvisor/metrics",
    "/monitor/caddy/metrics",
    "/monitor/lug/metrics",
    "/monitor/mirror-intel/metrics",
    "/monitor/vector/metrics",
    "/monitor/rsync-gateway/_metrics",
]
monitor_targets = [
    f"https://{host}{path}" for host, _, _ in mirror_hosts for path in monitor_paths
]

header = """global:
  scrape_interval: 30s
  scrape_timeout: 10s
  evaluation_interval: 30s
  external_labels:
    source: mirrors-monitor-prometheus
    monitor_host: g-storage

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]
        labels:
          host: g-storage
          role: monitoring

  - job_name: alertmanager
    static_configs:
      - targets: ["alertmanager:9093"]
        labels:
          host: g-storage
          role: monitoring

  - job_name: blackbox_exporter
    static_configs:
      - targets: ["blackbox-exporter:9115"]
        labels:
          host: g-storage
          role: monitoring

  - job_name: node_exporter_g_storage
    # Preserve host labels emitted by remote textfile collectors.
    honor_labels: true
    static_configs:
      - targets: ["node-exporter:9100"]
        labels:
          host: g-storage
          role: storage
"""


def mirror_scrape_job(
    job_name: str,
    metrics_path: str,
    *,
    fallback: bool = False,
    honor_labels: bool = False,
) -> str:
    fallback_line = (
        "\n    fallback_scrape_protocol: PrometheusText0.0.4" if fallback else ""
    )
    honor_labels_line = "\n    honor_labels: true" if honor_labels else ""
    parts = [
        f"""
  - job_name: {job_name}
    scheme: https
    metrics_path: {quote(metrics_path)}{fallback_line}{honor_labels_line}
    basic_auth:
      username: {quote(user)}
      password_file: /run/secrets/monitor_password
    static_configs:"""
    ]
    for target, host_label, site in mirror_hosts:
        parts.append(
            f"""
      - targets: [{quote(target)}]
        labels:
          host: {host_label}
          site: {site}
          role: mirror"""
        )
    return "".join(parts) + "\n"


jobs = [header]
jobs.append(
    """
  - job_name: hotspot_vector
    static_configs:
      - targets: ["vector:9599"]
        labels:
          host: g-storage
          role: analytics

  - job_name: hotspot_clickhouse
    static_configs:
      - targets: ["clickhouse:9363"]
        labels:
          host: g-storage
          role: analytics
"""
)
jobs.append(
    mirror_scrape_job("node_exporter_mirrors", "/monitor/node_exporter/metrics")
)
jobs.append(mirror_scrape_job("cadvisor_mirrors", "/monitor/cadvisor/metrics"))
jobs.append(
    mirror_scrape_job("caddy_mirrors", "/monitor/caddy/metrics", honor_labels=True)
)
jobs.append(mirror_scrape_job("lug_mirrors", "/monitor/lug/metrics"))
jobs.append(
    mirror_scrape_job(
        "mirror_intel_mirrors", "/monitor/mirror-intel/metrics", fallback=True
    )
)
jobs.append(mirror_scrape_job("vector_mirrors", "/monitor/vector/metrics"))
jobs.append(
    mirror_scrape_job("rsync_gateway_mirrors", "/monitor/rsync-gateway/_metrics")
)

jobs.append(
    """
  - job_name: blackbox_public_http
    metrics_path: /probe
    params:
      module: [http_2xx_3xx]
    static_configs:
"""
)
for target in public_targets:
    host = (
        "mirror-siyuan"
        if "mirror.sjtu.edu.cn" in target and "mirrors.sjtug" not in target
        else "mirror-zhiyuan"
    )
    jobs.append(
        f"""      - targets: [{quote(target)}]
        labels:
          host: {host}
          probe_group: public
"""
    )
jobs.append(
    """    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
"""
)

jobs.append(
    """
  - job_name: blackbox_monitor_auth
    metrics_path: /probe
    params:
      module: [http_2xx_monitor_auth]
    static_configs:
"""
)
for target in monitor_targets:
    host = (
        "mirror-siyuan"
        if "mirror.sjtu.edu.cn" in target and "mirrors.sjtug" not in target
        else "mirror-zhiyuan"
    )
    service = target.rsplit("/monitor/", 1)[-1].split("/", 1)[0]
    jobs.append(
        f"""      - targets: [{quote(target)}]
        labels:
          host: {host}
          probe_group: monitor
          service: {service}
"""
    )
jobs.append(
    """    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
"""
)

write(RUNTIME_DIR / "prometheus.yml", "".join(jobs))
write(RUNTIME_DIR / "monitor_password", password + "\n")
print("rendered runtime/prometheus.yml")
print(
    "jobs: node_exporter_g_storage, mirror exporters, cAdvisor, Caddy, LUG, "
    "mirror-intel, Vector, rsync-gateway, blackbox, hotspot analytics"
)
