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
    frontends = Node("handle", [
        Node('file_server /*', [
            Node(f'root {FRONTEND_DIR}')
        ]),
        Node('rewrite /docs/* /', comment='for react app'),
        *hidden()
    ])

    lug = Node("handle /lug/*", [
        Node(f'reverse_proxy /lug/* {LUG_ADDR}', [
            Node('header_down Access-Control-Allow-Origin *'),
            Node('header_down Access-Control-Request-Method GET'),
        ]),
        Node('@reject_lug_api', [Node('path /lug/v1/admin/*')]),
        Node('respond @reject_lug_api 403')
    ])

    monitors = Node("handle /monitor/*", [
        *auth_guard('/monitor/*', '{$MONITOR_USER}',
                    '{$MONITOR_PASSWORD_HASHED}'),
        *reverse_proxy('/monitor/node_exporter', NODE_EXPORTER_ADDR),
        *reverse_proxy('/monitor/cadvisor', CADVISOR_ADDR),
        *reverse_proxy('/monitor/lug', LUG_EXPORTER_ADDR),
        *reverse_proxy('/monitor/mirror-intel', MIRROR_INTEL_ADDR),
        *reverse_proxy('/monitor/rsync-gateway', RSYNC_GATEWAY_ADDR),
        *reverse_proxy('/monitor/docker-gcr', 'siyuan-gcr-registry:5001'),
        *reverse_proxy('/monitor/docker-registry', 'siyuan-docker-registry:5001')
        # *metrics("/monitor/caddy")    # enable metrics in global config
    ])

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

    return \
        log() + \
        [BLANK_NODE] + \
        [frontends] + [BLANK_NODE] + \
        [lug] + [BLANK_NODE] + \
        [monitors]


def common_http() -> list[Node]:
    http_redirect_to_https = Node("handle", [
        Node("redir https://{hostport}{uri} 308", [],
             "redirect remaining http requests to https")
    ])
    return log() + [BLANK_NODE] + [http_redirect_to_https]


def handle(repo: Repo, children: list[Node]) -> list[Node]:
    return [Node(f"handle /{repo.get_name()}", children)]


def repo_redir(repo: Repo) -> list[Node]:
    return [Node(f'redir /{repo.get_name()} /{repo.get_name()}/ 301')]


def dict_to_repo(repo: dict) -> Repo:
    extra_directives = [Node(directive)
                        for directive in repo.get('extra_directives', list())]
    serve_mode = repo.get('serve_mode', 'default')
    if serve_mode == 'redir':
        return RedirRepo(repo['name'], repo['target'], False, extra_directives)
    if serve_mode == 'redir_force':
        return RedirRepo(repo['name'], repo['target'], True, extra_directives)
    if serve_mode == 'default':
        path = repo['path']
        name = repo['name']
        if not path.endswith(name):
            logger.error(
                f'repo "{name}": {path} should have the same suffix as {name}, ignored')
            return None
        return FileServerRepo(name, path, extra_directives)
    if serve_mode == 'mirror_intel':
        return ProxyRepo(repo['name'], 'mirror-intel:8000', False, False, extra_directives)
    if serve_mode == 'rsync_gateway':
        return ProxyRepo(repo['name'], 'rsync-gateway:8000', False, False, extra_directives)
    if serve_mode == 'proxy':
        if repo.get('strip_prefix', False):
            return ProxyRepo(repo['name'], repo['proxy_to'], False, True, extra_directives)
        else:
            return ProxyRepo(repo['name'], repo['proxy_to'], True, True, extra_directives)
    if serve_mode == 'git':
        return ProxyRepo(repo['name'], 'git-backend', False, False, extra_directives)
    if serve_mode == 'ignore':
        return None
    logger.error(
        f'repo "{repo["name"]}": unsupported serve mode {serve_mode}, ignored')
    return None


