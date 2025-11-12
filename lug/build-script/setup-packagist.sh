#!/bin/bash
set -e

curl -sS https://getcomposer.org/installer -o composer-setup.php
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
git clone https://github.com/sjtug/packagist-mirror --depth 1 && cd packagist-mirror
composer install
