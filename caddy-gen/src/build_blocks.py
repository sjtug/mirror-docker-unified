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
