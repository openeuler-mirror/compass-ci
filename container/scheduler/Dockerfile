FROM alpine:3.11

RUN apk add --no-cache 'ruby-dev' \
	'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'cpio' 'bash' 

RUN umask 002 &&\
    gem install rest-client && \
    gem install activesupport && \
    gem install git && \
    gem install json && \
    gem install yaml


RUN mkdir -p /c/cci/scheduler

# should build with: crystal build src/scheduler.cr
COPY scheduler /c/cci/scheduler

RUN chown -R 1090:1090 /c

EXPOSE 3000

WORKDIR /c/cci/scheduler

