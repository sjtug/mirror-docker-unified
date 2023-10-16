#!/bin/bash

set -e

export $(cat /secrets_s3 | xargs)
export $(cat /secrets_pg | xargs)

export RUST_LOG=info
export RUST_BACKTRACE=1

export RSYNC_PASSWORD=$LUG_password

mkdir -p "${LUG_tmp_path}"

LUG_timeout="${LUG_timeout:-4h}"

eval timeout $LUG_timeout /app/rsync_sjtug/rsync-gc --s3-url "\"${LUG_s3_api}\"" --s3-region "\"${LUG_s3_region}\"" --s3-bucket "\"${LUG_s3_bucket}\"" --s3-prefix "\"rsync/${LUG_name}\"" --pg-url "\"${LUG_pg}\"" --namespace "\"${LUG_name}\"" --keep "\"${LUG_keep}\"" --partial "\"${LUG_partial}\""
eval timeout $LUG_timeout /app/rsync_sjtug/rsync-fetcher --src "\"${LUG_source}\"" --s3-url "\"${LUG_s3_api}\"" --s3-region "\"${LUG_s3_region}\"" --s3-bucket "\"${LUG_s3_bucket}\"" --s3-prefix "\"rsync/${LUG_name}\"" --pg-url "\"${LUG_pg}\"" --namespace "\"${LUG_name}\"" --tmp-path "\"${LUG_tmp_path}\"" ${LUG_rsync_extra_flags}
