#!/usr/bin/env bash
# Build and push a multi-arch (linux/amd64 + linux/arm64) aifinance-next frontend image.
# Run from the ey-ai-finance monorepo root (directory containing apps/ and package.json).
# CI: deploy-poc job build-frontend-image, or manual build-push-image.yml — same tagging/build-arg behavior (not this script).
#
# Usage:
#   ./path/to/build-aifinance-next-frontend-buildx.sh
#   NEXT_PUBLIC_BACKEND_ENDPOINT_BASE=https://... IMAGE=registry/repo:tag ./path/to/...
#
# ACR auth: this script runs `az acr login` when IMAGE is *.azurecr.io (set SKIP_ACR_LOGIN=1 to skip).
# If you still see "failed to fetch oauth token: unauthorized":
#   - az login && az acr login --name <acrName>
#   - Confirm your identity has AcrPush (or Owner) on the registry
#   - docker logout <registry> then az acr login again (stale docker config)

set -euo pipefail

EY_AI_FINANCE_ROOT="${EY_AI_FINANCE_ROOT:-.}"
cd "${EY_AI_FINANCE_ROOT}"

IMAGE="${IMAGE:-creyaifinmain.azurecr.io/aifinance-next-frontend:testauth9-workaround}"
NEXT_PUBLIC_BACKEND_ENDPOINT_BASE="${NEXT_PUBLIC_BACKEND_ENDPOINT_BASE:-https://eyaifinance-backend-testauth9.azurewebsites.net}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILDER_NAME="${BUILDER_NAME:-ey-aifinance-multiarch}"

if [[ "${SKIP_ACR_LOGIN:-0}" != "1" ]]; then
  registry_host="${IMAGE%%/*}"
  if [[ "${registry_host}" == *.azurecr.io ]]; then
    acr_name="${registry_host%.azurecr.io}"
    if command -v az >/dev/null 2>&1; then
      echo "ACR login: az acr login --name ${acr_name}"
      az acr login --name "${acr_name}"
    else
      echo "Install Azure CLI and run: az acr login --name ${acr_name}" >&2
      exit 1
    fi
  fi
fi

if ! docker buildx inspect "${BUILDER_NAME}" >/dev/null 2>&1; then
  docker buildx create --name "${BUILDER_NAME}" --driver docker-container --use
else
  docker buildx use "${BUILDER_NAME}"
fi

docker buildx build \
  -f apps/aifinance-next/frontend/Dockerfile \
  --build-arg "NEXT_PUBLIC_BACKEND_ENDPOINT_BASE=${NEXT_PUBLIC_BACKEND_ENDPOINT_BASE}" \
  --platform "${PLATFORMS}" \
  -t "${IMAGE}" \
  --push \
  .

echo "Pushed multi-arch manifest: ${IMAGE}"
