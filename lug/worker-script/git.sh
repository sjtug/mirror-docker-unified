#!/bin/bash

set -e

if [[ ! -d $LUG_path ]]; then
    git clone --mirror $LUG_source $LUG_path
fi

cd $LUG_path

git remote set-url origin $LUG_source
git remote add upstream $LUG_target || git remote set-url upstream $LUG_target

git config --unset-all remote.origin.fetch
git config --add remote.origin.fetch "+refs/heads/*:refs/heads/*"
git config --add remote.origin.fetch "+refs/tags/*:refs/tags/*"

git fetch -p origin

# dpdk repo contains "remotes/github". We should remove them.
git for-each-ref --format 'delete %(refname)' refs/remotes | git update-ref --stdin
git for-each-ref --format 'delete %(refname)' refs/pull | git update-ref --stdin

git push --mirror upstream
