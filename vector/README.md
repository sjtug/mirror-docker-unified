# Edge Caddy log adapter

This directory is the edge adapter between Caddy's native structured access
log, local repository metrics, and the optional `mirrorz-log` central Vector
interface. Caddy remains responsible for safely encoding untrusted request
values. Edge Vector parses that JSON, selects the downstream fields, and
re-encodes one compact JSON object in the Vector event's `message` field. The
event also retains Vector's `file` field and adds `org` and `server` outside
`message`.

## Forwarded fields

Every valid access event sends the compact fields consumed by
`mirrorz-log/config/vector/central.yaml`:

- numeric `timestamp`, `status`, `size`, and `resp_time`;
- `clientip`, `serverip`, `method`, `scheme`, `url`, and `proto`;
- `http_host`, `referer`, `user_agent`, and `request_id`;
- `sent_http_content_type`, taken from Caddy's final response headers.

For a Caddy `reverse_proxy` response only, the adapter also sends:

- `upstream_addr`, from the selected upstream host and port;
- `upstream_header_time`, Caddy's upstream header latency converted from
  milliseconds to seconds;
- `upstream_response_time`, Caddy's selected-upstream duration converted from
  milliseconds to seconds.

The presence of `upstream_addr` lets the central normalizer derive `proxied=1`.
Static-file events omit all upstream keys instead of sending empty placeholders.

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
output. It adds `central-sink.yaml` only when `ca.crt`, `client.crt`, and
`client.key` are all readable under `/etc/mirrorz/vector/tls`. This keeps the
monitoring endpoint available before optional forwarding credentials are
provisioned. The Siyuan and Zhiyuan Compose overrides set
`VECTOR_REQUIRE_CENTRAL_FORWARDING=true`, making central forwarding mandatory
for production while local and CI configurations remain metrics-only.

Run `make vector-check` to validate both configuration layers, their field
contract, and metrics-only startup without TLS credentials.
