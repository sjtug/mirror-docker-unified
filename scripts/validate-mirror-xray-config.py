#!/usr/bin/env python3
"""Validate the shared edge xray door contract without printing secrets."""

from __future__ import annotations

import argparse
import json
import sys
import uuid
from pathlib import Path
from typing import Any

EXPECTED_DOOR_PORTS = {5003, 5004, 5005, 5007, 5009, 5104}
EXPECTED_G_STORAGE_ADDRESS = "10.32.36.148"


def fail(message: str) -> None:
    raise ValueError(message)


def one(items: list[dict[str, Any]], description: str) -> dict[str, Any]:
    if len(items) != 1:
        fail(f"expected exactly one {description}, found {len(items)}")
    return items[0]


def validate(path: Path, template: bool) -> None:
    try:
        config = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot load xray configuration: {error}")

    inbounds = config.get("inbounds")
    outbounds = config.get("outbounds")
    rules = config.get("routing", {}).get("rules")
    if not isinstance(inbounds, list) or not isinstance(outbounds, list):
        fail("inbounds and outbounds must be lists")
    if not isinstance(rules, list):
        fail("routing.rules must be a list")

    doors = [item for item in inbounds if item.get("protocol") == "dokodemo-door"]
    ports = {item.get("port") for item in doors}
    if ports != EXPECTED_DOOR_PORTS:
        got_ports = sorted(ports, key=str)
        fail(
            f"dokodemo-door ports must be {sorted(EXPECTED_DOOR_PORTS)}, got {got_ports}"
        )
    destinations = {item.get("settings", {}).get("address") for item in doors}
    if destinations != {EXPECTED_G_STORAGE_ADDRESS}:
        fail(
            "all dokodemo-door destinations must use the private g-storage "
            f"address {EXPECTED_G_STORAGE_ADDRESS}"
        )

    door_5104 = one(
        [item for item in doors if item.get("tag") == "door-5104"],
        "door-5104 inbound",
    )
    settings = door_5104.get("settings", {})
    if door_5104.get("listen") != "0.0.0.0" or door_5104.get("port") != 5104:
        fail("door-5104 must listen on 0.0.0.0:5104")
    if settings.get("port") != 5104 or "tcp" not in settings.get("network", ""):
        fail("door-5104 must forward TCP port 5104")
    destination = settings.get("address")
    if destination != EXPECTED_G_STORAGE_ADDRESS:
        fail(
            "door-5104 destination must use the private g-storage address "
            f"{EXPECTED_G_STORAGE_ADDRESS}"
        )

    g_storage = one(
        [item for item in outbounds if item.get("tag") == "g-storage"],
        "g-storage outbound",
    )
    if g_storage.get("protocol") != "vless":
        fail("g-storage outbound must use VLESS")
    vnext = g_storage.get("settings", {}).get("vnext", [])
    server = one(vnext, "g-storage VLESS server")
    if server.get("address") != destination:
        fail("door-5104 and VLESS outbound must use the same g-storage address")
    if server.get("port") != 19200:
        fail("g-storage VLESS outbound must use port 19200")
    user = one(server.get("users", []), "g-storage VLESS user")
    user_id = user.get("id")
    if not isinstance(user_id, str):
        fail("g-storage VLESS user id is missing")
    if template:
        if user_id != "__XRAY_UUID__":
            fail("tracked xray template must contain the UUID placeholder")
    else:
        try:
            uuid.UUID(user_id)
        except ValueError as error:
            raise ValueError("g-storage VLESS user id is not a UUID") from error

    route = one(
        [item for item in rules if item.get("outboundTag") == "g-storage"],
        "route to g-storage",
    )
    routed_tags = set(route.get("inboundTag", []))
    expected_tags = {f"door-{port}" for port in EXPECTED_DOOR_PORTS}
    if routed_tags != expected_tags:
        fail(f"g-storage route must contain {sorted(expected_tags)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument("--template", action="store_true")
    args = parser.parse_args()
    try:
        validate(args.path, args.template)
    except (AttributeError, TypeError, ValueError) as error:
        print(f"xray configuration validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
