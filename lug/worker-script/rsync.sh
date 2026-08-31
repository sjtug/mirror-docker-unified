#!/bin/bash

# Retry policy for unstable connections.
#
# lug re-invokes this script `retry` times with a fixed `retry_interval`
# between attempts (oneshot_common in config.siyuan.yaml / config.zhiyuan.yaml),
# which cannot ride out longer network hiccups. Retry transient rsync failures
# here with exponential backoff and jitter; --partial-dir=.rsync-partial lets
# every attempt resume interrupted files instead of starting them over.
#
# Tunables (optional, per repo in the config yaml, exported as LUG_*):
#   rsync_retries     extra attempts after the first one (default 4)
#   rsync_retry_base  initial backoff in seconds, doubled per attempt (default 30)
#   rsync_retry_cap   maximum backoff in seconds (default 600)

if [ "$LUG_ignore_vanish" ]; then
	IGNOREEXIT=24
	IGNOREOUT='^(file has vanished: |rsync warning: some files vanished before they could be transferred)'
fi

if [ "$LUG_mirror_path" ]; then
	LUG_path="$LUG_mirror_path"
fi

if [[ -z "$RSYNC_SSH" ]]; then
	# Fail fast on unreachable upstreams so the retry ladder below (and
	# lug's own outer retry) kicks in instead of hanging on a dead path.
	conntimeout=--contimeout=60
fi

max_retries="${LUG_rsync_retries:-4}"
retry_base="${LUG_rsync_retry_base:-30}"
retry_cap="${LUG_rsync_retry_cap:-600}"

# Transient failures worth retrying:
#   5  error starting client-server protocol (e.g. daemon at max connections)
#   10 error in socket I/O
#   12 error in rsync protocol data stream ("connection unexpectedly closed")
#   23 partial transfer due to error
#   30 timeout in data send/receive
#   35 timeout waiting for daemon connection
is_retryable() {
	case "$1" in
	5 | 10 | 12 | 23 | 30 | 35) return 0 ;;
	*) return 1 ;;
	esac
}

tmp_stderr=$(mktemp "/tmp/lug-rsync.XXX")

attempt=0
while :; do
	attempt=$((attempt + 1))

	eval rsync -aHvh --no-o --no-g --stats --delete --delete-delay --safe-links --exclude '.~tmp~' --partial-dir=.rsync-partial --timeout=600 $conntimeout $LUG_rsync_extra_flags "$LUG_source" "$LUG_path" 2> "$tmp_stderr"
	retcode="$?"

	if [ "$LUG_ignore_vanish" ]; then
		if [ "$retcode" -eq "$IGNOREEXIT" ]; then
			if grep -E "$IGNOREOUT" "$tmp_stderr"; then
				retcode=0
			fi
		fi
	fi

	if [ "$retcode" -eq 0 ]; then
		break
	fi

	if [ "$attempt" -gt "$max_retries" ] || ! is_retryable "$retcode"; then
		break
	fi

	delay=$((retry_base << (attempt - 1)))
	if [ "$delay" -gt "$retry_cap" ]; then
		delay=$retry_cap
	fi
	delay=$((delay + RANDOM % (retry_base + 1)))
	echo "[$LUG_name] rsync attempt $attempt failed (exit $retcode), retrying in ${delay}s" >&2
	cat "$tmp_stderr" >&2
	sleep "$delay"
done

cat "$tmp_stderr" >&2
rm -f "$tmp_stderr"

chmod 755 $LUG_path

exit "$retcode"
