#!/usr/bin/env bash
# Primary (read-write key 1) connection string — portal: Access keys → Primary.
# Use this in CI: ARM does not return @secure() output values from az deployment sub show.
set -euo pipefail
STORE="${1:?App Configuration store name}"
RG="${2:?resource group}"

RAW=$(az appconfig credential list --name "$STORE" --resource-group "$RG" -o json)
ARR=$(echo "$RAW" | jq -c 'if type == "array" then . elif .value then .value else [] end')
CRED=$(echo "$ARR" | jq -c --arg n 'Primary' 'map(select(.name == $n)) | .[0]')
if [[ "$CRED" == "null" || -z "$CRED" ]]; then
  echo "app_configuration_connection_string: no credential named 'Primary' for ${STORE}" >&2
  exit 1
fi

CONN=$(echo "$CRED" | jq -r '.connectionString // empty')
if [[ -z "$CONN" || "$CONN" == "null" ]]; then
  ENDPOINT=$(az appconfig show --name "$STORE" --resource-group "$RG" --query endpoint -o tsv)
  ID=$(echo "$CRED" | jq -r '.id // empty')
  SECRET=$(echo "$CRED" | jq -r '.value // empty')
  if [[ -n "$ENDPOINT" && -n "$ID" && -n "$SECRET" ]]; then
    CONN="Endpoint=${ENDPOINT};Id=${ID};Secret=${SECRET}"
  fi
fi

if [[ -z "$CONN" || "$CONN" == "null" ]]; then
  echo "app_configuration_connection_string: could not resolve connection string for ${STORE}" >&2
  exit 1
fi
printf '%s' "$CONN"
