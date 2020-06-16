#!/bin/sh

# dotfiles
cp -a /mnt/skel/ /etc/
cp -a /mnt/skel/.??* /root/
cp -a /mnt/skel/.??* /home/team/
chown -R team.team /home/team


# ssh authorized_keys
[[ "$SSH_KEYS" ]] || exit 0

mkdir -p /root/.ssh /home/team/.ssh
echo "$SSH_KEYS" | grep -w "$USER@" > /root/.ssh/authorized_keys
echo "$SSH_KEYS" > /home/team/.ssh/authorized_keys
chown -R team.team /home/team/.ssh
chmod -R go-rwxs /root/.ssh /home/team/.ssh
