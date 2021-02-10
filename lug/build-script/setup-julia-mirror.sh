#!/bin/bash

set -e

if [ "$USE_SJTUG" = true ] ; then
    export JULIA_PKG_SERVER=https://mirrors.sjtug.sjtu.edu.cn/julia
fi

julia -e 'using Pkg; pkg"add StorageMirrorServer@v0.2.1"'
