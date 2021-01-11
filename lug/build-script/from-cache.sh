#!/bin/bash

set -e

if [ "$USE_SJTUG" = true ] ; then
    wget -O tmp.tar.gz $1 || wget -O tmp.tar.gz $2 || wget -O tmp.tar.gz $3
else
    timeout 5 curl -I $1 & 
    wget -O tmp.tar.gz $3
fi
