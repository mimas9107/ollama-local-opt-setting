#!/bin/bash

# ==============================================================================
#  Ollama GPU 快速診斷腳本 (v2)
# ==============================================================================
#
#  此腳本會檢查 Ollama 服務的環境配置，並執行一個簡短的推理測試，
#  透過分析 eval rate 來判斷 GPU 是否被成功用於加速。
#
#  用法:
#    bash check-gpu.sh
#    bash check-gpu.sh <要測試的模型名稱>
#
# ==============================================================================

# --- 配置 ---
MODEL_NAME=${1:-"qwen3:8b-optimized"} # 如果沒有提供參數，則使用預設模型
CPU_PERF_THRESHOLD=8.0  # CPU 性能閾值 (tokens/s)，低於此值可能表示純 CPU
GPU_PERF_THRESHOLD=10.0 # GPU 性能閾值 (tokens/s)，高於此值表示 GPU 加速成功

# --- 顏色 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- 函數 ---
print_ok() {
    echo -e "${GREEN}[  OK  ]${NC} $1"
}

print_fail() {
    echo -e "${RED}[ FAIL ]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[ WARN ]${NC} $1"
}

print_info() {
    echo "         $1"
}


# --- 主程序 ---
echo "=== Ollama GPU 快速診斷 v2 ==="
echo ""

# 1. 檢查 Ollama 服務狀態
echo "【1】檢查 Ollama 服務..."
if ! systemctl is-active --quiet ollama; then
    print_fail "Ollama 服務 (ollama.service) 未在運行。"
    exit 1
else
    print_ok "Ollama 服務正在運行。"
fi
echo ""

# 2. 檢查 systemd 環境變數
echo "【2】檢查 systemd 服務環境配置..."
SERVICE_ENV=$(systemctl show ollama | grep Environment=)

if [[ "$SERVICE_ENV" == *"OLLAMA_NVIDIA_DRIVERS=all"* ]]; then
    print_ok "檢測到 OLLAMA_NVIDIA_DRIVERS=all"
else
    print_warn "未檢測到 OLLAMA_NVIDIA_DRIVERS=all。這可能導致 GPU 無法被偵測。"
fi

if [[ "$SERVICE_ENV" == *"LD_LIBRARY_PATH"* ]]; then
    print_ok "檢測到 LD_LIBRARY_PATH 已設定。"
    print_info "$(systemctl show ollama | grep LD_LIBRARY_PATH)"
else
    print_warn "未檢測到 LD_LIBRARY_PATH。如果自動偵測失效，這可能是個問題。"
fi
echo ""

# 3. 執行性能測試
echo "【3】執行簡短推理性能測試..."
print_info "測試模型: $MODEL_NAME"
print_info "正在運行，請稍候..."

# 執行 ollama run 並捕獲輸出
RUN_OUTPUT=$(ollama run "$MODEL_NAME" "請用一句話介紹你自己。" --verbose 2>&1)

if [[ $? -ne 0 ]]; then
    print_fail "Ollama 推理執行失敗。"
    print_info "錯誤訊息: "
    echo "$RUN_OUTPUT"
    exit 1
fi

# 解析 eval rate
EVAL_RATE=$(echo "$RUN_OUTPUT" | grep "eval rate" | awk '{print $3}')

if [ -z "$EVAL_RATE" ]; then
    print_fail "無法從輸出中解析 eval rate。請檢查 Ollama 是否正常工作。"
    exit 1
fi

print_info "原始輸出: $(echo "$RUN_OUTPUT" | grep "eval rate")"
echo ""

# 4. 評估性能
echo "【4】性能評估..."
# 使用 bc 進行浮點數比較
if (( $(echo "$EVAL_RATE > $GPU_PERF_THRESHOLD" | bc -l) )); then
    print_ok "性能符合預期！ (${EVAL_RATE} tokens/s)"
    print_info "GPU 加速已成功啟用。"
elif (( $(echo "$EVAL_RATE > $CPU_PERF_THRESHOLD" | bc -l) )); then
    print_warn "性能介於 CPU 和 GPU 之間 (${EVAL_RATE} tokens/s)。"
    print_info "GPU 可能已啟用，但效率不高。請檢查 Modelfile 的 num_ctx 和 num_gpu 配置。"
else
    print_fail "性能低下！ (${EVAL_RATE} tokens/s)"
    print_info "很可能仍在使用 CPU 模式。請檢查步驟 [2] 的配置。"
fi
echo ""

# 5. 檢查 nvidia-smi
echo "【5】檢查 nvidia-smi 進程..."
if nvidia-smi --query-compute-apps=pid --format=csv,noheader | grep -q "$(pgrep -f 'ollama serve')"; then
    print_ok "在 nvidia-smi 中檢測到 Ollama 進程。"
else
    print_fail "未在 nvidia-smi 中檢測到 Ollama 進程。"
fi
echo ""
echo "=== 診斷完成 ==="