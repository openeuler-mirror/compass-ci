FROM python:3.9-alpine

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
	&& apk update

RUN apk add --update gcc python3-dev libffi-dev musl-dev \
    && pip3 wheel --wheel-dir=/srv/wheels pip 'devpi-server==6.4.0' 'devpi-client==5.2.3' 'devpi-semantic-ui==0.2.2' \
    -i https://mirrors.aliyun.com/pypi/simple 

FROM python:3.9-alpine

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories \
	&& apk update

COPY --from=0 /srv/wheels /srv/wheels

VOLUME /srv/devpi

ENV DEVPISERVER_SERVERDIR=/var/lib/devpi

ENV SOURCE_MIRROR_URL=https://mirrors.aliyun.com/pypi/simple

RUN apk add --update openssl

RUN pip3 install --no-cache-dir --no-index --find-links=/srv/wheels devpi-server devpi-client devpi-semantic-ui \
    -i https://mirrors.aliyun.com/pypi/simple \
    && pip3 install --upgrade pip -i https://mirrors.aliyun.com/pypi/simple \
    && pip install --upgrade setupTools -i https://mirrors.aliyun.com/pypi/simple

EXPOSE 5032

COPY entrypoint.sh /srv/entrypoint.sh

ENTRYPOINT ["/srv/entrypoint.sh"]

