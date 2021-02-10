#!/bin/bash
set -e

wget -q -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
if [ "$USE_SJTUG" = true ] ; then
    echo "deb https://mirror.sjtu.edu.cn/sury/php/ buster main" > /etc/apt/sources.list.d/php.list
else
    echo "deb https://packages.sury.org/php/ buster main" > /etc/apt/sources.list.d/php.list
fi
