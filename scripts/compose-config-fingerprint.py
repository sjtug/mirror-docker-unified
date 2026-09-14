#!/usr/bin/env python3
"""Emit a Compose override that fingerprints service runtime configuration.

Compose notices image and service-definition changes, but not content changes to
bind-mounted files.  The generated labels make those contents part of each
service definition so `docker compose up` recreates exactly the affected
containers.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Protocol


class Digest(Protocol):
    def update(self, data: bytes) -> None: ...


LABEL = "org.sjtug.runtime-config-sha256"

COMMON_INPUTS: dict[str, tuple[str, ...]] = {
    "caddy": (
        "caddy/Caddyfile.{site}",
        "caddy/waf",
        "secrets/caddy.env",
    ),
    "lug": (
        "config.{site}.yaml",
        "common/gai.conf",
        "secrets/git-credentials",
        "secrets/lug-secrets.sh",
        "secrets/mirror-clone.env",
        "secrets/mirror-intel.env",
        "secrets/pg.env",
    ),
    "rsync-gateway": (
        "rsync-gateway/config.{site}.toml",
        "secrets/mirror-intel.env",
        "secrets/pg.env",
    ),
    "postgres": (
        "postgresql.{site}.conf",
        "secrets/pg.env",
    ),
    "vector": (
        "vector/vector.yaml",
        "vector/central-sink.yaml",
        "vector/run.sh",
        "caddy/repositories.{site}.csv",
    ),
    "clash": ("secrets/clash_config.yaml",),
    "mirror-intel": (
        "common/gai.conf",
        "secrets/mirror-intel.env",
    ),
    "tunnel": ("secrets/xray.json",),
    "rsyncd": (
        "rsyncd/rsyncd.{site}.conf",
        "rsyncd/motd.{site}",
    ),
}

SITE_INPUTS: dict[str, dict[str, tuple[str, ...]]] = {
    "siyuan": {},
    "zhiyuan": {
        "k8s-registry": ("secrets/k8s-registry.yml",),
        "docker-registry": ("secrets/docker-registry.yml",),
    },
}


def _update_record(
    digest: Digest, relative_path: str, kind: bytes, data: bytes
) -> None:
    path_bytes = relative_path.encode()
    digest.update(len(path_bytes).to_bytes(8, "big"))
    digest.update(path_bytes)
    digest.update(kind)
    digest.update(len(data).to_bytes(8, "big"))
    digest.update(data)


def fingerprint(root: Path, inputs: tuple[str, ...], site: str) -> str:
    digest = hashlib.sha256()
    for pattern in inputs:
        relative = Path(pattern.format(site=site))
        metadata_only = relative.parts[0] == "secrets"
        source = root / relative
        if not source.exists() and not source.is_symlink():
            raise FileNotFoundError(f"runtime configuration input is missing: {source}")

        paths = [source]
        if source.is_dir():
            paths.extend(sorted(source.rglob("*")))

        for path in paths:
            rel = path.relative_to(root).as_posix()
            if path.is_symlink():
                _update_record(digest, rel, b"L", str(path.readlink()).encode())
            elif path.is_dir():
                _update_record(digest, rel, b"D", b"")
            elif path.is_file():
                if metadata_only:
                    stat = path.stat()
                    metadata = ":".join(
                        str(value)
                        for value in (
                            stat.st_dev,
                            stat.st_ino,
                            stat.st_mode,
                            stat.st_size,
                            stat.st_mtime_ns,
                            stat.st_ctime_ns,
                        )
                    ).encode()
                    _update_record(digest, rel, b"M", metadata)
                else:
                    _update_record(digest, rel, b"F", path.read_bytes())
            else:
                raise ValueError(f"unsupported runtime configuration input: {path}")
    return digest.hexdigest()


def compose_override(root: Path, site: str) -> dict[str, object]:
    service_inputs = {**COMMON_INPUTS, **SITE_INPUTS[site]}
    return {
        "services": {
            service: {
                "labels": {LABEL: fingerprint(root, inputs, site)},
            }
            for service, inputs in service_inputs.items()
        }
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", choices=sorted(SITE_INPUTS), required=True)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    print(json.dumps(compose_override(args.root.resolve(), args.site), indent=2))


if __name__ == "__main__":
    main()
