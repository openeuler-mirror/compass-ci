#!/bin/bash

# dotfiles
cp -a /mnt/skel/ /etc/
cp -a /mnt/skel/.??* /root/
cp -a /mnt/skel/.??* /home/team/
chown -R team.team /home/team


# ssh authorized_keys
[ -n "$SSH_KEYS" ] || exit 0

mkdir -p /root/.ssh /home/team/.ssh
echo "$SSH_KEYS" | grep -E " (${COMMITTERS//,/|})@" > /root/.ssh/authorized_keys
echo "$SSH_KEYS" > /home/team/.ssh/authorized_keys
chown -R team.team /home/team/.ssh
chmod -R go-rwxs /root/.ssh /home/team/.ssh
