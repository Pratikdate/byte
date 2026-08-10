#!/usr/bin/env python3
"""
Fix and standardize training_1.jsonl format to match Byte's MLX / JSONL specifications.

Converts all entries (both pretty-printed multi-line JSON and {"text": ...} lines)
into standard 1-line JSON objects with {"messages": [{"role": "user", "content": ...}, {"role": "assistant", "content": ...}]}.
"""

import json
import os

def format_training_1():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    target_file = os.path.join(script_dir, "training_data", "training_1.jsonl")

    if not os.path.exists(target_file):
        print(f"❌ File not found: {target_file}")
        return

    print(f"📖 Reading and reformatting {target_file}...")

    # Read entire file content
    with open(target_file, "r", encoding="utf-8") as f:
        content = f.read()

    formatted_records = []

    # Attempt to parse both concatenated multi-line JSON objects and single-line JSON objects
    # 1. First split by lines and try single-line parse, or parse using JSONDecoder
    decoder = json.JSONDecoder()
    idx = 0
    length = len(content)

    while idx < length:
        # Skip whitespace
        while idx < length and content[idx].isspace():
            idx += 1
        if idx >= length:
            break

        try:
            obj, end_idx = decoder.raw_decode(content, idx)
            idx = end_idx

            user_content = ""
            asst_content = ""

            if "messages" in obj:
                user_msg = next((m["content"] for m in obj["messages"] if m["role"] == "user"), "")
                asst_msg = next((m["content"] for m in obj["messages"] if m["role"] == "assistant"), "")
                user_content = user_msg
                asst_content = asst_msg
            elif "text" in obj:
                text = obj["text"]
                if "RESPONSE:" in text:
                    parts = text.split("RESPONSE:", 1)
                    user_content = parts[0].replace("CONTEXT:", "").strip()
                    asst_content = parts[1].strip()
                    if not user_content.startswith("User:"):
                        user_content = f"User: {user_content}"
                    user_content = f"CONTEXT: {user_content}"
                else:
                    continue

            if user_content and asst_content:
                # Normalize user_content prefix
                if not user_content.startswith("CONTEXT:"):
                    user_content = f"CONTEXT: {user_content}"

                record = {
                    "messages": [
                        {"role": "user", "content": user_content},
                        {"role": "assistant", "content": asst_content}
                    ]
                }
                formatted_records.append(record)

        except json.JSONDecodeError as e:
            # If decode fails, advance by line
            next_newline = content.find("\n", idx)
            if next_newline == -1:
                break
            idx = next_newline + 1

    print(f"✅ Successfully parsed and formatted {len(formatted_records)} records!")

    # Write back clean JSONL (1 record per line)
    with open(target_file, "w", encoding="utf-8") as f:
        for rec in formatted_records:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    print(f"💾 Overwritten {target_file} with standardized 1-line JSONL records.")

if __name__ == "__main__":
    format_training_1()
