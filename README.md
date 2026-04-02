# ey-ai-finance-infra

Azure infrastructure for EY AI Finance POC environments. Bicep templates deploy a per-POC stack: resource group, App Configuration, Key Vault, PostgreSQL (Citus), Azure OpenAI, Blob Storage, and frontend/backend App Services. The recommended way to deploy is the GitHub Actions workflow.

---

## How to run the workflow

The **Deploy POC** workflow runs all phases in one go (core deploy → Key Vault population → **Mongo** ensure **`eyaifin`** / empty **`chats`** → **blob payload seeding** → App Configuration sync → optional **Azure OpenAI** account + model deployments (when **`createAzureOpenAiResource`** is **true**) → **Postgres init (init.sql)** → App Services). That checkbox defaults **off**; enable it to provision a per-POC OpenAI resource. Run it manually from the GitHub Actions tab. Job **deploy-main-resources** runs **azure/login** before **main.bicep** and again after that deployment (before Key Vault / storage / App Config) so short-lived GitHub OIDC tokens are not exhausted across long Azure CLI segments.

**One-time run per `pocSlug`:** Intended as a **single bootstrap** for each new POC id. Re-running with the **same** `pocSlug` can conflict with existing resources, re-run `init.sql`, and overwrite blobs and App Config for that environment. Use a **new** `pocSlug` for a new stack; update existing POCs with deliberate, scoped changes instead of repeating the full workflow.

**Build frontend image:** **Deploy POC** (default) runs job **`build-frontend-image`** when **`buildFrontendImage`** is **true** (same steps as **Build Push Image**, **inlined** in **`deploy-poc.yml`** so OIDC **`id-token: write`** works — **`workflow_call` cannot grant it to nested jobs here). Pushes **`aifinance-next-frontend:<pocSlug>`** or **`aifinance-frontend:<pocSlug>`** with **`NEXT_PUBLIC_BACKEND_ENDPOINT_BASE=https://eyaifinance-backend-<pocSlug>.azurewebsites.net`**. When that job **succeeds**, **`deploy-app-services`** uses that tag for the frontend (not the **`frontendImage`** input). **`deploy-app-services`** waits for **`build-frontend-image`** (or **skipped**). **AcrPush** required. Standalone: **Actions → Build Push Image\*\* (`workflow_dispatch`).

### 1. Prerequisites

- **Azure:** A user-assigned managed identity **id-aifinance-poc-deploy** in resource group **rg-eyaifin-pipeline**, with a federated credential for this repo (OIDC). Grant this identity **Contributor** at subscription scope.
- **GitHub Secrets:** In the repo go to **Settings → Secrets and variables → Actions** and add:

