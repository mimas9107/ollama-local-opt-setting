# 本地 LLM 优化完整指南

## 硬件配置分析

### 当前配置
- CPU: 20 核心
- 内存: 15GB (可用 8.1GB)
- GPU: NVIDIA RTX 4060 Laptop (8GB VRAM)
- ollama 版本: 0.15.2 (官方最新)

### 配置评估
✅ **优点**:
- GPU 可用（8GB VRAM）
- 内存充足（15GB）
- 多核 CPU

⚠️ **限制**:
- RTX 4060 Laptop 性能有限（相比台式显卡）
- 8GB VRAM 限制了可以高效运行的模型大小，尤其是长上下文模型。

---

## 步骤 1：硬件配置优化

### 1.1 确保 GPU 加速启用 (Ollama systemd 服务配置)
這是確保 Ollama 服務能正確存取 GPU 的關鍵一步。

1.  **建立或更新 `systemd` 的 `drop-in` 設定檔**，以確保 Ollama 服務能正確偵測和使用 GPU。
    ```bash
    # 建立 systemd drop-in 設定檔目錄 (如果不存在)
    sudo mkdir -p /etc/systemd/system/ollama.service.d

    # 寫入或更新修正設定
    echo '[Service]
    Environment="OLLAMA_NVIDIA_DRIVERS=all"
    Environment="LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu/"' | sudo tee /etc/systemd/system/ollama.service.d/override.conf
    ```
2.  **重新載入 `systemd` 配置並重啟 Ollama 服務**，使變更生效。
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl restart ollama
    ```

### 1.2 检查 ollama 是否使用 GPU

```bash
# 運行 ollama 並監控 GPU
ollama run qwen3:8b-optimized "你好" --verbose & # 在背景執行一個簡短推理
watch -n 1 nvidia-smi # 在另一個終端持續監控 GPU

# 預期：nvidia-smi 應顯示 ollama 進程佔用顯存，且推理時 GPU-Util 會有明顯波動。
```

### 1.3 优化系统资源

```bash
# 检查是否有其他 GPU 占用进程
nvidia-smi

# 如果 GPU 被占用，可以限制 ollama GPU 使用 (透過 Modelfile 中的 num_gpu 設定更精確)
# 或者手動關閉其他占用 GPU 的應用程式。
```

---

## 步骤 2：模型量化选择

### 2.1 量化级别对比

| 量化级别 | 模型大小 | 显存需求 | 质量 | 推荐用途 |
|---------\|---------\|---------\|------|--------|
| Q8_0 | 最大 | 最高 | 最好 | 生产环境，高质量 |
| Q5_K_M | 中等 | 中等 | 很好 | 平衡选择 |
| Q4_K_M | 较小 | 较低 | 好 | 日常使用（当前） |
| Q4_0 | 小 | 低 | 一般 | 资源受限 |
| Q3_K_M | 最小 | 最低 | 较差 | 快速测试 |

### 2.2 查看当前模型量化

```bash
# 查看模型详细信息
ollama show qwen3:8b

# 输出包含 quantization_level: "Q4_K_M"
```

### 2.3 下载不同量化版本（可选）

```bash
# 如果需要更高质量，可以下载 Q5 或 Q8 版本
ollama pull qwen3:8b-q5_k_m  # 如果可用
ollama pull qwen3:8b-q8_0    # 如果可用
```

---

## 步骤 3：Ollama 运行参数优化

### 3.1 上下文窗口设置（最关键）

上下文窗口 (num_ctx) 大小對 VRAM 佔用和 CPU/GPU 數據傳輸效率影響巨大。
對於 8GB 顯存的 GPU，過大的 num_ctx (例如 32768) 即使在有 GPU 加速下也可能導致效能瓶頸。

```bash
# 方法 1：在运行时指定参数 (不建議作為長期優化)
ollama run qwen3:8b "你好" --num_ctx 4096 --num_predict 4096

# 方法 2：通过 Modelfile（推荐，實現持久化優化）
```

### 3.2 创建优化 Modelfile (推荐配置)

```bash
# 创建优化版本的 Modelfile (例如 Modelfile.qwen3-optimized)
cat > Modelfile.qwen3-optimized << 'EOF'
FROM qwen3:8b

# 核心参数
PARAMETER num_ctx 4096        # 上下文窗口：建議 4K tokens，對於 8GB GPU 是更佳平衡點
PARAMETER num_predict 8192     # 最大輸出：8K tokens (根據需求調整)
PARAMETER temperature 0.7      # 温度：适度创造性
PARAMETER top_p 0.9           # 核采样：提高质量
PARAMETER top_k 40            # Top-K采样：增加多样性
PARAMETER repeat_penalty 1.1  # 重复惩罚：减少重复
PARAMETER seed 42             # 随机种子：可重现输出

# GPU 优化 (對於 8GB GPU，建議將大部分層放入 GPU)
PARAMETER num_gpu 33          # 放置 33 層到 GPU，避免 VRAM 溢出或 CPU/GPU 頻繁切換
EOF

# 刪除舊模型 (如果存在)
ollama rm qwen3:8b-optimized

