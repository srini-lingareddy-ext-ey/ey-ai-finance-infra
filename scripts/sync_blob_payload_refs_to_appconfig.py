#!/usr/bin/env python3
"""
Set Azure App Configuration keys to blob paths (relative to the storage container) from blob_payloads.json.

Manifest shape matches scripts/seed_blob_payloads.py:
  <container> -> <tenantKey> -> configs -> payloads (folder -> file list), lighthouse (file list), chat (file list).

Every "{pocSlug}" in the manifest is replaced by --poc-slug (full-file text substitution before JSON parse).

Key: path under **configs/** only, **/** → **:**, last segment = filename **without** extension.
  configs/payloads/kpi/all.json   -> payloads:kpi:all
  configs/lighthouse/lh.yml       -> lighthouse:lh
  configs/chat/chat.yml           -> chat:chat

Value: blob name inside the container (same layout as seed_blob_payloads): **{tenantPrefix}/configs/...**
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def subst_poc_slug(s: str, poc_slug: str) -> str:
    return s.replace("{pocSlug}", poc_slug)


def app_config_key_from_configs_relative(relative_under_configs: str) -> str:
    """
    relative_under_configs: e.g. payloads/kpi/all.json or lighthouse/lh.yml (no leading configs/).
    """
    parts = relative_under_configs.strip("/").split("/")
    if not parts or parts == [""]:
        raise ValueError(f"empty path under configs: {relative_under_configs!r}")
    parts[-1] = Path(parts[-1]).stem
    return ":".join(parts)


def collect_key_value_pairs(manifest: dict, poc_slug: str) -> list[tuple[str, str]]:
    """Return (app_config_key, blob_path) for each payload / lighthouse / chat file."""
    pairs: list[tuple[str, str]] = []
    for _container_name, container_content in manifest.items():
        if not isinstance(container_content, dict):
            continue
        for tenant_key, tenant_val in container_content.items():
            if not isinstance(tenant_val, dict):
                continue
            prefix = subst_poc_slug(tenant_key, poc_slug)
            configs = tenant_val.get("configs")
            if not isinstance(configs, dict):
                continue

            payloads = configs.get("payloads")
            if isinstance(payloads, dict):
                for folder, files in payloads.items():
                    if not isinstance(files, list):
                        continue
                    folder_res = subst_poc_slug(folder, poc_slug)
                    for fname in files:
                        if not isinstance(fname, str):
                            continue
                        fname_res = subst_poc_slug(fname, poc_slug)
                        rel = f"payloads/{folder_res}/{fname_res}"
                        key = app_config_key_from_configs_relative(rel)
                        blob = f"{prefix}/configs/payloads/{folder_res}/{fname_res}"
                        pairs.append((key, blob))

            for segment in ("lighthouse", "chat"):
                files = configs.get(segment)
                if not isinstance(files, list):
                    continue
                for fname in files:
                    if not isinstance(fname, str):
                        continue
                    fname_res = subst_poc_slug(fname, poc_slug)
                    rel = f"{segment}/{fname_res}"
                    key = app_config_key_from_configs_relative(rel)
                    blob = f"{prefix}/configs/{segment}/{fname_res}"
                    pairs.append((key, blob))

    return pairs


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync tenants payload blob paths to App Configuration")
    parser.add_argument("--manifest", type=Path, default=Path("bicep/configs/blob_payloads.json"))
    parser.add_argument("--store", required=True, help="App Configuration store name")
    parser.add_argument("--label", required=True, help="App Configuration label (Deploy POC uses tenant-1)")
    parser.add_argument(
        "--poc-slug",
        required=True,
        dest="poc_slug",
        help="POC slug (replaces {pocSlug} in manifest and paths)",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.manifest.exists():
        print(f"Error: manifest not found: {args.manifest}", file=sys.stderr)
        return 1

    manifest_text = subst_poc_slug(
        args.manifest.read_text(encoding="utf-8"),
        args.poc_slug,
    )
    data = json.loads(manifest_text)

    pairs = collect_key_value_pairs(data, args.poc_slug)
    if not pairs:
        print("No payloads/lighthouse/chat entries in manifest; nothing to sync.", file=sys.stderr)
        return 0

    for key, value in pairs:
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
