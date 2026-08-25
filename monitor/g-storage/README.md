# g-storage monitoring

This directory is the source of truth for the monitoring stack deployed on
`g-storage`. The active checkout and bind-mount root is
`/home/sjtug/mirror-docker-g-storage`; the stack uses rootful containerd through
`nerdctl compose`. Alertmanager joins the externally managed containerd CNI
network `metacubexd_default` and reaches mihomo through its `metacubexd` alias.
The mirror hosts continue to use Docker Compose.

Host-local values are committed SOPS-encrypted as
`monitor/g-storage/g-storage.sops.env`, `monitor/g-storage/bot.sops.env`, and
`monitor/g-storage/xray/config.sops.json`; the Make targets decrypt them to the
ignored runtime filenames below before validation. Every SOPS invocation sets
`SOPS_AGE_SSH_PRIVATE_KEY_FILE` explicitly to
`G_STORAGE_SOPS_SSH_KEY_FILE` (default:
`/etc/ssh/ssh_host_ed25519_key`) instead of relying on a per-user age identity.
Fresh hosts only need a checkout: `sudo make g-storage-up` performs the whole
check → decrypt → render → validate → up chain. Override the host-key path, if
needed, with `G_STORAGE_SOPS_SSH_KEY_FILE=/path/to/ssh_host_key` as a Make
argument.

### Unified xray tunnel

The three hosts run one VLESS tunnel configuration with a shared UUID:

- **g-storage** (`xray/config.sops.json`) publishes the tunnel endpoint on host
  port `19200` and provides the internal HTTP proxy on port 1081 for
  Alertmanager/Grafana egress.
- **mirror-siyuan / mirror-zhiyuan**
  (`secrets/{siyuan,zhiyuan}/xray.json.sops`) expose dokodemo-door ports
  `5003`-`5010` to services on g-storage.

Door destinations use g-storage's public address rather than a Docker bridge,
so they remain valid for the rootful nerdctl stack. Legacy logspout traffic on
port `5004` is still consumed by the separate Docker Logstash deployment; it is
not part of the active Prometheus/Grafana Compose project.

### Caddy access logs

Mirror-host Caddy instances write structured JSON access logs under
`/var/log/caddy/mirrorz`. Edge Vector reads those files and sends them directly
to the central collector using the shared `CN=sjtu` mTLS client identity. The
Siyuan and Zhiyuan Compose overrides require central forwarding; Vector buffers
events on disk while the collector is unavailable.

The edge Vector instances also derive bounded per-repository request,
download-byte, and response-time metrics from those logs. Prometheus scrapes
them through authenticated `/monitor/vector/metrics` endpoints, and the
provisioned `Mirror Repository Traffic` dashboard compares access patterns and
traffic shares across Siyuan and Zhiyuan without indexing client identifiers.
It combines the traffic series with repository sizes from each host's local
textfile collector to show storage share and download turnover.

The authenticated `/monitor/caddy/metrics` proxy explicitly sends
`Host: localhost:2019` upstream. Caddy's admin API rejects the public request
host with `403 host not allowed`; without this override the `caddy_mirrors`
targets and the `Caddy Hosts` dashboard have no data.

Central forwarding is verified. The g-storage `vector` → `loki` pipeline on
port `5104` remains only for historical queries and rollback; it is not the
primary Caddy stream. Its configs live in `config/vector.toml` and
`config/loki.yml`. Enabling the old Caddy tunnel output alongside edge Vector
would duplicate access events.

### Current deployment

As of 2026-08-25, every configured scrape group and blackbox probe is healthy,
and all four provisioned dashboards render data. Two host issues remain outside
the containers: g-storage's retired SSH repository collector produces a
malformed textfile, and Siyuan's `/srv/mirror/postgres-data` bind mount is
absent. See [`../../MAINTENANCE.md`](../../MAINTENANCE.md) for current alerts,
cleanup steps, and rollback state.

Keep the Telegram token in an ignored `bot.env`:

```sh
cat >bot.env <<'EOF'
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...
EOF
chmod 600 bot.env
```

Use the repository-level Make targets from the active checkout to render,
validate, and deploy the stack. Generated configurations and credential files
are written atomically under the ignored `runtime/` directory and mounted into
individual services as read-only files under `/run/secrets`.

```sh
cd /home/sjtug/mirror-docker-g-storage
make g-storage-check
sudo make g-storage-render
sudo make g-storage-config
sudo make g-storage-build
sudo make g-storage-up

# Non-default host-key location:
sudo make g-storage-up G_STORAGE_SOPS_SSH_KEY_FILE=/path/to/ssh_host_key
```

`g-storage-up` never pulls or builds images. Preload missing images into the
rootful containerd namespace with nerdctl, and run `g-storage-build` explicitly
for the custom Grafana image. Rootful BuildKit must be running for builds.
`g-storage-reload` recreates the containers because an atomic replacement of a
bind-mounted configuration file is not visible through the old mount.

Docker and containerd have separate named-volume stores. The active monitoring
state now lives in rootful containerd volumes; the matching Compose project
name does not make Docker volumes interchangeable. Never use `down -v` during
normal deployment or rollback.

All dashboards are provisioned from this tree: `Mirror Monitor Overview`,
`Mirror Repository Traffic`, `Node Exporter Full` (`rYdddlPWk`), and
`Caddy Hosts` are shipped as JSON under `grafana/dashboards/json/` and picked up
by the provisioning provider.
Run `make g-storage-enable-collectors` on g-storage to refresh its local target
collector and remove the retired repository-statistics unit.

Per-repository sizes are already collected locally on both mirror hosts and
written atomically to their existing node-exporter textfile directories. From
each host's checkout, refresh the matching hardened systemd service and daily
timer with:

```sh
# mirror-siyuan
make mirror-enable-collectors MIRROR_SITE=siyuan

# mirror-zhiyuan
make mirror-enable-collectors MIRROR_SITE=zhiyuan
```

The install target verifies the host's existing socket-activated
`node_exporter.service` and `/etc/sysconfig/node_exporter` textfile setting; it
does not replace or restart node-exporter. On Siyuan it also installs the local
iSCSI collector. The independent timers write mode-0644 files that the
`node_exporter` user reads on its next scrape.

The Python size collector intersects disk directories with the generated
`caddy/local-repositories.<site>.txt` manifest, so cache/database directories
are not mislabeled as repositories. It runs `du` with systemd idle I/O
priority, retains the last successful size file after failures, and emits
separate attempt-health metrics. The active design requires no SSH polling from
g-storage, but the retired repository and iSCSI SSH units still need removal;
see `MAINTENANCE.md`.

Mirror-intel 0.1.42 independently exposes `mirror_intel_cache_size_bytes` and
scan-health metrics through the existing mirror-intel Prometheus endpoint.
Edge Vector exports bounded `mirror_repo_requests_total`,
`mirror_repo_download_bytes_total`, and `mirror_repo_response_time_seconds`
metrics through authenticated `/monitor/vector/metrics` on both hosts.

Siyuan's iSCSI/ext4 metrics are produced locally by
`mirror-siyuan-iscsi-textfile.timer` and scraped through the existing
`/monitor/node_exporter` endpoint. The data55T mount is currently healthy and
read-write; the separate Postgres bind mount is degraded.
