FROM alpine:scheduler-dev

COPY repositories /etc/apk/
RUN apk add --upgrade busybox && \
    apk add --no-cache 'ruby-dev' \
    'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'cpio' 'bash'

RUN umask 002 && \
    gem sources -r https://rubygems.org/ -a https://gems.ruby-china.com/ && \
    gem install yaml


ENV MONITOR_RUNTIME_DIR /c/cci/monitor

RUN mkdir -p $MONITOR_RUNTIME_DIR && \
    chown -R 1090:1090 /c

RUN apk del g++ gdb rpcgen

RUN for i in pem crt; do find / -name *.$i | xargs rm -rf; done

RUN rm -rf /usr/bin/cpp \
           /usr/bin/gcc \
           /usr/bin/objdump \
           /usr/bin/readelf \
           /usr/aarch64-alpine-linux-musl/bin/objdump \
           /usr/aarch64-alpine-linux-musl/bin/readelf \
           /usr/share/cmake/Modules/Compiler/XL-Fortran/cpp

COPY lkp-tests /c/lkp-tests

WORKDIR $MONITOR_RUNTIME_DIR

COPY --chown=1090:1090 monitoring .

RUN adduser -u 1090 -D lkp

RUN echo "umask 027" >>/home/lkp/.bashrc

RUN find / -perm -004 -regex '.*\.conf\|.*\.cnf\|.*\.cfg\|.*\.config\|.*\.xml\|.*\.properties\|.*\.yaml\|.*\.yml\|.*\.json\|.*\.sql\|.*\.ini\|.*\.key\|.*\.cacert\|.*\.log' -type f|xargs chmod 640
