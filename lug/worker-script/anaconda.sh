#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

$DIR/mirror-clone-v2.sh --target-type s3 --s3-prefix anaconda/pkgs \
    $@ conda $DIR/conda.pkgs.yaml
$DIR/mirror-clone-v2.sh --target-type s3 --s3-prefix anaconda/cloud \
    $@ conda $DIR/conda.cloud.yaml
