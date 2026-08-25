# mirror-docker-unified

Dockerfile for the all SJTUG mirror servers.

## Docs

![New Architecture](docs/images/new-arch.png)

For more information, refer to our [Wiki](https://github.com/sjtug/mirror-docker-unified/wiki).

## Project structure & maintenance

```sh
.
├── apache # apache dockerfile
├── caddy
├── caddy-gen # caddy configuration generator (for ./caddy)
├── clash # clash dockerfile (for secured connection with monitor node)
├── common # common network configuration
├── data # caddy & lug backend dist
├── docs # Documentation
├── frontend # lug frontend (Next.js)
├── gateway-gen # rsync-sjtug configuration generator (for ./rsync-gateway)
├── git-backend # git backend
├── integration-test # test
├── lug # lug backend dockerfile
├── mirror-intel # mirror-intel configuration
├── monitor # g-storage monitoring configuration and collectors
├── rsync-gateway
├── rsyncd
├── scripts
├── secrets
├── upstream
└── vector # edge Caddy access-log forwarding configuration
```

Python version, treefmt, pre-commit configurations are controlled by `devshell.toml` with Nix flakes.

See <https://nixos.org/download/> or <https://lix.systems/install/> for Nix installation manual.

### Caddy access-log forwarding

Caddy writes safely escaped native JSON to
`./data/caddy/log/mirrorz/access.log`. The edge Vector service converts the
nested Caddy event into the flat `mirrorz-log` schema and adds the site-specific
`org` and `server` values from the Compose override. Production sends the
events to the central collector with the shared mirror-host mTLS identity.
Invalid Caddy JSON is excluded from downstream processing and written under
`./data/vector/parse-errors-YYYY-MM-DD.log`. The exact forwarded field contract
and intentionally omitted Nginx-only fields are documented in
[`vector/README.md`](vector/README.md). Vector also exposes bounded
per-repository request, successful-download-byte, and response-time metrics
through authenticated `/monitor/vector/metrics`.

Vector retains file checkpoints and an at-least-once 4 GiB disk buffer under
`./data/vector`. Preserve that directory across container recreation. Validate
the pinned edge configuration and its Caddy mapping with:

```sh
make vector-check
```

### Vector TLS credentials

The Vector sink uses mutual TLS to send Caddy access logs to the central
collector. The current deployment uses one shared `CN=sjtu` client identity for
both mirror hosts. Install these host-local files before starting either
production stack:

```text
/etc/mirrorz/vector/tls/ca.crt
/etc/mirrorz/vector/tls/client.crt
/etc/mirrorz/vector/tls/client.key
```

`docker-compose.yml` mounts `/etc/mirrorz/vector/tls` read-only into the Vector
container. `vector/run.sh` loads the central sink only when all three files are
readable, so missing forwarding credentials do not take down the local
Prometheus metrics endpoint. The Siyuan and Zhiyuan Compose overrides set
`VECTOR_REQUIRE_CENTRAL_FORWARDING=true`, so production startup fails closed
when these files are absent. Keep the client key private (mode `0600`) and never
commit these credentials to this repository. The current deployment uses the
shared mirror-host client identity.

### Monitoring operations

The active g-storage stack, mirror-host collectors, dashboards, deployment
commands, and current operational issues are documented in
[`monitor/g-storage/README.md`](monitor/g-storage/README.md) and
[`MAINTENANCE.md`](MAINTENANCE.md).

## License

Apache 2.0
