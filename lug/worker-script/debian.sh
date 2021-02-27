#!/bin/bash

set -e

cd /app/archvsync

export LOGNAME=

cat > /app/archvsync/etc/ftpsync.conf <<EOF
MIRRORNAME="mirror.sjtu.edu.cn"
TO="$LUG_path"
MAILTO=""
# HUB=false

RSYNC_HOST="$LUG_origin"
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
EOF

/app/archvsync/bin/ftpsync sync:all
