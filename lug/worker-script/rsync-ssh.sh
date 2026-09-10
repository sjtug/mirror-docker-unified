#!/bin/bash

set -e
export RSYNC_SSH=1
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Refresh the upstream's SSH host keys before rsync. Host keys rotate over
# time, so a known_hosts baked into the image would eventually go stale.
# Extract the host from LUG_source ("user@host:path" or "host:path").
#
# shellcheck disable=SC2154
# `LUG_`-prefixed variables are injected by LUG backend
host="${LUG_source%%:*}"
host="${host##*@}"

if [[ -n "$host" ]]; then
	mkdir -p /root/.ssh
	chmod 700 /root/.ssh
	known_hosts=/root/.ssh/known_hosts
	if scanned=$(ssh-keyscan -t rsa,ecdsa,ed25519 -- "$host" 2>/dev/null) && [[ -n "$scanned" ]]; then
		# Replace any existing entries for this host with the fresh scan.
		touch "$known_hosts"
		grep -v "^${host}[ ,]" "$known_hosts" > "$known_hosts.tmp" || true
		printf '%s\n' "$scanned" >> "$known_hosts.tmp"
		mv "$known_hosts.tmp" "$known_hosts"
	elif [[ ! -s "$known_hosts" ]]; then
		echo "ssh-keyscan failed for $host and no cached known_hosts entry exists" >&2
		exit 1
	else
		echo "ssh-keyscan failed for $host; falling back to cached known_hosts" >&2
	fi
fi

. "$DIR"/rsync.sh