# 构建自定义模型
ollama create qwen3:8b-optimized -f Modelfile.qwen3-optimized

# 使用自定义模型
ollama run qwen3:8b-optimized "你好"
```

### 3.3 优化参数详解

| 参数 | 范围 | 默认值 | 推荐 (8GB GPU) | 说明 |
|------|------|--------|----------------|------|
| `num_ctx` | 512-128K | 4096 | 4096           | 上下文窗口，越大越好但占用更多内存，易造成 CPU/GPU 瓶頸 |
| `num_predict` | - | -1 | 4096-8192      | 最大输出 token 数 |
| `temperature` | 0-2 | 0.8 | 0.7-0.9        | 较低=确定性，较高=创造性 |
| `top_p` | 0-1 | 0.9 | 0.8-0.95       | 核采样概率 |
| `top_k` | 1-100 | 40 | 20-50          | 保留前 K 个候选 |
| `repeat_penalty` | 1-2 | 1.1 | 1.1-1.5        | 防止重复输出 |

---

## 步骤 4：OpenCode 配置优化

### 4.1 更新 opencode.json 配置 (示例)

```json
{
  "provider": {
    "ollama": {
      "models": {
        "qwen3:8b": {
          "name": "qwen3:8b",
          "tool": true,
          "limit": {
            "context": 4096,  // 更新为优化后的 context
            "output": 8192
          }
        },
        "qwen3:8b-optimized": {
          "name": "qwen3:8b-optimized",
          "tool": true,
          "limit": {
            "context": 4096,  // 更新为优化后的 context
            "output": 8192
          }
        }
      },
      "options": {
        "baseURL": "http://localhost:11434/v1"
      }
    }
  }
}
```

### 4.2 配置说明

- `limit.context`: 告诉 OpenCode 模型的上下文限制
- `limit.output`: 告诉 OpenCode 模型的输出限制
- `tool`: 启用工具调用功能

---

## 步骤 5：测试与验证

### 5.1 基础性能测试

```bash
# 测试 1：简单问答
time ollama run qwen3:8b-optimized "什么是 Python？"

# 测试 2：长上下文 (注意：即使 num_ctx=4096，長上下文仍然比短上下文慢)
cat large_file.txt | ollama run qwen3:8b-optimized "总结这个文件"

# 测试 3：代码生成
ollama run qwen3:8b-optimized "写一个快速排序算法"
```

### 5.2 GPU 使用率监控

```bash
# 实时监控 GPU
watch -n 1 nvidia-smi

# 在另一个终端运行推理，观察 GPU 使用率
ollama run qwen3:8b-optimized "你好"
```

### 5.3 基准测试对比

```bash
# 默认配置 vs 优化配置
echo "=== 默认配置 ==="
time ollama run qwen3:8b "写一个冒泡排序"

echo "=== 优化配置 ==="
time ollama run qwen3:8b-optimized "写一个冒泡排序"
```

---

## 步骤 6：高级优化（可选）

### 6.1 使用 llama.cpp 直接运行（更快）

如果需要极致性能，可以直接使用 llama.cpp：

```bash
# 下载模型 GGUF 文件
wget https://huggingface.co/microsoft/Phi-3-medium-128k-instruct-gguf/resolve/main/Phi-3-medium-128k-instruct-q4.gguf

# 使用 llama.cpp 运行
llama-cli -m Phi-3-medium-128k-instruct-q4.gguf \
  --n-gpu-layers 35 \
  --ctx-size 4096 \ # 调整 ctx-size 以匹配您的 Modelfile 优化
  --temp 0.7 \
  --top-p 0.9 \
  --color \
  -p "你好"
```

### 6.2 多 GPU 配置（如果有多个 GPU）

```bash
# 在 Modelfile 中指定 GPU 分配
PARAMETER num_gpu 35  # 将 35 层放到 GPU (对于多 GPU 且 VRAM 充足的情况)
```

### 6.3 系统级优化

```bash
# 增加 OOM 分配器限制 (對於 Ollama 可能不是主要瓶頸)
echo 1 | sudo tee /proc/sys/vm/overcommit_memory

# 优化交换分区使用 (對於 Ollama 可能不是主要瓶頸)
echo 10 | sudo tee /proc/sys/vm/swappiness
```

---

## 步骤 7：故障排查

### 7.1 常见问题

#### 问题 1：GPU 未被使用或效率低下
```bash
# 1. 检查 systemd 服务配置 (参见步骤 1.1)
# 2. 检查 CUDA 可用性 (通常在 nvidia-smi 正常工作时就已存在)
ldconfig -p | grep cuda

# 3. 重新安装支持 CUDA 的 ollama (确保是官方版本)
curl -fsSL https://ollama.com/install.sh | sh

