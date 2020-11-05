caddy-update-dist:
	./scripts/download_latest_frontend.sh

caddy-verify-config:
	docker-compose run --rm caddy caddy validate --config /etc/caddy/Caddyfile

caddy-format-config:
	docker-compose run --rm caddy caddy fmt /etc/caddy/Caddyfile > caddy/Caddyfile.new
	mv caddy/Caddyfile.new caddy/Caddyfile

caddy-gen:
	cd caddy-gen && pipenv run python caddy-gen.py -i ../lug/config.yaml -o ../caddy/Caddyfile

caddy-gen-local:
	cd caddy-gen && pipenv run python caddy-gen.py -i ../lug/config.local.yaml -o ../caddy/Caddyfile

integration-test:
	cd integration-test && pipenv run pytest

.PHONY: caddy-gen integration-test
