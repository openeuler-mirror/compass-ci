import os
import sys
import pika
import time
import argparse

sys.path.append(os.path.abspath("../../"))

from src.libpy.es_client import EsClient
from src.libpy.redis_client import RedisClient
from src.libpy.etcd_client import EtcdClient
from src.libpy.constants import ETCD_HOST, ETCD_PORT
from src.libpy.constants import MQ_HOST, MQ_PORT

def wait_for_service(service_name, check_function, delay=2):
    while True:
        try:
            print(f"accessing {service_name}.", flush=True)
            check_function()
            print(f"{service_name} is available.", flush=True)
            return
        except Exception as e:
            print(f"Waiting for {service_name}... {e}", flush=True)
            time.sleep(delay)

def access_redis():
    _redis = RedisClient()
    test_key = 'test_key'
    test_value = 'test_value'

    _redis.set(test_key, test_value)
    value = _redis.get(test_key)

    if value == test_value:
        print("Inserted into Redis and verified:", value, flush=True)
    else:
        raise Exception("Data verification failed for Redis.")

def access_rabbitmq():
    try:
        connection = pika.BlockingConnection(pika.ConnectionParameters(MQ_HOST, port=MQ_PORT))
        channel = connection.channel()
        channel.queue_declare(queue='k8s_test_queue')

        test_value = 'test_value'
        channel.basic_publish(exchange='', routing_key='k8s_test_queue', body=test_value)
        print("Sent to RabbitMQ:", test_value, flush=True)
    except Exception as e:
        raise Exception(f"Data verification failed for rabbitmq: {e}")
    finally:
        if connection is not None:
            print("Close connection.")
            connection.close()

def access_etcd():
    _etcd=EtcdClient()
    test_key = 'test_key'
    test_value = 'test_value'
    _etcd.put(test_key, test_value)
    value, metadata=_etcd.get(test_key)

    value = value.decode("utf-8")
    if value == test_value:
        print("Inserted into etcd and verified:", value, flush=True)
    else:
        raise Exception("Data verification failed for etcd: {}={}".format(value, test_value))

def access_es():
    _es = EsClient()
    health_info = _es.get_cluster_health()
    status = health_info.get("status")
    if status in ["green", "yellow"]:
        print(f"Elasticsearch is available with status: {status}", flush=True)
    else:
        raise Exception(f"Elasticsearch is unavailable with status: {status}", flush=True)


def main():
    parser = argparse.ArgumentParser(description="Access different services.")
    parser.add_argument("service", choices=["es", "redis", "etcd", "rabbitmq", "all"], help="The service to access")
    args = parser.parse_args()
    service = args.service
    if service == "es":
        wait_for_service(service, access_es)
    elif service == "redis":
        wait_for_service(service, access_redis)
    elif service == "etcd":
        wait_for_service(service, access_etcd)
    elif service == "rabbitmq":
        wait_for_service(service, access_rabbitmq)
    else:
        wait_for_service(service, access_es)
        wait_for_service(service, access_etcd)
        wait_for_service(service, access_redis)
        wait_for_service(service, access_rabbitmq)

if __name__ == "__main__":
    main()
