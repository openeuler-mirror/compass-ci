#!/bin/bash

# dotfiles
cp -a /mnt/skel/ /etc/

# ssh authorized_keys
[ -n "$SSH_KEYS" ] || exit 0

for user in ${TEAM//,/ }
do
	uid=$(awk -F: "/^$user:/ { print \$3}" /opt/passwd)
	gid=$(awk -F: "/^$user:/ { print \$4}" /opt/passwd)
	if command -v useradd >/dev/null; then
		# debian
		addgroup --gid $gid $user
		useradd --create-home --shell /bin/zsh -u $uid -g $gid $user
		passwd --lock $user
	else
		# alpine busybox
		addgroup -g $gid $user
		adduser -D -s /bin/zsh -k /etc/skel -u $uid $user
		passwd -u $user
	fi
	mkdir -p /home/$user/.ssh
	echo "$SSH_KEYS" | grep " $user@" > /home/$user/.ssh/authorized_keys
	chown -R $user.$user /home/$user/.ssh
done

# setup root
cp -a /mnt/skel/.??* /root/
passwd --lock root
chsh -s /bin/zsh
mkdir -p /root/.ssh
echo "$SSH_KEYS" | grep -E " (${COMMITTERS//,/|})@" > /root/.ssh/authorized_keys

echo "$SSH_KEYS" > /home/team/.ssh/authorized_keys

# alpine
if [ -d /etc/sudoers.d ]; then
	adduser team wheel
	echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-nopasswd
fi

chmod -R go-rwxs /root/.ssh /home/*/
