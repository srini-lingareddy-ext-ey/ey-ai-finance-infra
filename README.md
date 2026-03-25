# ey-ai-finance-infra

Azure infrastructure for EY AI Finance POC environments. Bicep templates deploy a per-POC stack: resource group, App Configuration, Key Vault, PostgreSQL (Citus), Azure OpenAI, Blob Storage, and frontend/backend App Services. The recommended way to deploy is the GitHub Actions workflow.

---

## How to run the workflow

The **Deploy POC** workflow runs all phases in one go (core deploy → Key Vault population → **blob payload seeding** → App Configuration sync → **Postgres init (init.sql)** → App Services). Run it manually from the GitHub Actions tab. The first job runs **azure/login** twice—before **main.bicep** and immediately after that deployment—so short-lived GitHub OIDC tokens are not exhausted before the rest of the Azure CLI steps.

**One-time run per `pocSlug`:** Intended as a **single bootstrap** for each new POC id. Re-running with the **same** `pocSlug` can conflict with existing resources, re-run `init.sql`, and overwrite blobs and App Config for that environment. Use a **new** `pocSlug` for a new stack; update existing POCs with deliberate, scoped changes instead of repeating the full workflow.

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
   - **pocSlug** (required): POC identifier, e.g. `test-main1`. The resource group will be `rg-<pocSlug>-poc`. Must yield a valid Azure resource group name: **≤ 83 characters** (so total length ≤ 90), **unique in the subscription**, only allowed characters (letters, digits, `_-.()`), **no trailing `.`** on the full name. See **Naming** below.
   - **location** (optional): Azure region; default `eastus`.
   - **appChoice** (optional): App variant for init.sql; chooses `db/<appChoice>/init.sql` from the ey-ai-finance repo (`aifinance-next` or `aifinance`; default `aifinance-next`).
   - **frontendImage** / **backendImage** (optional): Container images for the web apps; defaults point at `creyaifinmain.azurecr.io`.
   - **enableMicrosoftEntraAuthentication** (optional, default **true**): When **false**, App Services deploy **without** Microsoft Entra app settings or Easy Auth (ignores `MICROSOFT_PROVIDER_*` for that run). When **true**, requires **`MICROSOFT_PROVIDER_AUTHENTICATION_APP_ID`** (and tenant); see the [Deploy POC Workflow](https://github.com/ey-org/ey-ai-finance-infra/wiki/05.-Deploy-POC-Workflow) wiki.
5. Click **Run workflow** (green button).

### 3. What the workflow does

**Job `deploy-main-resources`** (single runner; order matches `.github/workflows/deploy-poc.yml`):

GitHub’s OIDC token used by **azure/login** is short-lived. This job calls **azure/login** once before **main.bicep** and again right after that deployment so long ARM runs do not consume the assertion before capture outputs, Key Vault work, blob seeding, and later `az` steps. See the [Deploy POC Workflow](https://github.com/ey-org/ey-ai-finance-infra/wiki/05.-Deploy-POC-Workflow) wiki page for the full step list and troubleshooting.

| Step | What happens                                                                                                                                                                                                                                                                                                 |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1    | Checks out this repo.                                                                                                                                                                                                                                                                                        |
| 2    | **Azure login (OIDC)** using repository secrets.                                                                                                                                                                                                                                                             |
| 3    | Deploys **main.bicep** at subscription scope: creates `rg-<pocSlug>-poc` and core resources (Key Vault, App Configuration, OpenAI, Postgres, Blob Storage).                                                                                                                                                  |
| 4    | **Azure login (OIDC)** — refresh after the ARM deployment.                                                                                                                                                                                                                                                   |
| 5    | Captures deployment outputs (resource group name, Key Vault name, App Config endpoint, Postgres host/DB, OpenAI name, storage account name).                                                                                                                                                                 |
| 6    | Waits 30s for RBAC propagation.                                                                                                                                                                                                                                                                              |
| 7    | Sets Key Vault network default action to **Allow** so the runner can write secrets.                                                                                                                                                                                                                          |
| 8    | Populates the POC Key Vault with **PostgresConnectionString** and **OpenAIApiKey**.                                                                                                                                                                                                                          |
| 9    | Lists secret names in the vault (verify only; no values).                                                                                                                                                                                                                                                    |
| 10   | **Allow Blob Storage access from all networks:** `az storage account update` (public access **Enabled**, default action **Allow**, bypass **AzureServices**), then polls until the account shows **Allow** + **Enabled** (see **Blob storage** below).                                                       |
| 11   | **Create blob payload files:** reads the storage connection string, probes the **data plane** with `az storage container list` (retries with backoff), uploads `{}` JSON blobs from `bicep/configs/blob_payloads.json` (quiet uploads). Total sleep for this step’s waits is **capped at 5 minutes (300s)**. |
| 12   | Syncs App Configuration from `bicep/configs/backend_configs.yml` (label = `pocSlug`).                                                                                                                                                                                                                        |
| 13   | Syncs blob payload path references into App Configuration via `scripts/sync_blob_payload_refs_to_appconfig.py`.                                                                                                                                                                                              |
| 14   | Prints deployment outputs to the log.                                                                                                                                                                                                                                                                        |

**Job `init-postgres`:** checks out **ey-ai-finance** and runs `db/<appChoice>/init.sql`, then inserts a **tenant** row for `pocSlug`.

**Job `deploy-app-services`:** deploys **appservices-stack.bicep** (frontend and backend App Services). Microsoft Entra on the Web Apps runs only when **`enableMicrosoftEntraAuthentication`** is **true** (workflow input).

When it finishes, the POC resource group contains the full stack and the apps pull images from the central ACR using **acr-managed-identity**.

---

## Prerequisites (infrastructure)

- **Central ACR:** Registry **creyaifinmain** in resource group **rg-eyaifin-acr** (resource IDs are hardcoded in the templates).
- **ACR pull:** User-assigned managed identity **acr-managed-identity** in **rg-eyaifin-acr** has **AcrPull** on the registry. App Services use this identity (and **Key Vault Secrets User** on each POC Key Vault).
- **App Configuration:** If you deploy App Configuration (via workflow or Bicep) and get a **Forbidden** error, ensure the identity has **App Configuration Data Owner** on the resource group (or the App Configuration store), and **Contributor** to create the store.
- **Blob storage “blocked by network rules”:** The workflow uses a dedicated step **Allow Blob Storage access from all networks** (`az storage account update`, then polling until **Enabled** + **Allow** are visible—up to ~5 minutes of 15s sleeps). A following step **Create blob payload files** uses a **separate** sleep budget (**300s** total) for data-plane probes and per-blob upload retries; if that budget is exhausted you will see `Sleep budget exhausted (300s). Aborting.` If **Azure Policy** (or manual changes) keeps forcing **Deny** or **public access disabled**, either step can still fail after retries. Fix: policy exception for POC storage accounts, align firewall rules, or use a **self-hosted runner** in an allowed network. **Logs:** expect `Waiting for storage network settings to propagate...`, then `Storage data-plane connectivity is ready.`, `Sleeping … (budget used: …/300s)` during uploads, and a summary line `Seeded payload JSON blobs from bicep/configs/blob_payloads.json (containers: …)`.
- **Redeploy same `pocSlug` / `blobStorage` error:** If deployment fails with **“Blob Delete Retention policy days should be longer than Point In Time Restore policy days”**, Azure requires **blob soft-delete retention to be strictly longer than PITR days** (e.g. both set to 7 is invalid). **`blobStorage.bicep`** turns **PITR off** and sets **blob soft-delete to 14 days** so updates pass. If it still fails, check **Data protection** on the storage account in the portal.

---

## Manual deploy (without the workflow)

If you prefer to run Bicep locally or in your own pipeline:

### Phase 1 — Core (subscription scope)

```bash
az deployment sub create \
  --location eastus \
  --template-file bicep/main.bicep
```

The CLI will prompt for template parameters as needed. You can also pass a parameters JSON file with `--parameters`, for example `--parameters @bicep/parameters/main.parameters.json`, or supply individual values with `--parameters key=value` (see [Parameters (summary)](#parameters-summary) for `main.bicep`).

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

Standalone module for RG only: **bicep/modules/resourceGroup.bicep** (subscription scope, creates only `rg-<pocSlug>-poc`). For per-module docs, stack composition, and the Deploy POC workflow, see the repository **wiki** (e.g. [Quick start: Deploy POC](https://github.com/ey-org/ey-ai-finance-infra/wiki/02.-Quick-Start-%E2%80%90-Deploy-POC), [Bicep Templates](https://github.com/ey-org/ey-ai-finance-infra/wiki/03.-Bicep-Templates), [Stack Bicep Templates](https://github.com/ey-org/ey-ai-finance-infra/wiki/04.-Stack-Bicep-Templates)).

---

## Naming

- **Resource group:** `rg-<pocSlug>-poc` (e.g. `rg-mypoc-poc`). Azure rules for that **full** name:
  - **Unique within the subscription only** (not globally unique).
  - **Length:** 1–90 characters → with `rg-` and `-poc`, use **`pocSlug` ≤ 83** characters.
  - **Allowed in the RG name:** letters, digits, `_`, `-`, `.`, `(`, `)` — avoid spaces, `@`, `/`, and other symbols in `pocSlug` so the composed name stays valid.
  - **Must not end with** a period (`.`); the `-poc` suffix normally satisfies this.
- **Resources in the RG:** `<resource-name>-<pocSlug>-poc` (e.g. `appconfig-mypoc-poc`, `kv-mypoc-poc`, `pg-mypoc-poc`). App Services: **frontend** **`eyaifinance-<pocSlug>`** → **`https://eyaifinance-<pocSlug>.azurewebsites.net`** (user-facing site); **backend** **`eyaifinance-backend-<pocSlug>`** → **`https://eyaifinance-backend-<pocSlug>.azurewebsites.net`** (**not** for end users to open directly — the frontend calls the backend). Storage account: `st<slug>poc<unique>` (globally unique; lowercase, no hyphens). Web app names are **globally** unique; choose `pocSlug` accordingly. Each resource type may impose **additional** constraints beyond the resource group rules.

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
- **storageAccountName** — Blob Storage account name.

### Phase 3 (appservices-stack.bicep)

- **frontendAppName**, **backendAppName** — Web App resource names (`eyaifinance-<pocSlug>` and `eyaifinance-backend-<pocSlug>`).

---

## Optional: core only or app services only

- **Core only (existing RG):** Deploy **core-resources.bicep** at resource group scope with the same parameters as main (no RG creation). Omit frontend/backend images if not running App Services.
- **App services only:** Use **appservices-stack.bicep** as in phase 3, with `keyVaultName` and `appConfigEndpoint` from the existing core deployment.

---

## Post-deploy

- App Services pull images from **creyaifinmain** using the shared managed identity **acr-managed-identity**.
- The workflow (or your pipeline) populates Key Vault in phase 2; App Services read secrets at runtime from Key Vault.
- **Health checks:** Both frontend and backend web apps use probe path **`/api/health`**. Azure sends **`GET /api/health` with no `Authorization` header** — implement that route in each app so it returns HTTP **2xx** without requiring auth (e.g. exempt it from FastAPI JWT middleware). Otherwise the platform may mark instances unhealthy.
