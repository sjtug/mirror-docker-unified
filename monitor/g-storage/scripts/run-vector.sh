#!/bin/sh
set -eu

read_secret() {
  name=$1
  path=$2
  if [ ! -r "$path" ]; then
    echo "required Vector secret is not readable: $path" >&2
    exit 78
  fi
  value=$(tr -d '\r\n' <"$path")
  if [ -z "$value" ]; then
    echo "required Vector secret is empty: $path" >&2
    exit 78
  fi
  export "$name=$value"
}

read_secret HOTSPOT_CLICKHOUSE_INGEST_PASSWORD /run/secrets/hotspot_clickhouse_ingest_password
read_secret HOTSPOT_CLIENT_HASH_KEY /run/secrets/hotspot_client_hash_key

exec vector --config /etc/vector/vector.toml --require-healthy true
