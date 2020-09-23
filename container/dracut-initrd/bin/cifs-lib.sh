#!/bin/sh
# From: https://github.com/dracutdevs/dracut/blob/master/modules.d/95cifs/cifs-lib.sh
# SPDX-License-Identifier: GPL-2.0

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

    server=${server%%/*}

    # append cifs custom mount opts to ${options}
    # allow guest mount type
    if [ ! "$cifsuser" ]; then
        options="${initial_options}"
    else
        if [ ! "$cifspass" ]; then
            options="username=$cifsuser,${initial_options}"
        else
            options="username=$cifsuser,password=$cifspass,${initial_options}"
        fi
    fi
}
