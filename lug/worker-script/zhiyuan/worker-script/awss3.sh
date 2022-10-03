#!/bin/bash

set -e

aws s3 sync --exact-timestamps --no-sign-request "$LUG_source" "$LUG_path" $ADDITIONAL_FLAGS
