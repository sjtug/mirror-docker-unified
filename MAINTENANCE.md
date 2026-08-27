# Server Configuration

## Zhiyuan (legacy)

comonad in 🌐 mirrors2 in ~ took 4s
❯ ./pfetch
,'''''. comonad@mirrors2.sjtug.org
| ,. | os Fedora Linux 44 (Server Edition)
| | '_' host Lenovo WQ R520 G7 empty
,....| |.. kernel 7.0.9-202.fc44.x86_64
.' ,_;| ..' uptime 57d 2h 39m
| | | | pkgs 1209
| ',\_,' | memory 19855M / 47991M
'. ,'
'''''

Login via `ssh mirror-zhiyuan`
Mirror info:

- Canonical checkout: `/opt/mirror-docker-zhiyuan`.
- Run `sudo just mirror-up zhiyuan` from the canonical checkout for full startup.
- Run `sudo just mirror-tunnel-{reload,status} zhiyuan` for tunnel-only operations.

## Siyuan

comonad in 🌐 mirror1a in ~ took 3s
❯ ./pfetch
**\_** comonad@mirror1a
/ ** \ os Debian GNU/Linux 12 (bookworm)
| / | host OpenStack Nova 16.0.0
| \_**- kernel 6.7.12+bpo-amd64 -_ uptime 427d 9h 24m
--_ pkgs 757
memory 47624M / 128804M

Login via `ssh mirror-siyuan`
Mirror info:

- Canonical checkout: `/opt/mirror-docker-siyuan`.
- Run `sudo just mirror-up siyuan` from the canonical checkout for full startup.
- Run `sudo just mirror-tunnel-{reload,status} siyuan` for tunnel-only operations.

iSCSI client (`open-iscsi.service`) with follow mount record:

```
#/etc/fstab

# iSCSI 55T storage - allow failures with nofail option
/dev/disk/by-path/ip-10.32.36.148:3260-iscsi-iqn.2025-05.cn.edu.sjtu.mirror:storage.data55T-lun-1 /mnt/data55T ext4 _netdev,nofail,x-systemd.requires=iscsi.service,x-systemd.after=iscsi.service,x-systemd.device-timeout=30,auto 0 0

```

## Storage (shared machine; private network only)

➜ ./pfetch
_ sjtug@ubuntu-R740
---(_) os Ubuntu 22.04.5 LTS (Jammy Jellyfish)
_/ --- \ host PowerEdge R740
(_) | | kernel 6.8.0-90-generic
\ --- _/ uptime 164d 7h 9m
---(_) pkgs 2446
memory 30819M / 385430M

Login via `ssh g-storage`

Mirror monitoring checkout:

- `/home/sjtug/mirror-docker-g-storage`; stack directory `monitor/g-storage`.
  This is the active checkout and bind-mount source for the rootful nerdctl
  monitoring stack.
- The monitoring stack runs in rootful containerd's `default` namespace through
  `sudo nerdctl compose`. The two mirror hosts continue to use Docker Compose.
- `/home/sjtug/mirror-ng` is retired and retained only for rollback/reference.
- `/home/sjtug/mirrors-docker-staging/monitor/docker-prometheus-grafana` is not
  the active monitoring checkout. Its Docker Elasticsearch and Logstash
  containers still run for legacy log history; they are separate from the
  nerdctl Prometheus/Grafana stack.
- Alertmanager joins the external containerd CNI network `metacubexd_default`
  and reaches the proxy through the `metacubexd` alias.

iSCSI server (`tgt.service`):

```
#/etc/tgt/conf.d/data55T.conf
<target iqn.2025-05.cn.edu.sjtu.mirror:storage.data55T>
        backing-store /dev/sdc1
        initiator-address 111.186.58.212/31
        # params for unstable network
        param MaxConnections 128
        param ErrorRecoveryLevel 2
        param FirstBurstLength 262144
        param MaxBurstLength 1048576
        param MaxRecvDataSegmentLength 262144
        param InitialR2T No
        param ImmediateData Yes
        nop_interval 5
        nop_count    20
</target>
```

## Monitoring

The active monitoring stack runs on `g-storage` from:

```sh
ssh g-storage
cd /home/sjtug/mirror-docker-g-storage
```

It uses rootful containerd's `default` namespace through `sudo nerdctl compose`.
The mirror hosts themselves continue to use Docker Compose. The active
monitoring services are Prometheus, Alertmanager, Grafana, node-exporter,
blackbox-exporter, Xray, Vector, Loki, and ClickHouse. On 2026-08-27 all 40
Prometheus `up` series and all 20 blackbox probes were healthy.

