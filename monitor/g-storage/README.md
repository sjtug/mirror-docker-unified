# g-storage monitoring

This directory is the source of truth for the monitoring stack deployed on
`g-storage`. The active checkout and bind-mount root is
`/home/sjtug/mirror-docker-g-storage`; the stack uses rootful containerd through
`nerdctl compose`. Alertmanager joins the externally managed containerd CNI
network `metacubexd_default` and reaches mihomo through its `metacubexd` alias.
The mirror hosts continue to use Docker Compose.

Host-local values are committed SOPS-encrypted as
`monitor/g-storage/g-storage.sops.env`, `monitor/g-storage/bot.sops.env`, and
`monitor/g-storage/xray/config.sops.json`; the Just recipes decrypt them to the
ignored runtime filenames below before validation. Every SOPS invocation sets
`SOPS_AGE_SSH_PRIVATE_KEY_FILE` explicitly to
`G_STORAGE_SOPS_SSH_KEY_FILE` (default:
`/etc/ssh/ssh_host_ed25519_key`) instead of relying on a per-user age identity.
Fresh hosts only need a checkout: `sudo just g-storage-up` performs the whole
check → decrypt → render → validate → up chain. Override the host-key path, if
needed, by exporting `G_STORAGE_SOPS_SSH_KEY_FILE=/path/to/ssh_host_key` for
the Just invocation.

### Unified xray tunnel

The three hosts run one VLESS tunnel configuration with a shared UUID:

- **g-storage** (`xray/config.sops.json`) publishes the tunnel endpoint on host
  port `19200` and provides the internal HTTP proxy on port 1081 for
  Alertmanager/Grafana egress.
- **mirror-siyuan / mirror-zhiyuan** use the reviewable non-secret template
  `xray/config.edge.json` for their existing dokodemo-door ports, including
  `5104` for central log/analytics forwarding. The shared VLESS user ID is the
  only value in the per-host `secrets/{siyuan,zhiyuan}/xray.env.sops` files.

Deploy edge tunnel changes only through the site-specific targets from the
canonical checkout. They require `/opt/mirror-docker-*` and activate the
host-specific dotenv file with `sops exec-file --no-fifo`. Compose consumes the
short-lived file through `--env-file`; the xray entrypoint creates its complete
configuration in container tmpfs, validates it, and removes the UUID from the
xray process environment. The tunnel reload target recreates only that service
and waits for door `5104` to listen:

```sh
# mirror-siyuan
cd /opt/mirror-docker-siyuan
sudo just mirror-tunnel-reload siyuan
sudo just mirror-tunnel-status siyuan

# mirror-zhiyuan
cd /opt/mirror-docker-zhiyuan
sudo just mirror-tunnel-reload zhiyuan
sudo just mirror-tunnel-status zhiyuan
```

The `mirror-up` and `mirror-build` recipes use the same activation path.

Override `MIRROR_SOPS_SSH_KEY_FILE` only when the deployment host key is stored
somewhere other than `/etc/ssh/ssh_host_ed25519_key`. There is no generated
host-side `secrets/xray.json`; use the activation targets instead.

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

Port `5104` is the unified xray door for the hotspot event branch into the same
g-storage Vector instance that owns the legacy Loki rollback branch. Hotspot
events carry an explicit marker: Vector sanitizes and writes them to ClickHouse
but excludes them from Loki, avoiding a second raw-log copy. Legacy unmarked
Caddy events can still reach Loki for rollback. The shared configuration lives
in `config/vector.toml` and `config/loki.yml`. Use the Just status recipe and
ClickHouse row counts to verify forwarding after each edge rollout.

### Hotspot analytics

Hotspot analytics is part of the normal monitoring stack and does not replace
the existing Prometheus repository metrics or external MirrorZ sink:

```text
edge Vector -> existing xray door tunnel:5104 -> g-storage Vector
  -> privacy normalization -> hotspot.requests_raw
  -> 5-minute repository and 1-hour object rollups
  -> provisioned Hotspot ClickHouse datasource and Mirror Hotspot Analytics dashboard
```

No additional TLS certificates are required: the existing xray tunnel is the
encrypted transport. The g-storage `5104` listener must remain reachable only
through the established tunnel/firewall policy.

