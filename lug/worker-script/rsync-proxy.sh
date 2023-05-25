#!/bin/bash

if [ "$LUG_ignore_vanish" ]; then
	IGNOREEXIT=24
	IGNOREOUT='^(file has vanished: |rsync warning: some files vanished before they could be transferred)'
fi

tmp_stderr=$(mktemp "/tmp/lug-rsync.XXX")

eval rsync -4aHvh --no-o --no-g --stats --delete --delete-delay --safe-links --exclude '.~tmp~' --partial-dir=.rsync-partial --timeout=600 $LUG_rsync_extra_flags "$LUG_source" "$LUG_path" 
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
