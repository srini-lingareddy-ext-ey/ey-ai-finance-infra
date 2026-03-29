#!/usr/bin/env python3
"""
Read a YAML config file (e.g. backend_configs.yml), flatten nested keys with colons,
and set each key-value in Azure App Configuration via `az appconfig kv set`.
"""
import argparse
import subprocess
import sys
from pathlib import Path


def flatten_to_kv(obj, prefix: str = "") -> list[tuple[str, str]]:
    """
    Recursively flatten a nested dict. Keys become path segments joined by ':'.
    Only leaf string values are emitted.
    """
    out: list[tuple[str, str]] = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            key = f"{prefix}:{k}" if prefix else k
            if isinstance(v, dict):
                out.extend(flatten_to_kv(v, key))
            elif isinstance(v, str):
                out.append((key, v))
            else:
                # numbers, bools, etc. -> stringify
                out.append((key, str(v)))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync YAML key-values to Azure App Configuration")
    parser.add_argument("--config", required=True, help="Path to YAML file (e.g. bicep/configs/backend_configs.yml)")
    parser.add_argument("--store", required=True, help="App Configuration store name")
    parser.add_argument("--label", default=None, help="Optional label for all key-values")
    parser.add_argument("--dry-run", action="store_true", help="Print key-value pairs without calling az")
    args = parser.parse_args()

    config_path = Path(args.config)
    if not config_path.exists():
        print(f"Error: config file not found: {config_path}", file=sys.stderr)
        return 1

    try:
        import yaml
    except ImportError:
        print("Error: PyYAML is required. Run: pip install pyyaml", file=sys.stderr)
        return 1

    with open(config_path, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    if not data:
        print("Error: YAML is empty or invalid", file=sys.stderr)
        return 1

    pairs = flatten_to_kv(data)
    if not pairs:
        print("No key-value pairs found in YAML", file=sys.stderr)
        return 1

    for key, value in pairs:
        if args.dry_run:
            print(f"  {key} -> <value length={len(value)}>")
            continue
        cmd = [
            "az", "appconfig", "kv", "set",
            "--name", args.store,
            "--key", key,
            "--value", value,
            "--yes",
        ]
        if args.label:
            cmd.extend(["--label", args.label])
        r = subprocess.run(cmd)
        if r.returncode != 0:
            print(f"Failed to set App Config key: {key}", file=sys.stderr)
            return r.returncode
        print(f"Set App Config key: {key}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
