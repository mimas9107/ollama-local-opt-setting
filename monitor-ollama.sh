#!/bin/bash

# ==============================================================================
#  Ollama 性能與診斷監控腳本 (v2)
# ==============================================================================
#
#  此腳本會即時監控系統資源，特別是針對 Ollama 的 GPU 使用情況，
#  並提供基於常見問題的智能診斷建議。
#
# ==============================================================================

# --- 顏色 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo "=== Ollama 性能與診斷監控 v2 ==="
echo "按 Ctrl+C 退出"
echo ""

while true; do
    # --- 資料獲取 ---
    TIMESTAMP=$(date "+%H:%M:%S")
    OLLAMA_PID=$(pgrep -f "ollama serve")

    # GPU Info
    GPU_INFO=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,power.draw,temperature.gpu --format=csv,noheader,nounits)
    GPU_UTIL=$(echo "$GPU_INFO" | awk -F', ' '{print $1}')
    GPU_MEM_USED=$(echo "$GPU_INFO" | awk -F', ' '{print $2}')
    GPU_MEM_TOTAL=$(echo "$GPU_INFO" | awk -F', ' '{print $3}')
    GPU_POWER=$(echo "$GPU_INFO" | awk -F', ' '{print $4}')
    GPU_TEMP=$(echo "$GPU_INFO" | awk -F', ' '{print $5}')

    # System RAM
    MEM_INFO=$(free -m | grep Mem)
    MEM_USED=$(echo "$MEM_INFO" | awk '{print $3}')
    MEM_TOTAL=$(echo "$MEM_INFO" | awk '{print $2}')

    # --- 介面輸出 ---
    clear
    echo -e "${BLUE}=== Ollama 性能與診斷監控 v2 @ ${TIMESTAMP} ===${NC}"
    echo ""

    echo "--- 系統資源 ---"
    printf "GPU: [%-20s] %3s%% | %5.0fW | %2s°C | VRAM: %5.0f / %5.0f MiB\n" \
           "$(printf '#%0.s' $(seq 1 $((GPU_UTIL / 5)) 2>/dev/null))" 
           "$GPU_UTIL" "$GPU_POWER" "$GPU_TEMP" "$GPU_MEM_USED" "$GPU_MEM_TOTAL"
    printf "RAM: [%-20s] %5.0f / %5.0f MiB\n" \
           "$(printf '#%0.s' $(seq 1 $((MEM_USED * 20 / MEM_TOTAL)) 2>/dev/null))" 
           "$MEM_USED" "$MEM_TOTAL"
    echo ""


    echo "--- Ollama 狀態 ---"
    if [ -n "$OLLAMA_PID" ]; then
        OLLAMA_CPU_USAGE=$(ps -p "$OLLAMA_PID" -o %cpu --no-headers | awk '{print $1}')
        OLLAMA_GPU_VRAM=$(nvidia-smi --query-compute-apps=pid,used_gpu_memory --format=csv,noheader,nounits | grep "$OLLAMA_PID" | awk -F', ' '{print $2}')
        IS_ON_GPU=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader | grep -c "$OLLAMA_PID")

        printf "Ollama 服務: ${GREEN}運行中${NC} | PID: %-7s | CPU: %5s%% | VRAM: %5s MiB\n" \
               "$OLLAMA_PID" "$OLLAMA_CPU_USAGE" "${OLLAMA_GPU_VRAM:-0}"
    else
        printf "Ollama 服務: ${RED}未運行${NC}\n"
    fi
    echo ""

    echo "--- 智能診斷 ---"
    if [ -n "$OLLAMA_PID" ]; then
        LAST_LOG=$(journalctl -u ollama -n 10 --no-pager --output cat 2>/dev/null)
        if [[ "$LAST_LOG" == *"memory layout cannot be allocated"* ]]; then
            echo -e " diagnosis: ${YELLOW}[顯存不足]${NC} 最近日誌顯示 'memory layout' 錯誤。"
            echo "   建議: 請編輯 Modelfile，嘗試降低 'num_gpu' 或 'num_ctx' 的值，然後重建模型。"
        elif [ "$IS_ON_GPU" -eq 0 ]; then
            echo -e " diagnosis: ${RED}[GPU 未啟用]${NC} Ollama 正在運行，但未在 nvidia-smi 中檢測到。"
            echo "   建議: 請檢查 /etc/systemd/system/ollama.service.d/override.conf 配置是否正確，然後重啟服務。"
        elif (( $(echo "$GPU_UTIL < 10 && $OLLAMA_CPU_USAGE > 50" | bc -l) )); then
             echo -e " diagnosis: ${YELLOW}[效率低下]${NC} GPU 利用率低，但 CPU 負載高。"
             echo "   建議: 可能是 CPU/GPU 數據交換瓶頸。請檢查 Modelfile 的 'num_ctx' 是否過大 (建議 4096)。"
        else
            echo -e " diagnosis: ${GREEN}[狀態良好]${NC} Ollama 正在使用 GPU 進行運算。"
        fi
    else
        echo " diagnosis: Ollama 服務未運行，無法診斷。"
    fi

    sleep 2
done