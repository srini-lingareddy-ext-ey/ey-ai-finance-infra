#!/usr/bin/env bash
# Build the same storage connection string as Azure portal: Access keys → key1 → Connection string.
# That format uses EndpointSuffix only (no explicit BlobEndpoint=/FileEndpoint=/...), which differs
# from `az storage account show-connection-string`, which often emits expanded endpoints and can
# break apps that expect the portal shape.
set -euo pipefail
RG="${1:?resource group}"
ACCOUNT="${2:?storage account name}"

KEY=$(az storage account keys list --resource-group "$RG" --account-name "$ACCOUNT" --query '[0].value' -o tsv)
BLOB=$(az storage account show --resource-group "$RG" --name "$ACCOUNT" --query 'primaryEndpoints.blob' -o tsv)
if [[ -z "$BLOB" || "$BLOB" == "null" ]]; then
  echo "storage_account_connection_string: missing primaryEndpoints.blob for ${ACCOUNT}" >&2
  exit 1
fi
BLOB="${BLOB#https://}"
BLOB="${BLOB#http://}"
BLOB="${BLOB%/}"
prefix="${ACCOUNT}.blob."
if [[ "$BLOB" != "$prefix"* ]]; then
  echo "storage_account_connection_string: unexpected blob host '${BLOB}' (expected ${prefix}<EndpointSuffix>)" >&2
  exit 1
fi
SUFFIX="${BLOB#"$prefix"}"
printf 'DefaultEndpointsProtocol=https;AccountName=%s;AccountKey=%s;EndpointSuffix=%s' "$ACCOUNT" "$KEY" "$SUFFIX"
