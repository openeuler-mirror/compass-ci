# 3.12 cannot install crystal
FROM alpine:3.11

MAINTAINER Wu Fenguang <wufengguang@huawei.com>

RUN apk update
RUN apk add bash zsh git openssh openrc rsync crystal shards make gcc g++ tzdata sudo coreutils util-linux libffi-dev openssl-dev libtool yaml-dev && shards init

RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

RUN	adduser -D -s /bin/zsh team && \
	adduser team wheel && \
	passwd -d root && \
	passwd -d team && \
	sed -i '1s/bin\/.*sh$/bin\/zsh/' /etc/passwd

RUN echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-nopasswd

RUN ssh-keygen -t rsa -P "" -f /etc/ssh/ssh_host_rsa_key && \
    ssh-keygen -t dsa -P "" -f /etc/ssh/ssh_host_dsa_key && \
    ssh-keygen -t ecdsa -P "" -f /etc/ssh/ssh_host_ecdsa_key && \
    ssh-keygen -t ed25519 -P "" -f /etc/ssh/ssh_host_ed25519_key && \
    echo "PermitRootLogin without-password" >> /etc/ssh/sshd_config

EXPOSE 2200
CMD ["/usr/sbin/sshd", "-D", "-p", "2200"]
