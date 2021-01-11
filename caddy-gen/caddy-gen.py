#!/usr/bin/env python3

import yaml
import logging
import argparse
import dataclasses as dc
from pathlib import Path
from config import BASE, LUG_ADDR, FRONTEND_DIR, NODE_EXPORTER_ADDR, CADVISOR_ADDR, LUG_EXPORTER_ADDR, MIRROR_INTEL_LIST, MIRROR_INTEL_ADDR

DESC = 'A simple Caddyfile generator for siyuan.'
INDENT_CNT = 4


def is_local(base: str):
    return base.startswith(':')


@dc.dataclass
class Node:
    name: str = ''
    children: list['Node'] = dc.field(default_factory=list)
    comment: str = ''

    def __str__(self, level: int = 0):
        if self.name == '' and len(self.children) == 0:
            return ''
        elif self.name == '':
            return '\n\n'.join(
                [child.__str__(level=level) for child in self.children])
        elif len(self.children) == 0:
            lines = self.name.split('\n')
            return '\n'.join([' ' * (level * INDENT_CNT) + line for line in lines]) + self.comment_str()
        else:
            children_str = '\n'.join(
                [child.__str__(level=level + 1) for child in self.children])
            return ' ' * (level * INDENT_CNT) + self.name + ' {' + self.comment_str() + '\n' + \
                children_str + '\n' + \
                ' ' * (level * INDENT_CNT) + '}'

    def comment_str(self):
        return '' if len(self.comment) == 0 else f'  # {self.comment}'


BLANK_NODE = Node()


def hidden() -> list[Node]:
    return [Node('@hidden', [Node('path */.*')]),  # hide dot files
            Node('respond @hidden 404')]


def log() -> list[Node]:
    return [Node('log', [
        Node('output stdout'),
        Node('format single_field common_log', comment='log in v1 style')
    ])]


def auth_guard(matcher: str, username: str, password: str):
    return Node(f'basicauth {matcher}', [
        Node(f'{username} {password}')
    ])


def reverse_proxy(prefix: str, target: str, strip_prifix=True):
    node_list = []
    if strip_prifix:
        node_list.append(Node(f'uri strip_prefix /{prefix}'))
    node_list.append(Node(f'reverse_proxy {target}'))

    return Node(f'route /{prefix}/*', node_list)


def gzip(matcher):
    return Node(f'encode {matcher} gzip zstd')


def common() -> list[Node]:
    frontends = [
        Node('file_server /*', [
            Node(f'root {FRONTEND_DIR}')
        ]),
        Node('rewrite /docs/* /', comment='for react app'),
    ]

    lug = Node(f'reverse_proxy /lug/* {LUG_ADDR}', [
        Node('header_down Access-Control-Allow-Origin *'),
        Node('header_down Access-Control-Request-Method GET'),
    ])

    monitors = [
        auth_guard('/monitor/*', '{$MONITOR_USER}',
                   '{$MONITOR_PASSWORD_HASHED}'),
        reverse_proxy('monitor/node_exporter', NODE_EXPORTER_ADDR),
        reverse_proxy('monitor/cadvisor', CADVISOR_ADDR),
        reverse_proxy('monitor/lug', LUG_EXPORTER_ADDR),
        reverse_proxy('monitor/mirror-intel', MIRROR_INTEL_ADDR),
        reverse_proxy('monitor/docker-gcr', 'siyuan-gcr-registry:5001'),
        reverse_proxy('monitor/docker-registry', 'siyuan-docker-registry:5001')
    ]

    mirror_intel = [
        reverse_proxy(prefix, MIRROR_INTEL_ADDR, False) for prefix in MIRROR_INTEL_LIST
    ]

    not_mirror_intel_repo = Node(
        '@not_mirror_intel_repo', [Node(f'not path /{prefix}/*') for prefix in MIRROR_INTEL_LIST])

    # removed
    crawler_rewrite = Node('rewrite', [
        Node('if_op or'),
        Node('if {>User-Agent} has bot'),
        Node('if {>User-Agent} has googlebot'),
        Node('if {>User-Agent} has crawler'),
        Node('if {>User-Agent} has spider'),
        Node('if {>User-Agent} has robot'),
        Node('if {>User-Agent} has crawling'),
        Node('to /render/{host}{uri}')
    ])

    # removed
    render = Node('reverse_proxy /render service.prerender.io/https://', [
        Node('without /render')
    ])

    reject_lug_api = Node('@reject_lug_api', [Node('path /lug/v1/admin/*')])
    reject_lug_api_respond = Node('respond @reject_lug_api 403')

    return \
        log() + [not_mirror_intel_repo, gzip("@not_mirror_intel_repo")] + [BLANK_NODE] + \
        frontends + [BLANK_NODE] + \
        [lug] + [BLANK_NODE] + \
        monitors + [BLANK_NODE] + \
        mirror_intel + [BLANK_NODE] + \
        hidden() + \
        [reject_lug_api, reject_lug_api_respond]


def repo_redir(repo: dict) -> list[Node]:
    return [Node(f'redir /{repo["name"]} /{repo["name"]}/ 301')]


