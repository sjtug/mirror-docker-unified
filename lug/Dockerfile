FROM debian:buster

ARG USE_SJTUG
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/deb.debian.org/http:\/\/mirrors.sjtug.sjtu.edu.cn/g' /etc/apt/sources.list ; fi

WORKDIR /app
RUN apt-get update && apt-get install rsync wget git jq curl unzip -y
RUN apt-get install apt-transport-https ca-certificates -y

ARG CLONE_VERSION
ARG LUG_VERSION

RUN if [ "$USE_SJTUG" = true ] ; then \
        wget -O tmp.tar.gz https://siyuan.internal.sjtug.org/sjtug-internal/lug/releases/download/${LUG_VERSION}/lug.tar.gz || \
        wget -O tmp.tar.gz https://s3.jcloud.sjtu.edu.cn/899a892efef34b1b944a19981040f55b-oss01/sjtug-internal/lug/releases/download/${LUG_VERSION}/lug.tar.gz || \
        wget -O tmp.tar.gz https://github.com/sjtug/lug/releases/download/${LUG_VERSION}/lug.tar.gz ; \
    else \
        curl -v -I https://mirrors.sjtug.sjtu.edu.cn/sjtug-internal/lug/releases/download/${LUG_VERSION}/lug.tar.gz && \
        wget -O tmp.tar.gz https://github.com/sjtug/lug/releases/download/${LUG_VERSION}/lug.tar.gz ; \
    fi && tar -xvf tmp.tar.gz && rm tmp.tar.gz && chmod +x ./lug

RUN if [ "$USE_SJTUG" = true ] ; then \
        wget -O tmp.tar.gz https://siyuan.internal.sjtug.org/sjtug-internal/mirror-clone/releases/download/${CLONE_VERSION}/mirror-clone.tar.gz || \
        wget -O tmp.tar.gz https://s3.jcloud.sjtu.edu.cn/899a892efef34b1b944a19981040f55b-oss01/sjtug-internal/lug/mirror-clone/releases/download/${CLONE_VERSION}/mirror-clone.tar.gz || \
        wget -O tmp.tar.gz https://github.com/sjtug/mirror-clone/releases/download/${CLONE_VERSION}/mirror-clone.tar.gz ; \
    else \
        curl -v -I https://mirrors.sjtug.sjtu.edu.cn/sjtug-internal/mirror-clone/releases/download/${CLONE_VERSION}/mirror-clone.tar.gz && \
        wget -O tmp.tar.gz https://github.com/sjtug/mirror-clone/releases/download/${CLONE_VERSION}/mirror-clone.tar.gz ; \
    fi && tar -xvf tmp.tar.gz && rm tmp.tar.gz

RUN git config --global credential.helper store

ENTRYPOINT ["./lug"]
