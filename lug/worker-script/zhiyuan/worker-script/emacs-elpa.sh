#!/bin/bash

set -xe
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

$DIR/rsync.sh

for value in gnu melpa melpa-stable org
do
    echo "Too many files to list" > ${LUG_path}/${value}/index.html
done
