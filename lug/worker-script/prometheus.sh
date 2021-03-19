#!/bin/bash

set -e

for REPO in "prometheus/prometheus" "prometheus/node_exporter" "prometheus/alertmanager" "prometheus/blackbox_exporter" "prometheus/consul_exporter" "prometheus/graphite_exporter" "prometheus/haproxy_exporter" "prometheus/memcached_exporter" "prometheus/mysqld_exporter" "prometheus/pushgateway" "prometheus/statsd_exporter"; do
    /worker-script/github-release.sh $REPO 5
done
