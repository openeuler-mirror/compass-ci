#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+

ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
	ssh-keygen -t rsa -P "" -f /etc/ssh/ssh_host_rsa_key
	ssh-keygen -t dsa -P "" -f /etc/ssh/ssh_host_dsa_key
	ssh-keygen -t ecdsa -P "" -f /etc/ssh/ssh_host_ecdsa_key
	ssh-keygen -t ed25519 -P "" -f /etc/ssh/ssh_host_ed25519_key
fi

# dotfiles
cp -a /mnt/skel/ /etc/

if ! grep -q '^wheel:' /etc/group; then
	if command -v groupadd >/dev/null; then
		# debian only created sudo group
		# archlinux has neither sudo no wheel group
		groupadd --system wheel
	else
		# alpine already has wheel group, so won't go here
		addgroup -S wheel
	fi
fi

# fix warnings in archlinux: no users group
sed -i '/GROUP=users/d' /etc/default/useradd
# everyone can sudo in docker testbed
echo 'GROUP=wheel'   >> /etc/default/useradd

# ssh authorized_keys
[ -n "$SSH_KEYS" ] || exit 0

for user in ${TEAM//,/ }
do
	uid=$(awk -F: "/^$user:/ { print \$3}" /opt/passwd)
	gid=$(awk -F: "/^$user:/ { print \$4}" /opt/passwd)
	if command -v useradd >/dev/null; then
		# debian
		groupadd --gid $gid $user
		useradd --create-home --shell /bin/zsh -u $uid -g $gid $user
		passwd --lock $user
	else
		# alpine busybox
		addgroup -g $gid $user
		adduser -D -s /bin/zsh -k /etc/skel -u $uid $user
		adduser $user wheel
		passwd -u $user # necessary for ssh login
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

if [ -d /etc/sudoers.d ]; then
	echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-nopasswd

	# https://github.com/sudo-project/sudo/issues/42
	sudo --version | grep -q -F 1.8 &&
	echo "Set disable_coredump false" >> /etc/sudo.conf
fi

chmod -R go-rwxs /root/.ssh /home/*/
