#!/bin/sh

nohup tunasync manager --config /etc/tunasync/manager.conf > /tmp/log/manager.log &
tunasync worker --config /etc/tunasync/worker.conf > /tmp/log/worker.log
