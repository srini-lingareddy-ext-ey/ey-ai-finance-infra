// POC deployment: creates resource group rg-<pocSlug> and deploys the core POC stack (no App Services).
// Deploy at subscription scope. After deploy: populate Key Vault, then deploy poc-stack-appservices.bicep for App Services.
targetScope = 'subscription'

@description('POC identifier used in resource names (e.g. mypoc). Resource group will be rg-<pocSlug>.')
param pocSlug string

@description('Azure region for the resource group and all resources.')
param location string

@description('App choice: aifinance or aifinance-next.')
@allowed(['aifinance', 'aifinance-next'])
param appChoice string = 'aifinance-next'

@description('Principal ID of the pipeline identity (for Key Vault secret set and ACR push).')
param pipelinePrincipalId string

@secure()
@description('PostgreSQL administrator login password.')
param postgresAdminPassword string

@description('Optional key-values for App Configuration (POC-specific).')
param pocAppConfigKeyValues array = []

@description('OpenAI deployments to create (name, model, version, capacity).')
param openAIDeployments array = [
  { name: 'gpt-4o', model: 'gpt-4o', version: '2024-11-20', capacity: 5000 }
  , { name: 'gpt-4o-mini', model: 'gpt-4o-mini', version: '2024-07-18', capacity: 10000 }
]

@description('Storage account blob container names to create.')
param storageContainerNames array = [
  'chat-completions'
  'chats'
  'clients'
  'responses'
]

@description('Frontend container image (e.g. DOCKER|registry.azurecr.io/image:tag).')
param frontendImage string

@description('Backend container image (e.g. DOCKER|registry.azurecr.io/image:tag).')
param backendImage string

// --- Resource group (naming: rg-<pocSlug>) ---
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${pocSlug}'
  location: location
}

// Central ACR and identity (creyaifinmain, acr-managed-identity in rg-eyaifin-acr) — hardcoded for this subscription.
var acrManagedIdentityResourceId = '/subscriptions/08d343af-2a3c-4f13-86a5-d9bde4948ae8/resourceGroups/rg-eyaifin-acr/providers/Microsoft.ManagedIdentity/userAssignedIdentities/acr-managed-identity'

resource acrManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  id: acrManagedIdentityResourceId
}

// --- POC core stack (no App Services; deploy app services after populating Key Vault) ---
module pocStack 'poc-stack-core.bicep' = {
  name: 'pocStack'
  scope: resourceGroup(rg.name)
  params: {
    pocSlug: pocSlug
    location: location
    appChoice: appChoice
    acrManagedIdentityPrincipalId: acrManagedIdentity.properties.principalId
    pipelinePrincipalId: pipelinePrincipalId
    postgresAdminPassword: postgresAdminPassword
    pocAppConfigKeyValues: pocAppConfigKeyValues
    openAIDeployments: openAIDeployments
    storageContainerNames: storageContainerNames
  }
}

// --- Outputs (pass through from core stack; use for Key Vault population, then poc-stack-appservices) ---
output resourceGroupName string = rg.name
output keyVaultName string = pocStack.outputs.keyVaultName
output appConfigEndpoint string = pocStack.outputs.appConfigEndpoint
output appConfigStoreName string = pocStack.outputs.appConfigStoreName
output postgresHost string = pocStack.outputs.postgresHost
output postgresDatabaseName string = pocStack.outputs.postgresDatabaseName
output searchEndpoint string = pocStack.outputs.searchEndpoint
output searchName string = pocStack.outputs.searchName
output openaiEndpoint string = pocStack.outputs.openaiEndpoint
output openaiName string = pocStack.outputs.openaiName
output storageAccountName string = pocStack.outputs.storageAccountName
output storageResourceId string = pocStack.outputs.storageResourceId
