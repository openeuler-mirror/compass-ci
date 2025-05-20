import pytest
from unittest.mock import patch, Mock
import json
import time
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

@patch('requests.post')
def test_custom_port_config():
    """测试自定义端口配置"""
    client = ManticoreClient(port=9309)
    with patch('requests.post') as mock_post:
        mock_post.return_value.status_code = 200
        client.insert("bisect", 1, {})
        assert ":9309" in mock_post.call_args[0][0]

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

# 异常处理测试
@patch('requests.post')
def test_request_timeout(default_client):
    """测试请求超时处理"""
    with patch('requests.post') as mock_post:
        mock_post.side_effect = TimeoutError
        assert default_client.insert("bisect", 1, {}) is False

@patch('requests.post')
def test_server_error_handling(mock_post, default_client):
    """测试服务端错误处理"""
    mock_post.return_value.status_code = 500
    assert default_client.replace("bisect", 1, {}) is False

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

# ID生成测试
def test_task_id_generation():
    """测试ID生成唯一性"""
    from manticore_simple import generate_task_id
    
    id_set = set()
    for _ in range(1000):
        new_id = generate_task_id("123", "error1")
        assert new_id not in id_set
        assert 0 <= new_id <= 0x7FFFFFFFFFFFFFFF  # 63位正整数验证
        id_set.add(new_id)
