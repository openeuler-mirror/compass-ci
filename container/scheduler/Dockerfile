FROM alpine:3.11

RUN apk add --no-cache 'ruby-dev' \
	'g++' 'gcc' 'pcre' 'libevent' 'make' 'git' 'cpio' 'bash' 

RUN umask 002 &&\
    gem install rest-client && \
    gem install activesupport && \
    gem install git && \
    gem install json && \
    gem install yaml


ENV SCHED_RUNTIME_DIR	/c/cci/scheduler

RUN mkdir -p $SCHED_RUNTIME_DIR && \
    chown -R 1090:1090 /c

WORKDIR $SCHED_RUNTIME_DIR

# should build with: crystal build src/scheduler.cr
COPY --chown=1090:1090 scheduler .
