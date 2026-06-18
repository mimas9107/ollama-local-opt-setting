---
name:          "AGENTS.md"
description:   "RTX 4060 GPU 效能調優與除錯指引"
created_date:  "2026/05/29 13:25:00"
modified_date: "2026/06/18 10:45:00"
project_version: "1.0.0"
document_version: "1.1.0"
agent_sign: ['human/mimas', 'gemini cli/gemini-cli']
---

# Ollama 效能優化專案 (AGENTS.md)

本文件定義此專案的特化開發行為。Agent 必須同時遵循工作區全域規範 (../AGENTS.md)。

## 1. 優化核心
- **硬體限制**: 考慮 8GB VRAM 限制，平衡 num_gpu 與 num_ctx。
- **環境**: 區分 systemd 服務環境 (override.conf) 與手動執行環境。
- **驗證**: 修改後必須檢查 eval rate (tokens/s) 與 nvidia-smi GPU 利用率。

---
*註：本文件專注於專案業務與技術細節，通用環境指令與 Token 節約準則請查閱全域規範。*
