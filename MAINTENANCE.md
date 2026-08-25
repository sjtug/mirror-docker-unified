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

- `$HOME/mirror-docker-zhiyuan` (linked to `/opt/mirror-docker-zhiyuan`)
- `sudo make up-zhiyuan` for startup

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

- `$HOME/mirror-docker-siyuan` (linked to `/opt/mirror-docker-siyuan`)
- `sudo make up-siyuan` for startup

iSCSI client (`open-iscsi.service`) with follow mount record:

```
#/etc/fstab

# iSCSI 55T storage - allow failures with nofail option (not tested)
/dev/disk/by-path/ip-10.32.36.148:3260-iscsi-iqn.2025-05.cn.edu.sjtu.mirror:storage.data55T-lun-1 /mnt/data55T ext4 _netdev,nofail,x-systemd.requires=iscsi.service,x-systemd.after=iscsi.service,x-systemd.device-timeout=30,auto 0 0
/mnt/data55T/mirror-postgres-data /srv/mirror/postgres-data none bind,x-systemd.requires=/mnt/data55T,x-systemd.after=/mnt/data55T 0 0

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
blackbox-exporter, Xray, Vector, and Loki. All configured scrape and blackbox
probe jobs were healthy on 2026-08-25.

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

### Current status (verified 2026-08-25)

- Every Prometheus target group and blackbox probe is healthy, including Caddy
  and Vector on both mirror hosts.
- Both local repository-size collectors report success. Siyuan's local iSCSI
  collector reports the data55T mount present and read-write; the target and LUN
  on g-storage are ready and writable.
- Two alerts are firing:
  - `MirrorNodeTextfileScrapeError`: g-storage still runs the retired
    `mirror-monitor-repo-stats-textfile.timer`. Its 5 MB
    `mirror_repo_stats_siyuan.prom` contains an invalid `\\u` escape and makes
    node-exporter reject that textfile.
  - `MirrorSiyuanPostgresBindMountDegraded`: `/mnt/data55T` is healthy, but
    `/srv/mirror/postgres-data` is not a bind mount. The running Postgres
    container therefore uses the root filesystem path instead of the data55T
    backing directory.
- Mirror-host root filesystems are not currently critical: Siyuan is about 79%
  used and Zhiyuan about 40% used.
- The legacy g-storage SSH iSCSI timer and repository-statistics timer remain
  enabled even though their local mirror-host replacements are active. Remove
  both timers, their scripts/keys, and stale outputs after preserving any
  rollback artifacts that are still needed.
- Mirror-host checkouts currently use a temporary Compose override at
  `~/.cache/mirror-monitor-vector-hotfix/compose.yml` for the deployed Caddy and
  Vector fixes. Replace it with a normal checkout deployment, then remove the
  override directory.

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
`Mirror Repository Traffic`, `Caddy Hosts`, and `Node Exporter Full`; all
rendered without query errors or no-data panels during the 2026-08-25 check.

### Render, validate, and deploy

Run the monitoring targets from `/home/sjtug/mirror-docker-g-storage`. They
operate on the rootful nerdctl stack and do not build or load mirror-host
images:

```sh
make g-storage-check
sudo make g-storage-render
sudo make g-storage-config
sudo make g-storage-build       # only after changing the custom Grafana image
sudo make g-storage-up
sudo make g-storage-ps
sudo make g-storage-logs
```

`g-storage-up` uses `--no-build --pull never`. Preload any missing pinned image
before deployment. The external containerd CNI network `metacubexd_default`
must contain Alertmanager and the mihomo proxy with the `metacubexd` alias.
Never create a disconnected placeholder network.

The renderers write ignored runtime files under `monitor/g-storage/runtime/`.
Prometheus, Alertmanager, blackbox-exporter, and Grafana receive only their
service-specific secret files. Renderer output is replaced atomically, so use
`make g-storage-reload` to recreate containers after a configuration change;
a simple in-container reload can retain the previous bind-mounted inode.

Persistent Prometheus, Alertmanager, Grafana, and Loki volumes live in rootful
containerd. Never run `nerdctl compose down -v`.

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
independently page. `MirrorSiyuanPostgresBindMountDegraded` separately checks
that `/srv/mirror/postgres-data` is backed by data55T; it is currently firing.

### Textfile collectors

`g-storage` node-exporter reads
`/var/lib/mirror-monitor/textfile_collector`. Its local
`mirror-monitor-g-storage-textfile.timer` reports `tgt` and backing-store state.
The local mirror-host collectors are active, but g-storage still runs two
retired SSH collectors. The repository-statistics output is malformed and
currently sets `node_textfile_scrape_error=1`; retire those old units before
considering the collector migration complete.

Refresh the tracked g-storage collector and remove the retired repository-stat
unit with:

```sh
cd /home/sjtug/mirror-docker-g-storage
make g-storage-install-collectors
make g-storage-enable-collectors
make g-storage-collector-status
```

Both mirror hosts already run the local `mirror-repo-size-textfile.timer`, and
Siyuan also runs `mirror-siyuan-iscsi-textfile.timer`. The Python size collector
intersects top-level directories with the generated local-repository manifest,
runs with idle I/O priority, serializes scans with a lock, and atomically writes
size and status textfiles to `/var/lib/node_exporter/textfile_collector`.
Refresh the matching tracked units from each host checkout with:

```sh
# mirror-siyuan
make mirror-enable-collectors MIRROR_SITE=siyuan

