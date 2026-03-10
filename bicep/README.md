# POC Bicep Stack

Deploys a **resource group** (`rg-<pocSlug>`) and a per-POC stack in two phases: **core** (App Configuration, Key Vault, PostgreSQL, Azure AI Search, Azure OpenAI, Storage) and **App Services** (frontend + backend). Staggering lets you populate Key Vault before the apps start.

## Prerequisites

- Deploy at **subscription** scope for phase 1 (the template creates the resource group).
- **Central ACR:** Registry **creyaifinmain** in resource group **rg-eyaifin-acr** (resource IDs are hardcoded in the templates for this subscription).
- **ACR pull:** User-assigned managed identity **acr-managed-identity** in **rg-eyaifin-acr** has **AcrPull** on the registry. App Services use this identity (and **Key Vault Secrets User** on each POC Key Vault).
- Pipeline identity needs **Key Vault Administrator** (granted by the core template) and **AcrPush** on the central ACR for build/push.

## Deploy (staggered)

### Phase 1 — Core (subscription scope)

Creates the resource group and all resources **except** App Services. Use the outputs to populate Key Vault in phase 2.

```bash
az deployment sub create \
  --location eastus \
  --template-file bicep/main.bicep \
  --parameters bicep/main.parameters.json
```

Use `--location` to set the deployment location. The resource group name is **rg-<pocSlug>** (e.g. `rg-mypoc`).

### Phase 2 — Populate Key Vault

Using the phase 1 outputs (e.g. `keyVaultName`, `postgresHost`), have your pipeline or script write the required secrets into the POC Key Vault. The pipeline identity has **Key Vault Administrator** on that vault.

### Phase 3 — App Services (resource group scope)

Deploy the frontend and backend App Services into the existing resource group. Pass `keyVaultName` and `appConfigEndpoint` from phase 1 outputs (e.g. into `main-appservices.parameters.json` or via `--parameters`).

```bash
az deployment group create \
  --resource-group rg-mypoc \
  --template-file bicep/poc-stack-appservices.bicep \
  --parameters bicep/main-appservices.parameters.json
```

Override `keyVaultName` and `appConfigEndpoint` with the actual values from phase 1 (e.g. `keyVaultName=@phase1-outputs.json`, or set in the parameters file). Same `pocSlug` and image names as in `main.parameters.json`.

## Naming

- **Resource group:** `rg-<pocSlug>` (e.g. `rg-mypoc`).
- **Resources in the RG:** `<resource-name>-<pocSlug>` (e.g. `appconfig-mypoc`, `kv-mypoc`, `pg-mypoc`, `frontend-mypoc`, `backend-mypoc`). Storage account uses `st` + slug (no hyphens, 3–24 chars).

## Parameters

### main.bicep / poc-stack-core (phase 1)

| Parameter | Required | Description |
|-----------|----------|-------------|
| pocSlug | Yes | POC identifier (e.g. mypoc). Resource group will be `rg-{pocSlug}`; other resources use `{resource-name}-{pocSlug}`. |
| location | Yes | Azure region for the resource group and all resources. |
| appChoice | No | `aifinance` or `aifinance-next` (default: aifinance-next). |
| pipelinePrincipalId | Yes | Object (principal) ID of the pipeline identity (service principal or managed identity). |
| postgresAdminPassword | Yes | PostgreSQL administrator password (secure). |
| pocAppConfigKeyValues | No | Array of { key, value, contentType? } for App Configuration. |
| openAIDeployments | No | Array of { name, model, version, capacity } for OpenAI deployments. |
| storageContainerNames | No | Blob container names to create. |
| frontendImage | Yes* | Container image for frontend; used only when running phase 3 (same file or pipeline). |
| backendImage | Yes* | Container image for backend; used only when running phase 3. |

\* `main.parameters.json` can still include these for use with `main-appservices.parameters.json` or pipeline.

### poc-stack-appservices (phase 3)

| Parameter | Required | Description |
|-----------|----------|-------------|
| pocSlug | Yes | Same POC identifier as phase 1. |
| location | No | Defaults to resource group location. |
| keyVaultName | Yes | Key Vault name in this RG (from phase 1 output **keyVaultName**). |
| appConfigEndpoint | Yes | App Configuration endpoint (from phase 1 output **appConfigEndpoint**). |
| frontendImage | Yes | Container image for frontend (e.g. DOCKER\|creyaifinmain.azurecr.io/image:tag). |
| backendImage | Yes | Container image for backend. |

## Outputs

### Phase 1 (main.bicep / core)

- **resourceGroupName** — Name of the created resource group (`rg-<pocSlug>`).
- **keyVaultName** — Key Vault name (pipeline writes secrets here; pass to phase 3).
- **appConfigEndpoint**, **appConfigStoreName** — App Configuration (pass **appConfigEndpoint** to phase 3).
- **postgresHost**, **postgresDatabaseName** — PostgreSQL.
- **searchEndpoint**, **searchName** — Azure AI Search.
- **openaiEndpoint**, **openaiName** — Azure OpenAI.
- **storageAccountName**, **storageResourceId** — Storage account.

### Phase 3 (poc-stack-appservices)

- **frontendAppName**, **backendAppName** — App Service names.

## Post-deploy

- App Services pull images from **creyaifinmain** using the shared managed identity **acr-managed-identity**.
- Pipeline populates Key Vault in phase 2; App Services read secrets at runtime from Key Vault.

## Optional: core or app-services only (existing resource group)

To deploy only the **core** stack into an existing resource group (no RG creation):

```bash
az deployment group create \
  --resource-group rg-mypoc \
  --template-file bicep/poc-stack-core.bicep \
  --parameters bicep/main.parameters.json
```

Omit `frontendImage` and `backendImage` from the parameters when calling `poc-stack-core.bicep` (they are not used). For **app services only**, use `poc-stack-appservices.bicep` as in phase 3 above, with `keyVaultName` and `appConfigEndpoint` set from the existing core deployment.
