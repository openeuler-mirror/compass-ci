# 脚本使用和配置文档见 README.md
# https://github.com/Athsus/Elastic-to-Manticore

import os
import json
from elasticsearch import Elasticsearch, helpers
import manticoresearch
from manticoresearch.rest import ApiException

# 用户需要填写的配置部分
MANTICORE_URL = "http://localhost:9308"  # 修改为实际的ManticoreSearch服务器地址
ELASTICSEARCH_URL = "https://localhost:9200"  # 修改为实际的Elasticsearch服务器地址
ES_USERNAME = 'elastic'  # Elasticsearch用户名
ES_PASSWORD = 'your_password'  # Elasticsearch密码
CA_CERTS_PATH = '/path/to/your/http_ca.crt'  # SSL证书路径，比如/Users/username/Downloads/http_ca.crt 如果不使用SSL，可以忽略

# 初始化Elasticsearch客户端
es_client = Elasticsearch(
    hosts=[ELASTICSEARCH_URL],
    basic_auth=(ES_USERNAME, ES_PASSWORD),
    ca_certs=CA_CERTS_PATH
)

# 输出文件夹路径，确保使用绝对路径或确保相对路径正确
output_folder = "nested_data"
if not os.path.exists(output_folder):
    os.makedirs(output_folder)

es_to_manticore_type_mapping = {
    "text": "text",
    "keyword": "string",
    "integer": "int",
    "long": "bigint",
    "float": "float",
    "boolean": "bool",
    "date": "timestamp"  # 可以转成timestamp类型
}

# Step 1: 导出所有非系统索引的mapping信息，并保存为json文件
def export_index_mappings(es, output_folder):
    try:
        # 获取所有索引，并过滤掉以 "." 开头的系统索引
        indices = [index for index in es.indices.get_alias(index="*").keys() if not index.startswith('.')]
        print(f"发现的非系统索引: {list(indices)}")

        for index in indices:
            # 获取每个索引的mapping信息
            mapping = es.indices.get_mapping(index=index).body
            
            # 保存mapping信息为json文件，文件名为索引名
            with open(f"{output_folder}{index}_mapping.json", "w") as f:
                json.dump(mapping, f, indent=2)
            print(f"索引 {index} 的mapping已保存.")
            return 0
    except Exception as e:
        print(f"导出mapping时出错: {e}")
        return -1

# Step 2: 导出每个非系统索引对应的documents，并保存为json文件
def export_index_documents(es, output_folder):
    try:
        # 获取所有非系统索引，并过滤掉系统索引
        indices = [index for index in es.indices.get_alias(index="*").keys() if not index.startswith('.')]

        for index in indices:
            # Scroll API用于处理大量数据
            documents = helpers.scan(es, index=index, query={"query": {"match_all": {}}})
            docs = [doc['_source'] for doc in documents]  # 获取所有文档的_source部分
            
            # 保存documents为json文件，文件名为索引名
            with open(f"{output_folder}{index}_documents.json", "w") as f:
                json.dump(docs, f, indent=2)
            print(f"索引 {index} 的documents已保存.")
            return 0
    except Exception as e:
        print(f"导出documents时出错: {e}")
        return -1

# Step 1: 读取 mapping JSON 文件并创建 ManticoreSearch 索引
def create_manticore_index_from_mapping(api_client, mapping_file, index_name):
    try:
        with open(mapping_file, "r") as f:
            mapping = json.load(f)
        
        # 获取索引的字段定义
        properties = mapping[index_name]['mappings']['properties']
        
        # 构建 ManticoreSearch 的 CREATE TABLE 语句
        fields = []
        for field, field_def in properties.items():
            # 处理嵌套类型，映射为 JSON
            if field_def.get("type") == "nested" or "properties" in field_def:
                manticore_type = "json"
            else:
                # 获取映射的类型，默认为 text
                es_type = field_def.get("type", "text")  # 默认类型为 text
                manticore_type = es_to_manticore_type_mapping.get(es_type, "text")  # 使用映射转换类型
        
            # 添加字段和其类型到 CREATE TABLE 语句
            fields.append(f"{field} {manticore_type}")
        
        fields_sql = ", ".join(fields)
        create_index_sql = f"CREATE TABLE {index_name} ({fields_sql})"
        
         # 打印生成的 SQL 语句进行调试
        print(f"生成的 SQL 语句: {create_index_sql}")

        # 执行 SQL 创建索引
        api_instance = manticoresearch.UtilsApi(api_client)
        api_instance.sql(f"DROP TABLE IF EXISTS {index_name}")
        api_instance.sql(create_index_sql)
        print(f"索引 {index_name} 在 ManticoreSearch 中创建成功。")
    
    except ApiException as e:
        print(f"创建索引 {index_name} 时出错: {e}")
    except json.JSONDecodeError as e:
        print(f"读取文件 {mapping_file} 时发生错误: {e}")

