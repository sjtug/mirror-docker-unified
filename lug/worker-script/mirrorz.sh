#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

curl -sSLf https://mirror.sjtu.edu.cn/lug/v1/manager/summary > /tmp/siyuan-summary.json
curl -sSLf https://mirrors.sjtug.sjtu.edu.cn/lug/v1/manager/summary > /tmp/zhiyuan-summary.json
curl -sSLf https://sjtug-portal-1251836446.file.myqcloud.com/tags/mirror-help/index.xml > /tmp/help.xml
curl -sSLf https://mirrorz.org/static/json/cname.json > /tmp/cname.json

$DIR/mirrorz.py $DIR/mirrorz/siyuan.json /tmp/siyuan-summary.json /tmp/help.xml /tmp/cname.json > /mirrorz/siyuan.json
$DIR/mirrorz.py $DIR/mirrorz/zhiyuan.json /tmp/zhiyuan-summary.json /tmp/help.xml /tmp/cname.json > /mirrorz/zhiyuan.json
