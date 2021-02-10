#!/bin/bash

set -e

if [ "$USE_SJTUG" = true ] ; then
    wget -q -O julia.tar.gz https://mirrors.ustc.edu.cn/julia-releases/bin/linux/x64/1.5/julia-1.5.0-linux-x86_64.tar.gz
else
    wget -q -O julia.tar.gz https://julialang-s3.julialang.org/bin/linux/x64/1.5/julia-1.5.0-linux-x86_64.tar.gz
fi

tar -xf julia.tar.gz && rm julia.tar.gz
