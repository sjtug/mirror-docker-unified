FROM debian:buster

ARG USE_SJTUG

RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/deb.debian.org/http:\/\/mirror.sjtu.edu.cn/g' /etc/apt/sources.list ; fi
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/security.debian.org/http:\/\/mirror.sjtu.edu.cn/g' /etc/apt/sources.list ; fi

WORKDIR /app

RUN apt-get update -y -qq && apt-get install wget curl -y -qq

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

CMD /app/mirror-intel
