FROM debian:trixie-slim

ARG USE_SJTUG

RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/deb.debian.org/http:\/\/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources ; fi
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/security.debian.org/http:\/\/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources ; fi

WORKDIR /app

RUN apt-get update -y -qq && apt-get install wget curl -y -qq

ARG RSYNC_SJTUG_VERSION

RUN wget -O tmp.tar.gz https://github.com/sjtug/rsync-sjtug/releases/download/${RSYNC_SJTUG_VERSION}/rsync-sjtug-x86_64-unknown-linux-musl.tar.gz \
    && tar -xzf tmp.tar.gz --strip-components=2 && rm tmp.tar.gz

CMD /app/rsync-gateway
