caddy-update-dist:
	./scripts/download_latest_frontend.sh

caddy-verify-config:
	docker-compose run --rm caddy caddy validate --config /etc/caddy/Caddyfile.siyuan
	docker-compose run --rm caddy caddy validate --config /etc/caddy/Caddyfile.zhiyuan

caddy-gen:
	cd caddy-gen && pipenv run python caddy-gen.py -i ../lug/config.siyuan.yaml -o ../caddy/Caddyfile.siyuan -D
	cd caddy-gen && pipenv run python caddy-gen.py -i ../lug/config.zhiyuan.yaml -o ../caddy/Caddyfile.zhiyuan -D

caddy-hash-password:
	docker-compose run --rm caddy caddy hash-password

caddy-gen-local:
	cd caddy-gen && pipenv run python caddy-gen.py -i ../lug/config.local.yaml -o ../caddy/Caddyfile -D

caddy-reload:
	docker-compose exec -w /etc/caddy caddy caddy reload

lug-format-config: # You need to install prettier from npm to use this functionality
	prettier lug/*.yaml -w

integration-test:
	cd integration-test && pipenv run pytest

up:
	docker-compose up -d --build

up-siyuan:
	docker-compose -f docker-compose.yml -f docker-compose.siyuan.yml up -d --build

up-zhiyuan:
	docker-compose -f docker-compose.yml -f docker-compose.zhiyuan.yml up -d --build

build-siyuan:
	docker-compose -f docker-compose.yml -f docker-compose.siyuan.yml build

build-zhiyuan:
	docker-compose -f docker-compose.yml -f docker-compose.zhiyuan.yml build

build:
	docker-compose build

update-mirrorz:
	docker-compose exec lug /worker-script/mirrorz.sh /srv/disk1/.mirrorz
	cp /mnt/disk1/.mirrorz/* ./data/caddy/dists/mirrorz/

.PHONY: caddy-gen integration-test
