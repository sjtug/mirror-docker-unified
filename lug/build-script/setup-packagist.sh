#!/bin/bash
set -e

curl -sS https://getcomposer.org/installer -o composer-setup.php
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
git clone https://github.com/sjtug/packagist-mirror && cd packagist-mirror
git checkout b911d35edc976c6348a3aefd05ff1fe963d8015e
if [ "$USE_SJTUG" = true ] ; then
    composer config -g repos.packagist composer https://packagist.mirrors.sjtug.sjtu.edu.cn
fi
composer install
