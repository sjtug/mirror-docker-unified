#!/bin/bash

set -e

for REPO in "prometheus/prometheus" "prometheus/node_exporter" "prometheus/alertmanager" "prometheus/blackbox_exporter" "prometheus/consul_exporter" "prometheus/graphite_exporter" "prometheus/haproxy_exporter" "prometheus/memcached_exporter" "prometheus/mysqld_exporter" "prometheus/pushgateway" "prometheus/statsd_exporter"; do
/app/mirror-clone --concurrent_resolve 8 --workers 4 github_release --repo $REPO --target http://siyuan-mirror-intel:8000/github-release
done
