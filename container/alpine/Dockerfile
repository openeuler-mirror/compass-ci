FROM alpine

MAINTAINER Wu Fenguang <wufengguang@huawei.com>

RUN apk update
RUN apk add bash zsh git openssh openrc rsync crystal shards tzdata sudo

ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

RUN adduser -D team && \
    adduser -G wheel team

RUN chsh -s /bin/zsh team && \
    chsh -s /bin/zsh root 

RUN echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-nopasswd

RUN ssh-keygen -t rsa -P "" -f /etc/ssh/ssh_host_rsa_key && \
    ssh-keygen -t dsa -P "" -f /etc/ssh/ssh_host_dsa_key && \
    ssh-keygen -t ecdsa -P "" -f /etc/ssh/ssh_host_ecdsa_key && \
    ssh-keygen -t ed25519 -P "" -f /etc/ssh/ssh_host_ed25519_key && \

EXPOSE 2200
CMD ["/usr/sbin/sshd", "-D", "-p", "2200"]
