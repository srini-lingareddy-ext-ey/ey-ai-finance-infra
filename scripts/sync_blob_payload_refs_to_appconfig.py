#!/usr/bin/env python3
"""
Set Azure App Configuration keys for blob payload paths under the "tenants" container.

Reads bicep/configs/blob_payloads.json, walks tenants -> <root> (e.g. configs) -> <ver> -> payloads -> kpi|pnl -> files.

Each key maps to the blob name (path within the container), with {pocSlug} replaced by --poc-slug.

Key format (version is always included; last segment is the full filename, e.g. all.json):
  payloads:<ver>:<folder>:<filename>
  (e.g. payloads:v1:kpi:all.json, payloads:v1:pnl:residential.json, payloads:v2:kpi:all.json)

Value: <pocSlug>/<root>/<ver>/payloads/<folder>/<filename>  (relative blob name in the tenants container)
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def iter_payload_entries(
    tenants_block: dict,
) -> list[tuple[str, str, str, str]]:
    """Collect (root, ver, folder, filename) for each file under tenants/*/.../payloads."""
    rows: list[tuple[str, str, str, str]] = []
    for root, root_val in tenants_block.items():
        if not isinstance(root_val, dict):
            continue
        for ver, ver_val in root_val.items():
            if not isinstance(ver_val, dict) or "payloads" not in ver_val:
                continue
            payloads = ver_val["payloads"]
            if not isinstance(payloads, dict):
                continue
            for folder, files in payloads.items():
                if not isinstance(files, list):
                    continue
                for fname in files:
                    if not isinstance(fname, str):
                        continue
                    rows.append((root, ver, folder, fname))
    return rows


def build_keys(rows: list[tuple[str, str, str, str]]) -> list[tuple[str, str, str, str, str, str]]:
    """Return list of (key, blob_path_template, root, ver, folder, fname)."""
    out: list[tuple[str, str, str, str, str, str]] = []
    for root, ver, folder, fname in rows:
        key = f"payloads:{ver}:{folder}:{fname}"
        # blob name within container (template with literal {pocSlug} for docs, substituted by caller)
        blob_path = f"{{pocSlug}}/{root}/{ver}/payloads/{folder}/{fname}"
        out.append((key, blob_path, root, ver, folder, fname))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync tenants payload blob paths to App Configuration")
    parser.add_argument("--manifest", type=Path, default=Path("bicep/configs/blob_payloads.json"))
    parser.add_argument("--store", required=True, help="App Configuration store name")
    parser.add_argument("--label", required=True, help="Label (e.g. pocSlug)")
    parser.add_argument("--poc-slug", required=True, dest="poc_slug", help="POC slug (replaces {pocSlug} in blob path values)")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.manifest.exists():
        print(f"Error: manifest not found: {args.manifest}", file=sys.stderr)
        return 1

    data = json.loads(args.manifest.read_text(encoding="utf-8"))
    tenants = data.get("tenants")
    if not isinstance(tenants, dict):
        print("Error: blob_payloads.json must have a 'tenants' object", file=sys.stderr)
        return 1

    rows = iter_payload_entries(tenants)
    if not rows:
        print("No payloads entries under tenants; nothing to sync.", file=sys.stderr)
        return 0

    built = build_keys(rows)
    for item in built:
        key = item[0]
        blob_template = item[1]
        value = blob_template.replace("{pocSlug}", args.poc_slug)

        if args.dry_run:
            print(f"  {key} -> {value}")
            continue
        cmd = [
            "az",
            "appconfig",
            "kv",
            "set",
            "--name",
            args.store,
            "--key",
            key,
            "--value",
            value,
            "--yes",
            "--label",
            args.label,
        ]
        r = subprocess.run(cmd)
        if r.returncode != 0:
            print(f"Failed to set key: {key}", file=sys.stderr)
            return r.returncode
        print(f"Set App Config key: {key}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
