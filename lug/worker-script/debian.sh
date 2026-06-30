#!/bin/bash

set -e

archvsync_src="${ARCHVSYNC_DIR:-/app/archvsync}"
archvsync_dir="$(mktemp -d)"
trap 'rm -rf "$archvsync_dir"' EXIT

cp -R "$archvsync_src/." "$archvsync_dir"
chmod -R u+w "$archvsync_dir"

cd "$archvsync_dir"

export LOGNAME=

cat > "$archvsync_dir/etc/ftpsync.conf" <<EOF
MIRRORNAME="mirror.sjtu.edu.cn"
TO="$LUG_path"
MAILTO=""
# HUB=false

RSYNC_HOST="$LUG_source"
RSYNC_PATH="debian"
# RSYNC_USER=
# RSYNC_PASSWORD=

INFO_MAINTAINER="Shanghai Jiao Tong University Linux User Group <sjtug-mirror-maintainers@googlegroups.com>"
INFO_SPONSOR="SJTU NIC <https://net.sjtu.edu.cn>"
INFO_COUNTRY="CN"
INFO_LOCATION="Shanghai"
INFO_THROUGHPUT="1Gb"

# ARCH_INCLUDE=
# ARCH_EXCLUDE=

LOGDIR="/var/log/ftpsync"
LOCKDIR="/tmp/ftpsync-locks"
EOF

"$archvsync_dir/bin/ftpsync" sync:all
