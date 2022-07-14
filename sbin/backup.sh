#!/bin/bash
#
# Increamental backup based on rsync.
#
# usage:
# 	mkdir backup && cd backup
# 	echo "server:dir" > source
# 	./backup.sh
#
# 2007.11  Fengguang Wu <wfg@ustc.edu>
#

DST=$(date +'%F-%H%M%S')
DST=$(date +'%F')
CURRENT=$(readlink -e current)

[[ "$CURRENT" ]] && LINK_DEST="--link-dest=${CURRENT}"
[[ -f ./exclude ]] && EXCLUDE_FROM="--exclude-from=./exclude"
[[ -f ./files   ]] && FILES_FROM="--files-from=./files"

BASIC_OPTIONS="-axvR --delete --numeric-ids"
RSYNC_OPTIONS="${BASIC_OPTIONS} ${FILES_FROM} ${EXCLUDE_FROM}"

sync_source()
{
	[[ -f ./source ]] || return

	while read SRC
	do
		df . | grep -q '(100|9[0-9])%' && return 1

		echo \
		rsync ${RSYNC_OPTIONS} ${LINK_DEST} "${SRC}" ${DST}
		rsync ${RSYNC_OPTIONS} ${LINK_DEST} "${SRC}" ${DST} || return
		df . | grep -q '(100|9[0-9])%' && return 1
	done < ./source

	rm -f ./current
	ln -s ${DST} ./current
}

sync_files()
{
	[[ -s $source_file ]] || return

	df . | grep -q '(100|9[0-9])%' && return 1

	local host_src=${source_file#*:}:/

	echo \
	rsync ${RSYNC_OPTIONS} "--files-from=$source_file" ${LINK_DEST} $host_src ${DST}
	rsync ${RSYNC_OPTIONS} "--files-from=$source_file" ${LINK_DEST} $host_src ${DST} || return

	df . | grep -q '(100|9[0-9])%' && return 1

	rm -f ./current
	ln -s ${DST} ./current
}

sync_files_from()
{
	local source_file
	for source_file
	do
		sync_files
	done
}

sync_source
sync_files_from ./source:*
