# Mirror monitoring Grafana panels

Grafana is the human-facing UI while Prometheus remains internal to the Docker
network. The Prometheus datasource and `Mirror Monitor Overview` dashboard are
provisioned from this directory.

## Host overview: `g-storage`, `mirror-siyuan`, `mirror-zhiyuan`

- CPU busy: `100 * (1 - avg by (host) (rate(node_cpu_seconds_total{mode="idle",job=~"node_exporter_mirrors|node_exporter_g_storage"}[5m])))`
- Memory used: `100 * (1 - (node_memory_MemAvailable_bytes{job=~"node_exporter_mirrors|node_exporter_g_storage"} / node_memory_MemTotal_bytes{job=~"node_exporter_mirrors|node_exporter_g_storage"}))`
- Filesystem used: `100 * (1 - node_filesystem_avail_bytes{job=~"node_exporter_mirrors|node_exporter_g_storage",fstype!~"tmpfs|devtmpfs|overlay|squashfs|proc|sysfs|cgroup2?"} / node_filesystem_size_bytes{job=~"node_exporter_mirrors|node_exporter_g_storage",fstype!~"tmpfs|devtmpfs|overlay|squashfs|proc|sysfs|cgroup2?"})`
- Disk read/write throughput: `rate(node_disk_read_bytes_total{job=~"node_exporter_mirrors|node_exporter_g_storage"}[5m])` and `rate(node_disk_written_bytes_total{job=~"node_exporter_mirrors|node_exporter_g_storage"}[5m])`
- Disk I/O time: `rate(node_disk_io_time_seconds_total{job=~"node_exporter_mirrors|node_exporter_g_storage"}[5m])`

## Docker/cAdvisor

- Container CPU: `sum by (host, name) (rate(container_cpu_usage_seconds_total{job="cadvisor_mirrors",name!=""}[5m]))`
- Container memory: `container_memory_working_set_bytes{job="cadvisor_mirrors",name!=""}`
- Container availability: `up{job="cadvisor_mirrors"}`

## HTTP/HTTPS endpoint health

- Probe success: `probe_success{job=~"blackbox_public_http|blackbox_monitor_auth"}`
- Probe duration: `probe_duration_seconds{job=~"blackbox_public_http|blackbox_monitor_auth"}`
- TLS expiry: `probe_ssl_earliest_cert_expiry{job=~"blackbox_public_http|blackbox_monitor_auth"} - time()`

## Service exporters

- Target availability: `up{job=~"caddy_mirrors|lug_mirrors|mirror_intel_mirrors|rsync_gateway_mirrors"}`
- Caddy response throughput: `sum by (host) (rate(caddy_http_response_size_bytes_sum{job="caddy_mirrors"}[5m]))`
- Caddy request rate: `sum by (host) (rate(caddy_http_requests_total{job="caddy_mirrors"}[5m]))`

## ext4 over iSCSI health

- Client collector: `mirror_siyuan_iscsi_collector_success`
- Alerting mount state: `mirror_siyuan_data55t_mount_ok` (`findmnt` reports a source and `rw`)
- Diagnostic mount state: `mirror_siyuan_iscsi_mount_present`, `mirror_siyuan_iscsi_mount_rw`, `mirror_siyuan_iscsi_fs_type_ext4`, `mirror_siyuan_iscsi_mount_source_matches`
- Diagnostic session state: `mirror_siyuan_iscsi_session_logged_in`, `mirror_siyuan_iscsi_connection_up`
- Server state: `mirror_storage_tgt_service_active`, `mirror_storage_tgt_target_ready`, `mirror_storage_tgt_lun_online`, `mirror_storage_tgt_lun_readonly`
- Active initiators: `mirror_storage_tgt_active_connections`

## Mirror Intel cache size

Both mirror-intel instances expose their configured `buffer_path` size directly
through the existing `/monitor/mirror-intel/metrics` scrape:

`mirror_intel_cache_size_bytes{job="mirror_intel_mirrors",host=~"mirror-siyuan|mirror-zhiyuan"}`

The provisioned `Mirror Intel cache size` panel shows both hosts. Scan success
and last-success time are available as `mirror_intel_cache_size_scan_success`
and `mirror_intel_cache_size_scan_timestamp_seconds`; no host-side textfile or
SSH collector is required for this cache metric.

## Per-repository size and downloads

Both mirror hosts run the local repository-size textfile collector. The
`Largest repositories` panel uses:

`topk(20, mirror_repo_size_bytes{job="node_exporter_mirrors"})`

Edge Vector derives the repository from each Caddy URL and exports bounded
log-derived metrics through `/monitor/vector/metrics`:

- `mirror_repo_requests_total{repo,method,status_class}`;
- `mirror_repo_download_bytes_total{repo}` for successful 2xx GET responses;
- `mirror_repo_response_time_seconds{repo}`.

The overview's `Repository download throughput` panel uses:

`topk(20, sum by (host, repo) (rate(mirror_repo_download_bytes_total{job="vector_mirrors",repo!="_other"}[5m])))`

The dedicated provisioned `Mirror Repository Traffic` dashboard adds host and
repository selectors, selected-range totals, request and download-byte share
pie charts, per-repository request and throughput trends, status and method
patterns, p95 response time, repository storage share from the textfile
collectors, and download turnover relative to stored size. It reads only
bounded Prometheus labels and covers both `mirror-siyuan` and
`mirror-zhiyuan`.

The first URL path segment is the repository label; `/git/<repo>/...` is
normalized to `/git/<repo>`. Root, `/monitor/`, and `/lug/` requests are
excluded. Unknown repository paths use `_other`, methods are reduced to `GET`,
`HEAD`, or `OTHER`, and statuses are reduced to HTTP classes.

## Alerts

- Active: `ALERTS{alertstate="firing"}`
- Pending: `ALERTS{alertstate="pending"}`
