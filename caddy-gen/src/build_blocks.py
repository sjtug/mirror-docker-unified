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
    return [Node('@hidden', [Node('path */.*')]),  # hide dot files
            Node('respond @hidden 404')]


def log() -> list[Node]:
    return [Node('log', [
        Node('output stdout'),
        Node('format single_field common_log', comment='log in v1 style')
    ])]


def reverse_proxy(prefix: str, target: str, strip_prifix=True) -> list[Node]:
    node_list = []
    if strip_prifix:
        node_list.append(Node(f'uri strip_prefix {prefix}'))
    node_list.append(Node(f'reverse_proxy {target}'))

    return [Node(f'route {prefix}/*', node_list)]
