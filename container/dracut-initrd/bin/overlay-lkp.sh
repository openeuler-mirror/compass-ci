
# transfer LKP dirs
[  -d /lkp ] || return 0

cp -a /lkp 				$NEWROOT/

for i in /lkp/lkp/src/rootfs/addon/*
do
	[  -f $i/.keep ] && continue 	# skip empty dir
	dir=$(basename $i)
	for j in $i/*
	do
		[ -f $j ] && {
			cp -a $j $NEWROOT/$dir/
			continue
		}

		subdir=$(basename $j)

		[  -d $NEWROOT/$dir/$subdir ] ||
		mkdir $NEWROOT/$dir/$subdir

		cp -a $j/* 	$NEWROOT/$dir/$subdir/
	done
done

[  -d /usr/src ] &&
cp -a /usr/src			$NEWROOT/usr/

kmdir=/lib/modules/$(uname -r)
if test -d $kmdir &&  ! test -d $NEWROOT/$kmdir; then
    cp -an $kmdir		$NEWROOT/lib/modules/
    cp -an /lib/firmware	$NEWROOT/lib/
fi
