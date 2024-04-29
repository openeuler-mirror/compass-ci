#!/bin/bash
# SPDX-License-Identifier: MulanPSL-2.0+

# the imported variable by k8s was added a new line characters at the end of the string
# before use the variable, del the new line character first
rpm_gpg_name=$(echo $RPM_GPG_NAME | sed 's/\n//')

sed -i "s/RPM_GPG_NAME/${rpm_gpg_name}/" /home/lkp/.rpmmacros
gpg --import --batch /gpg-key/pri.key
gpg-connect-agent reloadagent /bye
[[ -d /srv/log/result-webdav ]] || mkdir -p /srv/log/result-webdav

umask 002
/usr/local/openresty/bin/openresty -g 'daemon off;'
