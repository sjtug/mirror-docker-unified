#!/bin/bash

set -e

wget  -q -O ftpsync.tar.gz http://ftp-master.debian.org/ftpsync.tar.gz
tar -xf ftpsync.tar.gz && rm ftpsync.tar.gz
