#!/bin/bash

if [ "$LUG_ignore_vanish" ]; then
	IGNOREEXIT=24
	IGNOREOUT='^(file has vanished: |rsync warning: some files vanished before they could be transferred)'
fi

if [ "$LUG_mirror_path" ]; then
	LUG_path="$LUG_mirror_path"
fi

tmp_stderr=$(mktemp "/tmp/lug-rsync.XXX")

eval rsync -aHvh --no-o --no-g --stats --delete --delete-delay --safe-links --exclude '.~tmp~' --partial-dir=.rsync-partial --timeout=600 $LUG_rsync_extra_flags "$LUG_source" "$LUG_path" 2> "$tmp_stderr"
retcode="$?"

cat "$tmp_stderr" >&2

if [ "$LUG_ignore_vanish" ]; then
	if [ "$retcode" -eq "$IGNOREEXIT" ]; then
		if egrep "$IGNOREOUT" "$tmp_stderr"; then
			retcode=0
		fi
	fi
fi

rm -f "$tmp_stderr"

chmod 755 $LUG_path

exit "$retcode"