Mirror-host Vector instances send Caddy access logs to the central collector
with the shared `CN=sjtu` mTLS client identity. Production Compose requires the
credentials, while a disk buffer tolerates central outages. The g-storage
Vector/Loki pipeline remains available for historical queries and rollback; it
is not the primary Caddy log destination after central forwarding was verified.
The older Docker Elasticsearch/Logstash project also remains running for legacy
history.

The running nerdctl containers bind configuration and rendered secrets from
`/home/sjtug/mirror-docker-g-storage/monitor/g-storage`. Editing
`/home/sjtug/mirror-ng` or the Docker reference tree does not affect them.

### Current status (verified 2026-08-27)

- Scrapes and probes: all 40 Prometheus `up` series and 20 blackbox probes are
  healthy. Node-exporter textfile scrape errors are zero on all hosts.
- Storage: Siyuan's data55T iSCSI mount is present and read-write; target and
  LUN on g-storage are ready.
- Alerts: `MirrorSiyuanPostgresBindMountDegraded` fires on the retired
  `/srv/mirror/postgres-data` bind path. Postgres now mounts
  `/mnt/data55T/mirror-postgres-data` directly; update the alert contract.
- Hotspot analytics: g-storage runs Vector, ClickHouse, and Grafana, but
  ClickHouse has zero request rows because edge xray configs lack door `5104`.
  Siyuan buffers ~1.9 GiB; Zhiyuan buffers ~2.1 GiB.
- Deployment: commit `37aa0df` is ready for rollout across all checkouts.
  Activate xray with `sudo just mirror-tunnel-reload SITE` from the `/opt`
  checkouts, then monitor buffer drain and dashboard population.
- Paths: mirror Caddy and Vector containers run from `/opt/mirror-docker-*`.
  Unused `~/.cache/mirror-monitor-vector-hotfix` directories can be removed.
- Root filesystems: Siyuan is at 58% usage; Zhiyuan is at 35%.
- Cleanup: malformed repository-stats textfile generation is retired. Stale SSH
  iSCSI timers and keys on g-storage remain for removal after verification.

### Status and access

```sh
# All monitoring containers
sudo nerdctl ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' |
  grep docker-prometheus-grafana

# Prometheus and Alertmanager health. -Y off prevents the container's HTTP proxy
# environment from proxying localhost checks through Xray.
sudo nerdctl exec docker-prometheus-grafana-prometheus-1 \
  wget -Y off -qO- http://127.0.0.1:9090/-/healthy
sudo nerdctl exec docker-prometheus-grafana-alertmanager-1 \
  wget -Y off -qO- http://127.0.0.1:9093/-/healthy

# Logs and host collectors
sudo nerdctl logs --tail 200 docker-prometheus-grafana-prometheus-1
sudo nerdctl logs --tail 200 docker-prometheus-grafana-alertmanager-1
systemctl list-timers 'mirror-monitor-*-textfile.timer'
```

Grafana is bound to `127.0.0.1:3000`:

```sh
ssh -L 3000:127.0.0.1:3000 g-storage
# open http://127.0.0.1:3000/
```

Grafana uses GitHub OAuth restricted to the `sjtug` organization and mirrors
maintainer team. Provisioned datasources and dashboards live under
`monitor/g-storage/grafana/`. The active set is `Mirror Monitor Overview`,
`Mirror Repository Traffic`, `Mirror Hotspot Analytics`, `Caddy Hosts`, and
`Node Exporter Full`. The hotspot dashboard queries successfully but remains
empty until edge xray door `5104` is activated.

### Render, validate, and deploy

Run the monitoring targets from `/home/sjtug/mirror-docker-g-storage`. They
operate on the rootful nerdctl stack and do not build or load mirror-host
images:

```sh
just g-storage-check
sudo just g-storage-render
sudo just g-storage-config
sudo just g-storage-build       # only after changing the custom Grafana image
sudo just g-storage-up
sudo just g-storage-ps
sudo just g-storage-logs
```

`g-storage-up` uses `--no-build --pull never`. Preload any missing pinned image
before deployment. The external containerd CNI network `metacubexd_default`
must contain Alertmanager and the mihomo proxy with the `metacubexd` alias.
Never create a disconnected placeholder network.

The renderers write ignored runtime files under `monitor/g-storage/runtime/`.
Prometheus, Alertmanager, blackbox-exporter, and Grafana receive only their
service-specific secret files. Renderer output is replaced atomically, so use
`sudo just g-storage-reload` to recreate containers after a configuration change;
a simple in-container reload can retain the previous bind-mounted inode.

