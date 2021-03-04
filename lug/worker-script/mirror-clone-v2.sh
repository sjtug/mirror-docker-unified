#!/bin/bash

set -e

export $(cat /secrets_s3 | xargs)

/app/v2/mirror-clone $@
