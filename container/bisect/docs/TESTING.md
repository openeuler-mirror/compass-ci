# Bisect 测试指南

## 快速开始

Bisect 系统有完整的测试套件，位于 `tests/` 目录。

### 运行所有测试
```bash
cd tests/
./run_tests.sh
```

### 运行特定类别的测试
```bash
./run_tests.sh core          # 核心功能测试
./run_tests.sh filters       # 过滤器测试
./run_tests.sh validators    # Validator 测试
./run_tests.sh api           # API 测试
./run_tests.sh integration   # 集成测试
```

## 测试套件说明

详细的测试文档请参考：**[tests/README.md](../tests/README.md)**

### 测试分类

1. **核心功能测试**
   - test_errid_filters.py - ErridIntelligence 过滤器测试
   - test_errid_intelligence.py - 错误智能分析测试
   - test_repo_manager_simplified.py - 仓库管理测试

2. **Validator 测试**
   - test_head_validator.py - HEAD 验证测试
   - test_success_task_validator.py - 成功任务验证测试
   - test_verification_consumer.py - 验证消费者测试
   - test_unified_verification.py - 统一验证流程测试

3. **其他测试**
   - test_summary_generation.py - 摘要生成测试
   - test_regression_write.py - Regression 写入测试
   - test_api_controllers.py - API 控制器测试
   - integration_test.py - 完整集成测试

## 环境准备

### 必需环境变量
```bash
export CCI_SRC=/c/compass-ci
export WORK_DIR=/c/bisect
export LKP_SRC=/c/lkp-tests
export MANTICORE_HOST=localhost
export MANTICORE_HTTP_PORT=9308
```

### 检查环境
```bash
# 检查环境变量
env | grep -E "CCI_SRC|WORK_DIR|MANTICORE"

# 检查数据库连接
curl -X POST http://$MANTICORE_HOST:$MANTICORE_HTTP_PORT/sql \
  -d "SELECT COUNT(*) FROM bisect"
```

## 运行单个测试

```bash
cd tests/

# 运行过滤器测试
python3 test_errid_filters.py

# 运行仓库管理测试
python3 test_repo_manager_simplified.py

# 运行验证器测试（需要数据库）
python3 test_success_task_validator.py
```

## 集成测试

集成测试需要 Bisect 服务正在运行：

```bash
# 确保服务运行
ps aux | grep -E "flask|bisect"

# 运行集成测试
./run_tests.sh integration
```

## 添加新测试

1. 在 `tests/` 目录创建测试文件
2. 确保文件名以 `test_` 开头
3. 在 `run_tests.sh` 中添加测试条目
4. 更新 `tests/README.md`

示例测试文件结构：
```python
#!/usr/bin/env python3
import os
import sys

# 设置环境
os.environ['CCI_SRC'] = os.environ.get('CCI_SRC', '/c/compass-ci')
sys.path.append(os.path.join(os.environ['CCI_SRC'], 'container/bisect/lib'))

def test_feature():
    """测试某个功能"""
    # 测试代码
    assert result == expected

if __name__ == "__main__":
    test_feature()
    print("测试通过")
```

## 测试覆盖范围

当前测试覆盖：
- 错误过滤和优先级排序
- 粗粒度签名聚类
- 仓库管理和克隆优化
- 任务验证（边界验证、HEAD 检查）
- 摘要生成
- Regression 数据写入
- API 接口
- 完整集成流程

## 常见问题

### 1. 模块导入失败
```bash
# 检查 PYTHONPATH
export PYTHONPATH=$CCI_SRC/container/bisect/lib:$PYTHONPATH
```

### 2. 数据库连接失败
```bash
# 检查 ManticoreSearch 服务
systemctl status manticore
# 或
ps aux | grep manticore
```

### 3. 测试数据问题
某些测试需要数据库中有测试数据。可以：
- 运行 Producer 生成测试任务
- 手动插入测试数据
- 使用 mock 数据

## 持续集成

测试应该在每次代码变更后运行：

```bash
# 快速测试（核心功能）
./run_tests.sh core

# 完整测试（所有测试）
./run_tests.sh

# 特定测试（调试时）
python3 test_errid_filters.py
```

---

## 性能基准测试 (Clone Benchmark)

### 目的

确定当前 tmpfs 环境下最优的并发 clone 数量，优化 `BISECT_MAX_CONCURRENT_CLONES` 配置。

### 背景

重构后的 `SharedRepoManager` 使用简化架构：
- 每个任务独立克隆（使用 `--reference` 优化空间）
- 通过 semaphore 控制并发克隆数
- 需要测试确定最优并发数以平衡性能和资源使用

### 测试工具

提供两个基准测试脚本：

#### 1. benchmark_clones_quick.py（推荐）

**特点**：
- Python 实现，测量精确
- 默认使用小型测试仓库（快速测试）
- 可配置真实仓库进行准确测试
- 输出详细统计和配置建议

**使用方法**：

```bash
# 快速测试（使用小型测试仓库，2-3分钟完成）
cd /home/shiptux/git/gitee/compass-ci/container/bisect/scripts
./benchmark_clones_quick.py

# 使用真实仓库测试（准确但较慢，10-20分钟）
./benchmark_clones_quick.py --repo https://gitee.com/openeuler/kernel.git

# 自定义参数
./benchmark_clones_quick.py \
  --repo https://gitee.com/openeuler/kernel.git \
  --clones 10 \
  --work-dir /tmp/clone_benchmark
```

