# Ollama GPU 問題最終解決方案

## 問題確認
Ollama 在運行模型時，GPU 利用率低（甚至 0%），CPU 利用率卻接近滿載，導致推理速度緩慢。
- **具體現象**: 運行 `qwen3:8b` 模型時，CPU 滿載，速度僅 3-4 tokens/s。
- **環境**: Debian 13, Ollama `0.15.2` (官方最新), i5-13500HX CPU, NVIDIA GeForce RTX 4060 8GB Laptop GPU。

## 解決方案（按優先順序）

### 方案 1：更新 Ollama (推薦)
確保您使用的是最新版本的 Ollama，以獲得最佳的 GPU 兼容性。
```bash
# 停止服務
sudo systemctl stop ollama

# 下載並安裝最新版 (會自動覆蓋舊版並設定服務)
curl -fsSL https://ollama.com/install.sh | sh

# 驗證版本
ollama --version  # 應為最新版本，目前為 0.15.2 (此版本已包含良好 GPU 支援)

# 重啟服務 (如果上一步沒有自動重啟)
sudo systemctl restart ollama
```

### 方案 2：手動運行（繞過 systemd）
此方法用於快速測試，不建議作為長期方案。
```bash
# 1. 停止 systemd 服務
sudo systemctl stop ollama

# 2. 手動啟動（帶完整環境變數）
# 確保 LD_LIBRARY_PATH 包含您的 CUDA 函式庫路徑
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/lib/ollama/cuda_v13:$LD_LIBRARY_PATH
export OLLAMA_LLM_LIBRARY=cuda # (此變數在新版 Ollama 中可能不再需要，但無害)
ollama serve

# 3. 在另一個終端測試
ollama run qwen3:8b-optimized --verbose
```

### 方案 3：使用 Docker 運行
Docker 提供了一個隔離的環境，通常能更好地處理 GPU 驅動問題。
```bash
# 安裝 nvidia-container-toolkit（如果還沒裝）
# (具體安裝步驟請參考 NVIDIA Docker 官方文檔，因發行版而異)
# 例如 (Debian):
# distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
# curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
# curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
# sudo apt update && sudo apt install -y nvidia-container-toolkit

# 運行 Ollama Docker（GPU 支援）
docker run -d --gpus all -p 11434:11434 -v ollama:/root/.ollama --name ollama ollama/ollama:latest

# 測試
docker exec -it ollama ollama run qwen3:8b-optimized
```

### 方案 4：修改模型參數（降低 CPU 使用）
創建 Modelfile 強制 GPU 層數。此方案需與**方案 5** 結合，才能實現最佳效果。
```dockerfile
FROM qwen3:8b-optimized
PARAMETER num_gpu 33   # 放入 33 層到 GPU (根據顯存微調)
PARAMETER num_ctx 4096 # 上下文窗口限制 (根據顯存微調)
```

然後運行：
```bash
ollama create qwen3-gpu -f Modelfile
ollama run qwen3-gpu --verbose
```

### 方案 5：完整 GPU 加速解決方案 (已驗證)
針對 RTX 4060 8GB GPU 和 `qwen3:8b` 模型，此方案已驗證成功。

**問題概述**：即使 Ollama 版本最新，`systemd` 服務配置可能未正確賦予 Ollama 進程存取 NVIDIA GPU 的完整權限，且模型參數 `num_gpu` 及 `num_ctx` 設定不當導致 VRAM 不足或 CPU/GPU 頻繁切換瓶頸。

**解決步驟**：

