# ey-ai-finance-infra

Azure infrastructure for EY AI Finance POC environments. Bicep templates deploy a per-POC stack: resource group, App Configuration, Key Vault, PostgreSQL (Citus), Azure OpenAI, Blob Storage, and frontend/backend App Services. The recommended way to deploy is the GitHub Actions workflow.

---

## How to run the workflow

The **Deploy POC** workflow runs all phases in one go (core → Key Vault population → App Configuration sync → **Postgres init (init.sql)** → App Services). Run it manually from the GitHub Actions tab.

### 1. Prerequisites

- **Azure:** A user-assigned managed identity **id-aifinance-poc-deploy** in resource group **rg-eyaifin-pipeline**, with a federated credential for this repo (OIDC). Grant this identity **Contributor** at subscription scope.
- **GitHub Secrets:** In the repo go to **Settings → Secrets and variables → Actions** and add:

| Secret                             | Purpose                                                                                                                                                                                                 |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **AZURE_POC_CLIENT_ID**            | Managed identity's client (application) ID for Azure login.                                                                                                                                             |
| **AZURE_POC_TENANT_ID**            | Azure AD tenant ID.                                                                                                                                                                                     |
| **AZURE_POC_SUBSCRIPTION_ID**      | Target subscription ID.                                                                                                                                                                                 |
| **POSTGRES_ADMIN_PASSWORD**        | PostgreSQL admin password (used by Bicep, Key Vault, and the app).                                                                                                                                      |
| **ACR_MANAGED_IDENTITY_CLIENT_ID** | Client ID of **acr-managed-identity** (in rg-eyaifin-acr) for App Services image pull. Get with: `az identity show --resource-group rg-eyaifin-acr --name acr-managed-identity --query clientId -o tsv` |
| **EY_AI_FINANCE_REPO_TOKEN**       | PAT to checkout the **ey-ai-finance** repo; required for the init step (run init.sql on the new Postgres).                                                                                              |

Omit **EY_AI_FINANCE_REPO_TOKEN** only if you skip or replace the init step.

### 2. Trigger the workflow

1. Open the repo on GitHub → **Actions**.
2. Select **Deploy POC** in the left sidebar.
3. Click **Run workflow**.
4. Fill in the inputs:
   - **pocSlug** (required): POC identifier, e.g. `test-main1`. The resource group will be `rg-<pocSlug>-poc`.
   - **location** (optional): Azure region; default `eastus`.
   - **appChoice** (optional): App variant for init.sql; chooses `db/<appChoice>/init.sql` from the ey-ai-finance repo (`aifinance-next` or `aifinance`; default `aifinance-next`).
   - **frontendImage** / **backendImage** (optional): Container images for the web apps; defaults point at `creyaifinmain.azurecr.io`.
5. Click **Run workflow** (green button).

### 3. What the workflow does

| Step | What happens                                                                                                                                                                                                                                                                                                                 |
| ---- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | Deploys **main.bicep** at subscription scope: creates `rg-<pocSlug>-poc` and core resources (Key Vault, App Configuration, OpenAI, Postgres, Blob Storage).                                                                                                                                                                  |
| 2    | Captures deployment outputs (resource group name, Key Vault name, App Config endpoint, Postgres host/DB, OpenAI name, storage account name/ID).                                                                                                                                                                              |
| 3    | Waits 30s for RBAC propagation.                                                                                                                                                                                                                                                                                              |
| 4    | Ensures the storage account allows public blob access (network rules), then seeds empty JSON payload blobs from [`bicep/configs/blob_payloads.json`](bicep/configs/blob_payloads.json) (top-level keys = **blob container** names; second level may be **`configs`**, **`data`**, etc. → versions → segments → `kpi`/`pnl`). |
| 5    | Sets Key Vault default action to Allow.                                                                                                                                                                                                                                                                                      |
| 6    | Populates the POC Key Vault with **PostgresConnectionString** and **OpenAIApiKey**.                                                                                                                                                                                                                                          |
| 7    | Syncs App Configuration from `bicep/configs/backend_configs.yml` into the App Config store.                                                                                                                                                                                                                                  |
| 8    | Syncs **blob payload path** keys to App Config for the **`tenants`** container (keys = `payloads:` + path after `/payloads/` with the last segment sans `.json`, e.g. `payloads:kpi:all` → `<pocSlug>/configs/v1/payloads/kpi/all.json`); see [`scripts/sync_blob_payload_refs_to_appconfig.py`](scripts/sync_blob_payload_refs_to_appconfig.py). |
| 9    | Runs **init.sql** on the new Postgres: checks out the **ey-ai-finance** repo and executes `db/<appChoice>/init.sql` (creates schema/tables).                                                                                                                                                                                 |
| 10   | Deploys **appservices-stack.bicep** into the resource group (frontend and backend App Services).                                                                                                                                                                                                                             |

