# -*- coding: utf-8 -*-
# Generated by the protocol buffer compiler.  DO NOT EDIT!
# source: func.proto
"""Generated protocol buffer code."""
from google.protobuf import descriptor as _descriptor
from google.protobuf import descriptor_pool as _descriptor_pool
from google.protobuf import symbol_database as _symbol_database
from google.protobuf.internal import builder as _builder
# @@protoc_insertion_point(imports)

_sym_db = _symbol_database.Default()




DESCRIPTOR = _descriptor_pool.Default().AddSerializedFile(b'\n\nfunc.proto\".\n\x0cHelloRequest\x12\x10\n\x08workerID\x18\x01 \x01(\x05\x12\x0c\n\x04uuid\x18\x02 \x01(\t\"/\n\rHelloResponse\x12\x10\n\x08workerID\x18\x01 \x01(\x05\x12\x0c\n\x04uuid\x18\x02 \x01(\t\"$\n\x10HeartBeatRequest\x12\x10\n\x08workerID\x18\x01 \x01(\x05\"I\n\x11HeartBeatResponse\x12\x0e\n\x06status\x18\x01 \x01(\x05\x12\x11\n\tadd_repos\x18\x02 \x03(\t\x12\x11\n\tdel_repos\x18\x03 \x03(\t2p\n\x0b\x43oordinator\x12+\n\x08SayHello\x12\r.HelloRequest\x1a\x0e.HelloResponse\"\x00\x12\x34\n\tHeartBeat\x12\x11.HeartBeatRequest\x1a\x12.HeartBeatResponse\"\x00\x62\x06proto3')

_globals = globals()
_builder.BuildMessageAndEnumDescriptors(DESCRIPTOR, _globals)
_builder.BuildTopDescriptorsAndMessages(DESCRIPTOR, 'func_pb2', _globals)
if _descriptor._USE_C_DESCRIPTORS == False:

  DESCRIPTOR._options = None
  _globals['_HELLOREQUEST']._serialized_start=14
  _globals['_HELLOREQUEST']._serialized_end=60
  _globals['_HELLORESPONSE']._serialized_start=62
  _globals['_HELLORESPONSE']._serialized_end=109
  _globals['_HEARTBEATREQUEST']._serialized_start=111
  _globals['_HEARTBEATREQUEST']._serialized_end=147
  _globals['_HEARTBEATRESPONSE']._serialized_start=149
  _globals['_HEARTBEATRESPONSE']._serialized_end=222
  _globals['_COORDINATOR']._serialized_start=224
  _globals['_COORDINATOR']._serialized_end=336
# @@protoc_insertion_point(module_scope)
