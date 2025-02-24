#!/usr/bin/bash

# before running this scipt:
# - make sure manticore docker has finished installing packages (check with 'docker logs manticore')
# - old table has been manually deleted

CURL="curl -sX POST http://localhost:9308/sql -d"

for sql in manti-table-*.sql
do
	echo $sql
	# $CURL "mode=raw&query=$(tr -d '\n' <$sql)"
	docker exec -i manticore mysql <"$sql"
done

echo
$CURL "mode=raw&query=desc jobs"
$CURL "mode=raw&query=desc hosts"
$CURL "mode=raw&query=desc accounts"
