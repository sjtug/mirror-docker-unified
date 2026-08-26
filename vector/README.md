# Edge Caddy log adapter

This directory is the edge adapter between Caddy's native structured access
log, local repository metrics, and the `mirrorz-log` central Vector interface.
Caddy remains responsible for safely encoding untrusted request values. Edge
Vector parses that JSON, selects the downstream fields, and re-encodes one
compact JSON object in the Vector event's `message` field. The event also
retains Vector's `file` field and adds `org` and `server` outside `message`.
Central forwarding is required on Siyuan and Zhiyuan and uses the shared
`CN=sjtu` mTLS client identity; local and CI configurations remain metrics-only.

## Forwarded fields

Every valid access event sends the compact fields consumed by
`mirrorz-log/config/vector/central.yaml`:

- numeric `timestamp`, `status`, `size`, and `resp_time`;
- `clientip`, `serverip`, `method`, `scheme`, `url`, and `proto`;
- `http_host`, `referer`, `user_agent`, and `request_id`;
- `sent_http_content_type`, taken from Caddy's final response headers;
- `range_requested`, a bounded 0/1 value derived from the presence of the
  request `Range` header. The raw header is not forwarded.

For a Caddy `reverse_proxy` response only, the adapter also sends:

- `upstream_addr`, from the selected upstream host and port;
- `upstream_header_time`, Caddy's upstream header latency converted from
  milliseconds to seconds;
- `upstream_response_time`, Caddy's selected-upstream duration converted from
  milliseconds to seconds.

The presence of `upstream_addr` lets the central normalizer derive `proxied=1`.
Static-file events omit all upstream keys instead of sending empty placeholders.
The central normalizer maps `size` to `body_bytes_sent`, `resp_time` to
`request_time`, `referer` to `http_referer`, and `user_agent` to
`http_user_agent`; it derives request method, URL, and HTTP version from
`method`, `url`, and `proto`. It preserves outer `org` and `server` before
parsing `message`.

## Deliberately omitted

The adapter does not forward Caddy's logger metadata, remote port, bytes read,
rewritten URI, full request/response header maps, or duplicate combined
`request` string. It also omits Nginx-specific fields that have no reliable
Caddy equivalent: `proxy_pass`, `upstream_status`, `upstream_connect_time`, and
`cache_status`.

`remote_user` and `http_x_forwarded_for` are not persisted by the current
ClickHouse document and are unnecessary personal/untrusted data, so they are
not sent. `clientip` deliberately uses Caddy's direct peer `remote_ip`, matching
Nginx `$remote_addr`; it does not trust `X-Forwarded-For`.

Invalid Caddy JSON is rerouted to the edge parse-error file and never reaches
the central sink.

The same normalized event feeds local Prometheus metrics. Vector derives the
repository from the first URL path segment (`/git/<repo>` is kept as a compound
repository name), excludes root and operational `/monitor/` and `/lug/`
requests, and validates the label against the site-specific generated
`caddy/repositories.<site>.csv` enrichment table. Unknown public path segments
share the bounded `_other` label instead of creating attacker-controlled time
series. Method labels are similarly bounded to `GET`, `HEAD`, or `OTHER`, and
status labels to HTTP classes.

Vector exposes the following log-derived metrics on port 9598:

- `mirror_repo_requests_total{repo,method,status_class}` for access patterns;
- `mirror_repo_download_bytes_total{repo}` for successful 2xx GET response
  bytes;
- `mirror_repo_response_time_seconds{repo}` as a response-time histogram.

Caddy publishes the endpoint as authenticated `/monitor/vector/metrics`.
Vector restarts reset counters and Prometheus `rate`/`increase` handle resets.

`run.sh` always loads `vector.yaml`, which owns parsing, metrics, and parse-error
output. It adds `central-sink.yaml` when `ca.crt`, `client.crt`, and
`client.key` are readable under `/etc/mirrorz/vector/tls`. The Siyuan and
Zhiyuan Compose overrides set `VECTOR_REQUIRE_CENTRAL_FORWARDING=true`, so
production fails closed when credentials are absent. Central sink healthchecks
are disabled because its 4 GiB disk buffer is the outage boundary: collector
unavailability queues logs without taking down `/monitor/vector/metrics`.

The same `vector.yaml` also sends a hotspot branch through the existing
`tunnel:5104` xray door. It classifies repositories against the generated
catalog, drops operational paths, marks the event for the central router, and
uses an independent 4 GiB disk buffer. No additional TLS configuration is
needed because xray is the encrypted transport. The central Vector excludes
these marked events from the legacy Loki branch and writes only the sanitized
form to ClickHouse.

Run `make vector-check` to validate the shared configuration, field contract,
and startup without the optional external MirrorZ TLS credentials.
