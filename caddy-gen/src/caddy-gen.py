#!/usr/bin/env python3

import yaml
from loguru import logger
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

    render = Node('route /render/*', [
        Node('uri strip_prefix /render'),
        Node('reverse_proxy https://service.prerender.io')
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
        [reject_lug_api, reject_lug_api_respond]


def repo_redir(repo: Repo) -> list[Node]:
    return [Node(f'redir /{repo.get_name()} /{repo.get_name()}/ 301')]


def repo_no_redir(base: str, repo: Repo, site: str) -> list[Node]:
    return [
        Node(f'http://{base}/{repo.get_name()}', repo_redir(repo)),
        Node(f'http://{base}/{repo.get_name()}/*',
             repo.as_site() + [sjtug_mirror_id(site)])
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
            logger.error(
                f'repo "{name}": {path} should have the same suffix as {name}, ignored')
            return None
        return FileServerRepo(name, path)
    if serve_mode == 'mirror_intel':
        return ProxyRepo(repo['name'], 'mirror-intel:8000', False, False)
    if serve_mode == 'proxy':
        return ProxyRepo(repo['name'], repo['proxy_to'], True, True)
    if serve_mode == 'git':
        return ProxyRepo(repo['name'], 'git-backend', False, False)
    if serve_mode == 'ignore':
        return None
    logger.error(
        f'repo "{repo["name"]}": unsupported serve mode {serve_mode}, ignored')
    return None


def gen_repos(base: str, repos: dict, first_site: bool, site: str) -> tuple[list[Node], list[Node]]:
    outer_nodes = []
    file_server_nodes = []
    git_server_nodes = []

    gzip_disabled_list = []

    for repo_ in repos:
        repo = dict_to_repo(repo_)
        if repo is not None:
            if repo_.get('no_direct_serve', False):
                continue

            if repo_.get('no_redir_http', False):
                if is_local(base):
                    logger.warning(
                        f'repo "{repo["name"]}": BASE "{base}" might be a local url, "no_redir_http" will be ignored')
                else:
                    outer_nodes += repo_no_redir(base, repo, site)
            file_server_nodes += repo_redir(repo)
            if repo.get_name().startswith('git/'):
                git_server_nodes += repo.as_repo()
            else:
                file_server_nodes += repo.as_repo()

            if 'subdomain' in repo_ and first_site:
                outer_nodes += [Node(repo_['subdomain'],
                                     repo.as_subdomain() + [sjtug_mirror_id(site)])]

            if not repo.enable_repo_gzip():
                gzip_disabled_list.append(repo.get_name())

    file_server_nodes += [BLANK_NODE]
    file_server_nodes += [Node('@git_libgit2', [Node(f'path /git/*'),
                                                Node(f'header User-Agent *libgit2*')])]
    file_server_nodes += [Node('reverse_proxy @git_libgit2 git-backend', [])]
    file_server_nodes += [Node('@git_normal', [Node(f'path /git/*'),
                                               Node(f'not header User-Agent *libgit2*')])]
    file_server_nodes += [Node('route @git_normal', git_server_nodes)]

    # disable gzip for all proxy repos
    gzip_disabled = [Node(
        '@gzip_enabled', [Node(f'not path /{prefix}/*') for prefix in gzip_disabled_list])]
    file_server_nodes += gzip_disabled
    file_server_nodes += gzip('@gzip_enabled')

    return outer_nodes, file_server_nodes


def sjtug_mirror_id(site: str) -> Node:
    return Node(f'header * x-sjtug-mirror-id {site}')


def build_root(base, config_yaml: dict, first_site: bool, site: str) -> Node:
    common_nodes = common()
    no_redir_nodes, file_server_nodes = gen_repos(
        base, config_yaml['repos'], first_site, site)

    main_children = common_nodes + [BLANK_NODE]
    main_children += [sjtug_mirror_id(site)]  # SJTUG mirror ID header
    main_children += cors("/mirrorz/*")   # mirrorz.org protocol support
    main_children += [BLANK_NODE] + file_server_nodes
    main_node = Node(f'{base}', main_children)
    http_base = Node(f'http://{base}/', log() + [
        Node(f'redir / https://{base}/ 308')
    ])
    return Node('',
                [http_base] +
                no_redir_nodes +
                [main_node])


def rewrite_config(repo: dict, site: str):
    serve_mode = repo.get('serve_mode', 'default')
    if repo.get('unified', '') == 'proxy':
        return {
            'name': repo['name'],
            'proxy_to': f"{BASES[site][0]}/{repo['name']}",
            'serve_mode': 'proxy'
        }
    if serve_mode == 'default' or serve_mode == 'git':
        name = repo['name']
        return {
            'name': name,
            'serve_mode': 'redir',
            'target': f'https://{BASES[site][0]}/{name}'
        }
    if serve_mode == 'redir' or serve_mode == 'redir_force':
        return {
            'name': repo['name'],
            'serve_mode': serve_mode,
            'target': repo['target']
        }
    if serve_mode == 'mirror_intel':
        return {
            'name': repo['name'],
            'serve_mode': serve_mode
        }
    if serve_mode == 'proxy':
        return {
            'name': repo['name'],
            'proxy_to': repo['proxy_to']
        }
    return None


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
    args = parser.parse_args()

    INDENT_CNT = args.indent

    sites = args.site.split(',')
    site_configs = {}
    for site in sites:
        logger.info(f"parsing config for {site}")
        with open(f'{args.input}/config.{site}.yaml', 'r') as fp:
            content = fp.read().replace('\t', '')
            site_configs[site] = yaml.load(content, Loader=yaml.FullLoader)

    logger.info(f'rewriting configs')
    rewritten_repos = {}

    for site in sites:
        site_config = site_configs[site]
        for repo in site_config['repos']:
            name = repo['name']
            if name in rewritten_repos:
                logger.info(f'duplicated entry found: {name}')
                continue
            if repo.get('unified', '') == 'disable':
                continue
            rewritten_repo = rewrite_config(repo, site)
            if rewritten_repo is not None:
                rewritten_repos[name] = rewritten_repo

    for site in sites:
        repos = site_configs[site]['repos']
        names = [repo['name'] for repo in repos]
        new_repo_names = []
        for (name, repo) in rewritten_repos.items():
            if name not in names:
                repos.append(repo)
                new_repo_names.append(name)
        logger.info(
            f'{site}: {len(names)} local repos, {len(new_repo_names)} remote repos')
        logger.info(f'local repos: {str(sorted(names))}')
        logger.info(f'remote repos: {str(sorted(new_repo_names))}')

    for site in sites:
        logger.info(f"generating {site}")

        config_yaml = site_configs[site]
        roots = []
        roots.append(Node(" ", [Node('key_type rsa4096')]))

        for (idx, base) in enumerate(BASES[site]):
            roots.append(build_root(base, config_yaml, idx == 0, site))

        output = f'{args.output}/Caddyfile.{site}'
        with open(output, 'w') as fp:
            for root in roots:
                fp.write(str(root))
                fp.write("\n\n")

        logger.info(f'{output}: done')
