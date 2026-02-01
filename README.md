# Ollama RTX 4060 8GB 性能優化專案

## 專案目標
本專案旨在記錄並解決在特定硬體（NVIDIA GeForce RTX 4060 8GB Laptop GPU）上，Ollama 無法正確利用 GPU 進行加速（導致 GPU 利用率低、CPU 滿載）的問題。

## 問題概述
最初，在運行 `qwen3:8b` 等模型時，即使系統已安裝 NVIDIA 驅動，Ollama 的推理速度也僅有 **~4 tokens/s**，伴隨 CPU 滿載而 GPU 利用率幾乎為零。

## 最終解決方案
經過深入的除錯，我們發現問題根源於 **`systemd` 服務權限不完整**以及 **`Modelfile` 參數與 8GB 顯存不匹配**。

完整的解決方案包含兩個核心步驟：
1.  **修復 `systemd` 服務**：透過建立 `override.conf` 檔案，強制為 Ollama 服務注入 GPU 驅動相關的環境變數。
2.  **優化 `Modelfile`**：平衡 GPU 層數（`num_gpu`）和上下文窗口大小（`num_ctx`），以在 8GB VRAM 中達到最佳效能，避免記憶體不足或 CPU/GPU 交換瓶頸。

**詳細的、可直接複製執行的步驟，請務必參閱：[`FINAL-SOLUTION.md`](./FINAL-SOLUTION.md)**

---

## 核心配置
這是最終在 RTX 4060 8GB 顯卡上被驗證成功的 `Modelfile.qwen3-optimized` 內容：

```dockerfile
FROM qwen3:8b

# 优化上下文窗口 (對於 8GB VRAM, 4K 是效能與記憶體的平衡點)
PARAMETER num_ctx 4096

# 优化推理参数
PARAMETER num_predict 8192
PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40
PARAMETER repeat_penalty 1.1

# GPU 优化 (對於 8GB VRAM, 33 層是個不錯的起點)
PARAMETER num_gpu 33
```

---

## 重要檔案索引

| 檔案 | 說明 |
| :--- | :--- |
| **[`FINAL-SOLUTION.md`](./FINAL-SOLUTION.md)** | **首要閱讀！** 包含從零到解決問題的完整、詳細步驟。 |
| **[`ollama-optimization-guide.md`](./ollama-optimization-guide.md)** | 通用優化指南，包含了我們學到的針對 8GB GPU 的原則。 |
| **[`Modelfile.qwen3-optimized`](./Modelfile.qwen3-optimized)** | 最終成功的模型設定檔，可作為未來建立新模型的範本。 |
| **[`check-gpu.sh`](./check-gpu.sh)** | v2 版的智能診斷腳本，用於快速檢查 Ollama GPU 加速是否正常。 |
| **[`monitor-ollama.sh`](./monitor-ollama.sh)** | v2 版的即時監控腳本，提供豐富的系統資訊和智能診斷建議。 |

---

## 快速開始

1.  **閱讀解決方案**：
    *   詳細閱讀 [`FINAL-SOLUTION.md`](./FINAL-SOLUTION.md) 以理解完整的系統配置和模型建立過程。

2.  **診斷目前環境**：
    *   運行診斷腳本，檢查您的 Ollama 服務和配置是否正確。
    ```bash
    bash check-gpu.sh
    ```

3.  **監控性能**：
    *   在進行推理時，打開另一個終端運行監控腳本，以觀察即時效能。
    ```bash
    bash monitor-ollama.sh
    ```

## 最終性能
在本專案的硬體環境下，採用此解決方案後，`qwen3:8b-optimized` 模型的推理速度從 `~4 tokens/s` 提升至 **`~13 tokens/s`**，並成功利用 GPU 加速（佔用約 4.5GB VRAM），問題得到圓滿解決。