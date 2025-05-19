import pickle
from concurrent.futures import ProcessPoolExecutor
import threading

# --------------------------
# 错误案例部分
# --------------------------
class ProblematicLogger:
    """模拟含线程本地存储的日志记录器"""
    def __init__(self):
        self.local_data = threading.local()  # 含_thread._local对象
        
class ProblematicTask:
    def __init__(self):
        self.lock = threading.Lock()        # 不可序列化对象
        self.logger = ProblematicLogger()   # 含不可序列化组件
        
    def process(self, task_id):
        with self.lock:
            print(f"[ERROR DEMO] Processing task {task_id}")

# --------------------------
# 修正案例部分
# --------------------------
class FixedTask:
    @staticmethod
    def process(task_id):
        # 子进程内部创建资源
        lock = threading.Lock()  # ✅ 每个进程独立创建
        logger = ProblematicLogger()  # ✅ 进程内初始化
        
        with lock:
            print(f"[FIXED DEMO] Processing task {task_id}")

# --------------------------
# 验证函数
# --------------------------
def verify_serialization():
    """验证对象序列化能力"""
    print("\n=== 序列化验证 ===")
    
    # 测试错误案例
    try:
        bad_obj = ProblematicTask()
        pickle.dumps(bad_obj.process)  # 尝试序列化绑定方法
        print("❌ 错误案例意外序列化成功")
    except Exception as e:
        print(f"✅ 错误案例验证成功（预期失败）")
        print(f"   → 错误类型: {type(e).__name__}")
        print(f"   → 错误信息: {e}")

    # 测试修正案例
    try:
        pickle.dumps(FixedTask.process)  # 序列化静态方法
        print("✅ 修正案例序列化验证通过")
    except Exception as e:
        print(f"❌ 修正案例验证失败")
        print(f"   → 错误信息: {str(e)}")

# --------------------------
# 多进程执行测试
# --------------------------
def run_process_demo():
    print("\n=== 多进程执行测试 ===")
    
    # 错误案例测试
    print("\n[测试错误案例]")
    try:
        with ProcessPoolExecutor() as executor:
            tasks = [executor.submit(ProblematicTask().process, i) for i in range(3)]
            for f in tasks:
                f.result()
    except Exception as e:
        print(f"✅ 错误案例多进程测试成功（预期失败）")
        print(f"   → 错误类型: {type(e).__name__}")
        print(f"   → 错误信息: {e}")

    # 修正案例测试
    print("\n[测试修正案例]")
    try:
        with ProcessPoolExecutor() as executor:
            tasks = [executor.submit(FixedTask.process, i) for i in range(3)]
            for f in tasks:
                f.result()
        print("✅ 修正案例多进程测试通过")
    except Exception as e:
        print(f"❌ 修正案例测试失败: {str(e)}")

if __name__ == '__main__':
    verify_serialization()
    run_process_demo()
    print("\n测试完成")