# 4. 检查 Modelfile 参数 (参见步骤 3.2)
# 确保 num_gpu 设置合理，num_ctx 没有过大。
```

#### 问题 2：内存不足 (Error: memory layout cannot be allocated)
```bash
# 1. 减小 Modelfile 中的 num_gpu 值 (例如从 33 减到 30 或 25)
# 2. 减小 Modelfile 中的 num_ctx 值 (例如从 4096 减到 2048)
# 3. 确保没有其他应用占用大量 GPU 显存。
```

#### 问题 3：推理速度慢 (即使 GPU 已启用)
```bash
# 1. 检查 Modelfile 中 num_ctx 是否过大 (参见步骤 3.1)
#    过大的上下文窗口即使有 GPU 也可能因数据传输而变慢。
# 2. 检查是否有其他进程占用 GPU (nvidia-smi)。
# 3. 增加线程数 (PARAMETER num_thread 在 Modelfile 中)。
```

### 7.2 日志调试

```bash
# 启用详细日志
OLLAMA_DEBUG=1 ollama run qwen3:8b "你好"

# 查看系统日志 (Ollama 服务的运行日志)
journalctl -u ollama -f
```

---

## 步骤 8：自动化脚本

### 8.1 一键优化脚本 (示例，请根据实际情况修改 num_ctx 和 num_gpu)

```bash
#!/bin/bash
# optimize-ollama.sh

echo "=== 本地 LLM 优化脚本 ==="

# 1. 检查硬件
echo "检查硬件配置..."
nvidia-smi
free -h

# 2. 更新 systemd 服务配置以确保 GPU 存取
echo "更新 systemd 服务配置以确保 GPU 存取..."
sudo mkdir -p /etc/systemd/system/ollama.service.d
echo '[Service]
Environment="OLLAMA_NVIDIA_DRIVERS=all"
Environment="LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu/"' | sudo tee /etc/systemd/system/ollama.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl restart ollama

# 3. 创建优化 Modelfile
echo "创建优化模型 Modelfile..."
# 以下参数已根据 8GB RTX 4060 笔记本 GPU 和 qwen3:8b 模型进行优化
cat > Modelfile.qwen3-optimized << 'EOF'
FROM qwen3:8b

# 核心参数
PARAMETER num_ctx 4096         # 上下文窗口：对于 8GB GPU 是更佳平衡点
PARAMETER num_predict 8192     # 最大输出 (根据需求调整)
PARAMETER temperature 0.7      # 温度：适度创造性
PARAMETER top_p 0.9           # 核采样：提高质量
PARAMETER top_k 40            # Top-K采样：增加多样性
PARAMETER repeat_penalty 1.1  # 重复惩罚：减少重复
PARAMETER seed 42             # 随机种子：可重现输出

# GPU 优化 (对于 8GB GPU，建议将大部分层放入 GPU)
PARAMETER num_gpu 33           # 放置 33 层到 GPU，避免 VRAM 溢出或 CPU/GPU 频繁切換
EOF

# 4. 构建模型
echo "删除旧模型并构建优化模型..."
ollama rm qwen3:8b-optimized || true # 尝试删除，如果不存在则忽略错误
ollama create qwen3:8b-optimized -f Modelfile.qwen3-optimized

# 5. 测试
echo "测试优化模型..."
ollama run qwen3:8b-optimized "优化完成！请简要介绍一下你自己。"

echo "=== 优化完成 ==="
```

### 8.2 监控脚本

```bash
#!/bin/bash
# monitor-ollama.sh

while true; do
  clear
  echo "=== Ollama 性能监控 ==="
  date
  echo ""
  echo "GPU 使用："
  nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader
  echo ""
  echo "内存使用："
  free -h | grep Mem
  echo ""
  echo "Ollama 进程："
  ps aux | grep ollama | grep -v grep
  sleep 2
done
```

---

## 附录：推荐配置 (8GB GPU 优化)

### 开发环境 (8GB GPU 推荐)
- 模型: qwen3:8b-optimized (Q4_K_M 或類似量化)
- 上下文: 4K (对于 8GB GPU 是更佳平衡点)
- 温度: 0.7
- GPU: 33 层 (对于 8GB GPU，根据实际显存使用调整)

### 生产环境 (更高 VRAM 或多 GPU)
- 模型: qwen3:8b-q5_k_m 或 qwen2.5-coder:7b (更高质量量化)
- 上下文: 16K-32K (需確認 VRAM 充足)
- 温度: 0.5-0.7
- GPU: 35-99 层 (根据可用 VRAM 选择合适的层数)

### 快速测试
- 模型: qwen2.5:1.5b
- 上下文: 4K-8K
- 温度: 0.8
- CPU-only 模式 (對於小模型也很快)

---

## 总结

优化本地 LLM 的关键步骤：

1. ✅ **硬件优化**: 确保 GPU 加速 (通过 systemd 服务配置)
2. ✅ **模型选择**: 选择合适的量化级别
3. ✅ **参数调优**: 特别是 `num_ctx` 和 `num_gpu`
4. ✅ **工具配置**: 正确配置 OpenCode
5. ✅ **测试验证**: 持续监控和调优
6. ✅ **自动化**: 使用脚本简化流程

记住：**参数优化是一个迭代过程，需要根据具体任务和硬件配置进行调整。**

---

## 参考资源

- [Ollama 文档](https://docs.ollama.com)
- [Modelfile 参考](https://docs.ollama.com/modelfile)
- [llama.cpp 参数](https://github.com/ggerganov/llama.cpp)
- [OpenCode 文档](https://opencode.ai)