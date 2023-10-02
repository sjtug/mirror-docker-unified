from node import Node


def cors(matcher: str) -> list[Node]:
    return [
        Node(f'header {matcher} Access-Control-Allow-Origin *'),
        Node(f'header {matcher} Access-Control-Request-Method GET')
    ]


def gzip(matcher: str) -> list[Node]:
    return [Node(f'encode {matcher} gzip zstd')]


def auth_guard(matcher: str, username: str, password: str) -> list[Node]:
    return [Node(f'basicauth {matcher}', [
        Node(f'{username} {password}')
    ])]


def hidden() -> list[Node]:
    return [
        Node('@hidden path */.*'),
        Node('respond @hidden 404')
    ]


def log() -> list[Node]:
    return [Node('log', [
        Node('output stdout'),
        Node('format transform "{common_log}"',
             comment='log in v1 style, caddyserver/transform-encoder required')
    ])]


def reverse_proxy(prefix: str, target: str, strip_prefix=True) -> list[Node]:
    directive = "handle_path" if strip_prefix else "handle"

    return [Node(f"{directive} {prefix}/*", [Node(f"reverse_proxy {target}")])]


def metrics(prefix: str) -> list[Node]:
    return [Node(f"metrics {prefix}")]