When it finishes, the POC resource group contains the full stack and the apps pull images from the central ACR using **acr-managed-identity**.

---

## Prerequisites (infrastructure)

- **Central ACR:** Registry **creyaifinmain** in resource group **rg-eyaifin-acr** (resource IDs are hardcoded in the templates).
- **ACR pull:** User-assigned managed identity **acr-managed-identity** in **rg-eyaifin-acr** has **AcrPull** on the registry. App Services use this identity (and **Key Vault Secrets User** on each POC Key Vault).
- **App Configuration:** If you deploy App Configuration (via workflow or Bicep) and get a **Forbidden** error, ensure the identity has **App Configuration Data Owner** on the resource group (or the App Configuration store), and **Contributor** to create the store.
- **Blob storage “blocked by network rules”:** The workflow runs `az storage account update` to set **public network access = Enabled** and **default network action = Allow** before uploading seed blobs (GitHub-hosted runners need this). If **Azure Policy** (or manual changes) forces **Deny** or **public access disabled**, the update or upload can still fail. Fix: add a policy exception for POC storage accounts, use a **self-hosted runner** in a network that is allowed, or seed blobs manually from the Azure portal / Storage Explorer while your IP is allowed.

---

## Manual deploy (without the workflow)

If you prefer to run Bicep locally or in your own pipeline:

### Phase 1 — Core (subscription scope)

```bash
az deployment sub create \
  --location eastus \
  --template-file bicep/main.bicep \
  --parameters bicep/parameters/main.parameters.json
```

Or pass parameters inline (workflow-style, no Key Vault/App Config key-values):

```bash
az deployment sub create \
  --location eastus \
  --template-file bicep/main.bicep \
  --parameters \
    pocSlug=mypoc \
    location=eastus \
    administratorLoginPassword='YOUR_SECURE_PASSWORD' \
    openAIDeployments='[]' \
    pocAppConfigKeyValues='[]' \
    blobContainerNames='[]'
```

Resource group name will be **rg-<pocSlug>-poc** (e.g. `rg-mypoc-poc`).

### Phase 2 — Populate Key Vault

Using the phase 1 outputs, write **PostgresConnectionString** and **OpenAIApiKey** (and any other secrets) into the POC Key Vault. The deployment identity needs **Key Vault Administrator** (or equivalent) on that vault.

### Phase 3 — App Services (resource group scope)

```bash
az deployment group create \
  --resource-group rg-mypoc-poc \
  --template-file bicep/appservices-stack.bicep \
  --parameters bicep/parameters/main-appservices.parameters.json
```

Set `keyVaultName` and `appConfigEndpoint` in the parameters file (or override on the command line) to the values from phase 1 outputs.

---

## Modules and stack templates

- **main.bicep** — Subscription scope: creates the resource group and deploys **core-resources.bicep** (Key Vault, App Configuration, OpenAI, Postgres, Blob Storage). Does not deploy App Services.
- **core-resources.bicep** — Resource group scope: invoked by main.bicep; deploys the five core modules. Not run standalone in the normal flow.
- **appservices-stack.bicep** — Resource group scope: deploys the App Service plan and frontend/backend web apps; call after core is deployed and Key Vault is populated.

