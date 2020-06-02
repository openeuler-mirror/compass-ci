# default system run, you may see log like this (cmd: docker logs -f containID)
# ERROR: [1] bootstrap checks failed
# [1]: max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]
#
# so, the host need modify
# -- this set at host, need sudo
sudo sysctl -w vm.max_map_count=655360

chmod -R 707 /srv/es/alpine/server01
docker run -d -p 9200:9200 -p 9300:9300 -v /srv/es/alpine/server01:/srv/es --name es-server01 es643b:alpine311

# test server start?
echo test es server, this will sleep 10s
sleep 10s
curl -XGET http://localhost:9200
