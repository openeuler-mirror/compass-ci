import subprocess
import os
import re
import json
from libpy.es_client import EsClient

class SubmitJob():
    def __init__(self, request_body):
        self.request_body = request_body

    def submit_job(self):
        job_ids = []
        job_id_pattern = re.compile(r"got job id=([^ ]*)")

        pre_submit_command = "/c/lkp-tests/sbin/submit"
        pre_submit_command += " os=" + self.request_body["os"].strip()
        pre_submit_command += " os_arch=" + self.request_body["os_arch"].strip()
        pre_submit_command += " os_version=" + self.request_body["os_version"].strip()
        pre_submit_command += " " + self.request_body["framework"].strip() + ".yaml"

        for case in self.request_body["case_list"]:
            submit_command = pre_submit_command
            submit_command += " name=" + case["name"]

            if case["machine_type"] == "vm":
                testbox = "vm-" + case["cpu"] + case["memory"]
            elif case["machine_type"] == "vt":
                testbox = "vt-" + case["cpu"] + case["memory"]
            else:
                testbox = "dc-" + case["memory"]

            submit_command += " testbox=" + testbox

            submit_output = subprocess.getoutput(submit_command)
            job_id = job_id_pattern.findall(submit_output)[0]
            job_ids.append(job_id)

        return {'job_ids': job_ids}

class CheckJob():
    def __init__(self):
        self.es = EsClient()

    def check_job_info(self, job_id):
        job_info = self.es.search_by_id("jobs", job_id)['_source']
        extract_keys = ['os', 'os_arch', 'os_variant', 'os_version', 'os_project', 'testbox', 'job_stage', 'job_health', 'submit_time', 'start_time', 'end_time']
        extract_dict = {}

        for key in extract_keys:
            if key in job_info:
                extract_dict[key] = job_info[key]

        return extract_dict