**参数说明**：
- `--repo`: 测试仓库 URL（默认：小型测试仓库）
- `--clones`: 每个并发级别的克隆数（默认：6）
- `--work-dir`: 工作目录（默认：临时目录）

**测试并发级别**：`[1, 2, 4, 6, 8, 12, 16]`

#### 2. benchmark_concurrent_clones.sh

**特点**：
- Bash 实现，兼容性好
- 默认使用 openeuler-kernel 仓库
- 输出 CSV 格式结果

**使用方法**：

```bash
cd /home/shiptux/git/gitee/compass-ci/container/bisect/scripts
./benchmark_concurrent_clones.sh
```

**测试并发级别**：`[1, 2, 4, 8, 12, 16, 20, 24, 32]`

### 输出解读

#### 示例输出

```
======================================================================
并发数 | 总耗时(s) | 平均(s) | 吞吐量       | tmpfs使用
----------------------------------------------------------------------
     1 |      60.00 |     10.00 |      0.10 c/s | 1.2G/32G (4%)
     2 |      32.00 |      5.33 |      0.19 c/s | 2.1G/32G (7%)
     4 |      18.00 |      3.00 |      0.33 c/s | 3.5G/32G (11%)
     6 |      16.00 |      2.67 |      0.38 c/s | 4.8G/32G (15%)
     8 |      15.50 |      2.58 |      0.39 c/s | 6.2G/32G (19%)
    12 |      15.80 |      2.63 |      0.38 c/s | 8.5G/32G (27%)
    16 |      17.00 |      2.83 |      0.35 c/s | 11G/32G (34%)
======================================================================

✓ 推荐并发数: 8
  - 吞吐量: 0.39 clones/s
  - 平均耗时: 2.58s/clone

配置建议:
  1. 在 config.py 中设置:
     BISECT_MAX_CONCURRENT_CLONES = 8

  2. 考虑因素:
     - CPU核心数: 16
     - 推荐并发数是CPU核心数的: 0.5x
     ℹ  并发数低于CPU核心数，可能受网络/IO限制
```

#### 关键指标

1. **吞吐量 (throughput)**：每秒完成的克隆数
   - **最重要的指标**
   - 越高越好，但需平衡 tmpfs 使用

2. **平均耗时 (avg_time)**：单个克隆的平均时间
   - 反映克隆效率
   - 并发增加时应该降低（到达瓶颈前）

3. **tmpfs 使用**：内存文件系统占用
   - 确保不超过可用容量的 60-70%
   - 避免内存交换影响性能

4. **总耗时 (total_time)**：完成所有克隆的总时间
   - 最小值对应最优并发数

### 选择最优并发数的原则

#### 1. 吞吐量优先

选择吞吐量最高的并发数，这通常是：
- 吞吐量达到峰值
- 平均耗时最低
- 总耗时最短

#### 2. 资源约束

确保：
- tmpfs 使用不超过 70%（留有安全边际）
- 不引起系统内存交换
- 网络带宽未饱和

#### 3. 实际场景考虑

**小型仓库**（如测试仓库）：
- 网络/IO 是主要瓶颈
- 最优并发数通常在 4-8

**大型仓库**（如 openeuler-kernel）：
- CPU 和磁盘 IO 更重要
- 最优并发数可能更高（8-16）

#### 4. 安全建议

- 如果曲线在某点达到平台期，选择该点之前的值
- 如果吞吐量在高并发时下降，避免使用该并发数
- 在生产环境留有 20% 余量

### 实际测试流程

#### 第一步：快速测试

```bash
# 使用小型仓库快速评估
./benchmark_clones_quick.py
```

观察：
- 系统能否稳定运行
- tmpfs 使用是否合理
- 最优并发数的大致范围

#### 第二步：真实仓库测试

```bash
# 使用实际生产环境的仓库
./benchmark_clones_quick.py --repo https://gitee.com/openeuler/kernel.git --clones 10
```

获得：
- 准确的最优并发数
- 真实的资源使用情况
- 生产环境的性能预测

#### 第三步：应用配置

根据测试结果更新 `config.py`：

```python
# container/bisect/lib/config.py
BISECT_MAX_CONCURRENT_CLONES = 8  # 根据测试结果调整
```

或设置环境变量：

```bash
export BISECT_MAX_CONCURRENT_CLONES=8
```

#### 第四步：监控验证

部署后监控：
- bisect 任务处理速度
- tmpfs 使用情况
- 系统负载和内存使用
- 是否有克隆超时

### 常见问题

#### Q1: 测试过程中出现克隆失败

**原因**：网络不稳定或仓库服务器限制

**解决**：
- 重试测试
- 检查网络连接
- 使用 `--clones` 减少测试克隆数

#### Q2: tmpfs 使用过高

**原因**：并发数过高或仓库过大

**解决**：
- 降低测试并发数
- 增加 tmpfs 大小
- 考虑使用更小的测试仓库

#### Q3: 吞吐量持续增长

**原因**：未达到瓶颈

**解决**：
- 扩展测试并发级别（修改脚本中的 `CONCURRENCY_LEVELS`）
- 在生产环境逐步调整观察

#### Q4: 测试结果与生产环境不符

**原因**：测试仓库与生产仓库差异大

**解决**：
- 使用 `--repo` 参数指定真实仓库
- 增加测试克隆数以更准确反映实际情况
- 考虑测试时段的网络状况