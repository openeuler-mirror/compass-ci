#!/usr/bin/env python
# coding=utf-8

import os
import sys
from flask import Flask
from flask_restful import Api
from flask import request
from flasgger import Swagger

sys.path.append(os.path.abspath("../"))

from scheduled_task.app.route import RadiaTest, CheckJobResult

app = Flask(__name__)

api = Api(app)
api.add_resource(RadiaTest, '/api/submit/radia-test')
api.add_resource(CheckJobResult, '/api/data-api/get-job-info/<string:job_id>')

Swagger(app, Swagger.DEFAULT_CONFIG)
