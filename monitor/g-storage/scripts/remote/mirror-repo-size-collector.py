#!/usr/bin/env python3
"""Collect per-repository apparent sizes for node_exporter's textfile collector."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DEFAULT_DATA_DIRS = {
    "siyuan": Path("/mnt/data55T/data"),
    "zhiyuan": Path("/mnt/data12T"),
}
DEFAULT_OUTPUT_DIR = Path("/var/lib/node_exporter/textfile_collector")
DEFAULT_REPOSITORIES_FILE = Path("/etc/mirror-monitor/local-repositories.txt")


def metric_label(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as output:
            output.write(content)
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def repository_paths(data_dir: Path, repositories_file: Path) -> dict[str, Path]:
    allowed = set()
    for raw_line in repositories_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line and not line.startswith("#"):
            allowed.add(line)
    if not allowed:
        raise RuntimeError(f"no repository names found in {repositories_file}")

    repositories: dict[str, Path] = {}
    with os.scandir(data_dir) as entries:
        for entry in entries:
            try:
                if entry.name in allowed and entry.is_dir(follow_symlinks=True):
                    repositories[entry.name] = Path(entry.path)
            except OSError:
                continue
    if not repositories:
        raise RuntimeError(f"no repository directories found under {data_dir}")
    return repositories


def collect_sizes(data_dir: Path, repositories_file: Path) -> dict[str, int]:
    repositories = repository_paths(data_dir, repositories_file)
    sizes: dict[str, int] = {}
    for name, path in sorted(repositories.items()):
        result = subprocess.run(
            ["du", "-b", "-s", "-H", "--", str(path)],
            check=True,
            capture_output=True,
            text=True,
        )
        line = result.stdout.rstrip("\n")
        raw_size, separator, raw_path = line.partition("\t")
        if not separator or raw_path != str(path):
            raise RuntimeError(f"unexpected du output for {path}: {line!r}")
        size = int(raw_size)
        if size < 0:
            raise RuntimeError(f"negative size returned for {path}")
        sizes[name] = size
    return sizes


def size_metrics(host: str, sizes: dict[str, int], timestamp: int) -> str:
    host_label = metric_label(host)
    lines = [
        "# HELP mirror_repo_size_bytes Repository apparent size in bytes.",
        "# TYPE mirror_repo_size_bytes gauge",
    ]
    for repo, size in sorted(sizes.items()):
        lines.append(
            f"mirror_repo_size_bytes{{host={host_label},repo={metric_label(repo)}}} {size}"
        )
    lines.extend(
        [
            "# HELP mirror_repo_size_scan_timestamp_seconds Unix timestamp of the latest successful repository size scan.",
            "# TYPE mirror_repo_size_scan_timestamp_seconds gauge",
            f"mirror_repo_size_scan_timestamp_seconds{{host={host_label}}} {timestamp}",
            "# HELP mirror_repo_size_repositories Number of repositories in the latest successful size scan.",
            "# TYPE mirror_repo_size_repositories gauge",
            f"mirror_repo_size_repositories{{host={host_label}}} {len(sizes)}",
        ]
    )
    return "\n".join(lines) + "\n"


def status_metrics(host: str, success: bool, timestamp: int) -> str:
    host_label = metric_label(host)
    return "\n".join(
        [
            "# HELP mirror_repo_size_collector_success Whether the latest repository size collection attempt succeeded.",
            "# TYPE mirror_repo_size_collector_success gauge",
            f"mirror_repo_size_collector_success{{host={host_label}}} {int(success)}",
            "# HELP mirror_repo_size_collector_timestamp_seconds Unix timestamp of the latest repository size collection attempt.",
            "# TYPE mirror_repo_size_collector_timestamp_seconds gauge",
            f"mirror_repo_size_collector_timestamp_seconds{{host={host_label}}} {timestamp}",
            "",
        ]
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--site", choices=sorted(DEFAULT_DATA_DIRS), required=True)
    parser.add_argument("--data-dir", type=Path)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument(
        "--repositories-file", type=Path, default=DEFAULT_REPOSITORIES_FILE
    )
    parser.add_argument("--lock-dir", type=Path, default=Path("/run/lock"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    site: str = args.site
    data_dir: Path = args.data_dir or DEFAULT_DATA_DIRS[site]
    output_dir: Path = args.output_dir
    host = f"mirror-{site}"
    timestamp = int(time.time())
    lock_path = args.lock_dir / f"mirror-repo-size-{site}.lock"
    success = False

    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            sizes = collect_sizes(data_dir, args.repositories_file)
            atomic_write(
                output_dir / "mirror_repo_sizes.prom",
                size_metrics(host, sizes, timestamp),
            )
            success = True
        except (OSError, RuntimeError, subprocess.SubprocessError, ValueError) as error:
            print(f"repository size collection failed: {error}", file=sys.stderr)
        finally:
            atomic_write(
                output_dir / "mirror_repo_size_collector.prom",
                status_metrics(host, success, timestamp),
            )

    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main())
