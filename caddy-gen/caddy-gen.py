#!/usr/bin/env python3

import yaml
import logging
import argparse
import dataclasses as dc
from pathlib import Path
from config import BASE, LUG_ADDR, ROOT_DIR, FRONTEND_DIR

DESC = 'A simple Caddyfile generator for siyuan.'
INDENT_CNT = 4
IS_LOCAL = BASE.startswith(':')


@dc.dataclass
class Node:
    name: str = ''
    children: list['Node'] = dc.field(default_factory=list)

    def __str__(self, level: int = 0):
        if self.name == '' and len(self.children) == 0:
            return ''
        elif self.name == '':
            return '\n\n'.join(
                [child.__str__(level=level) for child in self.children])
        elif len(self.children) == 0:
            lines = self.name.split('\n')
            return '\n'.join([' ' * (level * INDENT_CNT) + line for line in lines])
        else:
            children_str = '\n'.join(
                [child.__str__(level=level + 1) for child in self.children])
            return ' ' * (level * INDENT_CNT) + self.name + ' {\n' + \
                children_str + '\n' + \
                ' ' * (level * INDENT_CNT) + '}'


BLANK_NODE = Node()


def hidden() -> list[Node]:
    return [Node('@hidden', [Node('path */.*')]),  # hide dot files
            Node('respond @hidden 404')]


def log() -> list[Node]:
    return [Node('log', [
        Node('output stdout'),
        Node('format single_field common_log')  # v1 style logging
    ])]


def common() -> list[Node]:
    frontend = Node('file_server /*', [
        Node(f'root {FRONTEND_DIR}')
    ])

    # TODO: the ratelimit plugin seems to support v1 only? removed
    ratelimit = Node('ratelimit * /lug 40 80 second')

    lug = Node(f'reverse_proxy /lug/* {LUG_ADDR}', [
        # Node('max_conns 500'),
        # Node('max_fails 9999'),
        # Node('fail_timeout 0'),
        Node('header_down Access-Control-Allow-Origin *'),
        Node('header_down Access-Control-Request-Method GET'),
    ])

    gzip = Node('encode gzip')

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

    return log() + \
        [frontend, lug, gzip, BLANK_NODE] + \
        hidden() + \
        [reject_lug_api, reject_lug_api_respond]


def repo_redir(repo: dict) -> list[Node]:
    return [Node(f'redir /{repo["name"]} /{repo["name"]}/ 301')]


def repo_file_server(repo: dict, has_prefix: bool = True) -> list[Node]:
    return [Node(f'file_server {"/" + repo["name"] if has_prefix else ""}/* browse', [
        Node(f'root {ROOT_DIR}'),
        Node(f'hide .*')
    ])]


def repo_no_redir(repo: dict) -> list[Node]:
    return [
        Node(f'http://{BASE}/{repo["name"]}', repo_redir(repo)),
        Node(f'http://{BASE}/{repo["name"]}/*',
             log() + repo_file_server(repo, has_prefix=False) + hidden())
    ]


def repos(repos: dict) -> tuple[list[Node], list[Node]]:
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

        path = Path(repo['path'])
        path_should_be = Path(ROOT_DIR) / repo['name']
        if path != path_should_be:
            logging.error(
                f'repo "{repo["name"]}": path should be {path_should_be}, ignored')
            return False

        return True

    no_redir_nodes = []
    file_server_nodes = []

    for repo in filter(repo_valid, repos):
        if repo.get('no_redir_http', False):
            if IS_LOCAL:
                logging.warning(
                    f'repo "{repo["name"]}": BASE "{BASE}" might be a local url, "no_redir_http" will be ignored')
            else:
                no_redir_nodes += repo_no_redir(repo)
        file_server_nodes += repo_redir(repo)
        file_server_nodes += repo_file_server(repo)

    return no_redir_nodes, file_server_nodes


def build_root(config_yaml: dict) -> Node:
    common_nodes = common()
    no_redir_nodes, file_server_nodes = repos(config_yaml['repos'])

    main_node = Node(f'{BASE}',
                     common_nodes + [BLANK_NODE] +
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

    root = build_root(config_yaml)

    with open(args.output, 'w') as fp:
        fp.write(str(root))
        fp.write("\n")

    print(f'{args.output}: done')
