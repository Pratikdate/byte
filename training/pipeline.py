#!/usr/bin/env python3
"""
Byte Training Pipeline CLI Entry Point.

Usage:
  python3 training/pipeline.py [--version v1.1.0] [--raw-dir training/training_data/raw]
"""

import argparse
import sys
import os

# Ensure package root is in path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from src.pipeline_engine import run_pipeline

def main():
    parser = argparse.ArgumentParser(description="Byte Automated Dataset Versioning Pipeline")
    parser.add_argument("--version", type=str, help="Specific dataset version tag (e.g. v1.1.0)")
    parser.add_argument("--raw-dir", type=str, help="Directory containing raw JSONL datasets")
    args = parser.parse_args()

    run_pipeline(specified_version=args.version, raw_dir=args.raw_dir)

if __name__ == "__main__":
    main()
