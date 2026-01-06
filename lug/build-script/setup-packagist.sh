#!/bin/bash
set -e

curl -sS https://getcomposer.org/installer -o composer-setup.php
php composer-setup.php --install-dir=/usr/local/bin --filename=composer
wget https://github.com/sjtug/packagist-mirror/archive/refs/heads/master.tar.gz && \
  tar -xf master.tar.gz && mv packagist-mirror-master packagist-mirror && rm master.tar.gz && \
  cd packagist-mirror
composer install
