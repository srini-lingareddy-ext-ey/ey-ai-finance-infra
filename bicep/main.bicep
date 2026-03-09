// POC deployment: creates resource group rg-<pocSlug> and deploys the full POC stack into it.
// Deploy at subscription scope. Pipeline populates Key Vault after deploy.
targetScope = 'subscription'

@description('POC identifier used in resource names (e.g. mypoc). Resource group will be rg-<pocSlug>.')
param pocSlug string

@description('Azure region for the resource group and all resources.')
param location string

@description('App choice: aifinance or aifinance-next.')
@allowed(['aifinance', 'aifinance-next'])
param appChoice string = 'aifinance-next'

@description('Resource group containing the central ACR (creyaifinmain).')
param centralAcrResourceGroupName string = 'rg-eyaifin-acr'

@description('Name of the central Container Registry.')
param centralAcrName string = 'creyaifinmain'

@description('Resource group containing the ACR managed identity (acr-managed-identity with AcrPull).')
param acrManagedIdentityResourceGroupName string = 'rg-eyaifin-acr'

@description('Name of the user-assigned managed identity used by App Services to pull from ACR.')
param acrManagedIdentityName string = 'acr-managed-identity'

@description('Principal ID of the pipeline identity (for Key Vault secret set and ACR push).')
param pipelinePrincipalId string

@secure()
@description('PostgreSQL administrator login password.')
param postgresAdminPassword string

@description('MongoDB cluster administrator username.')
param mongoAdminUsername string = 'main'

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

var centralAcrResourceId = resourceId(subscription().subscriptionId, centralAcrResourceGroupName, 'Microsoft.ContainerRegistry/registries', centralAcrName)
var acrManagedIdentityResourceId = resourceId(subscription().subscriptionId, acrManagedIdentityResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', acrManagedIdentityName)

resource acrManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  scope: resourceGroup(acrManagedIdentityResourceGroupName)
  name: acrManagedIdentityName
}

// --- POC stack (all resources in the new resource group) ---
module pocStack 'poc-stack.bicep' = {
  name: 'pocStack'
  scope: resourceGroup(rg.name)
  params: {
    pocSlug: pocSlug
    location: location
    appChoice: appChoice
    centralAcrResourceId: centralAcrResourceId
    acrManagedIdentityResourceId: acrManagedIdentityResourceId
    acrManagedIdentityPrincipalId: acrManagedIdentity.properties.principalId
    pipelinePrincipalId: pipelinePrincipalId
    postgresAdminPassword: postgresAdminPassword
    mongoAdminUsername: mongoAdminUsername
    pocAppConfigKeyValues: pocAppConfigKeyValues
    openAIDeployments: openAIDeployments
    storageContainerNames: storageContainerNames
    frontendImage: frontendImage
    backendImage: backendImage
  }
}

// --- Outputs (pass through from stack) ---
output resourceGroupName string = rg.name
output keyVaultName string = pocStack.outputs.keyVaultName
output appConfigEndpoint string = pocStack.outputs.appConfigEndpoint
output appConfigStoreName string = pocStack.outputs.appConfigStoreName
output postgresHost string = pocStack.outputs.postgresHost
output postgresDatabaseName string = pocStack.outputs.postgresDatabaseName
output mongoConnectionStringPrefix string = pocStack.outputs.mongoConnectionStringPrefix
output mongoClusterName string = pocStack.outputs.mongoClusterName
output searchEndpoint string = pocStack.outputs.searchEndpoint
output searchName string = pocStack.outputs.searchName
output openaiEndpoint string = pocStack.outputs.openaiEndpoint
output openaiName string = pocStack.outputs.openaiName
output storageAccountName string = pocStack.outputs.storageAccountName
output storageResourceId string = pocStack.outputs.storageResourceId
output frontendAppName string = pocStack.outputs.frontendAppName
output backendAppName string = pocStack.outputs.backendAppName
