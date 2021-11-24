#!/bin/bash
# SPDX-License-Identifier: GPL-2.0

. /lib/dracut-lib.sh

if ! getargbool 0 local; then
        return
fi

# transfer custom bootstrap
[ -d /custom_bootstrap ] && {
	cp -a /custom_bootstrap/* "$NEWROOT"/
}

# transfer LKP dirs
[ -d /lkp ] || return 0

cp -a /lkp 				"$NEWROOT"/

for i in /lkp/lkp/src/rootfs/addon/*
do
	dir=$(basename "$i")

	[ "$i" != "${i%/\*}" ] && continue  # skip when i is an empty dir, it's unnecessary to copy
	
	[ -d "$NEWROOT/$dir" ] || mkdir -p "$NEWROOT/$dir"

	for j in "$i"/* "$i"/.??*
	do
		[ "$j" != "${j%/\*}" ] && continue  # skip when j is an empty dir

		[ -f "$j" ] && {
			cp -a "$j" "$NEWROOT/$dir"/
			continue
		}

		subdir=$(basename "$j")

		[ -d "$NEWROOT/$dir/$subdir" ] || mkdir -p "$NEWROOT/$dir/$subdir"

		for k in "$j"/*
		do
			[ "$k" != "${k%/\*}" ] && continue	# skip when k is an empty dir

			cp -a "$j"/* 	"$NEWROOT/$dir/$subdir"/
		done
	done
done

[ -d /opt ] &&
	cp -a /opt			"$NEWROOT"/

mkdir -p "$NEWROOT"/usr
[ -d /usr/local ] &&
	cp -a /usr/local		"$NEWROOT"/usr/

[ -d /usr/src ] &&
	cp -a /usr/src			"$NEWROOT"/usr/

kmdir=/lib/modules/$(uname -r)
if test -d "$kmdir" &&  ! test -d "$NEWROOT/$kmdir"; then
    cp -an "$kmdir"		"$NEWROOT"/lib/modules/
    cp -an /lib/firmware	"$NEWROOT"/lib/
fi

if getargbool 0 local; then
    rm -f "$NEWROOT"/lkp/run/lkp-bootstrap.pid
fi
