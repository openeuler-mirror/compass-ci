#!/bin/sh
# From: https://github.com/dracutdevs/dracut/blob/master/modules.d/95cifs/cifs-lib.sh
# SPDX-License-Identifier: GPLv2

# cifs_to_var CIFSROOT
# use CIFSROOT to set $server, $path, and $options.
# CIFSROOT is something like: cifs://[<username>[:<password>]]@<host>/<path>
# NETIF is used to get information from DHCP options, if needed.

type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

cifs_to_var() {
    local cifsuser; local cifspass
    # Check required arguments
    # $1 example: "cifs://172.168.x.x/os/xx,vers=1.0,xx,xx"
    server=${1##cifs://}
    cifsuser=${server%@*}
    cifspass=${cifsuser#*:}

    # store cifs custom mount opts
    initial_options=${server#*,}

    if [ "$cifspass" != "$cifsuser" ]; then
	cifsuser=${cifsuser%:*}
    else
	cifspass=$(getarg cifspass)
    fi
    if [ "$cifsuser" != "$server" ]; then
	server="${server#*@}"
    else
	cifsuser=$(getarg cifsuser)
    fi

    path=${server#*/}

    # remove cifs custom mount opts from ${path}
    path=${path%%,*}

    server=${server%/*}

    if [ ! "$cifsuser" -o ! "$cifspass" ]; then
	die "For CIFS support you need to specify a cifsuser and cifspass either in the cifsuser and cifspass commandline parameters or in the root= CIFS URL."
    fi

    # append cifs custom mount opts to ${options}
    options="user=$cifsuser,pass=$cifspass,${initial_options}"
}
