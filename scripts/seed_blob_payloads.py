#!/usr/bin/env python3
"""
Seed blob paths from blob_payloads.json into Azure Storage (tenants container).

- Under configs/payloads/*.json: uploads minimal "{}" as application/json (placeholders).
- Under configs/lighthouse/*.yml and configs/chat/*.yml: uploads files from --config-dir
  (default bicep/configs) by matching the manifest filename (e.g. lh.yml -> config-dir/lh.yml).

Tenant keys may contain "{pocSlug}"; replaced by --poc-slug for blob paths.

Uses Azure CLI: az storage blob upload --connection-string (same as deploy-poc workflow).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def collect_uploads(manifest: dict, poc_slug: str) -> list[tuple[str, str, str, str | None]]:
    """
    Return list of (container_name, blob_path, content_type, local_filename_or_none).
    local_filename_or_none is None for empty JSON placeholders.
    """
    out: list[tuple[str, str, str, str | None]] = []
    for container_name, container_content in manifest.items():
        if not isinstance(container_content, dict):
            continue
        for tenant_key, tenant_val in container_content.items():
            if not isinstance(tenant_val, dict):
                continue
            prefix = tenant_key.replace("{pocSlug}", poc_slug)
            configs = tenant_val.get("configs")
            if not isinstance(configs, dict):
                continue

            payloads = configs.get("payloads")
            if isinstance(payloads, dict):
                for folder, files in payloads.items():
                    if not isinstance(files, list):
                        continue
                    for fname in files:
                        if not isinstance(fname, str):
                            continue
                        blob = f"{prefix}/configs/payloads/{folder}/{fname}"
                        out.append((container_name, blob, "application/json", None))

            for segment in ("lighthouse", "chat"):
                files = configs.get(segment)
                if not isinstance(files, list):
                    continue
                for fname in files:
                    if not isinstance(fname, str):
                        continue
                    blob = f"{prefix}/configs/{segment}/{fname}"
                    out.append((container_name, blob, "text/yaml", fname))

    return out


def az_upload(
    connection_string: str,
    container: str,
    blob_path: str,
    file_path: Path,
    content_type: str,
    max_attempts: int = 8,
) -> None:
    for attempt in range(1, max_attempts + 1):
        r = subprocess.run(
            [
                "az",
                "storage",
                "blob",
                "upload",
                "--connection-string",
                connection_string,
                "--container-name",
                container,
                "--name",
                blob_path,
                "--file",
                str(file_path),
                "--content-type",
                content_type,
                "--overwrite",
                "--no-progress",
                "--output",
                "none",
            ],
            capture_output=True,
            text=True,
        )
        if r.returncode == 0:
            return
        if attempt == max_attempts:
            print(r.stderr or r.stdout, file=sys.stderr)
            raise RuntimeError(f"az storage blob upload failed for {container}/{blob_path}")
        time.sleep(min(attempt * 10, 60))


def main() -> int:
    parser = argparse.ArgumentParser(description="Seed blob storage from blob_payloads.json")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--poc-slug", required=True, dest="poc_slug")
    parser.add_argument(
        "--config-dir",
        type=Path,
        default=Path("bicep/configs"),
        help="Directory containing lh.yml, chat.yml, etc. (default: bicep/configs)",
    )
    parser.add_argument(
        "--connection-string",
        required=True,
        dest="connection_string",
        help="Storage account connection string",
    )
    args = parser.parse_args()

    if not args.manifest.exists():
        print(f"Manifest not found: {args.manifest}", file=sys.stderr)
        return 1

    data = json.loads(args.manifest.read_text(encoding="utf-8"))
    uploads = collect_uploads(data, args.poc_slug)
    if not uploads:
        print("No blob paths derived from manifest; nothing to upload.", file=sys.stderr)
        return 0

    config_dir = args.config_dir.resolve()
    empty_json = tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False)
    try:
        empty_json.write("{}")
        empty_json.flush()
        empty_path = Path(empty_json.name)

        for container, blob_path, content_type, source_name in uploads:
            if source_name is None:
                src = empty_path
                ct = content_type
            else:
                src = config_dir / source_name
                if not src.is_file():
                    print(
                        f"Missing config file for blob {blob_path}: expected {src}",
                        file=sys.stderr,
                    )
                    return 1
                ct = content_type

            az_upload(
                args.connection_string,
                container,
                blob_path,
                src,
                ct,
            )
            print(f"Uploaded {container}/{blob_path}")
    finally:
        empty_json.close()
        Path(empty_json.name).unlink(missing_ok=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
