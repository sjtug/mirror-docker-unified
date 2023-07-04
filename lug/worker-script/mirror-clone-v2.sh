#!/bin/bash

set -e

export $(cat /secrets_s3 | xargs)

if [ "${LUG_use_proxy}" ]; then 
    export http_proxy=http://clash:8080
    export https_proxy=http://clash:8080
fi

timeout 4h /app/v2/mirror-clone $@
