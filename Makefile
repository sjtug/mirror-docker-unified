caddy-update-dist:
	./scripts/download_latest_frontend.sh

caddy-verify-config:
	docker-compose run --rm caddy caddy validate --config /etc/caddy/Caddyfile.siyuan
	docker-compose run --rm caddy caddy validate --config /etc/caddy/Caddyfile.zhiyuan

caddy-gen:
	cd caddy-gen && pipenv run python src/caddy-gen.py -i ../ -o ../caddy --site siyuan,zhiyuan

caddy-hash-password:
	docker-compose run --rm caddy caddy hash-password

caddy-gen-local:
	cd caddy-gen && pipenv run python src/caddy-gen.py -i ../lug -o ../caddy --site local

caddy-reload:
	docker-compose exec -w /etc/caddy caddy caddy reload

format-config: # You need to install prettier from npm to use this functionality
	prettier *.yaml -w

integration-test:
	cd integration-test && pipenv run pytest

gateway-gen:
	cd gateway-gen && pipenv run python src/gateway-gen.py -i ../ -o ../rsync-gateway --site siyuan,zhiyuan
	cd gateway-gen && pipenv run python src/gateway-gen.py -i ../ -o ../rsync-gateway-v4 --site siyuan,zhiyuan --v4

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

.PHONY: caddy-gen gateway-gen integration-test
