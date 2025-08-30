from typing_extensions import override
from loguru import logger
import dataclasses as dc

from node import Node
from build_blocks import *


class Repo:
    def as_repo(self) -> list[Node]:  # pyright: ignore[reportReturnType]
        pass

    def enable_repo_gzip(self) -> bool:  # pyright: ignore[reportReturnType]
        pass

    def as_site(self) -> list[Node]:  # pyright: ignore[reportReturnType]
        pass

    def as_subdomain(self) -> list[Node]:  # pyright: ignore[reportReturnType]
        pass

    def get_name(self) -> str:  # pyright: ignore[reportReturnType]
        pass


@dc.dataclass
class FileServerRepo(Repo):
    name: str = ""
    path: str = ""
    show_hidden: str | bool = False
    extra_directives: list[Node] = dc.field(default_factory=list)

    @override
    def as_repo(self) -> list[Node]:
        real_root = self.path[: -len(self.name)][:-1]
        base = f"/{self.name}/*"
        if not self.show_hidden:  # '' or False, hide .*
            return [
                Node(
                    f"handle {base}",
                    [
                        Node(
                            "file_server browse",
                            [
                                Node(f"root {real_root}"),
                                Node("hide .*"),
                                *self.extra_directives,
                            ],
                        ),
                        *hidden(),
                    ],
                )
            ]
        elif isinstance(self.show_hidden, str):  # show specific hidden files
            return [
                Node(
                    f"handle {base}",
                    [
                        Node(f"@show_hidden path {self.show_hidden}"),
                        Node(
                            "file_server @show_hidden",
                            [
                                Node(f"root {real_root}"),
                            ],
                        ),
                        Node(
                            "file_server browse",
                            [
                                Node(f"root {real_root}"),
                                Node("hide .*"),
                                *self.extra_directives,
                            ],
                        ),
                        *hidden(self.show_hidden),
                    ],
                )
            ]
        else:  # do not hide any file
            return [
                Node(
                    f"handle {base}",
                    [
                        Node(
                            "file_server browse",
                            [Node(f"root {real_root}"), *self.extra_directives],
                        )
                    ],
                )
            ]

    @override
    def enable_repo_gzip(self) -> bool:
        return True

    @override
    def as_subdomain(self) -> list[Node]:
        if not self.show_hidden:  # '' or False, hide .*
            return (
                gzip("/*")
                + log()
                + [
                    Node(
                        "file_server /* browse",
                        [
                            Node(f"root {self.path}"),
                            Node("hide .*"),
                            *self.extra_directives,
                        ],
                    )
                ]
                + hidden()
            )
        elif isinstance(self.show_hidden, str):  # show specific hidden files
            return (
                gzip("/*")
                + log()
                + [
                    Node(f"@show_hidden path {self.show_hidden}"),
                    Node(
                        "file_server @show_hidden",
                        [
                            Node(f"root {self.path}"),
                        ],
                    ),
                    Node(
                        "file_server /* browse",
                        [
                            Node(f"root {self.path}"),
                            Node("hide .*"),
                            *self.extra_directives,
                        ],
                    ),
                ]
                + hidden(self.show_hidden)
            )
        else:  # do not hide any file
            return (
                gzip("/*")
                + log()
                + [
                    Node(
                        "file_server /* browse",
                        [Node(f"root {self.path}"), *self.extra_directives],
                    )
                ]
            )

    @override
    def get_name(self) -> str:
        return self.name


@dc.dataclass
class ProxyRepo(Repo):
    name: str = ""
    proxy_to: str = ""
    strip_prefix: bool = False
    rewrite_host: bool = True
    extra_directives: list[Node] = dc.field(default_factory=list)

    @override
    def as_repo(self) -> list[Node]:
        proxy_node = Node(
            f"reverse_proxy {self.proxy_to}",
            [Node("header_up Host {http.reverse_proxy.upstream.hostport}")]
            if self.rewrite_host
            else [],
        )
        directive = "handle_path" if self.strip_prefix else "handle"
        return [
            Node(f"{directive} /{self.name}/*", [proxy_node, *self.extra_directives])
        ]

    @override
    def enable_repo_gzip(self) -> bool:
        return False

    @override
    def as_site(self) -> list[Node]:
        return self.as_repo() + log()

    @override
    def as_subdomain(self) -> list[Node]:
        proxy_node = Node(
            f"reverse_proxy {self.proxy_to}",
            [Node("header_up Host {http.reverse_proxy.upstream.hostport}")]
            if self.rewrite_host
            else [],
        )
        proxy_node_prefix = [
            Node(f"rewrite * /{self.name}{{uri}}"),
            Node(f"reverse_proxy {self.proxy_to}"),
        ]
        if self.strip_prefix:
            return log() + [proxy_node, *self.extra_directives]
        else:
            return log() + [*proxy_node_prefix, *self.extra_directives]

    @override
    def get_name(self) -> str:
        return self.name


@dc.dataclass
class RedirRepo(Repo):
    name: str = ""
    target: str = ""
    always_target: bool = False
    extra_directives: list[Node] = dc.field(default_factory=list)

    @override
    def as_repo(self) -> list[Node]:
        redir_always_node = Node(f"redir * {self.target} 302")
        redir_node = Node(f"redir * {self.target}{{uri}} 302")
        if self.always_target:
            return [
                Node(
                    f"handle_path /{self.name}/*",
                    [redir_always_node, *self.extra_directives],
                )
            ]
        else:
            return [
                Node(
                    f"handle_path /{self.name}/*", [redir_node, *self.extra_directives]
                )
            ]

    @override
    def enable_repo_gzip(self) -> bool:
        return False

    @override
    def as_site(self) -> list[Node]:
        logger.warning(f"{self.name}: site redirect repo is not supported")
        return []

    @override
    def as_subdomain(self) -> list[Node]:
        redir_always_node = Node(f"redir * {self.target} 302")
        redir_node = Node(f"redir * {self.target}{{uri}} 302")
        if self.always_target:
            return log() + [redir_always_node, *self.extra_directives]
        else:
            return log() + [redir_node, *self.extra_directives]

    @override
    def get_name(self) -> str:
        return self.name
