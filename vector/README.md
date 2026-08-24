# Edge Caddy log adapter

This directory is the edge adapter between Caddy's native structured access
log and the `mirrorz-log` central Vector interface. Caddy remains responsible
for safely encoding untrusted request values. Edge Vector parses that JSON,
selects the downstream fields, and re-encodes one compact JSON object in the
Vector event's `message` field. The event also retains Vector's `file` field
and adds `org` and `server` outside `message`.

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

The same normalized event feeds a local Prometheus counter. Vector derives the
repository from the first URL path segment (`/git/<repo>` is kept as a compound
repository name), excludes root and operational `/monitor/` and `/lug/`
requests, ignores non-GET and non-2xx responses, and validates the label
against the site-specific generated
`caddy/repositories.<site>.csv` enrichment table. Unknown public path segments
share the bounded `_other` label instead of creating attacker-controlled time
series. Vector increments `mirror_repo_download_bytes_total{repo=...}` by the
Caddy response body size and exposes it on port 9598. Caddy publishes that
endpoint as authenticated `/monitor/vector/metrics`; Vector restarts reset the
counter and Prometheus `rate`/`increase` handle the reset.

Run `make vector-check` to validate the configuration and its field contract.
