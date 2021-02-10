FROM debian:buster

ARG USE_SJTUG
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/deb.debian.org/http:\/\/mirror.sjtu.edu.cn/g' /etc/apt/sources.list ; fi
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/security.debian.org/http:\/\/mirror.sjtu.edu.cn/g' /etc/apt/sources.list ; fi

WORKDIR /app
RUN apt-get update && apt-get install rsync wget git jq curl unzip -y
RUN apt-get install apt-transport-https ca-certificates -y

RUN mkdir build-script

# PHP, composer
COPY build-script/setup-php.sh build-script/setup-php.sh
RUN /app/build-script/setup-php.sh
RUN apt-get update && apt-get install php-cli php-mbstring php-xml php-curl -y

# Python
RUN apt-get install python3 python3-pip -y

# packagist-mirror
COPY build-script/setup-packagist.sh build-script/setup-packagist.sh
RUN /app/build-script/setup-packagist.sh

# Julia
COPY build-script/setup-julia.sh build-script/setup-julia.sh
RUN /app/build-script/setup-julia.sh
ENV PATH="/app/julia-1.5.0/bin:${PATH}"

# Python packages
RUN if [ "$USE_SJTUG" = true ] ; then pip3 install python-dateutil -i https://mirrors.sjtug.sjtu.edu.cn/pypi/web/simple; else pip3 install python-dateutil ; fi

# StorageMirrorServer.jl
COPY build-script/setup-julia-mirror.sh build-script/setup-julia-mirror.sh
RUN /app/build-script/setup-julia-mirror.sh

# AWS
RUN apt-get install awscli -y

COPY build-script/from-cache.sh build-script/from-cache.sh

# yq
RUN /app/build-script/from-cache.sh \
    https://mirror.sjtu.edu.cn/github-release/mikefarah/yq/download/3.4.0/yq_linux_amd64 \
    https://s3.jcloud.sjtu.edu.cn/899a892efef34b1b944a19981040f55b-oss01/github-release/yq/releases/download/3.4.0/yq_linux_amd64 \
    https://github.com/mikefarah/yq/releases/download/3.4.0/yq_linux_amd64 \
    /usr/local/bin/yq \
        && chmod +x /usr/local/bin/yq

ARG CLONE_VERSION
ARG LUG_VERSION

RUN /app/build-script/from-cache.sh \
        https://mirror.sjtu.edu.cn/sjtug-internal/lug/releases/download/${LUG_VERSION}/lug.tar.gz \
        https://s3.jcloud.sjtu.edu.cn/899a892efef34b1b944a19981040f55b-oss01/sjtug-internal/lug/releases/download/${LUG_VERSION}/lug.tar.gz \
        https://github.com/sjtug/lug/releases/download/${LUG_VERSION}/lug.tar.gz \
        tmp.tar.gz \
            && tar -xvf tmp.tar.gz && rm tmp.tar.gz

RUN /app/build-script/from-cache.sh \
        https://mirror.sjtu.edu.cn/sjtug-internal/mirror-clone/releases/download/${CLONE_VERSION}/mirror-clone.tar.gz \
        https://s3.jcloud.sjtu.edu.cn/899a892efef34b1b944a19981040f55b-oss01/sjtug-internal/lug/mirror-clone/releases/download/${CLONE_VERSION}/mirror-clone.tar.gz \
        https://github.com/sjtug/mirror-clone/releases/download/${CLONE_VERSION}/mirror-clone.tar.gz \
        tmp.tar.gz \
            && tar -xvf tmp.tar.gz && rm tmp.tar.gz

RUN mkdir /root/.ssh && ssh-keyscan cran.r-project.org >> /root/.ssh/known_hosts
RUN git config --global credential.helper store

ENTRYPOINT ["./lug"]
