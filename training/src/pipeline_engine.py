"""
Core Versioning & Pipeline Engine for Byte Datasets
"""

import json
import os
import re
import shutil
from datetime import datetime
from .validators import parse_and_validate_record

def recursively_ingest_dir(raw_dir: str) -> list:
    """Recursively ingests all .jsonl and .json dataset files from raw_dir."""
    records = []
    decoder = json.JSONDecoder()

    print(f"🔍 Recursively scanning for raw dataset files in: {raw_dir}")

    for root, _, files in os.walk(raw_dir):
        for fname in files:
            if fname.endswith(".jsonl") or fname.endswith(".json"):
                filepath = os.path.join(root, fname)
                print(f"  📄 Ingesting {filepath}...")
                with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()

                idx = 0
                length = len(content)
                while idx < length:
                    while idx < length and content[idx].isspace():
                        idx += 1
                    if idx >= length:
                        break
                    try:
                        obj, end_idx = decoder.raw_decode(content, idx)
                        idx = end_idx
                        parsed = parse_and_validate_record(obj)
                        if parsed:
                            records.append(parsed)
                    except json.JSONDecodeError:
                        next_newline = content.find("\n", idx)
                        if next_newline == -1:
                            break
                        idx = next_newline + 1

    print(f"📥 Total raw records ingested: {len(records)}")
    return records

def deduplicate_records(records: list) -> list:
    """Deduplicates user-assistant dialogue pairs."""
    seen = set()
    deduped = []
    for r in records:
        u = r["messages"][0]["content"]
        a = r["messages"][1]["content"]
        key = (u, a)
        if key not in seen:
            seen.add(key)
            deduped.append(r)
    print(f"✨ Total unique records after deduplication: {len(deduped)}")
    return deduped

def determine_next_version(versions_dir: str) -> str:
    """Calculates semver tag for next dataset version."""
    os.makedirs(versions_dir, exist_ok=True)
    existing = [d for d in os.listdir(versions_dir) if d.startswith("v") and os.path.isdir(os.path.join(versions_dir, d))]
    if not existing:
        return "v1.0.0"

    version_numbers = []
    for v in existing:
        match = re.match(r"^v(\d+)\.(\d+)\.(\d+)$", v)
        if match:
            version_numbers.append((int(match.group(1)), int(match.group(2)), int(match.group(3))))

    if not version_numbers:
        return "v1.0.0"

    version_numbers.sort()
    latest = version_numbers[-1]
    return f"v{latest[0]}.{latest[1] + 1}.0"

def run_pipeline(specified_version=None, raw_dir=None):
    """Executes full dataset ingestion, validation, versioning snapshot, and root target sync."""
    script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    base_data_dir = os.path.join(script_dir, "training_data")

    if raw_dir is None:
        raw_dir = os.path.join(base_data_dir, "raw")
        os.makedirs(raw_dir, exist_ok=True)

    versions_dir = os.path.join(base_data_dir, "versions")
    version = specified_version or determine_next_version(versions_dir)
    target_ver_dir = os.path.join(versions_dir, version)
    os.makedirs(target_ver_dir, exist_ok=True)

    raw_records = recursively_ingest_dir(raw_dir)

    # Ingest synthetic data from master generator module if present
    try:
        from .generators.master_generator import generate_all_samples
        print("⚡ Ingesting synthetic data from master generator module...")
        synthetic_samples = generate_all_samples()
        for s in synthetic_samples:
            parsed = parse_and_validate_record(s)
            if parsed:
                raw_records.append(parsed)
    except Exception as e:
        print(f"⚠️ Master generator import skipped: {e}")

    unique_records = deduplicate_records(raw_records)
    if not unique_records:
        print("⚠️ No valid records found to build pipeline!")
        return

    cmd_count = sum(1 for r in unique_records if r["_meta"]["has_cmd"])
    dialogue_count = len(unique_records) - cmd_count
    cmd_ratio = round(cmd_count / len(unique_records), 4)

    import random
    random.seed(42)
    random.shuffle(unique_records)

    total = len(unique_records)
    val_size = max(50, int(total * 0.10))
    test_size = max(25, int(total * 0.05))

    test_records = unique_records[:test_size]
    valid_records = unique_records[test_size:test_size + val_size]
    train_records = unique_records[test_size + val_size:]

    def clean_format(recs):
        return [{"messages": r["messages"]} for r in recs]

    ver_train = os.path.join(target_ver_dir, "train.jsonl")
    ver_valid = os.path.join(target_ver_dir, "valid.jsonl")
    ver_test = os.path.join(target_ver_dir, "test.jsonl")
    ver_meta = os.path.join(target_ver_dir, "metadata.json")

    with open(ver_train, "w", encoding="utf-8") as f:
        for r in clean_format(train_records):
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    with open(ver_valid, "w", encoding="utf-8") as f:
        for r in clean_format(valid_records):
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    with open(ver_test, "w", encoding="utf-8") as f:
        for r in clean_format(test_records):
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    metadata = {
        "version": version,
        "created_at": datetime.now().isoformat(),
        "stats": {
            "total_records": total,
            "train_records": len(train_records),
            "valid_records": len(valid_records),
            "test_records": len(test_records),
            "cmd_records": cmd_count,
            "dialogue_records": dialogue_count,
            "cmd_ratio_percent": round(cmd_ratio * 100, 2)
        }
    }

    with open(ver_meta, "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2)

    manifest_file = os.path.join(base_data_dir, "manifest.json")
    manifest = {"versions": []}
    if os.path.exists(manifest_file):
        try:
            with open(manifest_file, "r", encoding="utf-8") as f:
                manifest = json.load(f)
        except Exception:
            manifest = {"versions": []}

    manifest["versions"] = [v for v in manifest.get("versions", []) if v.get("version") != version]
    manifest["versions"].append(metadata)
    manifest["latest_version"] = version

    with open(manifest_file, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    shutil.copyfile(ver_train, os.path.join(script_dir, "train.jsonl"))
    shutil.copyfile(ver_valid, os.path.join(script_dir, "valid.jsonl"))
    shutil.copyfile(ver_test, os.path.join(script_dir, "test.jsonl"))

    print(f"\n🎉 Pipeline Build Complete for {version}!")
    print(f"📊 Dataset Analytics:")
    print(f"   - Total records: {total}")
    print(f"   - Train split: {len(train_records)}")
    print(f"   - Valid split: {len(valid_records)}")
    print(f"   - Test split: {len(test_records)}")
    print(f"   - CMD Ratio: {metadata['stats']['cmd_ratio_percent']}%")
    print(f"💾 Snapshot saved in: {target_ver_dir}")
    print(f"🚀 Synced active targets: training/train.jsonl, training/valid.jsonl, training/test.jsonl")
