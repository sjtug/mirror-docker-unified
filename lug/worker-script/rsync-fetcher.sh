#!/bin/bash

set -e

export $(cat /secrets_s3 | xargs)
export RUST_LOG=info
export RUST_BACKTRACE=1

mkdir -p "${LUG_tmp_path}"

timeout 4h /app/rsync-gc --s3-url "${LUG_s3_api}" --s3-region "${LUG_s3_region}" --s3-bucket "${LUG_s3_bucket}" --s3-prefix "rsync/${LUG_name}" --redis "${LUG_redis}" --redis-namespace "${LUG_name}" --keep "${LUG_keep}"
timeout 4h /app/rsync-fetcher --src "${LUG_source}" --s3-url "${LUG_s3_api}" --s3-region "${LUG_s3_region}" --s3-bucket "${LUG_s3_bucket}" --s3-prefix "rsync/${LUG_name}" --redis "${LUG_redis}" --redis-namespace "${LUG_name}" --repository "${LUG_name}" --gateway-base "${LUG_gateway}/${LUG_name}" --tmp-path "${LUG_tmp_path}" ${LUG_rsync_extra_flags}
