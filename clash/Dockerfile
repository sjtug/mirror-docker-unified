FROM metacubex/mihomo:latest

RUN mkdir -p /etc/clash \
    && wget -O /etc/clash/geoip.metadb https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb \
    && wget -O /etc/clash/geosite.dat https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat \
    && wget -O /etc/clash/geoip.dat https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat
