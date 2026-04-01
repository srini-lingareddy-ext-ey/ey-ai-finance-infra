// App Services only (resource-group scope). Deploy after poc-stack-core and after Key Vault is populated.
// Use outputs from the core deployment (or main.bicep) for keyVaultName and appConfigEndpoint.
targetScope = 'resourceGroup'

@description('POC identifier used in resource names (e.g. mypoc).')
param pocSlug string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('App Configuration connection endpoint (from core deployment output).')
param appConfigEndpoint string

@description('Key Vault name in this resource group (from core deployment output).')
param keyVaultName string

@description('Frontend container image (e.g. DOCKER|registry.azurecr.io/image:tag).')
param frontendImage string

@description('Backend container image (e.g. DOCKER|registry.azurecr.io/image:tag).')
param backendImage string

@description('Client ID of the user-assigned managed identity acr-managed-identity (used for ACR image pull). Get with: az identity show --ids <acr-managed-identity-resource-id> --query clientId -o tsv')
param acrManagedIdentityClientId string

@description('Microsoft Entra app registration client ID for frontend user sign-in. Empty = omit auth app settings.')
param microsoftIdentityClientId string = ''

@description('Microsoft Entra tenant ID for that app registration.')
param microsoftIdentityTenantId string = ''

@description('Optional client secret for confidential-client flows.')
@secure()
param microsoftIdentityClientSecret string = ''

@description('Frontend public HTTPS base URL (no trailing slash), e.g. https://eyaifinance-mypoc.azurewebsites.net')
param frontendPublicBaseUrl string = ''

@description('Frontend Web App health probe path (default /api/health; requires that route in the frontend app).')
param frontendHealthCheckPath string = '/api/health'

@description('Backend Web App health probe path. Default /health — backend must return HTTP 2xx without Authorization. Empty string omits the probe (manual deployments only).')
param backendHealthCheckPath string = '/health'

@description('Backend-only: Postgres host. Empty = do not set POSTGRES_* app settings.')
param postgresHost string = ''

@description('Backend-only: Postgres database name.')
param postgresDatabaseName string = ''

@description('Backend-only: Postgres user (e.g. citus for Citus).')
param postgresUser string = ''

@description('Backend-only: Postgres port.')
param postgresPort string = '5432'

@description('Backend-only: Postgres password (POSTGRES_PASSWORD app setting). Empty = omit POSTGRES_* block.')
@secure()
param postgresPassword string = ''

@description('Backend-only: Compact JSON array of two strings for OPENAI_ACCOUNT_EUS2, e.g. ["my-openai-account","api-key"]. Empty = omit.')
@secure()
param openAiAccountEus2Json string = ''

@description('Backend-only: MongoDB connection string for MONGO_CONN_STR on the backend Web App. Empty = omit.')
@secure()
param mongoConnStr string = ''

@description('Backend-only: POC Blob Storage connection string for STORAGE_ACCOUNT on the backend Web App. Empty = omit.')
@secure()
param storageConnectionString string = ''

@description('Backend-only: optional OPENAI_ACCOUNT_EUS2_LEGACY app setting. Empty = omit.')
@secure()
param openAiAccountEus2Legacy string = ''

@description('Backend-only: optional OPENAI_ACCOUNT_WUS app setting. Empty = omit.')
@secure()
param openAiAccountWus string = ''

@description('Backend-only: optional OPENAI_ACCOUNT_WUS3 app setting. Empty = omit.')
@secure()
param openAiAccountWus3 string = ''

@description('Backend-only: optional SEARCH_ACCOUNT app setting. Empty = omit.')
@secure()
param searchAccount string = ''

// Central ACR identity (acr-managed-identity in rg-eyaifin-acr) — hardcoded for this subscription.
var acrManagedIdentityResourceIdFinal = '/subscriptions/08d343af-2a3c-4f13-86a5-d9bde4948ae8/resourceGroups/rg-eyaifin-acr/providers/Microsoft.ManagedIdentity/userAssignedIdentities/acr-managed-identity'
var keyVaultUri = 'https://${keyVaultName}${environment().suffixes.keyvaultDns}/'

module appService 'modules/appService.bicep' = {
  name: 'appService'
  params: {
    pocSlug: pocSlug
    location: location
    acrManagedIdentityResourceId: acrManagedIdentityResourceIdFinal
    appConfigEndpoint: appConfigEndpoint
    keyVaultUri: keyVaultUri
    frontendImage: frontendImage
    backendImage: backendImage
    acrManagedIdentityClientId: acrManagedIdentityClientId
    microsoftIdentityClientId: microsoftIdentityClientId
    microsoftIdentityTenantId: microsoftIdentityTenantId
    microsoftIdentityClientSecret: microsoftIdentityClientSecret
    frontendPublicBaseUrl: frontendPublicBaseUrl
    frontendHealthCheckPath: frontendHealthCheckPath
    backendHealthCheckPath: backendHealthCheckPath
    postgresHost: postgresHost
    postgresDatabaseName: postgresDatabaseName
    postgresUser: postgresUser
    postgresPort: postgresPort
    postgresPassword: postgresPassword
    openAiAccountEus2Json: openAiAccountEus2Json
    mongoConnStr: mongoConnStr
    storageConnectionString: storageConnectionString
    openAiAccountEus2Legacy: openAiAccountEus2Legacy
    openAiAccountWus: openAiAccountWus
    openAiAccountWus3: openAiAccountWus3
    searchAccount: searchAccount
  }
}

output frontendAppName string = appService.outputs.frontendAppName
output backendAppName string = appService.outputs.backendAppName
