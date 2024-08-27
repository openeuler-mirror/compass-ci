#!/usr/bin/env sh

get_random_str()
{
	openssl rand -base64 9 | tr -dc 'a-zA-Z0-9' | head -c $DEVPISERVER_PASSWORD_LEN
	echo 
}

generat_password()
{
	devpiserver_root_password=$(get_random_str)
	devpiserver_password=$(get_random_str)

	cat <<-EOF >> /srv/.pypirc
	[devpi]
	username: $DEVPISERVER_USER
	devpiserver_root_password: $devpiserver_root_password
	devpiserver_password: $devpiserver_password

	EOF
}

set -e
generat_password

if [ -z "${DEVPISERVER_HOST}" ]; then
    DEVPISERVER_HOST="0.0.0.0"
fi

if [ -z "${DEVPISERVER_PORT}" ]; then
    DEVPISERVER_PORT="5032"
fi

if [ ! -f "${DEVPISERVER_SERVERDIR}/.nodeinfo" ]; then
    echo "start initialization"
    devpi-init

    (
        echo "waiting for devpi-server start"
        sleep 5
        devpi use "http://${DEVPISERVER_HOST}:${DEVPISERVER_PORT}"
        devpi login root --password=""


        echo "setup password for root"
        devpi user -m root password="${devpiserver_root_password}"


        echo "create user ${DEVPISERVER_USER}"
        devpi user -c "${DEVPISERVER_USER}" password="${devpiserver_password}"
        devpi logout  # logout from root
        devpi login "${DEVPISERVER_USER}" --password="${devpiserver_password}"


        echo "create index ${DEVPISERVER_USER}/${DEVPISERVER_MIRROR_INDEX}"
        devpi index -c "${DEVPISERVER_MIRROR_INDEX}" type=mirror mirror_url="${SOURCE_MIRROR_URL}" mirror_web_url_fmt=${SOURCE_MIRROR_URL}/{name}/
        devpi index -c "${DEVPISERVER_LIB_INDEX}" bases="${DEVPISERVER_USER}/${DEVPISERVER_MIRROR_INDEX}"

        devpi logout
    ) &

else
    echo "skip initialization"
fi

echo "+ devpi-server --host=\"${DEVPISERVER_HOST}\" --port=\"${DEVPISERVER_PORT}\" --theme /usr/local/lib/python3.9/site-packages/devpi_semantic_ui  $@"
exec devpi-server --host="${DEVPISERVER_HOST}" --port="${DEVPISERVER_PORT}" --theme /usr/local/lib/python3.9/site-packages/devpi_semantic_ui $@
