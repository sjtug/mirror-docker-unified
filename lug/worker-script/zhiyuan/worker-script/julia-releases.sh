#!/bin/bash

set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

ADDITIONAL_FLAGS="--exclude *DO_NOT_UPLOAD_HERE --exclude bin/mac/extras/cctools_bundle.tar.gz --delete" $DIR/awss3.sh
