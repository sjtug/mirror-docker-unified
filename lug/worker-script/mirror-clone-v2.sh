#!/bin/bash

set -e

export $(cat /secrets_s3 | xargs)

timeout 4h /app/v2/mirror-clone $@
