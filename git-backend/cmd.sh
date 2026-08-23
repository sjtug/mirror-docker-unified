#!/usr/bin/env bash

set -e

THREADS="${THREADS:-8}"
QUEUE_SIZE="${QUEUE_SIZE:-1}"
QUEUE_SERVER_PORT="${QUEUE_SERVER_PORT:-8888}"
export QUEUE_SERVER_PORT

# The minimal Nix base image does not create the conventional runtime
# directory. Both the FastCGI socket and nginx's PID file live here.
mkdir -p /run
rm -f /run/fcgi.sock

go-queue \
    --queue-size "$QUEUE_SIZE" \
    --port-number "$QUEUE_SERVER_PORT" &

spawn-fcgi -s /run/fcgi.sock -n -- \
    /runtime/bin/multiwatch -f "$THREADS" -- /runtime/bin/fcgiwrap &

nginx -e stderr -c /etc/nginx/nginx.conf -g "daemon off;" &

# Stop the container if any critical process exits. tini forwards signals to
# the complete process group and the container runtime cleans up on exit.
wait -n
exit 1
