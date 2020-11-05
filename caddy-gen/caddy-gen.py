#!/usr/bin/env python3

import yaml
import logging
import argparse
import dataclasses as dc
from pathlib import Path
from config import BASE, LUG_ADDR, ROOT_DIR

DESC = 'A simple Caddyfile generator for siyuan.'
INDENT_CNT = 4


@dc.dataclass
class Node:
    name: str
    children: list['Node'] = dc.field(default_factory=list)

    def __str__(self, level: int = 0):
        if self.name == '':
            return '\n\n'.join(
                [child.__str__(level=level) for child in self.children])
        elif len(self.children) == 0:
            return ' ' * (level * INDENT_CNT) + self.name
        else:
            children_str = '\n'.join(
                [child.__str__(level=level + 1) for child in self.children])
            return ' ' * (level * INDENT_CNT) + self.name + ' {\n' + \
                   children_str + '\n' + \
                   ' ' * (level * INDENT_CNT) + '}'


def https_redir() -> list[Node]:
    return [
        Node(f'http://{BASE}', [
            Node('redir / https://{host}{uri} 301')
        ])
    ]


def repo_redir(repo: dict) -> list[Node]:
    return [Node(f'redir /{repo["name"]} /{repo["name"]}/ 301')]


def repo_file_server(repo: dict) -> list[Node]:
    return [Node(f'file_server /{repo["name"]}/* browse', [
        Node(f'root {ROOT_DIR}')
    ])]


def repo_subdomain(repo: dict) -> list[Node]:
    def with_proto(proto: str) -> Node:
        return Node(f'{proto}{repo["subdomain"]}.{BASE}/',
                    repo_file_server(repo))

    if repo.get('no_redir_http', False):
        return [with_proto('https://'), with_proto('http://')]
    else:
        return [with_proto('')]


def repo_valid(repo: dict) -> bool:
    rtype = repo['type']
    if repo['type'] != 'shell_script':
        logging.warning(
            f'repo "{repo["name"]}": type "{rtype}" is not implemented')
        return False

    path = Path(repo['path'])
    path_should_be = Path(ROOT_DIR) / repo['name']
    if path != path_should_be:
        logging.error(
            f'repo "{repo["name"]}": path should be {path_should_be}, ignored')
        return False

    return True


def repos(repos: dict) -> list[Node]:
    subdomain_nodes = []
    file_server_node = Node(f'https://{BASE}', [])

    for repo in filter(repo_valid, repos):
        if 'subdomain' in repo:
            subdomain_nodes += repo_subdomain(repo)
        file_server_node.children += repo_redir(repo)
        file_server_node.children += repo_file_server(repo)

    return subdomain_nodes + [file_server_node]


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

    root = Node('',
                https_redir() +
                repos(config_yaml['repos']))

    with open(args.output, 'w') as fp:
        fp.write(str(root))

    print(f'{args.output}: done')