def repo_redirect(repo: dict) -> list[Node]:
    return [Node(f'route /{repo["name"]}/*', [
            Node(f'uri strip_prefix /{repo["name"]}'),
            Node(f'redir * {repo["target"]} 302') if repo.get('only_target',
                                                              False) else Node(f'redir * {repo["target"]}{{uri}} 302')
            ])]


def cors(matcher: str) -> list[Node]:
    return [
        Node(f'header {matcher} Access-Control-Allow-Origin *'),
        Node(f'header {matcher} Access-Control-Request-Method GET')
    ]


def repo_file_server(repo: dict, has_prefix: bool = True) -> list[Node]:
    real_root = repo["path"][:-len(repo["name"])][:-1]
    cors_node = cors(f"/{repo['name']}/*") if repo.get("cors", False) else []
    return [
        Node(f'file_server {"/" + repo["name"] if has_prefix else ""}/* browse', [
            Node(f'root {real_root}'),
            Node(f'hide .*')
        ])] \
        + cors_node


def repo_no_redir(base: str, repo: dict) -> list[Node]:
    return [
        Node(f'http://{base}/{repo["name"]}', repo_redir(repo)),
        Node(f'http://{base}/{repo["name"]}/*',
             log() + repo_file_server(repo, has_prefix=False) + hidden())
    ]


def repos(base: str, repos: dict) -> tuple[list[Node], list[Node]]:
    def repo_valid(repo: dict) -> bool:
        rtype = repo['type']
        if repo['type'] != 'shell_script':
            logging.warning(
                f'repo "{repo["name"]}": type "{rtype}" is not implemented, ignored')
            return False

        if repo.get('no_direct_serving', False):
            logging.warning(
                f'repo "{repo["name"]}": "no_direct_serving" set, ignored')
            return False

        if 'subdomain' in repo:
            logging.warning(
                f'repo "{repo["name"]}": subdomain is not supported in siyuan, ignored')
            return False

        if 'mirror_intel' in repo:
            if repo["name"] not in MIRROR_INTEL_LIST:
                logging.warning(
                    f'repo "{repo["name"]}": mirror-intel should be configured manually, ignored')
            return False

        if 'target' in repo:
            return True

        path = repo['path']
        name = repo['name']
        if not path.endswith(name):
            logging.error(
                f'repo "{name}": {path} should have the same suffix as {name}, ignored')
            return False

        return True

    no_redir_nodes = []
    file_server_nodes = []

    for repo in filter(repo_valid, repos):
        if repo.get('no_redir_http', False):
            if is_local(base):
                logging.warning(
                    f'repo "{repo["name"]}": BASE "{base}" might be a local url, "no_redir_http" will be ignored')
            else:
                no_redir_nodes += repo_no_redir(base, repo)
        if repo.get('name', '') == 'apache':
            file_server_nodes += [Node('reverse_proxy /apache/ apache:80')]
        if repo.get('no_direct_serve', False):
            pass
        elif "target" in repo:
            file_server_nodes += repo_redir(repo)
            file_server_nodes += repo_redirect(repo)
        else:
            file_server_nodes += repo_redir(repo)
            file_server_nodes += repo_file_server(repo)

    return no_redir_nodes, file_server_nodes


def sjtug_mirror_id() -> Node:
    return Node("header * x-sjtug-mirror-id siyuan")


def reverse_proxy_site(base, target) -> Node:
    return Node(f'{base}', [gzip(""), BLANK_NODE, Node(f'reverse_proxy {target}'), sjtug_mirror_id()])


def build_root(base, config_yaml: dict) -> Node:
    common_nodes = common()
    no_redir_nodes, file_server_nodes = repos(base, config_yaml['repos'])

    main_node = Node(f'{base}',
                     common_nodes + [BLANK_NODE] + [sjtug_mirror_id()] + [BLANK_NODE] +
                     file_server_nodes)

    return Node('',
                no_redir_nodes +
                [main_node])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=DESC)
    parser.add_argument('-i', '--input', required=True,
                        help='Input path for lug\'s config.yaml.')
    parser.add_argument('-o', '--output', required=True,
                        help='Output path for generated Caddyfile.')
    parser.add_argument('-I', '--indent', default=INDENT_CNT,
                        help='Number of spaces in indents.')
    parser.add_argument('-D', '--debug', action='store_true',
                        help='Show debug messages.')
    args = parser.parse_args()

    if not args.debug:
        logging.basicConfig(level=logging.ERROR)

    INDENT_CNT = args.indent

    with open(args.input, 'r') as fp:
        content = fp.read().replace('\t', '')
        config_yaml = yaml.load(content, Loader=yaml.FullLoader)

    roots = []

    for base in BASE:
        roots.append(build_root(base, config_yaml))
    roots.append(reverse_proxy_site(
        'k8s-gcr-io.siyuan.internal.sjtug.org', 'siyuan-gcr-registry:80'))
    roots.append(reverse_proxy_site(
        'docker.siyuan.internal.sjtug.org', 'siyuan-docker-registry:80'))

    with open(args.output, 'w') as fp:
        for root in roots:
            fp.write(str(root))
            fp.write("\n\n")

    print(f'{args.output}: done')
