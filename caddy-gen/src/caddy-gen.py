#!/usr/bin/env python3

import yaml
import logging
import argparse

from pathlib import Path
from config import *
from repos import *
from build_blocks import *
from node import *

DESC = 'A simple Caddyfile generator for siyuan.'


def is_local(base: str):
    return base.startswith(':')


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
        *auth_guard('/monitor/*', '{$MONITOR_USER}',
                    '{$MONITOR_PASSWORD_HASHED}'),
        *reverse_proxy('/monitor/node_exporter', NODE_EXPORTER_ADDR),
        *reverse_proxy('/monitor/cadvisor', CADVISOR_ADDR),
        *reverse_proxy('/monitor/lug', LUG_EXPORTER_ADDR),
        *reverse_proxy('/monitor/mirror-intel', MIRROR_INTEL_ADDR),
        *reverse_proxy('/monitor/docker-gcr', 'siyuan-gcr-registry:5001'),
        *reverse_proxy('/monitor/docker-registry', 'siyuan-docker-registry:5001')
    ]

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

    render = Node('reverse_proxy /render service.prerender.io/https://', [
        Node('without /render')
    ])

    reject_lug_api = Node('@reject_lug_api', [Node('path /lug/v1/admin/*')])
    reject_lug_api_respond = Node('respond @reject_lug_api 403')

    return \
        log() + \
        [BLANK_NODE] + \
        frontends + [BLANK_NODE] + \
        [lug] + [BLANK_NODE] + \
        monitors + [BLANK_NODE] + \
        hidden() + \
        [reject_lug_api, reject_lug_api_respond] + \
        [render, crawler_rewrite]


def repo_redir(repo: Repo) -> list[Node]:
    return [Node(f'redir /{repo.get_name()} /{repo.get_name()}/ 301')]


def repo_no_redir(base: str, repo: Repo) -> list[Node]:
    return [
        Node(f'http://{base}/{repo.get_name()}', repo_redir(repo)),
        Node(f'http://{base}/{repo.get_name()}/*',
             repo.as_site() + [sjtug_mirror_id()])
    ]


def dict_to_repo(repo: dict) -> Repo:
    serve_mode = repo.get('serve_mode', 'default')
    if serve_mode == 'redir':
        return RedirRepo(repo['name'], repo['target'], False)
    if serve_mode == 'redir_force':
        return RedirRepo(repo['name'], repo['target'], True)
    if serve_mode == 'default':
        path = repo['path']
        name = repo['name']
        if not path.endswith(name):
            logging.error(
                f'repo "{name}": {path} should have the same suffix as {name}, ignored')
            return None
        return FileServerRepo(name, path)
    if serve_mode == 'mirror_intel':
        return ProxyRepo(repo['name'], 'mirror-mirror-intel:8000', False)
    if serve_mode == 'proxy':
        return ProxyRepo(repo['name'], repo['proxy_to'], True)
    if serve_mode == 'ignore':
        return None
    logging.error(
        f'repo "{repo["name"]}": unsupported serve mode {serve_mode}, ignored')
    return None


def repos(base: str, repos: dict, first_site: bool) -> tuple[list[Node], list[Node]]:
    outer_nodes = []
    file_server_nodes = []

    gzip_disabled_list = []

    for repo_ in repos:
        repo = dict_to_repo(repo_)
        if repo is not None:
            if repo_.get('no_direct_serve', False):
                continue

            if repo_.get('no_redir_http', False):
                if is_local(base):
                    logging.warning(
                        f'repo "{repo["name"]}": BASE "{base}" might be a local url, "no_redir_http" will be ignored')
                else:
                    outer_nodes += repo_no_redir(base, repo)
            file_server_nodes += repo_redir(repo)
            file_server_nodes += repo.as_repo()

            if 'subdomain' in repo_ and first_site:
                outer_nodes += [Node(repo_['subdomain'],
                                     repo.as_subdomain() + [sjtug_mirror_id()])]

            if not repo.enable_repo_gzip():
                gzip_disabled_list.append(repo.get_name())

    # disable gzip for all proxy repos
    gzip_disabled = [Node(
        '@gzip_enabled', [Node(f'not path /{prefix}/*') for prefix in gzip_disabled_list])]
    file_server_nodes += gzip_disabled
    file_server_nodes += gzip('@gzip_enabled')

    return outer_nodes, file_server_nodes


def sjtug_mirror_id() -> Node:
    return Node("header * x-sjtug-mirror-id siyuan")


def build_root(base, config_yaml: dict, first_site: bool) -> Node:
    common_nodes = common()
    no_redir_nodes, file_server_nodes = repos(base, config_yaml['repos'], first_site)

    main_children = common_nodes + [BLANK_NODE]
    main_children += [sjtug_mirror_id()]  # SJTUG mirror ID header
    main_children += cors("/mirrorz/*")   # mirrorz.org protocol support
    main_children += [BLANK_NODE] + file_server_nodes
    main_node = Node(f'{base}', main_children)

    return Node('',
                no_redir_nodes +
                [main_node])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=DESC)
    parser.add_argument('-i', '--input', required=True,
                        help='Input folder for lug\'s config.yaml.')
    parser.add_argument('-o', '--output', required=True,
                        help='Output folder for generated Caddyfiles.')
    parser.add_argument('-s', '--site', required=True,
                        help='Site names.')
    parser.add_argument('-I', '--indent', default=INDENT_CNT,
                        help='Number of spaces in indents.')
    parser.add_argument('-D', '--debug', action='store_true',
                        help='Show debug messages.')
    args = parser.parse_args()

    if not args.debug:
        logging.basicConfig(level=logging.ERROR)

    INDENT_CNT = args.indent

    SITES = args.site.split(",")
    SITE = SITES[0]

    with open(f'{args.input}/config.{SITE}.yaml', 'r') as fp:
        content = fp.read().replace('\t', '')
        config_yaml = yaml.load(content, Loader=yaml.FullLoader)

    roots = []

    for (idx, base) in enumerate(BASES[SITE]):
        roots.append(build_root(base, config_yaml, idx == 0))

    with open(f'{args.output}/Caddyfile.{SITE}', 'w') as fp:
        for root in roots:
            fp.write(str(root))
            fp.write("\n\n")

    print(f'{args.output}: done')
