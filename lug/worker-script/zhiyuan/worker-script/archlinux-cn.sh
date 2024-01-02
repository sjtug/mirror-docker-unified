#!/bin/bash

source /root/lug-secrets.sh
RSYNC_PASSWORD=${ARCHLINUXCN_PASSWORD} rsync -rtlivH --delete-after --delay-updates --safe-links --max-delete=1000 --timeout=600 --contimeout=600 ${ARCHLINUXCN_USERNAME}@sync.repo.archlinuxcn.org::repo $LUG_path