Persistent Prometheus, Alertmanager, Grafana, Loki, and ClickHouse data live in
rootful containerd or the fixed host paths declared by Compose. Never run
`nerdctl compose down -v`.

Mirror-host SOPS activation and tunnel-only rollout are documented under
**Unified xray tunnel** in `monitor/g-storage/README.md`. Run the recipes from
the canonical checkout, for example:

```sh
cd /opt/mirror-docker-siyuan
sudo just mirror-config siyuan
sudo just mirror-tunnel-reload siyuan
sudo just mirror-tunnel-status siyuan
```

Use `zhiyuan` from `/opt/mirror-docker-zhiyuan` for the other edge.

### Alerts and probes

Prometheus scrapes both mirror hosts through authenticated `/monitor/*`
endpoints and sends alerts to Alertmanager. Alertmanager delivers Telegram
notifications through mihomo. If delivery fails, inspect Alertmanager logs and
query its notification metrics before changing credentials:

```promql
sum by (integration) (increase(alertmanager_notifications_total[1h]))
sum by (integration) (increase(alertmanager_notifications_failed_total[1h]))
```

Blackbox probes cover public pages and authenticated monitor endpoints. Caddy's
admin metrics endpoint is reverse-proxied through `/monitor/caddy/metrics`; the
deployed proxy overrides the upstream `Host` header to `localhost:2019` so the
admin endpoint accepts the request.

### Siyuan data55T mount health

Linux may assign a different `/dev/sd*` name after reconnect or reboot, so the
alert does not match a device label. The mirror-siyuan textfile collector runs:

```sh
findmnt -rn --mountpoint /mnt/data55T -o SOURCE,FSTYPE,OPTIONS
```

It publishes `mirror_siyuan_data55t_mount_ok=1` only when `findmnt` reports a
non-empty source and the mount options contain `rw`. A normal result resembles
`/dev/sda ext4 rw,relatime`; the `/dev/sd*` name is deliberately not part of
the alert identity.

`MirrorSiyuanData55TMountDegraded` is the critical data55T client-mount alert
and fires when the source is absent or the mount is read-only. The collector
still publishes filesystem, stable by-path, block, iSCSI session, and
connection metrics for incident diagnosis, but those diagnostics do not
independently page. Postgres mounts
`/mnt/data55T/mirror-postgres-data` directly; retire the obsolete
`MirrorSiyuanPostgresBindMountDegraded` check for `/srv/mirror/postgres-data`.

### Textfile collectors

`g-storage` node-exporter reads
`/var/lib/mirror-monitor/textfile_collector`. Its local
`mirror-monitor-g-storage-textfile.timer` reports `tgt` and backing-store state.
The malformed SSH repository-statistics collector has been retired and every
host currently reports `node_textfile_scrape_error=0`. The legacy SSH iSCSI
collector remains and should be removed now that Siyuan's local collector is
active.

Refresh the tracked g-storage collector and remove the retired repository-stat
unit with:

```sh
cd /home/sjtug/mirror-docker-g-storage
just g-storage-install-collectors
just g-storage-enable-collectors
just g-storage-collector-status
```

Both mirror hosts already run the local `mirror-repo-size-textfile.timer`, and
Siyuan also runs `mirror-siyuan-iscsi-textfile.timer`. The Python size collector
intersects top-level directories with the generated local-repository manifest,
runs with idle I/O priority, serializes scans with a lock, and atomically writes
size and status textfiles to `/var/lib/node_exporter/textfile_collector`.
Refresh the matching tracked units from each host checkout with:

```sh
# mirror-siyuan
just mirror-enable-collectors siyuan

# mirror-zhiyuan
just mirror-enable-collectors zhiyuan
```

Both hosts already run a socket-activated system `node_exporter.service` with
`--collector.textfile.directory /var/lib/node_exporter/textfile_collector` from
`/etc/sysconfig/node_exporter`. The install target verifies this contract and
enables independent timers; it does not replace or restart node-exporter.
Mirror-siyuan's target also installs its local iSCSI/ext4 textfile timer.
Validate every produced `.prom` file with `promtool check metrics`; one malformed
metric causes node-exporter to reject that entire textfile.

The new collectors are visible in Prometheus. Cleanup remains: Siyuan still has
one legacy forced-command repository-size entry in `authorized_keys`, and the
obsolete g-storage SSH iSCSI unit, script, key, and output remain. Review exact
forced-command and key paths before deletion; preserve unrelated SSH keys.