Raw ClickHouse events retain no query string, raw client IP, full Referer, or
full User-Agent. Central Vector stores a keyed HMAC client identifier, Referer
host, parsed UA classes, and request path. Raw events expire after 14 days;
repository rollups after 365 days and object rollups after 90 days. The current
first slice reserves geography columns but does not load GeoLite databases.
GeoIP enrichment requires an explicit database-update and privacy policy.

The non-secret paths and transport are committed directly in Compose and
Vector configuration:

```text
ClickHouse data: /var/lib/mirror-monitor/hotspot-clickhouse
Vector state:    /var/lib/mirror-monitor/hotspot-vector
Tunnel door:     tunnel:5104 -> g-storage:5104
```

Only these values belong in the existing `g-storage.sops.env`:

```dotenv
HOTSPOT_CLICKHOUSE_INGEST_PASSWORD=...
HOTSPOT_CLICKHOUSE_GRAFANA_PASSWORD=...
HOTSPOT_CLIENT_HASH_KEY=... # at least 32 random characters
```

`HOTSPOT_CLIENT_HASH_KEY` must remain stable while analytics data is retained;
rotating it starts a new pseudonymous-client epoch. Normal `g-storage-check`,
`g-storage-build`, `g-storage-up`, `g-storage-reload`, and `g-storage-logs`
targets validate and operate the complete stack. Preload
`clickhouse/clickhouse-server:26.3` and `timberio/vector:0.55.0-alpine` into
rootful containerd before `g-storage-up`; deployments never pull implicitly.
`g-storage-up` and `g-storage-reload` reapply the idempotent ClickHouse schema.
Never use `nerdctl compose down -v`.

### Current deployment

Every scrape target and blackbox probe is healthy, and all provisioned
dashboards render data. Two non-container host cleanups remain: g-storage's
retired SSH iSCSI unit and the stale Postgres bind-mount monitoring rule. See
[`../../MAINTENANCE.md`](../../MAINTENANCE.md) for alert status and rollout
steps.

Keep the Telegram token in an ignored `bot.env`:

```sh
cat >bot.env <<'EOF'
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...
EOF
chmod 600 bot.env
```

Use the repository-level Just recipes from the active checkout to render,
validate, and deploy the stack. Generated configurations and credential files
are written atomically under the ignored `runtime/` directory and mounted into
individual services as read-only files under `/run/secrets`.

```sh
cd /home/sjtug/mirror-docker-g-storage
just g-storage-check
sudo just g-storage-render
sudo just g-storage-config
sudo just g-storage-build
sudo just g-storage-up

# Non-default host-key location:
sudo env G_STORAGE_SOPS_SSH_KEY_FILE=/path/to/ssh_host_key just g-storage-up
```

`g-storage-up` never pulls or builds images. Preload missing images into the
rootful containerd namespace with nerdctl, and run `g-storage-build` explicitly
for the custom Grafana image. Rootful BuildKit must be running for builds.
`g-storage-reload` recreates the containers because an atomic replacement of a
bind-mounted configuration file is not visible through the old mount.

Docker and containerd have separate named-volume stores. The active monitoring
state now lives in rootful containerd volumes; the matching Compose project
name does not imply that Docker volumes are interchangeable. Never use `down -v` during
normal deployment or rollback.

All dashboards are provisioned from this tree: `Mirror Monitor Overview`,
`Mirror Repository Traffic`, `Mirror Hotspot Analytics`, `Node Exporter Full`
(`rYdddlPWk`), and `Caddy Hosts`. The hotspot renderer copies its dashboard into
the runtime provider directory alongside the generated ClickHouse datasource.
Run `just g-storage-enable-collectors` on g-storage to refresh its local target
collector and remove the retired repository-statistics unit.

Per-repository sizes are already collected locally on both mirror hosts and
written atomically to their existing node-exporter textfile directories. From
each host's checkout, refresh the matching hardened systemd service and daily
timer with:

```sh
# mirror-siyuan
just mirror-enable-collectors siyuan

# mirror-zhiyuan
just mirror-enable-collectors zhiyuan
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
