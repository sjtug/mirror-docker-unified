#!/bin/bash

set -xe

cd "$LUG_path"

git remote add upstream "$LUG_target" || git remote set-url upstream "$LUG_target"
git push --all -f upstream
