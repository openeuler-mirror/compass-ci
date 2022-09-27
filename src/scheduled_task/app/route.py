#!/usr/bin/env python3

from flask import request
from jsonschema.validators import validate
from flask_restful import Resource
from scheduled_task.app.lib.scheduled_task import SubmitJob, CheckJob
import time
import json

class RadiaTest(Resource):
    @staticmethod
    def post():
        request_body = request.json

        my_schema = {
            "type": "object",
            "properties": {
                 "os": {
                     "type": "string"
                 },
                 "os_arch": {
                     "type": "string"
                 },
                 "os_version": {
                     "type": "string"
                 },
                 "framework": {
                     "type": "string"
                 },
                 "case_list": {
                     "type": "array",
                     "items": {
                         "type": "object",
                         "required": [
                             "name",
                             "cpu",
                             "memory",
                             "machine_type"
                         ]
                     },
                     "properties": {
                         "name": {
                             "type": "string"
                         },
                         "cpu": {
                             "type": "string"
                         },
                         "memory": {
                             "type": "string"
                         },
                         "machine_type": {
                             "type": "string"
                         }
                     }
                 }
            },
            "required": [
                "os"
            ]
        }

        validate(instance=request_body, schema=my_schema)
        submit_job = SubmitJob(request_body)
        submit_result = submit_job.submit_job()

        return submit_result

class CheckJobResult(Resource):
    @staticmethod
    def get(job_id):
        check_job = CheckJob()
        check_result = check_job.check_job_info(job_id)

        return check_result
