# POC Bicep Stack

Deploys a **resource group** (`rg-<pocSlug>`) and a per-POC stack in two phases: **core** (App Configuration, Key Vault, PostgreSQL, Azure AI Search, Azure OpenAI, Storage) and **App Services** (frontend + backend). Staggering lets you populate Key Vault before the apps start.

## Testing the stack locally

1. **Validate** (no resources created):

   ```bash
   az bicep build --file bicep/main.bicep
   az deployment sub validate \
     --location eastus \
     --template-file bicep/main.bicep \
     --parameters pocSlug=eyaifin-testing administratorLoginPassword='YourSecurePassword1!' \
     --parameters openAIDeployments='[]' pocAppConfigKeyValues='[]'
   ```

2. **What-if** (preview changes against the subscription):

   ```bash
   az deployment sub what-if \
     --location eastus \
     --template-file bicep/main.bicep \
     --parameters pocSlug=eyaifin-testing administratorLoginPassword='YourSecurePassword1!' \
     --parameters openAIDeployments='[]' pocAppConfigKeyValues='[]'
   ```

3. **Deploy** (creates RG and all modules). Use a parameters file or inline:

   ```bash
   # Copy example and set a real password, then:
   cp bicep/main.parameters.example.json bicep/main.parameters.json
   # Edit main.parameters.json: set administratorLoginPassword

   az deployment sub create \
     --location eastus \
     --template-file bicep/main.bicep \
     --parameters bicep/main.parameters.json
   ```

   Or inline (avoid putting the password in shell history):

   ```bash
   az deployment sub create \
     --location eastus \
     --template-file bicep/main.bicep \
     --parameters pocSlug=eyaifin-testing location=eastus \
     --parameters openAIDeployments='[]' pocAppConfigKeyValues='[]' \
     --parameters administratorLoginPassword="$(read -s p; echo $p)"
   ```

   **Note:** Use **subscription** scope (`az deployment sub create`), not `az deployment group create`, because the template creates the resource group first, then deploys into it.

   **Postgres password:** Must be 8–256 characters and contain at least 3 of: lowercase, uppercase, digit, symbol (e.g. `YourSecurePassword1!`). Plain words like `YourSecurePassword` will be rejected.

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

Deploy the frontend and backend App Services into the existing resource group. You can either pass parameters manually or **populate them from the core deployment** using the script.

**Option A — Dynamic (recommended):** Script reads `keyVaultName` and `appConfigEndpoint` from the core deployment in the same resource group. Requires `jq`.

```bash
./scripts/deploy-appservices.sh rg-eyaifin-testing
# Or override pocSlug and images:
./scripts/deploy-appservices.sh rg-eyaifin-testing mypoc 'DOCKER|creyaifinmain.azurecr.io/aifinance-frontend:latest' 'DOCKER|creyaifinmain.azurecr.io/aifinance-backend:latest'
```

If the core stack was deployed with a different deployment name, set `CORE_DEPLOYMENT_NAME` (default is `pocStack`, from main.bicep).

**Option B — Manual:** Pass `keyVaultName` and `appConfigEndpoint` in `main-appservices.parameters.json` or via `--parameters`.

```bash
az deployment group create \
  --resource-group rg-mypoc \
  --template-file bicep/poc-stack-appservices.bicep \
  --parameters bicep/main-appservices.parameters.json
```

Override `keyVaultName` and `appConfigEndpoint` with the actual values from phase 1. Same `pocSlug` and image names as in `main.parameters.json`.

## GitHub Actions workflow

A single workflow automates all phases: **Actions** → **Deploy POC** (manual `workflow_dispatch`).

### Managed identity

- **Name:** id-aifinance-poc-deploy  
- **Resource group:** rg-eyaifin-pipeline  
- **Federated credential:** Configured for this infra repo so the workflow can authenticate with Azure via OIDC (no client secret).  
- Grant the managed identity **Contributor** at subscription scope. The core template grants it **Key Vault Administrator** on each POC Key Vault.

### Required secrets

Store these in **GitHub Secrets** (Settings → Secrets and variables → Actions). You can also store them in a **Key Vault in rg-eyaifin-pipeline**; if the workflow reads from that vault, grant **id-aifinance-poc-deploy** **Key Vault Secrets User** on that vault.

| Secret name | Purpose |
| ----------- | -------- |
| **AZURE_POC_CLIENT_ID** | Managed identity's client (application) ID — used by Azure/login for OIDC. |
| **AZURE_POC_TENANT_ID** | Azure AD tenant ID. |
| **AZURE_POC_SUBSCRIPTION_ID** | Target subscription ID. |
| **AZURE_POC_PIPELINE_PRINCIPAL_ID** | Managed identity's principal (object) ID — passed to Bicep as `pipelinePrincipalId`. |
| **POSTGRES_ADMIN_PASSWORD** | PostgreSQL admin password for the POC — used by Bicep, Key Vault population, and init.sql. |
| **EY_AI_FINANCE_REPO_TOKEN** (optional) | PAT to checkout the private **ey-ai-finance** repo; omit if `GITHUB_TOKEN` has access. |

### Key Vault secret names (phase 2 / workflow step 2)

The workflow writes these secrets into the **POC** Key Vault. The **ey-ai-finance** app must read the same names from Key Vault (or the workflow can be updated to match the app):

- **PostgresConnectionString** — PostgreSQL connection string.  
- **SearchApiKey** — Azure AI Search admin key.  
- **OpenAIApiKey** — Azure OpenAI account key.  
- **StorageConnectionString** — Storage account connection string.

### Init script (phase 2.5 / workflow step 3)

The workflow checks out the **ey-ai-finance** repo (same org as this repo) and runs **db/aifinance/init.sql** against the new Postgres database using the **postgresql-client** and **psql** (not `azure/sql-action`, which targets SQL Server).

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
