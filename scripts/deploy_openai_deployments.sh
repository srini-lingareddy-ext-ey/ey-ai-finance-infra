#!/usr/bin/env bash
# Best-effort Azure OpenAI model deployments from a JSON array (same shape as openAI.bicep / openai_default_deployments.json).
# Each object: name, model, version, capacity; optional skuName (default GlobalStandard).
# Exits 0 even when some deployments fail so CI can continue; logs OK / SKIP / FAIL per row.
set -u

RG="${1:?resource group}"
ACCOUNT="${2:?OpenAI account name}"
JSON_FILE="${3:?path to JSON array}"

if [[ ! -f "$JSON_FILE" ]]; then
  echo "::error::JSON file not found: $JSON_FILE"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "::error::jq is required"
  exit 1
fi

N=$(jq 'length' "$JSON_FILE")
if [[ "$N" -eq 0 ]]; then
  echo "OpenAI deployments: 0 entries in $JSON_FILE — nothing to do."
  exit 0
fi

echo "OpenAI best-effort deployments: $N row(s) from $JSON_FILE (account=$ACCOUNT, rg=$RG)"

ok=0
skip=0
fail=0

while IFS= read -r row; do
  name=$(echo "$row" | jq -r '.name')
  model=$(echo "$row" | jq -r '.model')
  version=$(echo "$row" | jq -r '.version')
  capacity=$(echo "$row" | jq -r '.capacity')
  sku=$(echo "$row" | jq -r 'if .skuName == null or .skuName == "" then "GlobalStandard" else .skuName end')

  if [[ -z "$name" || "$name" == "null" ]]; then
    echo "::warning::SKIP: row missing name — $row"
    fail=$((fail + 1))
    continue
  fi

  if az cognitiveservices account deployment show \
    --resource-group "$RG" \
    --name "$ACCOUNT" \
    --deployment-name "$name" \
    -o none 2>/dev/null; then
    echo "SKIP (already exists): $name"
    skip=$((skip + 1))
    continue
  fi

  if out=$(az cognitiveservices account deployment create \
    --resource-group "$RG" \
    --name "$ACCOUNT" \
    --deployment-name "$name" \
    --model-name "$model" \
    --model-version "$version" \
    --model-format OpenAI \
    --sku-name "$sku" \
    --sku-capacity "$capacity" \
    2>&1); then
    echo "OK: $name ($model $version, sku=$sku, capacity=$capacity)"
    ok=$((ok + 1))
  else
    msg=$(echo "$out" | tail -c 4000 | tr '\n' ' ')
    echo "::warning::FAIL: $name ($model $version) — $msg"
    fail=$((fail + 1))
  fi
done < <(jq -c '.[]' "$JSON_FILE")

echo "OpenAI deployment summary: OK=$ok SKIP=$skip FAIL=$fail (account=$ACCOUNT)"
if [[ "$fail" -gt 0 ]]; then
  echo "::notice title=OpenAI partial deploy::$fail deployment(s) failed or were skipped due to errors; core infra succeeded. Fix models/SKU/region/quota in $JSON_FILE or the catalog and re-run this job or create deployments manually."
fi
exit 0
