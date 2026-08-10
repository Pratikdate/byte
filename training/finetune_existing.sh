#!/bin/bash
# Fine-tune existing Byte LLM on training_1.jsonl using Apple Silicon Metal GPU with MLX

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
LOG_FILE="$SCRIPT_DIR/finetune.log"

# Tee output to finetune.log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================================"
echo "🐾 BYTE EXISTING MODEL FINE-TUNING"
echo "========================================================"
echo "📝 Log file: $LOG_FILE"

echo ""
echo "🚀 Step 1: Formatting training_1.jsonl & running dataset pipeline..."
python3 "$SCRIPT_DIR/format_training_1.py"
python3 "$SCRIPT_DIR/pipeline.py"

echo ""
echo "📦 Step 2: Verifying Python dependencies..."
python3 -m pip install -q mlx-lm mlx huggingface_hub

echo ""
echo "🧠 Step 3: Resuming LoRA Fine-Tuning on Metal GPU (400 steps, Masked Prompt)..."
RESUME_FILE="$SCRIPT_DIR/adapters/adapters.safetensors"
if [ ! -f "$RESUME_FILE" ]; then
    RESUME_FILE="$SCRIPT_DIR/adapters/0002000_adapters.safetensors"
fi

echo "   Resuming adapter weights from: $RESUME_FILE"

python3 -m mlx_lm lora \
    --model mlx-community/Llama-3.2-1B-Instruct-4bit \
    --data "$SCRIPT_DIR" \
    --train \
    --mask-prompt \
    --config "$SCRIPT_DIR/lora_config.yaml" \
    --num-layers -1 \
    --iters 400 \
    --batch-size 2 \
    --grad-accumulation-steps 2 \
    --grad-checkpoint \
    --learning-rate 2e-5 \
    --val-batches 25 \
    --resume-adapter-file "$RESUME_FILE" \
    --adapter-path "$SCRIPT_DIR/adapters"

echo ""
echo "⚙️ Step 4: Fusing fine-tuned LoRA adapters into standalone Byte model..."
python3 -m mlx_lm.fuse \
    --model mlx-community/Llama-3.2-1B-Instruct-4bit \
    --adapter-path "$SCRIPT_DIR/adapters" \
    --save-path "$SCRIPT_DIR/byte_fused_model"

echo ""
echo "🦙 Step 5: Updating Ollama model registry ('byte-llm')..."
if command -v ollama &> /dev/null; then
    ollama create byte-llm -f "$SCRIPT_DIR/ByteModelfile" || true
fi

echo ""
echo "========================================================"
echo "🎉 FINE-TUNING & MODEL FUSION COMPLETE!"
echo "Model Location: $SCRIPT_DIR/byte_fused_model"
echo "Ollama Model  : byte-llm"
echo "========================================================"