Standalone module for RG only: **bicep/modules/resourceGroup.bicep** (subscription scope, creates only `rg-<pocSlug>-poc`). For per-module docs and commands, see the wiki (e.g. **stack_template.md**, **bicep_templates.md**).

---

## Naming

- **Resource group:** `rg-<pocSlug>-poc` (e.g. `rg-mypoc-poc`).
- **Resources in the RG:** `<resource-name>-<pocSlug>-poc` (e.g. `appconfig-mypoc-poc`, `kv-mypoc-poc`, `pg-mypoc-poc`). App Services: `frontend-<pocSlug>`, `backend-<pocSlug>`. Storage account: `st<slug>poc<unique>` (globally unique; lowercase, no hyphens).

---

## Parameters (summary)

### main.bicep (phase 1)

| Parameter                  | Required | Description                                                         |
| -------------------------- | -------- | ------------------------------------------------------------------- |
| pocSlug                    | Yes      | POC identifier. Resource group will be `rg-<pocSlug>-poc`.          |
| location                   | No       | Azure region (default: eastus).                                     |
| administratorLoginPassword | Yes      | PostgreSQL administrator password (secure).                         |
| openAIDeployments          | No       | Array of { name, model, version, capacity } for OpenAI deployments. |
| pocAppConfigKeyValues      | No       | Array of { key, value, contentType? } for App Configuration.        |
| blobContainerNames         | No       | Array of blob container names to create (default: []).              |

Optional Postgres overrides (e.g. coordinatorVCores, nodeCount, postgresqlVersion, citusVersion) are passed through to core-resources; see **main.bicep** and **modules/postgres.bicep** for names.

### appservices-stack.bicep (phase 3)

| Parameter                  | Required | Description                                                             |
| -------------------------- | -------- | ----------------------------------------------------------------------- |
| pocSlug                    | Yes      | Same POC identifier as phase 1.                                         |
| location                   | No       | Defaults to resource group location.                                    |
| keyVaultName               | Yes      | Key Vault name in this RG (from phase 1 output).                        |
| appConfigEndpoint          | Yes      | App Configuration endpoint (from phase 1 output).                       |
| frontendImage              | Yes      | Container image for frontend (e.g. DOCKER\|creyaifinmain.azurecr.io/…). |
| backendImage               | Yes      | Container image for backend.                                            |
| acrManagedIdentityClientId | Yes      | Client ID of **acr-managed-identity** (for ACR image pull).             |

---

## Outputs

### Phase 1 (main.bicep)

- **resourceGroupName**, **resourceGroupLocation** — Created RG.
- **keyVaultName**, **keyVaultUri** — Key Vault (pipeline writes secrets here; pass keyVaultName to phase 3).
- **appConfigEndpoint**, **appConfigStoreName** — App Configuration (pass appConfigEndpoint to phase 3).
- **postgresHost**, **postgresDatabaseName** — PostgreSQL.
- **openaiEndpoint**, **openaiName** — Azure OpenAI.
- **storageAccountName**, **storageResourceId** — Blob Storage account (optional containers via `blobContainerNames`).

### Phase 3 (appservices-stack.bicep)

- **frontendAppName**, **backendAppName** — App Service names.

---

## Optional: core only or app services only

- **Core only (existing RG):** Deploy **core-resources.bicep** at resource group scope with the same parameters as main (no RG creation). Omit frontend/backend images if not running App Services.
- **App services only:** Use **appservices-stack.bicep** as in phase 3, with `keyVaultName` and `appConfigEndpoint` from the existing core deployment.

---

## Post-deploy

- App Services pull images from **creyaifinmain** using the shared managed identity **acr-managed-identity**.
- The workflow (or your pipeline) populates Key Vault in phase 2; App Services read secrets at runtime from Key Vault.
- **Health checks:** Both frontend and backend web apps have App Service health checks enabled with probe path **`/api/health`**. Each app must expose a `GET /api/health` endpoint that returns HTTP 2xx when healthy; otherwise the platform may mark instances unhealthy and avoid routing traffic to them.