Mirror-intel 0.1.42 reports its own `buffer_path` size and scan health through
`/monitor/mirror-intel/metrics`. Edge Vector derives bounded per-repository
request counts, successful download bytes, and response-time histograms from
native Caddy logs through authenticated `/monitor/vector/metrics` on both hosts.

Useful queries:

```promql
up{job=~"prometheus|alertmanager|node_exporter_g_storage|node_exporter_mirrors|cadvisor_mirrors|caddy_mirrors|lug_mirrors|mirror_intel_mirrors|vector_mirrors|rsync_gateway_mirrors|hotspot_vector|hotspot_clickhouse"}
probe_success{job=~"blackbox_public_http|blackbox_monitor_auth"}
node_textfile_scrape_error{job=~"node_exporter_g_storage|node_exporter_mirrors"}
mirror_siyuan_data55t_mount_ok
mirror_siyuan_iscsi_mount_rw
mirror_siyuan_iscsi_mount_source_matches
mirror_siyuan_iscsi_session_logged_in
mirror_siyuan_iscsi_connection_up
mirror_storage_tgt_target_ready
mirror_storage_tgt_lun_online
mirror_storage_tgt_lun_readonly
mirror_intel_cache_size_bytes{job="mirror_intel_mirrors"}
mirror_intel_cache_size_scan_success{job="mirror_intel_mirrors"}
time() - mirror_intel_cache_size_scan_timestamp_seconds{job="mirror_intel_mirrors"}
mirror_repo_size_collector_success{job="node_exporter_mirrors"}
mirror_repo_size_bytes{job="node_exporter_mirrors"}
mirror_repo_size_repositories{job="node_exporter_mirrors"}
rate(mirror_repo_requests_total{job="vector_mirrors"}[5m])
rate(mirror_repo_download_bytes_total{job="vector_mirrors"}[5m])
histogram_quantile(0.95, sum by (le, host, repo) (rate(mirror_repo_response_time_seconds_bucket{job="vector_mirrors"}[5m])))
```

### iSCSI incident checks

```sh
# mirror-siyuan
findmnt /mnt/data55T
docker inspect siyuan-postgres --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'
readlink -f /dev/disk/by-path/ip-10.32.36.148:3260-iscsi-iqn.2025-05.cn.edu.sjtu.mirror:storage.data55T-lun-1
find /sys/class/iscsi_session -maxdepth 2 -name targetname -o -name state
systemctl status open-iscsi.service mnt-data55T.mount
dmesg -T | grep -Ei 'iscsi|ext4|data55T|read-only' | tail -100

# g-storage
systemctl status tgt.service
sudo tgtadm --mode target --op show
lsblk -f /dev/sdc /dev/sdc1
cat /sys/class/block/sdc1/ro
systemctl list-timers 'mirror-monitor-*-textfile.timer'
```

### Deployment and rollback

The checkout cutover is complete: rootful nerdctl bind mounts resolve under
`/home/sjtug/mirror-docker-g-storage`. Validate and deploy from that checkout:

```sh
cd /home/sjtug/mirror-docker-g-storage
just g-storage-check
sudo just g-storage-config
sudo just g-storage-reload
```

Keep `/home/sjtug/mirror-ng`, the old Docker monitoring/ELK directories, and
their volumes unchanged until their rollback and retention value is explicitly
retired. Docker and containerd volumes are independent. Never use `-v` when
stopping either stack. Roll back the checkout migration by recreating the
nerdctl project from the retired checkout; roll back to Docker only when the
nerdctl stack itself must be abandoned.

## TODO List (with severity)

- High: rollout `37aa0df` to g-storage, Siyuan, and Zhiyuan. Reconcile the
  dirty g-storage checkout, then run `sudo just mirror-tunnel-reload SITE` from each
  canonical `/opt` checkout. Verify xray port `5104`, confirm buffer drain into
  ClickHouse, and check Grafana dashboard rendering.
- High: retire `MirrorSiyuanPostgresBindMountDegraded` rule/collector; Postgres
  now uses `/mnt/data55T/mirror-postgres-data` directly.
- High: remove retired `mirror-monitor-siyuan-iscsi-textfile` unit, script, SSH
  key, and output on g-storage.
- Medium: delete unreferenced `~/.cache/mirror-monitor-vector-hotfix` on mirror
  hosts.
- Medium: remove legacy forced-command repository-size SSH key on Siyuan.
- Medium: establish retention schedule for `/home/sjtug/mirror-ng`, legacy
  ELK stack, and Loki rollback pipeline.
- Medium: rotate legacy monitoring, Telegram, OAuth, and tunnel credentials.
