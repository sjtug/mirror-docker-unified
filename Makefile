caddy-update-dist:
	./scripts/download_latest_frontend.sh

caddy-verify-config:
	docker-compose run --rm caddy caddy validate --config /etc/caddy/Caddyfile

caddy-format-config:
	docker-compose run --rm caddy caddy fmt /etc/caddy/Caddyfile > caddy/Caddyfile.new
	mv caddy/Caddyfile.new caddy/Caddyfile
