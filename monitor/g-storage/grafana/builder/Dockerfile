ARG GRAFANA_VERSION="11.4.0"

FROM grafana/grafana:${GRAFANA_VERSION}

ARG GF_INSTALL_IMAGE_RENDERER_PLUGIN="false"
ARG GF_GID="0"

ENV GF_PATHS_PLUGINS="/var/lib/grafana-plugins"
ENV GF_PLUGIN_RENDERING_CHROME_BIN="/usr/bin/chrome"

USER root

RUN sed -i 's/dl-cdn.alpinelinux.org/mirror.nju.edu.cn/g' /etc/apk/repositories

RUN mkdir -p "$GF_PATHS_PLUGINS" && \
    chown -R grafana:${GF_GID} "$GF_PATHS_PLUGINS" && \
    if [ "$GF_INSTALL_IMAGE_RENDERER_PLUGIN" = "true" ]; then \
      if grep -i -q alpine /etc/issue; then \
        apk add --no-cache udev ttf-opensans chromium && \
        ln -s /usr/bin/chromium-browser "$GF_PLUGIN_RENDERING_CHROME_BIN"; \
      else \
        cd /tmp && \
        curl -sLO https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
        DEBIAN_FRONTEND=noninteractive apt-get update -q && \
        DEBIAN_FRONTEND=noninteractive apt-get install -q -y ./google-chrome-stable_current_amd64.deb && \
        rm -rf /var/lib/apt/lists/* && \
        rm ./google-chrome-stable_current_amd64.deb && \
        ln -s /usr/bin/google-chrome "$GF_PLUGIN_RENDERING_CHROME_BIN"; \
      fi; \
    fi

USER grafana

RUN if [ "$GF_INSTALL_IMAGE_RENDERER_PLUGIN" = "true" ]; then \
      if grep -i -q alpine /etc/issue; then \
        grafana cli \
          --pluginsDir "$GF_PATHS_PLUGINS" \
          --pluginUrl https://github.com/grafana/grafana-image-renderer/releases/download/v3.12.9/plugin-alpine-x64-no-chromium.zip \
          plugins install grafana-image-renderer; \
      else \
        grafana cli \
          --pluginsDir "$GF_PATHS_PLUGINS" \
          --pluginUrl https://github.com/grafana/grafana-image-renderer/releases/download/v3.12.9/plugin-linux-x64-glibc-no-chromium.zip \
          plugins install grafana-image-renderer; \
      fi; \
    fi
