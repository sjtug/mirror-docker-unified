#!/usr/bin/env python3

import argparse

import toml
import yaml

from config import *
from loguru import logger

DESC = "A simple rsync-gateway config generator for siyuan."

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=DESC)
    parser.add_argument(
        "-i", "--input", required=True, help="Input folder for lug's config.yaml."
    )
    parser.add_argument(
        "-o", "--output", required=True, help="Output folder for generated config.toml."
    )
    parser.add_argument("-s", "--site", required=True, help="Site names.")
    args = parser.parse_args()

    sites = args.site.split(",")
    site_configs = {}
    for site in sites:
        logger.info(f"parsing config for {site}")
        with open(f"{args.input}/config.{site}.yaml", "r") as fp:
            content = fp.read().replace("\t", "")
            site_configs[site] = yaml.load(content, Loader=yaml.FullLoader)

    logger.info("writing configs")
    base_config = {
        "bind": ["0.0.0.0:8000"],
        "s3_url": S3_API_URL,
        "s3_region": S3_REGION,
        "database_url": DATABASE_URL,
        "log": {
            "format": "json",
        },
    }
    gateway_configs = dict()

    for site in sites:
        gateway_configs[site] = dict()
        gateway_config = gateway_configs[site]
        gateway_config["endpoints"] = dict()
        endpoints = gateway_config["endpoints"]
        site_config = site_configs[site]
        for repo in site_config["repos"]:
            name = repo["name"]
            serve_mode = repo.get("serve_mode", "default")
            if serve_mode == "rsync_gateway":
                s3_bucket = repo["s3_bucket"]
                endpoints[name] = dict()
                endpoint = endpoints[name]
                endpoint["namespace"] = name
                endpoint["s3_bucket"] = s3_bucket
                endpoint["s3_prefix"] = f"rsync/{name}"
        endpoints = dict(sorted(endpoints.items()))

    for site in sites:
        endpoints = gateway_configs[site].get("endpoints", dict())
        logger.info(f"{site}: {len(endpoints)} gateway endpoints")
        logger.info(f"endpoints: {list(endpoints.keys())}")

    for site in sites:
        logger.info(f"generating {site}")

        config_toml = {**base_config, **gateway_configs[site]}
        config_toml["log"]["target"] = f"tcp://tunnel:{LOG_PORT[site]}"  # pyright: ignore[reportIndexIssue, reportCallIssue, reportArgumentType]

        output = f"{args.output}/config.{site}.toml"
        with open(output, "w") as fp:
            toml.dump(config_toml, fp)

        logger.info(f"{output}: done")
