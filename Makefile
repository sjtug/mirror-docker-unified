caddy-update-dist:
	./scripts/download_latest_frontend.sh

caddy-verify-config:
	docker-compose run --rm caddy caddy validate --config /etc/caddy/Caddyfile

caddy-format-config:
	docker-compose run --rm caddy caddy fmt /etc/caddy/Caddyfile > caddy/Caddyfile.new
	mv caddy/Caddyfile.new caddy/Caddyfile

caddy-gen:
	cd caddy-gen && pipenv run python caddy-gen.py -i ../lug/config.yaml -o ../caddy/Caddyfile -D

caddy-gen-local:
	cd caddy-gen && pipenv run python caddy-gen.py -i ../lug/config.local.yaml -o ../caddy/Caddyfile -D

lug-format-config: # You need to install prettier from npm to use this functionality
	prettier lug/*.yaml -w

integration-test:
	cd integration-test && pipenv run pytest

.PHONY: caddy-gen integration-test
