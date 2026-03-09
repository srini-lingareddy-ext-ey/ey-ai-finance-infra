# POC Bicep Stack

Deploys a **resource group** (`rg-<pocSlug>`) and a full per-POC stack inside it: App Configuration, Key Vault, PostgreSQL (Citus), MongoDB (DocumentDB), Azure AI Search, Azure OpenAI, Storage, and two App Services (frontend + backend).

## Prerequisites

- Deploy at **subscription** scope (the template creates the resource group).
- **Central ACR:** Registry **creyaifinmain** in resource group **rg-eyaifin-acr** (or override via parameters).
- **ACR pull:** A user-assigned managed identity **acr-managed-identity** in **rg-eyaifin-acr** has **AcrPull** on the registry. Frontend and backend App Services use **only** this user-assigned identity (no system-assigned identity); the same identity is granted **Key Vault Secrets User** on each POC Key Vault so the apps can read secrets.
- Pipeline identity needs **Key Vault Administrator** (granted by this template) and **AcrPush** on the central ACR for build/push.

## Deploy

The template creates the resource group `rg-<pocSlug>` in the specified location, then deploys all POC resources into it.

```bash
az deployment sub create \
  --location eastus \
  --template-file bicep/main.bicep \
  --parameters bicep/main.parameters.json
```

Use `--location` to set the deployment location (and default region for the resource group). The resource group name is derived from `pocSlug` following the naming convention **rg-<pocSlug>** (e.g. `rg-mypoc`).

## Naming

- **Resource group:** `rg-<pocSlug>` (e.g. `rg-mypoc`).
- **Resources in the RG:** `<resource-name>-<pocSlug>` (e.g. `appconfig-mypoc`, `kv-mypoc`, `pg-mypoc`, `frontend-mypoc`, `backend-mypoc`). Storage account uses `st` + slug (no hyphens, 3–24 chars).

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| pocSlug | Yes | POC identifier (e.g. mypoc). Resource group will be `rg-{pocSlug}`; other resources use `{resource-name}-{pocSlug}`. |
| location | Yes | Azure region for the resource group and all resources. |
| appChoice | No | `aifinance` or `aifinance-next` (default: aifinance-next). |
| centralAcrResourceGroupName | No | Resource group containing the central ACR (default: **rg-eyaifin-acr**). |
| centralAcrName | No | Central Container Registry name (default: **creyaifinmain**). |
| acrManagedIdentityResourceGroupName | No | Resource group containing the ACR managed identity (default: **rg-eyaifin-acr**). |
| acrManagedIdentityName | No | User-assigned managed identity name used by App Services for ACR pull (default: **acr-managed-identity**). Must have AcrPull on the ACR. |
| pipelinePrincipalId | Yes | Object (principal) ID of the pipeline identity (service principal or managed identity). |
| postgresAdminPassword | Yes | PostgreSQL administrator password (secure). |
| mongoAdminUsername | No | MongoDB admin username (default: main). |
| pocAppConfigKeyValues | No | Array of { key, value, contentType? } for App Configuration. |
| openAIDeployments | No | Array of { name, model, version, capacity } for OpenAI deployments. |
| storageContainerNames | No | Blob container names to create. |
| frontendImage | Yes | Container image for frontend (e.g. DOCKER\|creyaifinmain.azurecr.io/image:tag). |
| backendImage | Yes | Container image for backend. |

## Outputs (for pipeline T4, T6, T7)

- **resourceGroupName** — Name of the created resource group (`rg-<pocSlug>`).
- **keyVaultName** — Key Vault name (pipeline writes secrets here).
- **appConfigEndpoint**, **appConfigStoreName** — App Configuration endpoint and name.
- **postgresHost**, **postgresDatabaseName** — PostgreSQL host and database name.
- **mongoConnectionStringPrefix**, **mongoClusterName** — MongoDB; pipeline completes connection string with password.
- **searchEndpoint**, **searchName** — Azure AI Search endpoint and name.
- **openaiEndpoint**, **openaiName** — Azure OpenAI endpoint and name.
- **storageAccountName**, **storageResourceId** — Storage account name and ID.
- **frontendAppName**, **backendAppName** — App Service names.

## Post-deploy

- App Services pull images from **creyaifinmain** using the shared managed identity **acr-managed-identity** (no per-POC AcrPull setup needed).
- Pipeline populates Key Vault secrets from Bicep outputs (T6).

## Optional: deploy stack only (existing resource group)

To deploy only the POC stack into an existing resource group (no RG creation), use the stack template directly:

```bash
az deployment group create \
  --resource-group rg-mypoc \
  --template-file bicep/poc-stack.bicep \
  --parameters bicep/main.parameters.json
```

For `poc-stack.bicep`, `location` defaults to the resource group location if omitted. ACR and managed identity default to **creyaifinmain** and **acr-managed-identity** in **rg-eyaifin-acr**; override with `centralAcrResourceGroupName`, `centralAcrName`, `acrManagedIdentityResourceGroupName`, and `acrManagedIdentityName`, or pass `centralAcrResourceId` and `acrManagedIdentityResourceId` directly.
