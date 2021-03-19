#!/bin/bash

set -e

export http_proxy=http://clash:8080
export https_proxy=http://clash:8080
export HTTP_PROXY=http://clash:8080
export HTTPS_PROXY=http://clash:8080

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

$DIR/mirror-clone-v2.sh --workers 4 --target-type s3 --s3-prefix github-release/$1 --s3-buffer-path /var/cache --s3-scan-metadata --print-plan 100 github-release --repo $1 --version-to-retain $2