| Secret                             | Purpose                                                                                                                                                                                                                                |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **AZURE_POC_CLIENT_ID**            | Managed identity's client (application) ID for Azure login.                                                                                                                                                                            |
| **AZURE_POC_TENANT_ID**            | Azure AD tenant ID.                                                                                                                                                                                                                    |
| **AZURE_POC_SUBSCRIPTION_ID**      | Target subscription ID.                                                                                                                                                                                                                |
| **POSTGRES_ADMIN_PASSWORD**        | PostgreSQL admin password: **`main.bicep`**, Key Vault **`PostgresConnectionString`**, **`init-postgres`**, and (Deploy POC) backend app setting **`POSTGRES_PASSWORD`**.                                                              |
| **MONGO_ADMIN_PASSWORD**           | MongoDB (Azure Cosmos DB for MongoDB cluster) admin password: **`main.bicep`**, Key Vault **`MongoConnectionString`**, and (Deploy POC) backend app setting **`MONGO_CONN_STR`**.                                                      |
| **ACR_MANAGED_IDENTITY_CLIENT_ID** | Client ID of **acr-managed-identity** (in rg-eyaifin-acr) for App Services image pull. Get with: `az identity show --resource-group rg-eyaifin-acr --name acr-managed-identity --query clientId -o tsv`                                |
| **EY_AI_FINANCE_REPO_TOKEN**       | PAT to checkout the **ey-ai-finance** repo; required for **`build-frontend-image`** (when enabled) and the **`init-postgres`** step (run init.sql on the new Postgres).                                                                |
| **MICROSOFT_PROVIDER_AUTHENTICATION_APP_ID** | Entra app (client) id for frontend **Easy Auth** (users signing in to the POC). |
| **MICROSOFT_PROVIDER_AUTHENTICATION_SECRET** | Client secret for that app registration (**Easy Auth**). |
| **OPENAI_ACCOUNT_EUS2_LEGACY**     | Required. Passed to the backend Web App as **`OPENAI_ACCOUNT_EUS2_LEGACY`** (format expected by the app, often compact JSON **`["accountName","apiKey"]`**). |
| **OPENAI_ACCOUNT_WUS**             | Required. Backend app setting **`OPENAI_ACCOUNT_WUS`**. |
| **OPENAI_ACCOUNT_WUS3**            | Required. Backend app setting **`OPENAI_ACCOUNT_WUS3`**. |
| **SEARCH_ACCOUNT**                 | Required. Backend app setting **`SEARCH_ACCOUNT`** (e.g. Azure AI Search connection string or JSON). |
| **AZURE_OPENAI_ACCOUNT_NAME**      | Optional. Azure OpenAI **account name** (Cognitive Services resource name). When **createAzureOpenAiResource** is **false**, **Deploy POC** builds backend **`OPENAI_ACCOUNT_EUS2`** from this plus **`AZURE_OPENAI_ACCOUNT_SECRET`**. |
| **AZURE_OPENAI_ACCOUNT_SECRET**    | Optional. Azure OpenAI **API key** (e.g. key1) for the account in **`AZURE_OPENAI_ACCOUNT_NAME`**. Used only when **createAzureOpenAiResource** is **false** (shared/central OpenAI instead of per-POC resource).                      |

Omit **EY_AI_FINANCE_REPO_TOKEN** only if you skip or replace those steps (set **`buildFrontendImage`** false and supply **`frontendImage`** or rely on the **`appChoice`** default **`…-frontend:latest`** on **`creyaifinmain`**).

### 2. Trigger the workflow

1. Open the repo on GitHub → **Actions**.
2. Select **Deploy POC** in the left sidebar.
3. Click **Run workflow**.
4. Fill in the inputs:
   - **pocSlug** (required): POC identifier, e.g. `test-main1`. The resource group will be `rg-<pocSlug>-poc`. Must yield a valid Azure resource group name: **≤ 83 characters** (so total length ≤ 90), **unique in the subscription**, only allowed characters (letters, digits, `_-.()`), **no trailing `.`** on the full name. See **Naming** below.
   - **location** (optional): Azure region; default `eastus`.
   - **appChoice** (optional): App variant for init.sql; chooses `db/<appChoice>/init.sql` from the ey-ai-finance repo (`aifinance-next` or `aifinance`; default `aifinance-next`).
   - **buildFrontendImage** (optional, default **true**): When **true**, build and push from **ey-ai-finance** to **creyaifinmain** using **appChoice** + **pocSlug** (`aifinance-next-frontend:<pocSlug>` or `aifinance-frontend:<pocSlug>`). When that build job **succeeds**, deploy **always** uses that image (**`frontendImage`** is ignored). When the build job is **skipped** or **fails**, the frontend is **`frontendImage`** if non-empty, else **`DOCKER|creyaifinmain.azurecr.io/<appChoice>-frontend:latest`**.
   - **frontendImage** / **backendImage** (optional, default empty): **`DOCKER|registry/image:tag`**. **Backend:** non-empty **`backendImage`** always wins; if empty, **`DOCKER|creyaifinmain.azurecr.io/<appChoice>-backend:latest`**. **Frontend:** only used when the build did not succeed (see above).

