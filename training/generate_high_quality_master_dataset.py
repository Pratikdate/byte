#!/usr/bin/env python3
"""
Master High-Quality Dataset Generator CLI Entry Point for Byte.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src.generators.master_generator import generate_all_samples
from src.validators import parse_and_validate_record

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    raw_output = os.path.join(script_dir, "training_data", "raw", "master_synthetic_dataset.jsonl")
    os.makedirs(os.path.dirname(raw_output), exist_ok=True)

    print("🚀 Generating master high-quality dataset samples...")
    samples = generate_all_samples()

    with open(raw_output, "w", encoding="utf-8") as f:
        for s in samples:
            parsed = parse_and_validate_record(s)
            if parsed:
                f.write(f"{parsed['messages']}\n")

    print(f"✅ Generated {len(samples)} clean records into {raw_output}!")

if __name__ == "__main__":
    main()
