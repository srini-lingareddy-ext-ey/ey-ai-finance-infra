#!/usr/bin/env python3
"""
Compute updated ipRules for an Azure Cognitive Services (OpenAI) account.

- New IPs not already allowed are added as single host entries (bare IPv4, no CIDR).
- Whenever two or more distinct host entries fall in the same /14, they are replaced
  by that /14 (e.g. two hosts in 136.224.0.0/14 -> one 136.224.0.0/14 rule).
- Existing /14 (or wider) rules are kept; hosts inside them are dropped via minimize.

Reads the account JSON from a file (GET Microsoft.CognitiveServices/accounts/...).
Prints JSON: {"patch": {...}, "changed": true|false, "message": "..."}
"""
from __future__ import annotations

import argparse
import copy
import ipaddress
import json
import sys
from collections import defaultdict
from typing import List, Set


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


def slash14_for_ip(ip: ipaddress.IPv4Address) -> ipaddress.IPv4Network:
    """Smallest /14 network that contains this address (18 host bits)."""
    packed = int(ip) >> 18 << 18
    return ipaddress.IPv4Network((packed, 14))


def ip_allowed(ip: ipaddress.IPv4Address, nets: List[ipaddress.IPv4Network]) -> bool:
    return any(ip in n for n in nets)


def minimize_redundant(nets: List[ipaddress.IPv4Network]) -> List[ipaddress.IPv4Network]:
    out: List[ipaddress.IPv4Network] = []
    for n in sorted(nets, key=lambda x: x.prefixlen):
        out = [o for o in out if not o.subnet_of(n)]
        if any(n.subnet_of(o) for o in out):
            continue
        out.append(n)
    return sorted(out, key=lambda x: (int(x.network_address), x.prefixlen))


def consolidate_hosts_to_slash14(nets: List[ipaddress.IPv4Network]) -> List[ipaddress.IPv4Network]:
    """Replace 2+ distinct /32 in the same /14 with that /14."""
    hosts = [n for n in nets if n.prefixlen == 32]
    others = [n for n in nets if n.prefixlen != 32]
    by_s14: dict[ipaddress.IPv4Network, List[ipaddress.IPv4Network]] = defaultdict(list)
    for n in hosts:
        by_s14[slash14_for_ip(n.network_address)].append(n)

    kept_hosts: List[ipaddress.IPv4Network] = []
    new_14: List[ipaddress.IPv4Network] = []
    for s14, group in by_s14.items():
        addrs: Set[int] = {int(n.network_address) for n in group}
        if len(addrs) >= 2:
            new_14.append(s14)
        else:
            # one logical host; drop duplicate identical /32 if present
            rep = min(group, key=lambda x: int(x.network_address))
            kept_hosts.append(rep)
    return others + new_14 + kept_hosts


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

    nets = minimize_redundant(nets)

    added_bare: List[ipaddress.IPv4Address] = []
    for ip in input_ips:
        if ip_allowed(ip, nets):
            continue
        nets.append(ipaddress.ip_network(f"{ip}/32"))
        added_bare.append(ip)

    nets = minimize_redundant(nets)
    nets_before_consolidate = list(nets)
    nets = consolidate_hosts_to_slash14(nets)
    before14 = {n for n in nets_before_consolidate if n.prefixlen == 14}
    after14 = {n for n in nets if n.prefixlen == 14}
    promoted_14 = sorted(after14 - before14, key=lambda x: int(x.network_address))

    nets = minimize_redundant(nets)
    new_rules = networks_to_ip_rules(nets)

    if ip_rules_equal(original_rules, new_rules):
        buckets = ", ".join(str(slash14_for_ip(ip)) for ip in input_ips)
        return {
            "patch": None,
            "changed": False,
            "message": f"no change (inputs already allowed or subsumed; related /14: {buckets})",
        }

    na_out = copy.deepcopy(na)
    na_out["ipRules"] = new_rules
    patch = {"properties": {"networkAcls": na_out}}
    parts = []
    if added_bare:
        parts.append(f"added host(s): {', '.join(str(ip) for ip in added_bare)}")
    if promoted_14:
        parts.append(f"promoted to /14: {', '.join(str(n) for n in promoted_14)}")
    if not added_bare and not promoted_14:
        parts.append("rule list updated (minimize / dedupe)")
    parts.append(f"inputs: {', '.join(str(ip) for ip in input_ips)}")
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