# mirror-zhiyuan
make mirror-enable-collectors MIRROR_SITE=zhiyuan
```

Both hosts already run a socket-activated system `node_exporter.service` with
`--collector.textfile.directory /var/lib/node_exporter/textfile_collector` from
`/etc/sysconfig/node_exporter`. The install target verifies this contract and
enables independent timers; it does not replace or restart node-exporter.
Mirror-siyuan's target also installs its local iSCSI/ext4 textfile timer.
Validate every produced `.prom` file with `promtool check metrics`; one malformed
metric causes node-exporter to reject that entire textfile.

The new collectors are visible in Prometheus. Cleanup remains: Siyuan still has
one legacy forced-command repository-size entry in `authorized_keys`, and
obsolete g-storage SSH collector units, scripts, keys, and outputs remain.
Review exact forced-command and key paths before deletion; preserve unrelated
SSH keys.

Mirror-intel 0.1.42 reports its own `buffer_path` size and scan health through
`/monitor/mirror-intel/metrics`. Edge Vector derives bounded per-repository
request counts, successful download bytes, and response-time histograms from
native Caddy logs through authenticated `/monitor/vector/metrics` on both hosts.

Useful queries:

```promql
up{job=~"prometheus|alertmanager|node_exporter_g_storage|node_exporter_mirrors|cadvisor_mirrors|caddy_mirrors|lug_mirrors|mirror_intel_mirrors|vector_mirrors|rsync_gateway_mirrors"}
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
findmnt /srv/mirror/postgres-data
readlink -f /dev/disk/by-path/ip-10.32.36.148:3260-iscsi-iqn.2025-05.cn.edu.sjtu.mirror:storage.data55T-lun-1
find /sys/class/iscsi_session -maxdepth 2 -name targetname -o -name state
systemctl status open-iscsi.service mnt-data55T.mount 'srv-mirror-postgres\x2ddata.mount'
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
make g-storage-check
sudo make g-storage-config
sudo make g-storage-reload
```

Keep `/home/sjtug/mirror-ng`, the old Docker monitoring/ELK directories, and
their volumes unchanged until their rollback and retention value is explicitly
retired. Docker and containerd volumes are independent. Never use `-v` when
stopping either stack. Roll back the checkout migration by recreating the
nerdctl project from the retired checkout; roll back to Docker only when the
nerdctl stack itself must be abandoned.

## TODO List (with severity)

- Critical: restore `/srv/mirror/postgres-data` as the intended bind mount from
  `/mnt/data55T/mirror-postgres-data`. First determine whether the running
  Postgres root-filesystem directory contains newer data, then stop Postgres and
  reconcile data before mounting; do not mount over unexamined live data.
- High: disable and remove g-storage's retired
  `mirror-monitor-repo-stats-textfile` and
  `mirror-monitor-siyuan-iscsi-textfile` units, scripts, dedicated SSH keys, and
  stale outputs. Confirm `node_textfile_scrape_error{host="g-storage"}` returns
  to zero and `MirrorNodeTextfileScrapeError` resolves.
- High: deploy commits `f56de32`, `cf09417`, and `ab1a32d` through the normal
  mirror-host and g-storage checkouts, recreate Caddy/Vector as needed, then
  remove `~/.cache/mirror-monitor-vector-hotfix` from both mirror hosts.
- Medium: remove the verified legacy repository-size forced command and obsolete
  mirror-repo scripts/state on Siyuan, preserving unrelated SSH keys.
- Medium: decide retention dates for `/home/sjtug/mirror-ng`, the Docker
  Elasticsearch/Logstash project, and the g-storage Vector/Loki rollback
  pipeline now that central forwarding is verified.
- Medium: rotate legacy monitor, Telegram, OAuth, and tunnel credentials exposed
  by old generated or backup files.
