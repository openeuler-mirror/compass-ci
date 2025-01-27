#!/usr/bin/env bash

CURL="curl -sX POST http://localhost:9308/sql -d"

for sql in manti-table-*.sql
do
	$CURL "mode=raw&query=$(tr -d '\n' <$sql)"
done

echo
$CURL "mode=raw&query=desc jobs"
