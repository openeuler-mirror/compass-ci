
# transfer LKP dirs
[  -d /lkp ] || return 0

cp -a /lkp 				$NEWROOT/

for i in /lkp/lkp/src/rootfs/addon/*
do
	[  -f $i/.keep ] && continue 	# skip empty dir
	cp -a $i/* 		$NEWROOT/$(basename $i)/
done

[  -d /usr/src ] &&
cp -a /usr/src			$NEWROOT/usr/

kmdir=/lib/modules/$(uname -r)
if test -d $kmdir &&  ! test -d $NEWROOT/$kmdir; then
    cp -an $kmdir		$NEWROOT/lib/modules/
    cp -an /lib/firmware	$NEWROOT/lib/
fi
