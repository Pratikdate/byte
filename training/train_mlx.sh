#!/bin/bash
# High-Accuracy Masked LoRA Fine-Tuning on Apple Silicon Metal GPU with MLX

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
LOG_FILE="$SCRIPT_DIR/train.log"

# Tee stdout and stderr to train.log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "📝 Output logging to: $LOG_FILE"
echo "🚀 Step 1: Formatting prompt/completion dataset & 3-way split..."
python3 "$SCRIPT_DIR/prepare_compact_train.py"

echo "📦 Step 2: Verifying Python dependencies..."
python3 -m pip install -q mlx-lm mlx huggingface_hub

echo "🧠 Step 3: Starting Loss-Masked Metal GPU Fine-Tuning (Rank 32, Masked Prompt)..."
# Using --mask-prompt ensures loss is ONLY computed over completion tokens!
# Using --config lora_config.yaml (rank 32, alpha 64, all projection layers)
# Using --num-layers -1 (train all layers)
python3 -m mlx_lm.lora \
    --model mlx-community/Llama-3.2-3B-Instruct-4bit \
    --data "$SCRIPT_DIR" \
    --train \
    --mask-prompt \
    --config "$SCRIPT_DIR/lora_config.yaml" \
    --num-layers -1 \
    --iters 3000 \
    --batch-size 2 \
    --grad-accumulation-steps 2 \
    --grad-checkpoint \
    --learning-rate 2e-5 \
    --val-batches 25 \
    --resume-adapter-file "$SCRIPT_DIR/adapters/0001000_adapters.safetensors" \
    --adapter-path "$SCRIPT_DIR/adapters"

echo "⚙️ Step 4: Fusing LoRA adapters into compact standalone model..."
python3 -m mlx_lm.fuse \
    --model mlx-community/Llama-3.2-3B-Instruct-4bit \
    --adapter-path "$SCRIPT_DIR/adapters" \
    --save-path "$SCRIPT_DIR/byte_fused_model"

echo "🦙 Step 5: Registering trained model in Ollama..."
if command -v ollama &> /dev/null; then
    ollama create byte-llm -f "$SCRIPT_DIR/ByteModelfile" || true
fi

echo "========================================================"
echo "🎉 TRAINING & MODEL FUSION COMPLETE!"
echo "Model Location: $SCRIPT_DIR/byte_fused_model"
echo "Ollama Model  : byte-llm"
echo "========================================================"

# ── Optional Step 6: Compress model to 3-bit (or 2-bit) ──────────────
# Uncomment the lines below to automatically compress after training.
# Default is 3-bit (~500 MB, good quality preservation).
# Change --bits 3 to --bits 2 for maximum compression (~350 MB).
# Use --bits 3 --bits 2 to generate both and compare.
#
# echo "🗜️  Step 6: Compressing fused model to 3-bit..."
# python3 "$SCRIPT_DIR/compress_model.py" --bits 3 --register-ollama
# echo "✅ Compressed model saved to: $SCRIPT_DIR/byte_compressed_3bit"
