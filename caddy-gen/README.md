# caddy-gen

The Caddyfile generator for SJTUG mirror.

caddy-gen reads lug configuration of Siyuan and Zhiyuan, then generates the
corresponding Caddyfile for both servers. It also emits two monitoring inputs
per site:

- `caddy/repositories.<site>.csv`: bounded repository labels loaded by Vector;
- `caddy/local-repositories.<site>.txt`: local top-level repository names used
  by the node-exporter size collector.

These files are generated artifacts and are checked by `--fail-on-change` with
the Caddyfiles. The common generated monitor routes expose authenticated Caddy,
node-exporter, cAdvisor, LUG, mirror-intel, Vector, and rsync-gateway metrics.
The Caddy admin proxy rewrites to `/metrics` and sends
`Host: localhost:2019`; omitting that header makes the admin API return
`403 host not allowed`.

## Web application firewall

Every generated public site runs `caddy-waf` before Cerberus and redirects. Its
configuration lives under `caddy/waf/`:

- `general-policy.json` is the extension point for general rules and is currently empty;
- `crawler-policy.json` blocks crawler User-Agents confirmed in `crawler.md`;
- the private `blacklist` submodule contains `crawler-ip-blacklist.txt`, with
  the immediate and historical ban networks, `dns-blacklist.txt` for exact
  hostname bans, and `bandwidth-quota-whitelist.txt` for quota and WAF
  IP-reputation exemptions.

Initialize the private submodule before generation, validation, or deployment:

```sh
git submodule update --init caddy/waf/blacklist
```

Developer and deployment credentials performing that command need read access
to the private `sjtug/blacklist` repository. GitHub Actions deliberately skips
the private submodule and selects the tracked, empty `*.txt.example` fixtures
through `docker-compose.ci.yml` and the flake validation hooks.

Rule paths use `{$CADDY_WAF_DIR:caddy/waf}`. The access-list paths can be
overridden independently with `CADDY_WAF_IP_BLACKLIST_FILE`,
`CADDY_WAF_IP_WHITELIST_FILE`, and `CADDY_WAF_DNS_BLACKLIST_FILE`. Production
Compose points all four variables at the read-only `/etc/caddy/waf` mount and
its private submodule. WAF events
default to `/var/log/caddy/mirrorz/waf.log` and can be moved with
`CADDY_WAF_LOG_PATH`. Generic clients such as `python-requests` and `aria2` are
deliberately not blocked globally because legitimate mirror clients use them.

## Repository download quotas

Generated repository-serving routes run the `bandwidth_quota` Caddy module from
the SJTUG `caddy-waf` fork (`v0.4.1-sjtug.2`) after the WAF and before response
encoding. Redirect-only repositories, frontend pages, `/mirrorz/*`, `/lug/*`,
`/monitor/*`, and `/.cerberus/*` are not quota-controlled. The policy is local to each mirror host and groups clients by
IPv4 `/24` or IPv6 `/64`:

- 30 GiB in a rolling 5-hour window;
- 150 GiB in a rolling 7-day window;
- 500 GiB in a rolling 30-day window.

Only body bytes successfully written by `GET` responses with status `200`–`299`
count, including `206` range responses. Accounting happens as responses stream,
so reaching a limit prevents new repository downloads even while existing
transfers continue. A request rejected by any window receives `429 Too Many
Requests`, `Cache-Control: private, no-store`, and a `Retry-After` value for the
first time all exhausted rolling windows have resumed.

Usage state is shared by all generated hostnames in one Caddy process and is
persisted at `CADDY_BANDWIDTH_QUOTA_DB` (production defaults to
`/data/bandwidth-quota.db`). If that database cannot be opened or loaded, Caddy
logs an error and continues with fresh in-memory state rather than taking the
mirror offline. A hard shutdown may lose up to one second of flushed state and
less than 1 MiB of buffered accounting per in-flight response.

Networks listed in the private
`blacklist/bandwidth-quota-whitelist.txt` bypass quota accounting and
enforcement and are exempt from the WAF's IP blacklist, country, and ASN
checks. DNS, rate-limit, and rule-engine checks still apply. WAF exemptions are
hot-reloaded; reload Caddy after changing the file to also refresh quota
exemptions. Quota metrics are exposed with the normal Caddy
metrics as `caddy_bandwidth_quota_counted_bytes_total` and
`caddy_bandwidth_quota_blocked_requests_total`.

lug configuration for a repo can always be viewed in two parts:

- synchronization config (shell_script / external)
- serving config (target, etc.)

## Synchronization Config

lug only needs the following properties

- shell script
  ```yaml
  - type: shell_script
    script: /worker-script/rsync.sh
    source: rsync://mirrors.kernel.org/centos/
    interval: 5800
    path: /srv/disk1/centos
    <<: *oneshot_common
  ```
- external
  ```yaml
  - type: external
    name: docker-registry
    proxy_to: https://docker.siyuan.internal.sjtug.org/
    subdomain: docker
  ```
- repo is served but not displayed in repo list (see below for serving config)
  ```yaml
  - type: external
    name: manjarostable
    target: https://mirrors.sjtug.sjtu.edu.cn/manjaro/stable/
    disabled: true
  ```

## Serving Config (Outdated)

- default: contents will be served from `path`. `path` must have the same suffix as repo name.
  ```yaml
  - type: shell_script
    script: /worker-script/rsync.sh
    source: rsync://rsync.releases.ubuntu.com/releases/
    interval: 24600
    path: /srv/disk2/ubuntu-cd
    name: ubuntu-cd
    <<: *oneshot_common
  ```
- mirror-intel: when specified, a reverse proxy to local `mirror-intel` container will be generated for caddy.
  ```yaml
  - type: shell_script
    script: /app/mirror-clone --concurrent_resolve 128 --workers 8 homebrew_bottles --target http://siyuan-mirror-intel:8000/homebrew-bottles
    mirror_intel: true
    interval: 10800
    name: homebrew-bottles
    <<: *oneshot_common
  ```
- target: when specified, all requests will be 302 redirect to `$target/$request`
  ```yaml
  - type: shell_script
    script: /worker-script/git.sh
    interval: 3600
    name: git/linuxbrew-core.git
    source: https://github.com/Homebrew/linuxbrew-core.git
    path: /srv/disk2/git/linuxbrew-core.git
    target: https://git.sjtu.edu.cn/sjtug/linuxbrew-core.git
    <<: *oneshot_common
  ```
- (optional) only_target: when specified, all requests will be 302 redirect to `$target` regardless of the parameters
  ```yaml
  - type: xxx
    name: github/PowerShell
    target: /github-release/PowerShell/PowerShell/releases/download/?mirror_intel_list
    only_target: true
  ```
- proxy: reverse proxy to a site
  ```yaml
  - type: external
    name: gcr-registry-siyuan
    proxy_to: siyuan-gcr-registry:80
    disabled: true
    subdomain: k8s-gcr-io.siyuan.internal.sjtug.org
  ```
- (optional) subdomain: when specified, `$subdomain.mirrors.sjtug.sjtu.edu.cn` will be generated. Should only be used on Zhiyuan server.
  ```yaml
  - type: external
    name: docker-registry
    proxy_to: https://docker.siyuan.internal.sjtug.org/
    subdomain: docker
  ```
