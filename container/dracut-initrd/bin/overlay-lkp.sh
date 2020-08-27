#!/bin/bash
# transfer LKP dirs
[  -d /lkp ] || return 0

cp -a /lkp 				"$NEWROOT"/

for i in /lkp/lkp/src/rootfs/addon/* /usr/local/* /opt/*
do
	dir=$(basename "$i")

	[  -d "$NEWROOT/$dir" ] ||
		mkdir -p "$NEWROOT/$dir"
	[ "$i" != "${i%/\*}" ] && continue	# skip empty dir

	for j in "$i"/* "$i"/.??*
	do
		[ "$j" != "${j%/\*}" ] && continue	# skip empty dir

		[ -f "$j" ] && {
			cp -a "$j" "$NEWROOT/$dir"/
			continue
		}

		subdir=$(basename "$j")

		[  -d "$NEWROOT/$dir/$subdir" ] ||
			mkdir -p "$NEWROOT/$dir/$subdir"

		for k in "$j"/*
		do
			[ "$k" != "${k%/\*}" ] && continue	# skip empty dir

			cp -a "$j"/* 	"$NEWROOT/$dir/$subdir"/
		done
	done
done

[  -d /usr/src ] &&
	cp -a /usr/src			"$NEWROOT"/usr/

kmdir=/lib/modules/$(uname -r)
if test -d "$kmdir" &&  ! test -d "$NEWROOT/$kmdir"; then
    cp -an "$kmdir"		"$NEWROOT"/lib/modules/
    cp -an /lib/firmware	"$NEWROOT"/lib/
fi
