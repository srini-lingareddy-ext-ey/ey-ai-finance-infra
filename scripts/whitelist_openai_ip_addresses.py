#!/usr/bin/env python3
"""
Compute updated ipRules for an Azure Cognitive Services (OpenAI) account.

- Skips input IPs already contained in an existing CIDR rule.
- Otherwise merges an IP into an existing rule by expanding to the smallest
  supernet that exactly covers the old block plus the new IP (power-of-two aligned).
- If no single supernet fits, appends a /32 (or consolidates adjacent /32s).

Reads the account JSON from a file (GET Microsoft.CognitiveServices/accounts/...).
Prints JSON: {"patch": {...}, "changed": true|false, "message": "..."}
"""
from __future__ import annotations

import argparse
import copy
import ipaddress
import json
import sys
from typing import List, Optional, Tuple


def parse_existing_networks(ip_rules: object) -> List[ipaddress.IPv4Network]:
    networks: List[ipaddress.IPv4Network] = []
    for r in ip_rules or []:
        if not isinstance(r, dict):
            continue
        v = r.get("value")
        if not v or not isinstance(v, str):
            continue
        v = v.strip()
        try:
            if "/" in v:
                networks.append(ipaddress.ip_network(v, strict=False))
            else:
                networks.append(ipaddress.ip_network(f"{v}/32", strict=False))
        except ValueError:
            print(f"warning: skipping invalid existing ipRule value {v!r}", file=sys.stderr)
    return [n for n in networks if n.version == 4]


def parse_input_ips(s: str) -> List[ipaddress.IPv4Address]:
    ips: List[ipaddress.IPv4Address] = []
    for part in s.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            addr = ipaddress.ip_address(part)
        except ValueError as e:
            raise SystemExit(f"invalid IPv4 address: {part!r} ({e})") from e
        if addr.version != 4:
            raise SystemExit(f"only IPv4 supported, got: {part!r}")
        ips.append(addr)
    return ips


def single_cidr_for_inclusive_range(lo: int, hi: int) -> Optional[ipaddress.IPv4Network]:
    span = hi - lo + 1
    if span <= 0:
        return None
    if span & (span - 1):
        return None
    if lo & (span - 1):
        return None
    prefix_len = 32 - (span.bit_length() - 1)
    return ipaddress.IPv4Network((lo, prefix_len))


def merge_two_networks(
    a: ipaddress.IPv4Network, b: ipaddress.IPv4Network
) -> Optional[ipaddress.IPv4Network]:
    lo = min(int(a.network_address), int(b.network_address))
    hi = max(int(a.broadcast_address), int(b.broadcast_address))
    return single_cidr_for_inclusive_range(lo, hi)


def try_merge_ip(nets: List[ipaddress.IPv4Network], ip: ipaddress.IPv4Address) -> Tuple[List[ipaddress.IPv4Network], bool]:
    """Return (new_net_list, structural_change). If ip already covered, no change."""
    if any(ip in n for n in nets):
        return nets, False
    ip_int = int(ip)
    for i, net in enumerate(nets):
        lo = min(int(net.network_address), ip_int)
        hi = max(int(net.broadcast_address), ip_int)
        merged = single_cidr_for_inclusive_range(lo, hi)
        if merged is not None:
            new_nets = nets[:i] + nets[i + 1 :] + [merged]
            return new_nets, True
    return nets + [ipaddress.ip_network(f"{ip}/32")], True


def consolidate_networks(nets: List[ipaddress.IPv4Network]) -> List[ipaddress.IPv4Network]:
    changed = True
    while changed:
        changed = False
        for i in range(len(nets)):
            for j in range(i + 1, len(nets)):
                merged = merge_two_networks(nets[i], nets[j])
                if merged is not None:
                    nets = [n for k, n in enumerate(nets) if k not in (i, j)] + [merged]
                    changed = True
                    break
            if changed:
                break
    return nets


def minimize_redundant(nets: List[ipaddress.IPv4Network]) -> List[ipaddress.IPv4Network]:
    out: List[ipaddress.IPv4Network] = []
    for n in sorted(nets, key=lambda x: x.prefixlen):
        out = [o for o in out if not o.subnet_of(n)]
        if any(n.subnet_of(o) for o in out):
            continue
        out.append(n)
    return sorted(out, key=lambda x: (int(x.network_address), x.prefixlen))


def networks_to_ip_rules(nets: List[ipaddress.IPv4Network]) -> List[dict]:
    rules = []
    for n in nets:
        if n.prefixlen == 32:
            rules.append({"value": str(n.network_address)})
        else:
            rules.append({"value": n.with_prefixlen})
    return rules


def ip_rules_equal(a: List[dict], b: List[dict]) -> bool:
    def key(r):
        if not isinstance(r, dict):
            return ""
        return r.get("value") or ""

    return sorted((key(x) for x in a)) == sorted((key(x) for x in b))


def build_patch(get_json_path: str, input_ips_csv: str) -> dict:
    with open(get_json_path, encoding="utf-8") as f:
        current = json.load(f)
    props = current.get("properties") or {}
    na_raw = props.get("networkAcls")
    created_na = na_raw is None
    if created_na:
        na = {
            "bypass": "AzureServices",
            "defaultAction": "Allow",
            "virtualNetworkRules": [],
            "ipRules": [],
        }
    else:
        na = copy.deepcopy(na_raw)

    original_rules = list(na.get("ipRules") or [])
    nets = parse_existing_networks(original_rules)
    input_ips = parse_input_ips(input_ips_csv)
    if not input_ips:
        return {
            "patch": None,
            "changed": False,
            "message": "no input IP addresses after parsing",
        }

    initial_nets = list(nets)
    already = [str(ip) for ip in input_ips if any(ip in n for n in initial_nets)]
    to_apply = [ip for ip in input_ips if not any(ip in n for n in initial_nets)]

    if not to_apply and not created_na:
        return {
            "patch": None,
            "changed": False,
            "message": "all input IPs already covered by existing rules"
            + (f" ({', '.join(already)})" if already else ""),
        }

    for ip in input_ips:
        if any(ip in n for n in nets):
            continue
        nets, _ = try_merge_ip(nets, ip)

    if to_apply or created_na:
        nets = consolidate_networks(nets)
        nets = minimize_redundant(nets)

    new_rules = networks_to_ip_rules(nets)
    if ip_rules_equal(original_rules, new_rules):
        return {
            "patch": None,
            "changed": False,
            "message": "no net change after merge (unexpected); check account JSON",
        }

    na_out = copy.deepcopy(na)
    na_out["ipRules"] = new_rules
    patch = {"properties": {"networkAcls": na_out}}
    parts = []
    if already:
        parts.append(f"already allowed: {', '.join(already)}")
    if to_apply:
        parts.append(f"merged or added: {', '.join(str(p) for p in to_apply)}")
    if created_na:
        parts.append("initialized networkAcls (defaultAction Allow, bypass AzureServices)")
    return {"patch": patch, "changed": True, "message": "; ".join(parts)}


def main() -> None:
    p = argparse.ArgumentParser(description="Compute OpenAI/Cognitive Services ipRules PATCH body.")
    p.add_argument("--account-json", required=True, help="Path to GET account JSON file")
    p.add_argument("--ips", required=True, help="Comma-separated IPv4 addresses")
    args = p.parse_args()
    try:
        result = build_patch(args.account_json, args.ips)
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)
    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
