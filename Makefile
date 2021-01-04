caddy-update-dist:
	./scripts/download_latest_frontend.sh

caddy-verify-config:
	docker-compose run --rm caddy caddy validate --config /etc/caddy/Caddyfile

caddy-format-config:
	docker-compose run --rm caddy caddy fmt /etc/caddy/Caddyfile > caddy/Caddyfile.new
	mv caddy/Caddyfile.new caddy/Caddyfile

caddy-gen:
	cd caddy-gen && pipenv run python caddy-gen.py -i ../lug/config.yaml -o ../caddy/Caddyfile -D

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

.PHONY: caddy-gen integration-test