- **createAzureOpenAiResource** (optional, default **false**): When **true**, deploy a per-POC Azure OpenAI account, **OpenAIApiKey** in Key Vault, and model deployments. When **false** (default), the OpenAI module is not deployed and no per-POC OpenAI account is created; shared OpenAI via **`AZURE_OPENAI_ACCOUNT_NAME`** + **`AZURE_OPENAI_ACCOUNT_SECRET`** is used for backend **`OPENAI_ACCOUNT_EUS2`** when both secrets are set; otherwise that app setting is omitted. After App Services deploy, blob storage is restricted to Web App outbound IPs, and **deploy-app-services** merges the frontend Web App outbound IPs into the EUS2 OpenAI account firewall (POC account when **true**, else **`AZURE_OPENAI_ACCOUNT_NAME`** when set).
  - **Microsoft Entra** is always applied on deploy: requires **`MICROSOFT_PROVIDER_AUTHENTICATION_APP_ID`**, **`AZURE_POC_TENANT_ID`**, and **`MICROSOFT_PROVIDER_AUTHENTICATION_SECRET`** (Easy Auth). See the [Deploy POC Workflow](https://github.com/ey-org/ey-ai-finance-infra/wiki/07.-Deploy-POC-Workflow) wiki.

5. Click **Run workflow** (green button).

### 3. What the workflow does

**Job `validate-secrets`:** checks required repository secrets (Azure OIDC, Postgres/Mongo passwords, **`EY_AI_FINANCE_REPO_TOKEN`**, **`ACR_MANAGED_IDENTITY_CLIENT_ID`**, **`MICROSOFT_PROVIDER_AUTHENTICATION_APP_ID`**, **`MICROSOFT_PROVIDER_AUTHENTICATION_SECRET`**, **`OPENAI_ACCOUNT_EUS2_LEGACY`**, **`OPENAI_ACCOUNT_WUS`**, **`OPENAI_ACCOUNT_WUS3`**, **`SEARCH_ACCOUNT`**) before any Azure work.

**Job `deploy-main-resources`** (single runner; order matches `.github/workflows/deploy-poc.yml`; runs after **`validate-secrets`**):

GitHub’s OIDC token used by **azure/login** is short-lived. **deploy-main-resources** calls **azure/login** before **main.bicep** and again after that deployment (before Key Vault / storage / App Config). See the [Deploy POC Workflow](https://github.com/ey-org/ey-ai-finance-infra/wiki/07.-Deploy-POC-Workflow) wiki page for the full step list and troubleshooting.

| Step | What happens                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | Checks out this repo.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| 2    | **Azure login (OIDC)** using repository secrets.                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| 3    | Deploys **main.bicep** at subscription scope: creates `rg-<pocSlug>-poc` and core resources (Key Vault, App Configuration, optional **Azure OpenAI** account when **createAzureOpenAiResource** is **true** with `openAIDeployments=[]`, Postgres, Mongo, Blob Storage).                                                                                                                                                                                                                                       |
| 4    | Captures deployment outputs (resource group name, Key Vault name, App Config endpoint, Postgres host/DB, OpenAI name empty when skipped, storage account name, Mongo outputs).                                                                                                                                                                                                                                                                                                                                 |
| 5    | **Azure login (OIDC)** — refresh after the ARM deployment.                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| 6    | Waits 30s for RBAC propagation.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| 7    | Sets Key Vault network default action to **Allow** so the runner can write secrets.                                                                                                                                                                                                                                                                                                                                                                                                                            |
| 8    | Populates the POC Key Vault with **PostgresConnectionString**, **MongoConnectionString**, and **OpenAIApiKey** only when **createAzureOpenAiResource** is **true**.                                                                                                                                                                                                                                                                                                                                            |
| 9    | **Populate MongoDB:** runs **`scripts/seed_mongo_eyaifin.py`** — retries until Mongo is reachable (default **300s**), then ensures database **`eyaifin`** and an empty **`chats`** collection exist (**`create_collection`** when missing). **No** documents are inserted (no **`poc-bootstrap`**). URI matches Key Vault **`MongoConnectionString`** (**`authSource=admin`**). **`continue-on-error: true`** so later steps still run if this step fails.                                                     |
| 10   | **Allow Blob Storage access from all networks:** `az storage account update` (public access **Enabled**, default action **Allow**, bypass **AzureServices**), then polls until the account shows **Allow** + **Enabled** (see **Blob storage** below).                                                                                                                                                                                                                                                         |
| 11   | **Create blob payload files:** probes the storage **data plane** (retries; **300s** sleep budget shared with upload retries), then runs **`scripts/seed_blob_payloads.py`**: **`configs/payloads/*.json`** → minimal **`{}`** as **`application/json`**; **`configs/lighthouse/*.yml`** and **`configs/chat/*.yml`** → file contents from **`bicep/configs/`** (e.g. **`lh.yml`**, **`chat.yml`**). Tenant folder in the manifest uses the **`"{pocSlug}"`** key, substituted with the workflow **`pocSlug`**. |
| 12   | Syncs App Configuration from `bicep/configs/backend_configs.yml` (label = `pocSlug`).                                                                                                                                                                                                                                                                                                                                                                                                                          |
| 13   | Syncs blob path references (**payloads**, **lighthouse**, **chat** from `blob_payloads.json`) into App Configuration via `scripts/sync_blob_payload_refs_to_appconfig.py` (keys = path under `configs/` with `:` separators; values = blob names under the `tenants` container).                                                                                                                                                                                                                               |
| 14   | **OpenAI model deployments (best-effort):** runs only when **createAzureOpenAiResource** is **true** — **`scripts/deploy_openai_deployments.sh`** against **`bicep/configs/openai_default_deployments.json`** — logs OK / SKIP / FAIL per model; job continues even if some fail.                                                                                                                                                                                                                              |
| 15   | Prints deployment outputs to the log.                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

**Job `init-postgres`:** checks out **ey-ai-finance** and runs `db/<appChoice>/init.sql`, then runs **`upsert_preapproved_users.py`** with workflow input **`preapprovedUserEmails`** as **`PREAPPROVED_EXTRA_EMAILS`** (comma-separated; **`is_admin` true**; no built-in default list). If that input is empty, the script logs a GitHub **`::warning::`**, skips the upsert, and the job still succeeds — add admins to **`preapproved_users`** via SQL in PostgreSQL yourself.

**Job `build-frontend-image`:** runs when **`buildFrontendImage`** is **true**; checks out **ey-ai-finance**, builds with **Docker Buildx**, pushes **`creyaifinmain.azurecr.io/<image>:<pocSlug>`** ( **`aifinance-next-frontend`** or **`aifinance-frontend`** per **`appChoice`** ), with **`NEXT_PUBLIC_BACKEND_ENDPOINT_BASE=https://eyaifinance-backend-<pocSlug>.azurewebsites.net`**. Needs **AcrPush** and **`EY_AI_FINANCE_REPO_TOKEN`**.

**Job `deploy-app-services`:** runs after **deploy-main-resources**, **init-postgres**, and **build-frontend-image** (**success** or **skipped**). Resolves **frontend** and **backend** container refs (built frontend wins when the build succeeded; otherwise **`frontendImage`** or **`appChoice`** **`-frontend:latest`**; backend from **`backendImage`** or **`appChoice`** **`-backend:latest`**), then deploys **appservices-stack.bicep**. Passes **`POSTGRES_ADMIN_PASSWORD`**, builds **`OPENAI_ACCOUNT_EUS2`** from the POC OpenAI account when **createAzureOpenAiResource** is **true**, or from **`AZURE_OPENAI_ACCOUNT_NAME`** / **`AZURE_OPENAI_ACCOUNT_SECRET`** when that checkbox is **false** and both secrets are set; passes required secrets **`OPENAI_ACCOUNT_EUS2_LEGACY`**, **`OPENAI_ACCOUNT_WUS`**, **`OPENAI_ACCOUNT_WUS3`**, and **`SEARCH_ACCOUNT`** to the backend app settings of the same names; **`mongoConnStr`** always from POC Mongo; fetches the POC storage **`connectionString`** via **`az storage account show-connection-string`** and passes it securely as **`storageConnectionString`** → backend app setting **`STORAGE_ACCOUNT`**. After deploy, **Restrict Blob Storage to Web App outbound IPs** patches the POC storage account: **`defaultAction Deny`** with allow rules for merged **`possibleOutboundIpAddresses`** (**AzureServices** bypass), then merges frontend outbound IPs into the EUS2 OpenAI account firewall when applicable. **Microsoft Entra** with **Easy Auth** is always configured on the frontend for each deploy.

When it finishes, the POC resource group contains the full stack and the apps pull images from the central ACR using **acr-managed-identity**. The next **deploy-main-resources** run **opens blob storage to Allow** again (Step 10) before re-seeding so GitHub-hosted runners can upload.

---

## Prerequisites (infrastructure)

- **Central ACR:** Registry **creyaifinmain** in resource group **rg-eyaifin-acr** (resource IDs are hardcoded in the templates).
- **ACR pull:** User-assigned managed identity **acr-managed-identity** in **rg-eyaifin-acr** has **AcrPull** on the registry. App Services use this identity. Grant **Key Vault Secrets User** on each POC Key Vault if the apps use **Key Vault references** or runtime access to secrets via **`KEY_VAULT_URI`**; backend **`POSTGRES_PASSWORD`** is set directly on the web app by the workflow and does not require a Key Vault reference for Postgres.
- **App Configuration:** If you deploy App Configuration (via workflow or Bicep) and get a **Forbidden** error, ensure the identity has **App Configuration Data Owner** on the resource group (or the App Configuration store), and **Contributor** to create the store.
- **Blob storage “blocked by network rules”:** **deploy-main-resources** uses **Allow Blob Storage access from all networks** (`az storage account update`, then polling until **Enabled** + **Allow**—up to ~5 minutes). **Create blob payload files** then uses a **300s** sleep budget for data-plane probes and **`seed_blob_payloads.py`** upload retries. After **deploy-app-services**, storage may be locked to **Web App outbound IPs only**; the **next** workflow run opens storage again in Step 10 before uploading. If policy blocks **Allow**, use a policy exception or a runner on an allowed network. **Logs:** `Seeded blobs from …/blob_payloads.json (containers: …)`.
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

To match **Deploy POC**, pass **`openAIDeployments=[]`** (or omit) on **`main.bicep`**, then create models best-effort:

```bash
bash scripts/deploy_openai_deployments.sh rg-<pocSlug>-poc openai-<pocSlug>-poc bicep/configs/openai_default_deployments.json
```

For a single atomic deploy, pass a non-empty **`openAIDeployments`** array in your parameters file instead (all models must succeed or the deployment fails).

### Phase 2 — Populate Key Vault

Using the phase 1 outputs, write **PostgresConnectionString** and **OpenAIApiKey** (and any other secrets) into the POC Key Vault. The deployment identity needs **Key Vault Administrator** (or equivalent) on that vault.

### Phase 3 — App Services (resource group scope)

```bash
az deployment group create \
  --resource-group rg-mypoc-poc \
  --template-file bicep/appservices-stack.bicep \
  --parameters bicep/parameters/main-appservices.parameters.json
```

Set `keyVaultName` and secure **`appConfigConnectionString`** (read-only App Configuration connection string: `Endpoint=...;Id=...;Secret=...`) in the parameters file or override on the command line. Copy the read-only key from the App Configuration store (portal **Access keys**) or run `az appconfig credential list --name <store> --resource-group <rg> -o json` and pick an entry with **`readOnly`: true** — do not commit real secrets. To mirror the workflow’s backend Postgres env vars, pass **`postgresHost`**, **`postgresDatabaseName`**, **`postgresUser`**, **`postgresPort`**, and secure **`postgresPassword`** (use a Key Vault parameters reference or `--parameters postgresPassword=...` from a secure input—do not commit secrets).

---

## Modules and stack templates

- **main.bicep** — Subscription scope: creates the resource group and deploys **core-resources.bicep** (Key Vault, App Configuration, optional OpenAI account via **`deployAzureOpenAi`**, Postgres, MongoDB cluster, Blob Storage). Does not deploy App Services. **Deploy POC** leaves **`openAIDeployments`** empty and, when OpenAI is enabled, uses **`scripts/deploy_openai_deployments.sh`** afterward.
- **core-resources.bicep** — Resource group scope: invoked by main.bicep; deploys the five core modules. Not run standalone in the normal flow.
- **appservices-stack.bicep** — Resource group scope: deploys the App Service plan and frontend/backend web apps; call after core is deployed and Key Vault is populated.

Standalone module for RG only: **bicep/modules/resourceGroup.bicep** (subscription scope, creates only `rg-<pocSlug>-poc`). For per-module docs, stack composition, and the Deploy POC workflow, see the repository **wiki** (e.g. [Prerequisites](https://github.com/ey-org/ey-ai-finance-infra/wiki/02.-Prerequisites), [Quick start: Deploy POC](https://github.com/ey-org/ey-ai-finance-infra/wiki/03.-Quick-Start-%E2%80%90-Deploy-POC), [Bicep Templates](https://github.com/ey-org/ey-ai-finance-infra/wiki/05.-Bicep-Templates), [Stack Bicep Templates](https://github.com/ey-org/ey-ai-finance-infra/wiki/06.-Stack-Bicep-Templates)).

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

| Parameter                  | Required | Description                                                                                                                                                                                                                                                                                                                                  |
| -------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| pocSlug                    | Yes      | POC identifier. Resource group will be `rg-<pocSlug>-poc`.                                                                                                                                                                                                                                                                                   |
| location                   | No       | Azure region (default: eastus).                                                                                                                                                                                                                                                                                                              |
| administratorLoginPassword | Yes      | PostgreSQL administrator password (secure).                                                                                                                                                                                                                                                                                                  |
| openAIDeployments          | No       | Array of { name, model, version, capacity, skuName? } for models created **in the same Bicep deployment** (default **`[]`** for **Deploy POC**). **Deploy POC** applies **`bicep/configs/openai_default_deployments.json`** afterward via **`scripts/deploy_openai_deployments.sh`** (best-effort) when **`deployAzureOpenAi`** is **true**. |
| deployAzureOpenAi          | No       | When **false** (default), skip the Azure OpenAI module; **`openaiName`** / **`openaiEndpoint`** outputs are empty. **Deploy POC** maps workflow input **createAzureOpenAiResource** to this parameter (default **false**).                                                                                                                   |
| pocAppConfigKeyValues      | No       | Array of { key, value, contentType? } for App Configuration.                                                                                                                                                                                                                                                                                 |
| blobContainerNames         | No       | Array of blob container names to create (default: []).                                                                                                                                                                                                                                                                                       |

Optional Postgres overrides (e.g. coordinatorVCores, nodeCount, postgresqlVersion, citusVersion) are passed through to core-resources; see **main.bicep** and **modules/postgres.bicep** for names.

### appservices-stack.bicep (phase 3)

| Parameter                                                      | Required | Description                                                                                                                                                                                                                                                                                   |
| -------------------------------------------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| pocSlug                                                        | Yes      | Same POC identifier as phase 1.                                                                                                                                                                                                                                                               |
| location                                                       | No       | Defaults to resource group location.                                                                                                                                                                                                                                                          |
| keyVaultName                                                   | Yes      | Key Vault name in this RG (from phase 1 output).                                                                                                                                                                                                                                              |
| appConfigConnectionString                                      | Yes      | Secure. App Configuration **read-only** connection string (`Endpoint=...;Id=...;Secret=...`). From portal Access keys, or phase 1 output **`appConfigConnectionString`** (masked in some CLI views), or **`az appconfig credential list`**.                                                                                                                      |
| frontendImage                                                  | Yes\*    | Container image for frontend (e.g. DOCKER\|creyaifinmain.azurecr.io/…). \***Deploy POC** always passes a value (built **`<image>:<pocSlug>`**, or input, or **`appChoice`** **`-frontend:latest`**).                                                                                          |
| backendImage                                                   | Yes\*    | Container image for backend. \***Deploy POC** passes input or **`appChoice`** **`-backend:latest`**.                                                                                                                                                                                          |
| acrManagedIdentityClientId                                     | Yes      | Client ID of **acr-managed-identity** (for ACR image pull).                                                                                                                                                                                                                                   |
| postgresHost, postgresDatabaseName, postgresUser, postgresPort | No       | Backend **`POSTGRES_*`** app settings; omit or leave password empty to skip.                                                                                                                                                                                                                  |
| postgresPassword                                               | No       | Secure. Plain **`POSTGRES_PASSWORD`** on backend when set with host/db/user.                                                                                                                                                                                                                  |
| openAiAccountEus2Json                                          | No       | Secure. Compact JSON array of two **strings** **`["accountName","apiKey"]`** → backend **`OPENAI_ACCOUNT_EUS2`**. **Deploy POC** builds with **`json.dumps`** from the POC OpenAI resource or from **`AZURE_OPENAI_ACCOUNT_NAME`** / **`AZURE_OPENAI_ACCOUNT_SECRET`**. Omit (empty) to skip. |
| mongoConnStr                                                   | No       | Secure. MongoDB connection URI → backend app setting **`MONGO_CONN_STR`**. **Deploy POC** builds this from core outputs + **`MONGO_ADMIN_PASSWORD`**. Omit (empty) to skip.                                                                                                                   |

---

## Outputs

### Phase 1 (main.bicep)

- **resourceGroupName**, **resourceGroupLocation** — Created RG.
- **keyVaultName**, **keyVaultUri** — Key Vault (pipeline writes secrets here; pass keyVaultName to phase 3).
- **appConfigEndpoint**, **appConfigStoreName**, **appConfigConnectionString** (secure) — App Configuration. Pass **`appConfigConnectionString`** (read-only full connection string) to phase 3; **`appConfigEndpoint`** is the HTTPS endpoint only.
- **postgresHost**, **postgresDatabaseName** — PostgreSQL.
- **openaiEndpoint**, **openaiName** — Azure OpenAI.
- **storageAccountName** — Blob Storage account name.
- **mongoHost**, **mongoClusterName**, **mongoAdministratorLogin** — Azure Cosmos DB for MongoDB (vCore) cluster connection details.

### Phase 3 (appservices-stack.bicep)

- **frontendAppName**, **backendAppName** — Web App resource names (`eyaifinance-<pocSlug>` and `eyaifinance-backend-<pocSlug>`).

---

## Optional: core only or app services only

- **Core only (existing RG):** Deploy **core-resources.bicep** at resource group scope with the same parameters as main (no RG creation). Omit frontend/backend images if not running App Services.
- **App services only:** Use **appservices-stack.bicep** as in phase 3, with `keyVaultName` and secure **`appConfigConnectionString`** from the existing core deployment (or from **`az appconfig credential list`**).

---

## Post-deploy

- App Services pull images from **creyaifinmain** using the shared managed identity **acr-managed-identity**.
- The workflow (or your pipeline) populates Key Vault in phase 2; App Services read secrets at runtime from Key Vault.
- **Frontend → backend URL:** **`NEXT_PUBLIC_BACKEND_ENDPOINT_BASE`** is passed as a Docker build-arg when **`build-frontend-image`** runs (and in **Build Push Image**). The frontend Web App no longer injects **`BACKEND_ENDPOINT_BASE`**, **`BACKEND_URL`**, or **`RUNNING_IN_DOCKER`** / **`NEXT_PUBLIC_RUNNING_IN_DOCKER`** at deploy time—ensure **`ey-ai-finance`** resolves the backend via build-time config, App Configuration, or other settings you control.
- **Health checks:** Frontend probe path **`/api/health`**; backend **`/health`**. Azure sends **`GET`** on that path **with no `Authorization` header** — each app must return HTTP **2xx** without requiring auth on the probe route (e.g. exempt it in FastAPI). Otherwise the platform may mark instances unhealthy.
