# https://github.com/ehough/docker-nfs-server
# Copyright (C) 2017-2020  Eric D. Hough
# SPDX-License-Identifier: GPL-3.0

ARG BUILD_FROM=alpine:latest

FROM $BUILD_FROM

RUN apk --update --no-cache add bash nfs-utils && \
                                                  \
    # remove the default config files
    rm -v /etc/idmapd.conf /etc/exports

# http://wiki.linux-nfs.org/wiki/index.php/Nfsv4_configuration
RUN mkdir -p /var/lib/nfs/rpc_pipefs                                                     && \
    mkdir -p /var/lib/nfs/v4recovery                                                     && \
    echo "rpc_pipefs  /var/lib/nfs/rpc_pipefs  rpc_pipefs  defaults  0  0" >> /etc/fstab && \
    echo "nfsd        /proc/fs/nfsd            nfsd        defaults  0  0" >> /etc/fstab

EXPOSE 2049

# Need a volume to fix error "exportfs: /exports does not support NFS export"
VOLUME /exports

COPY ./entrypoint.sh /usr/local/bin
ADD root /
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