1.  **修復 `systemd` 服務的 GPU 存取權限**：
    *   建立或更新 `systemd` 的 `drop-in` 設定檔，以確保 Ollama 服務能正確偵測和使用 GPU。
    ```bash
    # 建立 systemd drop-in 設定檔目錄 (如果不存在)
    sudo mkdir -p /etc/systemd/system/ollama.service.d

    # 寫入或更新修正設定
    echo '[Service]
    Environment="OLLAMA_NVIDIA_DRIVERS=all"
    Environment="LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu/"' | sudo tee /etc/systemd/system/ollama.service.d/override.conf
    ```
    *   重新載入 `systemd` 配置並重啟 Ollama 服務，使變更生效。
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl restart ollama
    ```

2.  **優化 `Modelfile` 參數以適應 8GB VRAM**：
    *   編輯您的 `Modelfile.qwen3-optimized` 檔案（位於您工作目錄下），調整 `num_ctx` 和 `num_gpu` 參數。這能平衡顯存佔用與 GPU 加速效果，避免記憶體不足或 CPU/GPU 資料傳輸瓶頸。
    *   打開 `Modelfile.qwen3-optimized`，將內容修改為以下：
    ```dockerfile
    FROM qwen3:8b

    # 优化上下文窗口
    PARAMETER num_ctx 4096

    # 优化推理参数 (保持其他不变或根据需要微调)
    PARAMETER num_predict 8191
    PARAMETER temperature 0.7
    PARAMETER top_p 0.9
    PARAMETER top_k 40
    PARAMETER repeat_penalty 1.1

    # GPU 优化
    PARAMETER num_gpu 33
    ```
    *   **重新建立模型**，使 `Modelfile` 的變更生效。
    ```bash
    ollama rm qwen3:8b-optimized       # 刪除舊模型 (若存在)
    ollama create qwen3:8b-optimized -f Modelfile.qwen3-optimized # 建立新模型
    ```

3.  **驗證 GPU 加速效果**：
    *   運行模型進行推理，並同時監控 GPU 狀態。
    ```bash
    ollama run qwen3:8b-optimized "給我一句關於程式設計的勵志名言" --verbose & # 背景運行 Ollama 推理
    nvidia-smi --query-gpu=utilization.gpu,memory.used,power.draw --format=csv,noheader,nounits -l 1 # 每秒監控
    ```
    *   **預期結果**：
        *   `ollama run` 的 `eval rate` 顯著提升 (從 ~4 t/s 提升到 **~13 t/s**)。
        *   `nvidia-smi` 顯示 Ollama 進程使用約 **4.5GB VRAM**。
        *   推理時 `GPU-Util` 會有明顯的提升。

## 驗證 GPU 是否正常
運行這個命令監控：
```bash
watch -n 0.5 nvidia-smi
```

正常情況下：
- 載入時：GPU 內存佔用上升（Ollama 進程顯示約 4.5GB VRAM）
- **推理時**：GPU 利用率會有明顯波動 (例如 >10%)，而不是 0%。
- CPU 應該維持在較低水平。

## 進階調整建議
如果仍有效能問題或想進一步優化：
1.  **微調 `num_gpu`**：您可以嘗試在 `Modelfile` 中將 `num_gpu` 值微調至 33-40 之間，但請監控 VRAM 佔用，避免再次出現 `memory layout cannot be allocated` 錯誤。
2.  **調整 `num_ctx`**：如果您的應用不需要非常長的上下文，適當降低 `num_ctx` (例如 2048) 可以進一步減少 VRAM 佔用，甚至允許更高的 `num_gpu` 值。
3.  **檢查其他進程**：確保沒有其他應用程式佔用大量 GPU 資源。

## 快速檢查清單
- [x] `nvidia-smi` 顯示 GPU 驅動正常。
- [x] CUDA 版本 >= 12.0 (透過 `nvidia-smi` 確認)。
- [x] Ollama 版本為最新 (目前 `0.15.2`)。
- [x] `systemd` `override.conf` 已正確配置 `Environment="OLLAMA_NVIDIA_DRIVERS=all"`。
- [x] `systemd` `override.conf` 已正確配置 `Environment="LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/lib/x86_64-linux-gnu/"`。
- [x] `Modelfile` 中的 `num_gpu` 和 `num_ctx` 已針對 8GB VRAM 進行優化 (例如 `num_gpu 33`, `num_ctx 4096`)。
- [ ] 模型顯存 < GPU 總顯存（8GB）。
- [ ] 不是 vision 模型（mllama 架構有已知問題）。