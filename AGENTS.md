給 AI Agent 的專案指引 (AGENTS.md)

  1. 專案目標

  此專案旨在優化與除錯在特定硬體（NVIDIA RTX 4060 8GB Laptop GPU）上運行 Ollama 的效能問題，特別是解決 GPU 利用率低下而 CPU
  滿載的情況。所有腳本與文件都是為了達成此目標的產物。

  2. 核心組件

   * Ollama: v0.15.2 (或後續版本)
   * 模型: qwen3:8b (或基於此的自訂模型)
   * 作業系統: Debian 13 (Linux)
   * 核心配置檔案: Modelfile.qwen3-optimized, /etc/systemd/system/ollama.service.d/override.conf

  3. AI Agent 操作指引

   * 優先分析現有文件: 在提出新方案前，請務必先閱讀並理解此資料夾內的所有 .sh 腳本與 .md 文件，特別是 FINAL-SOLUTION.md。這些文件記錄了已成功的解決方案與除錯歷史。
   * 區分 `systemd` 與手動執行: 操作時請務必意識到，透過 sudo systemctl start ollama 運行的服務，其環境與直接在終端機中手動執行 ollama serve 的環境是不一樣的。服務的環境由
     /etc/systemd/system/ollama.service.d/override.conf 控制。
   * 尊重硬體限制: 所有效能調優都必須考慮到 8GB VRAM 的限制。這意味著 Modelfile 中的 num_gpu 和 num_ctx 參數需要謹慎平衡，不能盲目追求最大值。
   * 以 `Modelfile` 為主: 針對模型的效能調優，應優先透過修改 Modelfile.qwen3-optimized 並重建模型來實現，而不是僅依賴運行時參數。
   * 驗證必須徹底: 任何變更後，都應同時檢查 ollama run 的 eval rate (tokens/s) 和 nvidia-smi 的 VRAM 佔用與 GPU 利用率，以進行全面評估。

  4. 關鍵配置與檔案

   * `FINAL-SOLUTION.md`: 此檔案記錄了最終被驗證成功的完整解決方案。在進行任何操作前，請務必先閱讀此文件。
   * `ollama-optimization-guide.md`: 提供更通用的優化原則與建議。
   * `Modelfile.qwen3-optimized`: 這是控制模型行為的核心檔案。所有關於 GPU 層數 (num_gpu) 和上下文大小 (num_ctx) 的調整都在這裡進行。
   * `/etc/systemd/system/ollama.service.d/override.conf`: 這是控制 Ollama 系統服務行為的關鍵檔案，特別是用於賦予其 GPU 存取權限。

  5. 故障排查快速指引

   * 若 GPU 未被使用:
       1. 檢查 systemctl status ollama，確認 override.conf 已被載入。
       2. 檢查 override.conf 內容是否包含 OLLAMA_NVIDIA_DRIVERS=all 和正確的 LD_LIBRARY_PATH。
   * 若出現 `memory layout cannot be allocated` 錯誤:
       1. 這是 VRAM 不足的信號。
       2. 應編輯 Modelfile.qwen3-optimized，逐步降低 `num_gpu` 或 降低 `num_ctx` 的值，然後重建模型。
   * 若 GPU 已啟用但速度慢:
       1. 檢查 Modelfile.qwen3-optimized 中的 num_ctx 是否過大。
       2. 對於 8GB VRAM，過大的上下文視窗會導致 CPU/GPU 頻繁數據交換，成為效能瓶頸。建議將 num_ctx 調整至 4096 或更低。

  ---

