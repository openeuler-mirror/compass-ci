import pytest
from unittest.mock import patch, Mock
import json
import os
import sys
sys.path.append((os.environ['CCI_SRC']) + '/lib')
from manticore_simple import ManticoreClient


@pytest.fixture
def default_client():
    """默认配置客户端 (localhost:9308)"""
    return ManticoreClient()

@pytest.fixture
def bisect_test_data():
    """bisect索引测试数据"""
    return {
        "bad_job_id": 123123124123,
        "error_id": "stderr.eid../include/linux/thread_info.h:#:#:error",
        "bisect_status": "wait"
    }

# 基础功能测试
@patch('requests.post')
def test_insert_success(mock_post, default_client):
    """测试插入文档成功"""
    mock_post.return_value.status_code = 200
    doc = {"key": "value"}
    
    assert default_client.insert("bisect", 123123124123, doc) is True
    
    mock_post.assert_called_once_with(
        "http://localhost:9308/insert",
        json={"index": "bisect", "id": 123123124123, "doc": doc},
        timeout=3
    )

@patch('requests.post')
def test_update_success(mock_post, default_client):
    """测试部分更新文档成功"""
    mock_post.return_value.status_code = 200
    update_fields = {"bisect_status": "completed"}
    
    assert default_client.update("bisect", 123456, update_fields) is True
    
    mock_post.assert_called_once_with(
        "http://localhost:9308/update",
        json={"index": "bisect", "id": 123456, "doc": update_fields},
        timeout=3
    )

@patch('requests.post')
def test_update_partial_fields(mock_post, default_client):
    """测试仅更新部分字段"""
    mock_post.return_value.status_code = 200
    partial_update = {"status": "done", "progress": 100}
    
    assert default_client.update("bisect", 789, partial_update) is True
    assert mock_post.call_args[1]['json']['doc'] == partial_update

@patch('requests.post')
def test_update_failure(mock_post, default_client):
    """测试更新失败场景"""
    mock_post.return_value.status_code = 500
    assert default_client.update("bisect", 456, {"key": "value"}) is False

@patch('requests.post')
def test_replace_retry_success(mock_post, default_client, bisect_test_data):
    """测试带重试的替换操作"""
    # 第一次失败，第二次成功
    mock_post.side_effect = [
        Mock(status_code=500),
        Mock(status_code=200)
    ]
    
    assert default_client.replace_with_retry(
        index="bisect",
        id=123123124123,
        document=bisect_test_data,
        retries=2
    ) is True
    
    assert mock_post.call_count == 2
    expected_call = {
        "index": "bisect",
        "id": 123123124123,
        "doc": bisect_test_data
    }
    for call in mock_post.call_args_list:
        assert call[1]['json'] == expected_call

# 端口配置验证
@patch('requests.post')
def test_default_port_usage(mock_post, default_client):
    """验证默认端口9308"""
    mock_post.return_value.status_code = 200
    
    default_client.replace("bisect", 1, {"test": "data"})
    
    assert mock_post.call_args[0][0].startswith("http://localhost:9308/")


# 批量操作测试
@patch('requests.post')
def test_bulk_replace_format(mock_post, default_client, bisect_test_data):
    """验证批量操作数据格式"""
    mock_post.return_value.status_code = 200
    docs = {123123124123: bisect_test_data}
    
    assert default_client.bulk_replace("bisect", docs) is True
    
    # 构建预期请求体
    expected_lines = [
        json.dumps({"replace": {"_index": "bisect", "_id": 123123124123}}),
        json.dumps(bisect_test_data)
    ]
    mock_post.assert_called_once_with(
        "http://localhost:9308/bulk",
        data="\n".join(expected_lines),
        headers={"Content-Type": "application/x-ndjson"},
        timeout=10
    )


# 边界条件测试
@patch('requests.post')
def test_large_document_handling(mock_post, default_client):
    """测试大文档处理"""
    mock_post.return_value.status_code = 200
    large_doc = {"data": "a" * 1000000}  # 1MB数据
    
    assert default_client.insert("bisect", 1, large_doc) is True
    assert len(mock_post.call_args[1]['json']['doc']['data']) == 1000000

@patch('requests.post')
def test_empty_document(mock_post, default_client):
    """测试空文档处理"""
    mock_post.return_value.status_code = 200
    assert default_client.insert("bisect", 1, {}) is True
    assert mock_post.call_args[1]['json']['doc'] == {}

