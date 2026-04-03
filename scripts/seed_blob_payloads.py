#!/usr/bin/env python3
"""
Seed blob paths from blob_payloads.json into Azure Storage (tenants container).

- Under configs/payloads/*.json: uploads minimal "{}" as application/json (placeholders).
- Under configs/frontend/*.json: same "{}" placeholders (blob path only; not synced to App Configuration).
- Under configs/lighthouse/*.yml and configs/chat/*.yml: uploads files from --config-dir
  (default bicep/configs) by matching the manifest filename (e.g. lh.yml -> config-dir/lh.yml).

Every occurrence of the literal "{pocSlug}" is replaced by --poc-slug in:
  the manifest file itself (entire text, before JSON parse), tenant keys, paths/filenames derived
  from the manifest, and the full UTF-8 text of each file read from --config-dir before upload.

Uses Azure CLI: az storage blob upload --connection-string. Deploy POC supplies a portal-style
connection string from scripts/storage_account_connection_string.sh (EndpointSuffix form).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def subst_poc_slug(s: str, poc_slug: str) -> str:
    return s.replace("{pocSlug}", poc_slug)


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
                        blob = f"{prefix}/configs/payloads/{folder_res}/{fname_res}"
                        out.append((container_name, blob, "application/json", None))

            frontend = configs.get("frontend")
            if isinstance(frontend, list):
                for fname in frontend:
                    if not isinstance(fname, str):
                        continue
                    fname_res = subst_poc_slug(fname, poc_slug)
                    blob = f"{prefix}/configs/frontend/{fname_res}"
                    out.append((container_name, blob, "application/json", None))

            for segment in ("lighthouse", "chat"):
                files = configs.get(segment)
                if not isinstance(files, list):
                    continue
                for fname in files:
                    if not isinstance(fname, str):
                        continue
                    fname_res = subst_poc_slug(fname, poc_slug)
                    blob = f"{prefix}/configs/{segment}/{fname_res}"
                    out.append((container_name, blob, "text/yaml", fname_res))

    return out


def upload_config_file(
    connection_string: str,
    container: str,
    blob_path: str,
    source_path: Path,
    content_type: str,
    poc_slug: str,
    max_attempts: int = 8,
) -> None:
    """Read source_path as UTF-8, replace {pocSlug}, upload (temp file only if substitution occurs)."""
    text = source_path.read_text(encoding="utf-8")
    rendered = subst_poc_slug(text, poc_slug)
    if rendered == text:
        az_upload(
            connection_string,
            container,
            blob_path,
            source_path,
            content_type,
            max_attempts=max_attempts,
        )
        return
    suffix = source_path.suffix or ".txt"
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        suffix=suffix,
        delete=False,
    ) as tmp:
        tmp.write(rendered)
        tmp_path = Path(tmp.name)
    try:
        az_upload(
            connection_string,
            container,
            blob_path,
            tmp_path,
            content_type,
            max_attempts=max_attempts,
        )
    finally:
        tmp_path.unlink(missing_ok=True)


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

    manifest_text = subst_poc_slug(
        args.manifest.read_text(encoding="utf-8"),
        args.poc_slug,
    )
    data = json.loads(manifest_text)
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
                upload_config_file(
                    args.connection_string,
                    container,
                    blob_path,
                    src,
                    ct,
                    args.poc_slug,
                )
                print(f"Uploaded {container}/{blob_path}")
                continue

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
