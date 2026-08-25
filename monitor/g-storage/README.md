# g-storage monitoring

This directory is the source of truth for the monitoring stack deployed on
`g-storage`. Like the mirror hosts, it uses rootful containerd through
`nerdctl compose`. Alertmanager joins the externally managed containerd CNI
network `metacubexd_default`; migrate mihomo into that network before cutting
the monitoring stack over from Docker, preserving the `metacubexd` network
alias used by the proxy URL.

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

The three hosts run one unified xray tunnel configuration (VLESS, shared UUID):

- **g-storage** (`xray/config.sops.json`): VLESS server inbound on container
  port 1080, published as host port `19200` — this is the tunnel endpoint the
  mirror hosts dial — plus the internal HTTP proxy on port 1081 for
  alertmanager/grafana egress.
- **mirror-siyuan / mirror-zhiyuan** (`secrets/{siyuan,zhiyuan}/xray.json.sops`):
  dokodemo-door inbounds `5003`-`5010` that tunnel to g-storage `19200`, e.g.
  logspout syslog on `5004` lands on g-storage's logstash input.

Door destinations use g-storage's public address (hairpin) instead of the
legacy Docker bridge (`172.17.0.1`), so the tunnel survives the nerdctl-only
cutover. Hosts shipping logs must keep the matching logstash input ports
published on g-storage.

### Caddy access logs

Mirror-host Caddy instances write structured JSON access logs under
`/var/log/caddy/mirrorz`. The Vector service defined by the repository-level
Docker Compose configuration reads those files and sends them directly to the
central collector over mutual TLS.

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

The g-storage `vector` → `loki` pipeline on port `5104` is retained temporarily
for historical queries and rollback while central forwarding is verified. Its
configs live in `config/vector.toml` and `config/loki.yml`. Do not re-enable the
old Caddy tunnel output in parallel with file forwarding, or access events will
be duplicated.

Keep the Telegram token in an ignored `bot.env`:

```sh
cat >bot.env <<'EOF'
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...
EOF
chmod 600 bot.env
```

Use the repository-level Make targets to render, validate, and deploy the
stack. Generated configurations and credential files are written atomically
under the ignored `runtime/` directory and mounted into individual services as
read-only files under `/run/secrets`.

```sh
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

Docker and containerd have separate named-volume stores. Export and restore
the existing Prometheus, Alertmanager, and Grafana Docker volumes before the
first nerdctl deployment; the matching Compose project name does not migrate
their contents automatically.

All dashboards are provisioned from this tree: `Mirror Monitor Overview`,
`Node Exporter Full` (`rYdddlPWk`), and `Caddy Hosts` are shipped as JSON under
`grafana/dashboards/json/` and picked up by the provisioning provider.
Run `make g-storage-enable-collectors` on g-storage to install its local target
collector.

Per-repository sizes are collected locally on both mirror hosts and written
atomically to their existing node-exporter textfile directories. From each
host's checkout, install the matching hardened systemd service and daily timer:

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
separate attempt-health metrics. No SSH key, forced command, or g-storage polling service is required.

Mirror-intel 0.1.42 independently exposes `mirror_intel_cache_size_bytes` and
scan-health metrics through the existing mirror-intel Prometheus endpoint.
Edge Vector exports `mirror_repo_download_bytes_total` through the new
authenticated `/monitor/vector/metrics` endpoint on both hosts.

siyuan's iSCSI/ext4 metrics are produced locally by a siyuan systemd timer
(`scripts/systemd/siyuan/mirror-siyuan-iscsi-textfile.{service,timer}`) that
writes the node_exporter textfile; they are scraped through the existing
`/monitor/node_exporter` endpoint instead of an SSH forced command.
