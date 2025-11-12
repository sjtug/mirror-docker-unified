# No idea why Rust stable requires GLIBC_2.39 ...
# but at lease work around it here
FROM debian:trixie-slim

ARG USE_SJTUG

RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/deb.debian.org/http:\/\/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources ; fi
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/security.debian.org/http:\/\/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources ; fi

WORKDIR /app

RUN apt-get update && apt-get install wget curl -y -qq

ARG INTEL_VERSION

RUN if [ "$USE_SJTUG" = true ] ; then \
        wget -O tmp.tar.gz https://mirror.sjtu.edu.cn/sjtug-internal/mirror-intel/releases/download/${INTEL_VERSION}/mirror-intel.tar.gz || \
        wget -O tmp.tar.gz https://s3.jcloud.sjtu.edu.cn/899a892efef34b1b944a19981040f55b-oss01/sjtug-internal/mirror-intel/releases/download/${INTEL_VERSION}/mirror-intel.tar.gz || \
        wget -O tmp.tar.gz https://github.com/sjtug/mirror-intel/releases/download/${INTEL_VERSION}/mirror-intel.tar.gz ; \
    else \
        timeout 5 curl -v -I https://mirror.sjtu.edu.cn/sjtug-internal/mirror-intel/releases/download/${INTEL_VERSION}/mirror-intel.tar.gz ; \
        wget -O tmp.tar.gz https://github.com/sjtug/mirror-intel/releases/download/${INTEL_VERSION}/mirror-intel.tar.gz ; \
    fi && tar -xvf tmp.tar.gz && rm tmp.tar.gz

COPY Rocket.toml /app

ENV ROCKET_TOML_PATH=/app/Rocket.toml

CMD /app/mirror-intel
