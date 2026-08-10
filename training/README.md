# 🧠 Byte Fine-Tuning & Customization Suite

This directory contains everything you need to fine-tune and customize Byte's dialogue and action LLM (`byte-llm`) locally on your Mac using **Apple MLX** and **Ollama**.

---

## 📁 Directory Structure & Dataset Versioning Pipeline

```text
training/
├── pipeline.py                            # Master automated dataset versioning & validation pipeline
├── generate_high_quality_master_dataset.py# Synthetic dataset generator
├── OPUS_DATASET_GENERATOR_PROMPT.md       # Master prompt for Claude Opus / GPT-4o / Gemini
├── ByteModelfile                          # Ollama model definition with web & macOS commands
├── ByteModelfile.v1_best                  # Preserved best V1 Ollama configuration
├── train_mlx.sh                           # Apple Silicon LoRA fine-tuning script
├── training_data/
│   ├── raw/                               # Drop any raw .jsonl datasets here (e.g. training_1.jsonl)
│   ├── versions/                          # Automated version snapshots (v1.0.0, v1.1.0...)
│   └── manifest.json                      # Version registry tracking metrics & dataset evolution
├── train.jsonl                            # Active training dataset target (synced to latest version)
├── valid.jsonl                            # Active validation dataset target
└── test.jsonl                             # Active test dataset target
```

---

## 🔄 How to Add New Datasets & Build Versions

1. **Drop Raw Datasets into `training/training_data/raw/`**:
   Simply place any raw `.jsonl` or `.json` dataset file (e.g., outputs from Opus/GPT-4o or your own chat logs) into `training/training_data/raw/`.

2. **Run the Automated Dataset Pipeline**:
   ```bash
   python3 training/pipeline.py
   ```
   The pipeline will automatically:
   - Recursively scan `training_data/raw/` for all files.
   - Format, parse, and validate actions, emotions, and command security (`[CMD: open "https://..."]`).
   - Deduplicate repeated pairs.
   - Generate a version snapshot in `training/training_data/versions/vX.Y.Z/` with `metadata.json`.
   - Update `training/training_data/manifest.json`.
   - Sync the active datasets (`train.jsonl`, `valid.jsonl`, `test.jsonl`).

---

## 🚀 Quickstart Training Methods

### Method 1: Instant Ollama Customization (No Retraining Needed)

```bash
ollama create byte-llm -f training/ByteModelfile
```

---

### Method 2: Apple MLX Metal LoRA Fine-Tuning (Full Weight Fine-Tuning)

1. **Run Dataset Pipeline**:
   ```bash
   python3 training/pipeline.py
   ```

2. **Run Apple Silicon Metal GPU Training**:
   ```bash
   chmod +x training/train_mlx.sh
   ./training/train_mlx.sh
   ```

3. **Register Fused Model in Ollama**:
   ```bash
   ollama create byte-llm -f training/ByteModelfile
   ```
