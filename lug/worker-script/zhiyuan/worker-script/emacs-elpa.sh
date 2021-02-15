#!/bin/bash

set -xe
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

$DIR/rsync.sh

for value in emacswiki gnu marmalade melpa melpa-stable org SC sunrise-commander user42
do
    touch "$LUG_path/$value/index.html"
done
