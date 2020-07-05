#!/bin/bash

# dotfiles
cp -a /mnt/skel/ /etc/
cp -a /mnt/skel/.??* /root/
cp -a /mnt/skel/.??* /home/team/
chown -R team.team /home/team


# ssh authorized_keys
[ -n "$SSH_KEYS" ] || exit 0

for user in ${TEAM//,/ }
do
	if command -v useradd >/dev/null; then
		# debian
		useradd --create-home --shell /bin/zsh $user
		passwd --lock $user
	else
		# alpine busybox
		adduser -D -s /bin/zsh -k /etc/skel $user
		passwd -u $user
	fi
	mkdir -p /home/$user/.ssh
	echo "$SSH_KEYS" | grep " $user@" > /home/$user/.ssh/authorized_keys
	chown -R $user.$user /home/$user/.ssh
done

mkdir -p /root/.ssh
echo "$SSH_KEYS" | grep -E " (${COMMITTERS//,/|})@" > /root/.ssh/authorized_keys
echo "$SSH_KEYS" > /home/team/.ssh/authorized_keys

chmod -R go-rwxs /root/.ssh /home/*/