# Step 2: 读取 document JSON 文件并批量插入文档
def bulk_insert_documents_to_manticore(api_client, documents_file, index_name):
    try:
        with open(documents_file, "r") as f:
            documents = json.load(f)

        index_api = manticoresearch.IndexApi(api_client)
        # for doc in documents:
        #     doc.pop("id", None)  # 移除 _id 字段，避免插入时出错
        #     print(doc)
        #     res = index_api.insert({"index": index_name, "doc": doc})
        #     print(f'插入响应 {res}')
        docs = []
        for doc in documents:
            doc.pop("id", None)  # 移除 _id 字段，避免插入时出错
            docs.append({"insert": {"index": index_name, "id": 0, "doc": doc}})
        ndjson_body = "\n".join(map(json.dumps, docs))
        response = index_api.bulk(ndjson_body)

        print(f"批量插入响应: {response}") 
        print(f"文档已成功插入到索引 {index_name}。")
    
    except ApiException as e:
        print(f"插入文档时出错: {e}")
        print(f"API 响应: {e.body}")  # 显示 API 错误的具体响应
    except json.JSONDecodeError as e:
        print(f"读取文件 {documents_file} 时发生错误: {e}")

# Step 3: 批量处理目录下的所有 mapping 和 document 文件
def migrate_elasticsearch_to_manticore(api_client, mapping_folder, document_folder):
    mapping_files = [f for f in os.listdir(mapping_folder) if f.endswith("_mapping.json")]
    document_files = [f for f in os.listdir(document_folder) if f.endswith("_documents.json")]

    for mapping_file in mapping_files:
        index_name = mapping_file.replace("_mapping.json", "")
        mapping_file_path = os.path.join(mapping_folder, mapping_file)
        
        # 创建对应的 ManticoreSearch 索引
        create_manticore_index_from_mapping(api_client, mapping_file_path, index_name)
        
        # 对应的文档文件
        document_file = index_name + "_documents.json"
        document_file_path = os.path.join(document_folder, document_file)
        
        if os.path.exists(document_file_path):
            # 批量插入文档
            bulk_insert_documents_to_manticore(api_client, document_file_path, index_name)
        else:
            print(f"未找到索引 {index_name} 的文档文件。")

def output_es_data():
    print("============导出Elasticsearch数据============")
    try:
        if not os.path.exists(output_folder):
            os.makedirs(output_folder)
        
        # 导出索引的mapping和documents
        status1 = export_index_mappings(es_client, output_folder)
        status2 = export_index_documents(es_client, output_folder)

        print("ES导出执行结束。")
        if ~status1:
            print("导出mapping失败")
        else:
            print("导出mapping成功")
        
        if ~status2:
            print("导出documents失败")
        else:
            print("导出documents成功")
        
    except Exception as e:
        print(f"导出数据库出错 {e}")
        

def migrate_to_manticore():
    print("============迁移至ManticoreSearch============")
    # 目录路径
    global output_folder
    mapping_folder = output_folder
    document_folder = output_folder

    # 初始化 ManticoreSearch 客户端
    try:
        configuration = manticoresearch.Configuration(host="http://127.0.0.1:9308")
    except Exception as e:
        print(f"初始化 ManticoreSearch 客户端出错: {e}")

    with manticoresearch.ApiClient(configuration) as api_client:
        # 开始迁移
        migrate_elasticsearch_to_manticore(api_client, mapping_folder, document_folder)


if __name__ == "__main__":
    # output_es_data()
    migrate_to_manticore()