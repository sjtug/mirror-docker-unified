#!/usr/bin/env bash

yq ea '. as $item ireduce ({}; . * $item )' /config/*.yaml | sed 's/!!merge //g' > config.merged.yaml

./lug -c config.merged.yaml
