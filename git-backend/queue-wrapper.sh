#!/bin/bash

set -Eeuo pipefail

QUEUE_SERVER_HOST="${QUEUE_SERVER_HOST:-127.0.0.1}"
QUEUE_SERVER_PORT="${QUEUE_SERVER_PORT:-8888}"

if ! exec 3<"/dev/tcp/${QUEUE_SERVER_HOST}/${QUEUE_SERVER_PORT}"; then
    printf 'git queue is unavailable; refusing to start pack-objects\n' >&2
    exit 75
fi

# upload-pack writes the complete pack-objects revision input before reading
# its output. Buffer it before waiting so upload-pack cannot block on the pipe.
# A temporary file preserves the byte stream (command substitution would strip
# trailing newlines) and bounds the wrapper's memory use.
input_file=$(mktemp "${TMPDIR:-/tmp}/git-queue-input.XXXXXX")
cleanup() {
    rm -f "$input_file"
}
trap cleanup EXIT
cat >"$input_file"
exec 4>&1
exec >&2

waited=0
granted=0
while read -u 3 -r line; do
    if [[ "$line" == "0" ]]; then
        granted=1
        break
    fi
    if [[ ! "$line" =~ ^[1-9][0-9]*$ ]]; then
        printf 'invalid response from git queue: %q\n' "$line"
        exit 75
    fi
    printf 'Waiting in queue... (Position: %s)\r' "$line"
    waited=1
done
if (( waited == 1 )); then
    printf '\n'
fi
if (( granted == 0 )); then
    printf 'git queue disconnected before granting a slot\n'
    exit 75
fi

# Do not exec: keeping fd 3 open tells the queue that this slot remains active
# until pack-objects exits.
"$@" <"$input_file" 3<&- >&4 4>&-
