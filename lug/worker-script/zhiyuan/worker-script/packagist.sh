#!/bin/bash

export HTTP_PROXY="$(echo ${HTTP_PROXY} | sed 's/http:/tcp:/')"
export HTTPS_PROXY="$(echo ${HTTPS_PROXY} | sed 's/http:/tcp:/')"
/app/packagist-mirror/pull.sh
