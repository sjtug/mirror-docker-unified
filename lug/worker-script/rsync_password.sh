#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

export RSYNC_PASSWORD=$LUG_password

$DIR/rsync.sh
