#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

$DIR/mirror-clone-v2.sh --workers 8 --target-type s3 --s3-prefix anaconda/pkgs \
    --s3-buffer-path /srv/disk1/mirror-clone-cache --print-plan 100 --no-delete conda $DIR/conda.pkgs.yaml
$DIR/mirror-clone-v2.sh --workers 8 --target-type s3 --s3-prefix anaconda/cloud \
    --s3-buffer-path /srv/disk1/mirror-clone-cache --print-plan 100 --no-delete conda $DIR/conda.cloud.yaml
