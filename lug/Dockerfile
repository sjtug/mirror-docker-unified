FROM debian:buster

ARG USE_SJTUG
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/deb.debian.org/http:\/\/mirror.sjtu.edu.cn/g' /etc/apt/sources.list ; fi
RUN if [ "$USE_SJTUG" = true ] ; then sed -i 's/http:\/\/security.debian.org/http:\/\/mirror.sjtu.edu.cn/g' /etc/apt/sources.list ; fi

WORKDIR /app
RUN apt-get update && apt-get install rsync wget git jq curl unzip -y
RUN apt-get install apt-transport-https ca-certificates -y

ARG CLONE_VERSION
ARG LUG_VERSION

COPY build-script/* build-script/

RUN /app/build-script/from-cache.sh \
        https://mirror.sjtu.edu.cn/sjtug-internal/lug/releases/download/${LUG_VERSION}/lug.tar.gz \
        https://s3.jcloud.sjtu.edu.cn/899a892efef34b1b944a19981040f55b-oss01/sjtug-internal/lug/releases/download/${LUG_VERSION}/lug.tar.gz \
        https://github.com/sjtug/lug/releases/download/${LUG_VERSION}/lug.tar.gz \
            && tar -xvf tmp.tar.gz && rm tmp.tar.gz

RUN /app/build-script/from-cache.sh \
        https://mirror.sjtu.edu.cn/sjtug-internal/mirror-clone/releases/download/${CLONE_VERSION}/mirror-clone.tar.gz \
        https://s3.jcloud.sjtu.edu.cn/899a892efef34b1b944a19981040f55b-oss01/sjtug-internal/lug/mirror-clone/releases/download/${CLONE_VERSION}/mirror-clone.tar.gz \
        https://github.com/sjtug/mirror-clone/releases/download/${CLONE_VERSION}/mirror-clone.tar.gz \
            && tar -xvf tmp.tar.gz && rm tmp.tar.gz

RUN apt-get install python3 python3-pip -y
RUN if [ "$USE_SJTUG" = true ] ; then pip3 install python-dateutil -i https://mirrors.sjtug.sjtu.edu.cn/pypi/web/simple; else pip3 install python-dateutil ; fi

RUN git config --global credential.helper store

ENTRYPOINT ["./lug"]
