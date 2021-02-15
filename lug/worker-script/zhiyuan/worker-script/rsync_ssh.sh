#!/bin/bash

set -e
export RSYNC_SSH=1
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
$DIR/rsync.sh
