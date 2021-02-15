#!/bin/bash

RSYNC_PASSWORD=$LUG_password rsync -rtv --delete --delete-after --delay-updates --safe-links --max-delete=1000 --exclude '.~tmp~/' --partial-dir=.rsync-partial --timeout=600 --contimeout=600 $LUG_source $LUG_path
