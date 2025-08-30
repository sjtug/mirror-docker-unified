#!/bin/bash

set -e

if [ "$USE_SJTUG" = true ] ; then
    wget -q -O $4 $1 || wget -q -O $4 $2 || wget -q -O $4 $3
else
    timeout 5 curl -I $1 &
    wget -q -O $4 $3
fi
