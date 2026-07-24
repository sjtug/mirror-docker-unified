#!/bin/bash

set -e

THREADS="${THREADS:-8}"
QUEUE_SIZE="${QUEUE_SIZE:-1}"
QUEUE_SERVER_PORT="${QUEUE_SERVER_PORT:-8888}"
export QUEUE_SERVER_PORT

rm -f /run/fcgi.sock

go-queue \
    --queue-size "$QUEUE_SIZE" \
    --port-number "$QUEUE_SERVER_PORT" &

spawn-fcgi -s /run/fcgi.sock -n -- \
    /usr/bin/multiwatch -f "$THREADS" -- /usr/sbin/fcgiwrap &

nginx -g "daemon off;" &

# Stop the container if any critical process exits. tini forwards signals to
# the complete process group and the container runtime cleans up on exit.
wait -n
exit 1
