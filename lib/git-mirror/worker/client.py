import grpc
import subprocess
import time
import threading
import os
import yaml
import shelve
from concurrent import futures
import sys
sys.path.append('../protocal/')
import func_pb2
import func_pb2_grpc
import common
from dataclasses import dataclass
from typing import List
from queue import PriorityQueue
import math
import time

@dataclass
class SelfWorker:
    worker_id: int
    uuid: str
    urls: List[str]
    clone_disk_path: str

@dataclass
class Task:
    def __init__(self):
        self.pri = 0
        self.task_type = ''
        self.repo_url = ''
        self.clone_disk_path = ''
        self.clone_fail_cnt = 0
        self.fetch_fail_cnt = 0
        self.step = 0
        self.STEP_SECONDS = 150000
        self.last_commit_time = 0
        
    def clone_repo(self, task_queue):
        print('Start trying to clone...')
        command = "cd %s && git clone %s" %(self.clone_disk_path, self.repo_url)
        result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
              
        if result.returncode != 0:
            if common.std_neterr(result.stderr) == 1:
                print("[clone] repo cloning failed. Try again later..... ")
                self.clone_fail_cnt += 1
            elif common.std_cloneerr(result.stderr) == 2: 
                print("[clone] repo is clone, Start trying to update the repository... ")
                self.task_type = 'git fetch'
            elif common.std_cloneerr(result.stderr) == 1:
                print('[clone] clone fail: Invalid repository url')
                return
            
        self.task_type = 'git fetch'   
        self.get_task_priority()
        task_queue.put([self.pri, self])   
        print("repo cloning success! ")
        
    def fetch_repo(self, task_queue):
        print('start fetch ',self.repo_url)
        command = "cd %s && git fetch %s" %(self.clone_disk_path, self.repo_url)
        result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)

        if result.returncode != 0:
            if common.std_fetcherr(result.stderr) == 1:
                print('[fetch] Current warehouse does not exist!')
                return
            # 仓库存在但fetch失败 (重试
            self.fetch_fail_cnt += 1
        else:
            print('repo fetch successful!')
        
        self.get_task_priority()
        task_queue.put([self.pri, self])
    
    def get_task_priority(self):
        if self.pri is None:
            self.pri = 0
        step = (self.clone_fail_cnt + 1) * math.pow(self.STEP_SECONDS, 1/3)
    
        if self.task_type == 'git clone': # clone task
            self.pri += step  # Default step
            return
        return self.cal_priority()
    
    # [fetch]Prioritization based on the interval between the last commit of the repository and the current time
    def cal_priority(self):
        old_pri = self.pri
        step = (self.fetch_fail_cnt + 1) * math.pow(self.STEP_SECONDS, 1/3)
        
        if self.last_commit_time == -1:
            WorkerManager.get_last_commit_time(self.repo_url)
        elif self.last_commit_time == 0: 
            self.pri = old_pri + step
            return

        t = time.time()
        interval = t - self.last_commit_time
        if interval <= 0:
            self.pri = old_pri + step
            return

        self.pri = old_pri + math.pow(interval, 1/3)
        return

