import bisect
import hashlib

def get_hash(raw_str):
    md5_str = hashlib.md5(raw_str.encode('utf-8')).hexdigest()
    return int(md5_str, 16)

class HashRing(object):
    def __init__(self):
        self.cache_list = []
        self.cache_node = dict()
        self.virtual_num = 10

    # 添加节点
    def add_node(self, node):
        for index in range(0, self.virtual_num):
            node_hash = get_hash("%s_%s" % (node, index))
            bisect.insort(self.cache_list, node_hash)
            self.cache_node[node_hash] = node

    # 删除节点
    def remove_node(self, node):
            for index in range(0, self.virtual_num):
                    node_hash = get_hash("%s_%s" % (node, index))
                    if node_hash in self.cache_list:
                        self.cache_list.remove(node_hash)
                        del self.cache_node[node_hash]

    # 获取url所属节点
    def get_urls_node(self, source_key):
            key_hash = get_hash(source_key)
            index = bisect.bisect_left(self.cache_list, key_hash)
            if len(self.cache_list)==0 :
                return -1
            index = index % len(self.cache_list)  # 若比最大的node hash还大，分发给第一个node
            return self.cache_node[self.cache_list[index]]

     
        
def test():
    a = HashRing()
    a.add_node('1')
    a.add_node('2')
    a.add_node('3')
    a.add_node('4')
    
    print(a.get_urls_node("vnmbvdfvgyr")) #4
    
