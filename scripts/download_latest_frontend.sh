#!/bin/bash

set -e

LATEST_URL=$(curl -sfL https://api.github.com/repos/sjtug/sjtug-mirror-frontend/releases/latest | jq '.assets[0].browser_download_url' -r)
wget -N -O /tmp/dists.tar.gz "$LATEST_URL"
tar -zxf /tmp/dists.tar.gz --directory data/caddy/dists