class WorkerManager:
    def __init__(self):
        self.worker = SelfWorker(worker_id=-1, uuid='', urls=[], clone_disk_path='.')
        self.selfdb = shelve.open('self.db')
        if "worker" in self.selfdb:
            self.worker = self.selfdb["worker"]
        self.task_queue = PriorityQueue()
        for i in  self.worker.urls:
            task = Task()
            task.repo_url = i  
            task.task_type = 'git fetch'
            task.clone_disk_path = self.worker.clone_disk_path
            task.pri = 1
            self.task_queue.put([task.pri, task])
                
    def get_last_commit_time(self, repo):
        try:
            name = common.get_name_from_repo(repo)
            command = f"cd {self.worker.clone_disk_path} && git -C {name} log --pretty=format:%ct -1"
            output = subprocess.check_output(command, shell=True, stderr=subprocess.DEVNULL, universal_newlines=True)
            self.last_commit_time = int(output.strip())
            return self.last_commit_time
        except subprocess.CalledProcessError:
            self.last_commit_time = -1
            return None
    
    def add_repo(self, add_repos):
        for v in add_repos:
            if v in self.worker.urls:
                print('[add repo] repo already exists.', v)
                continue
            else:
                self.worker.urls.append(v)
            task = Task()
            task.repo_url = v
            task.task_type = 'git clone'
            task.clone_disk_path = self.worker.clone_disk_path
            task.pri = 1
            self.task_queue.put([task.pri, task])
        
        rm_list = []
        for v in self.worker.urls:
            if v not in add_repos:
                print("start remove repo", v)
                rm_list.append(v)
        self.del_repo(rm_list)

        self.selfdb["worker"] = self.worker

    def del_repo(self, del_repos):
        for v in del_repos:
            print('remove %s' %v)
            self.worker.urls.remove(v)
            repo_name = common.get_name_from_repo(v)
            command = 'cd %s && rm -rf %s' %(self.worker.clone_disk_path, repo_name)
            result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
            if result.returncode != 0:
                print('rm repo fail!') 
            print("rm repo success!")

        self.selfdb["worker"] = self.worker
    
    def process_tasks(self, thread_pool):
        while True:
            _, task = self.task_queue.get()
            if task.repo_url in self.worker.urls:
                if task.task_type == "git clone":
                    thread_pool.submit(task.clone_repo, self.task_queue)
                else:
                    thread_pool.submit(task.fetch_repo,self.task_queue)  
    
    def heart_beat(self, stub):
        while True:
            try:
                res = stub.HeartBeat(func_pb2.HeartBeatRequest(workerID=self.worker.worker_id))
                if res.status == common.ADD_DEL_REPO:
                    if res.add_repos:
                        self.add_repo(res.add_repos)
                    if res.del_repos:
                        self.del_repo(res.del_repos)
                time.sleep(5)
            except grpc.RpcError as e:
                if e.code() == grpc.StatusCode.UNAVAILABLE:
                    print('Coordinator hang-up detected.!')
                    sys.exit(0)
                else:
                    print(f"gRPC Error: {e.details()}")
                    sys.exit(0)

    @staticmethod
    def read_config_file():
        cur_path = os.path.dirname(os.path.realpath(__file__))
        yaml_path = os.path.join(cur_path, "config.yaml")
        with open(yaml_path, 'r', encoding='utf-8') as f:
            config = f.read()
        config_map = yaml.load(config, Loader=yaml.FullLoader)
        return config_map

    def connect_to_coordinator(self, config_map):
        try:
            coor_ip_addr = config_map.get('where_coor_ip_addr')
            clone_disk_path = config_map.get('clone_disk_path')
            if not os.path.exists(clone_disk_path):
                os.makedirs(clone_disk_path)
            self.worker.clone_disk_path = clone_disk_path
            channel = grpc.insecure_channel(coor_ip_addr) 
            stub = func_pb2_grpc.CoordinatorStub(channel)
            response = stub.SayHello(func_pb2.HelloRequest(workerID=self.worker.worker_id, uuid=self.worker.uuid))
            if response.uuid != self.worker.uuid:
                self.worker.worker_id = response.workerID
                self.worker.uuid = response.uuid
                self.worker.urls = []
            self.selfdb["worker"] = self.worker
            print('Connection to coordinator successful! workerID:', self.worker.worker_id, 'uuid:', self.worker.uuid)
            
            thread_pool = futures.ThreadPoolExecutor(max_workers=10)
            taskThread = threading.Thread(target=self.process_tasks, args=(thread_pool, ))
            taskThread.start()

            self.heart_beat(stub)
            
        except grpc.RpcError as e:
            if e.code() == grpc.StatusCode.UNAVAILABLE:
                print("Error: gRPC Server is not available. Make sure the server is running.")
            else:
                print(f"gRPC Error: {e.details()}")

if __name__ == '__main__':
    manager = WorkerManager()
    config_map = manager.read_config_file()
    manager.connect_to_coordinator(config_map)