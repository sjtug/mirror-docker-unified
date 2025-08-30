# caddy-gen

The Caddyfile generator for SJTUG mirror.

caddy-gen reads lug configuration of Siyuan and Zhiyuan, then generate
corresponding Caddyfile for both servers.

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