def gen_repos(base: str, repos: dict, first_site: bool, site: str) -> tuple[list[Node], list[Node], list[Node]]:
    outer_nodes = []

    http_file_server_nodes = []
    http_git_server_nodes = []
    http_gzip_disabled_list = ["speedtest"]

    https_file_server_nodes = []
    https_git_server_nodes = []
    https_gzip_disabled_list = ["speedtest"]

    for repo_ in repos:
        repo = dict_to_repo(repo_)
        if repo is not None:
            if repo_.get('no_direct_serve', False):
                continue

            no_redir_http = False
            if repo_.get('no_redir_http', False):
                if is_local(base):
                    logger.warning(
                        f'repo "{repo["name"]}": BASE "{base}" might be a local url, "no_redir_http" will be ignored')
                else:
                    no_redir_http = True

            leaf = repo_redir(repo) + repo.as_repo()
            if repo.get_name().startswith('git/'):
                if no_redir_http:
                    http_git_server_nodes += leaf
                https_git_server_nodes += leaf
            else:
                if no_redir_http:
                    http_file_server_nodes += leaf
                https_file_server_nodes += leaf

            if 'subdomain' in repo_ and first_site:
                outer_nodes += [Node(repo_['subdomain'],
                                     repo.as_subdomain() + [sjtug_mirror_id(site)])]

            if not repo.enable_repo_gzip():
                if no_redir_http:
                    http_gzip_disabled_list.append(repo.get_name())
                https_gzip_disabled_list.append(repo.get_name())

    http_file_server_nodes += [BLANK_NODE]
    https_file_server_nodes += [BLANK_NODE]

    # libgit2 patches -- libgit2 doesn't support 301 redirect
    # file_server_nodes += [Node('@git_libgit2', [Node(f'path /git/*'),
    #                                             Node(f'header User-Agent *libgit2*')])]
    # file_server_nodes += [Node('reverse_proxy @git_libgit2 git-backend', [])]
    # file_server_nodes += [Node('@git_normal', [Node(f'path /git/*'),
    #                                            Node(f'not header User-Agent *libgit2*')])]
    # file_server_nodes += [Node('route @git_normal', git_server_nodes)]

    http_file_server_nodes += http_git_server_nodes
    https_file_server_nodes += https_git_server_nodes

    speed_test_nodes = [BLANK_NODE,
                        Node('redir /speedtest /speedtest/ 308'),
                        Node('handle_path /speedtest/*', [
                            Node(f'reverse_proxy {SPEEDTEST_ADDR}')
                        ])]
    http_file_server_nodes += speed_test_nodes
    https_file_server_nodes += speed_test_nodes

    # disable gzip for all proxy repos
    http_gzip_disabled = [Node(
        '@gzip_enabled', [Node(f'not path /{prefix}/*') for prefix in http_gzip_disabled_list])]
    http_file_server_nodes = [
        *http_gzip_disabled, *gzip('@gzip_enabled'), BLANK_NODE] + http_file_server_nodes

    https_gzip_disabled = [Node(
        '@gzip_enabled', [Node(f'not path /{prefix}/*') for prefix in https_gzip_disabled_list])]
    https_file_server_nodes = [*https_gzip_disabled, *
                               gzip('@gzip_enabled'), BLANK_NODE] + https_file_server_nodes

    return outer_nodes, http_file_server_nodes, https_file_server_nodes


def sjtug_mirror_id(site: str) -> Node:
    return Node(f'header * x-sjtug-mirror-id {site}')


def build_root(base, config_yaml: dict, first_site: bool, site: str) -> Node:
    no_redir_nodes, http_file_server_nodes, https_file_server_nodes = gen_repos(
        base, config_yaml['repos'], first_site, site)

    http_main_children = common_http() + [BLANK_NODE]
    http_main_children += [sjtug_mirror_id(site)]  # SJTUG mirror ID header
    http_main_children += [BLANK_NODE] + http_file_server_nodes
    http_main_node = Node(f'http://{base}', http_main_children)

    https_main_children = common() + [BLANK_NODE]
    https_main_children += [sjtug_mirror_id(site)]  # SJTUG mirror ID header
    https_main_children += cors("/mirrorz/*")   # mirrorz.org protocol support
    https_main_children += [BLANK_NODE] + https_file_server_nodes
    https_main_node = Node(f'https://{base}', https_main_children)

    return Node('',
                no_redir_nodes +
                [http_main_node] +
                [https_main_node])


def rewrite_config(repo: dict, site: str):
    serve_mode = repo.get('serve_mode', 'default')
    if repo.get('unified', '') == 'proxy':
        return {
            'name': repo['name'],
            'proxy_to': f"{BASES[site][0]}",
            'serve_mode': 'proxy',
            'strip_prefix': False
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
    if serve_mode == 'rsync_gateway':
        name = repo['name']
        return {
            'name': name,
            'serve_mode': 'redir',
            'target': f'https://{BASES[site][0]}/{name}'
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
        roots.append(Node(" ", [
            Node('key_type rsa4096'),
            Node('email sjtug-mirror-maintainers@googlegroups.com'),
            Node('preferred_chains smallest'),
            Node('cert_issuer acme'),
            # Node('metrics')   # has performance issue
        ]))

        for (idx, base) in enumerate(BASES[site]):
            roots.append(build_root(base, config_yaml, idx == 0, site))

        output = f'{args.output}/Caddyfile.{site}'
        with open(output, 'w') as fp:
            for root in roots:
                fp.write(str(root))
                fp.write("\n\n")

        logger.info(f'{output}: done')
