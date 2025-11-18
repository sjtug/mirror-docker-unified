FROM debian:bookworm-slim

ARG USE_SJTUG

RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/deb.debian.org/http:\/\/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources ; fi
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/security.debian.org/http:\/\/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources ; fi

WORKDIR /app

RUN apt-get update -y -qq && apt-get install wget curl -y -qq

ARG RSYNC_SJTUG_VERSION

RUN wget -O tmp.tar.gz https://github.com/sjtug/rsync-sjtug/releases/download/${RSYNC_SJTUG_VERSION}/rsync-sjtug-x86_64-unknown-linux-musl.tar.gz \
    && tar -xvf tmp.tar.gz && rm tmp.tar.gz

RUN if [ "$USE_SJTUG" = true ] ; then \
        wget -O tmp.tar.gz https://mirror.sjtu.edu.cn/sjtug-internal/rsync-sjtug/releases/download/${RSYNC_SJTUG_VERSION}/rsync-sjtug-x86_64-unknown-linux-musl.tar.gz || \
        wget -O tmp.tar.gz https://s3.jcloud.sjtu.edu.cn/899a892efef34b1b944a19981040f55b-oss01/sjtug-internal/rsync-sjtug/releases/download/${RSYNC_SJTUG_VERSION}/rsync-sjtug-x86_64-unknown-linux-musl.tar.gz || \
        wget -O tmp.tar.gz https://github.com/sjtug/rsync-sjtug/releases/download/${RSYNC_SJTUG_VERSION}/rsync-sjtug-x86_64-unknown-linux-musl.tar.gz ; \
    else \
        timeout 5 curl -v -I https://mirror.sjtu.edu.cn/sjtug-internal/rsync-sjtug/releases/download/${RSYNC_SJTUG_VERSION}/rsync-sjtug-x86_64-unknown-linux-musl.tar.gz ; \
        wget -O tmp.tar.gz https://github.com/sjtug/rsync-sjtug/releases/download/${RSYNC_SJTUG_VERSION}/rsync-sjtug-x86_64-unknown-linux-musl.tar.gz ; \
    fi && tar -xvf tmp.tar.gz && rm tmp.tar.gz

CMD /app/rsync-gateway
