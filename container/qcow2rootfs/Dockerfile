FROM centos:8

MAINTAINER Yu Chuan <yuchuan6@huawei.com>, Shi Zhichao <shizhichao2@huawei.com>

RUN yum makecache && \
    yum install -y libvirt libguestfs-tools xz expect openssl && \
    yum clean all

ENV EXTRACT_USER=extract
ENV EXTRACT_ROOT=/root/extract

RUN useradd $EXTRACT_USER && \
    usermod -aG kvm,qemu,root $EXTRACT_USER
