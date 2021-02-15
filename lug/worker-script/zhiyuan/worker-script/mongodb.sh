#!/bin/bash

set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

ADDITIONAL_FLAGS='--exclude rsync-sentinal --exclude "*.html" --delete' $DIR/awss3.sh
