from node import Node


def cors(matcher: str) -> list[Node]:
    return [
        Node(f"header {matcher} Access-Control-Allow-Origin *"),
        Node(f"header {matcher} Access-Control-Request-Method GET"),
    ]


def gzip(matcher: str) -> list[Node]:
    return [Node(f"encode {matcher} gzip zstd")]


def auth_guard(matcher: str, username: str, password: str) -> list[Node]:
    return [Node(f"basic_auth {matcher}", [Node(f"{username} {password}")])]


def handler_order() -> list[Node]:
    """Return middleware order; Caddy applies these mutations sequentially."""
    return [
        Node("order cerberus before redir"),
        Node("order bandwidth_quota before cerberus"),
        Node("order waf before bandwidth_quota"),
    ]


def bandwidth_quota_policy(paths: list[str] | None = None) -> list[Node]:
    matcher_children = [Node("method GET")]
    if paths:
        matcher_children.append(Node(f"path {' '.join(paths)}"))
    return [
        Node("@bandwidth_quota_download", matcher_children),
        Node(
            "bandwidth_quota @bandwidth_quota_download",
            [
                Node("state_path {$CADDY_BANDWIDTH_QUOTA_DB:/data/bandwidth-quota.db}"),
                Node(
                    "whitelist_file "
                    "{$CADDY_BANDWIDTH_QUOTA_WHITELIST_FILE:"
                    "caddy/waf/blacklist/bandwidth-quota-whitelist.txt}"
                ),
                Node("ipv4_prefix 24"),
                Node("ipv6_prefix 64"),
                Node("window 5h 30GiB"),
                Node("window 168h 150GiB"),
                Node("window 720h 500GiB"),
            ],
        ),
    ]


def waf_policy() -> list[Node]:
    waf_dir = "{$CADDY_WAF_DIR:caddy/waf}"
    ip_blacklist_file = (
        "{$CADDY_WAF_IP_BLACKLIST_FILE:caddy/waf/blacklist/crawler-ip-blacklist.txt}"
    )
    ip_whitelist_file = (
        "{$CADDY_WAF_IP_WHITELIST_FILE:"
        "caddy/waf/blacklist/bandwidth-quota-whitelist.txt}"
    )
    dns_blacklist_file = (
        "{$CADDY_WAF_DNS_BLACKLIST_FILE:caddy/waf/blacklist/dns-blacklist.txt}"
    )
    return [
        Node(
            "waf",
            [
                Node(f"rule_file {waf_dir}/general-policy.json"),
                Node(f"rule_file {waf_dir}/crawler-policy.json"),
                Node(f"ip_blacklist_file {ip_blacklist_file}"),
                Node(f"ip_whitelist_file {ip_whitelist_file}"),
                Node(f"dns_blacklist_file {dns_blacklist_file}"),
                Node("anomaly_threshold 10"),
                Node("max_request_body_size 1048576"),
                Node("log_severity info"),
                Node("log_json"),
                Node("log_path {$CADDY_WAF_LOG_PATH:/var/log/caddy/mirrorz/waf.log}"),
                Node("redact_sensitive_data"),
            ],
        )
    ]


def hidden(exclude: str = "") -> list[Node]:
    if exclude:
        return [
            Node("@hidden", [Node("path */.*"), Node(f"not path {exclude}")]),
            Node("respond @hidden 404"),
        ]
    else:
        return [Node("@hidden path */.*"), Node("respond @hidden 404")]


def log() -> list[Node]:
    return [
        Node(
            "log",
            [
                Node(
                    "output file {$CADDY_LOG_PATH:/tmp/caddy/mirrorz/access.log}",
                    [Node("mode 0644")],
                ),
                Node(
                    "format json",
                    [
                        Node("time_key timestamp"),
                        Node("time_format unix_seconds_float"),
                        Node("duration_format seconds"),
                    ],
                ),
            ],
        ),
        Node("log_append serverip {http.request.local.host}"),
        Node("log_append server_port {http.request.local.port}"),
        Node("log_append scheme {http.request.scheme}"),
        Node("log_append uri {http.request.uri.path}"),
        Node("log_append http_host {http.request.host}"),
        Node("log_append request_id {http.request.uuid}"),
        # Reverse-proxy placeholders are empty for file-server responses. Vector
        # conditionally forwards them only when an upstream was selected.
        Node("log_append upstream_addr {http.reverse_proxy.upstream.hostport}"),
        Node(
            "log_append upstream_header_time_ms {http.reverse_proxy.upstream.latency_ms}"
        ),
        Node(
            "log_append upstream_response_time_ms {http.reverse_proxy.upstream.duration_ms}"
        ),
    ]


def reverse_proxy(prefix: str, target: str, strip_prefix: bool = True) -> list[Node]:
    directive = "handle_path" if strip_prefix else "handle"

    return [Node(f"{directive} {prefix}/*", [Node(f"reverse_proxy {target}")])]


def metrics(prefix: str) -> list[Node]:
    return [Node(f"metrics {prefix}")]
