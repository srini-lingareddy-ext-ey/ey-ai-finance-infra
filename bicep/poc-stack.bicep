// POC stack (resource-group scope). Invoked by main.bicep with scope to rg-<pocSlug>.
targetScope = 'resourceGroup'

@description('POC identifier used in resource names (e.g. mypoc).')
param pocSlug string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('App choice: aifinance or aifinance-next.')
@allowed(['aifinance', 'aifinance-next'])
param appChoice string = 'aifinance-next'

@description('Resource ID of the central Container Registry in the main resource group. Omit to use centralAcrResourceGroupName + centralAcrName.')
param centralAcrResourceId string = ''

@description('Resource group containing the central ACR (used when centralAcrResourceId is not provided).')
param centralAcrResourceGroupName string = 'rg-eyaifin-acr'

@description('Name of the central Container Registry (used when centralAcrResourceId is not provided).')
param centralAcrName string = 'creyaifinmain'

@description('Resource ID of the user-assigned managed identity for ACR pull. Omit to use acrManagedIdentityResourceGroupName + acrManagedIdentityName.')
param acrManagedIdentityResourceId string = ''

@description('Resource group containing the ACR managed identity (used when acrManagedIdentityResourceId is not provided).')
param acrManagedIdentityResourceGroupName string = 'rg-eyaifin-acr'

@description('Name of the user-assigned managed identity for ACR pull (used when acrManagedIdentityResourceId is not provided).')
param acrManagedIdentityName string = 'acr-managed-identity'

@description('Principal ID of the user-assigned managed identity (for Key Vault Secrets User role on POC Key Vault).')
param acrManagedIdentityPrincipalId string = ''

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

var centralAcrResourceIdFinal = empty(centralAcrResourceId) ? resourceId(subscription().subscriptionId, centralAcrResourceGroupName, 'Microsoft.ContainerRegistry/registries', centralAcrName) : centralAcrResourceId
var acrManagedIdentityResourceIdFinal = empty(acrManagedIdentityResourceId) ? resourceId(subscription().subscriptionId, acrManagedIdentityResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', acrManagedIdentityName) : acrManagedIdentityResourceId

// --- Modules ---
module appConfig 'modules/appConfiguration.bicep' = {
  name: 'appConfig'
  params: {
    pocSlug: pocSlug
    location: location
    pocAppConfigKeyValues: pocAppConfigKeyValues
  }
}

module keyVault 'modules/keyVault.bicep' = {
  name: 'keyVault'
  params: {
    pocSlug: pocSlug
    location: location
  }
}

module postgres 'modules/postgres.bicep' = {
  name: 'postgres'
  params: {
    pocSlug: pocSlug
    location: location
    administratorLoginPassword: postgresAdminPassword
  }
}

module mongo 'modules/mongo.bicep' = {
  name: 'mongo'
  params: {
    pocSlug: pocSlug
    location: location
    administratorUserName: mongoAdminUsername
  }
}

module search 'modules/search.bicep' = {
  name: 'search'
  params: {
    pocSlug: pocSlug
    location: location
  }
}

module openAI 'modules/openAI.bicep' = {
  name: 'openAI'
  params: {
    pocSlug: pocSlug
    location: location
    openAIDeployments: openAIDeployments
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    pocSlug: pocSlug
    location: location
    containerNames: storageContainerNames
  }
}

module appService 'modules/appService.bicep' = {
  name: 'appService'
  params: {
    pocSlug: pocSlug
    location: location
    centralAcrResourceId: centralAcrResourceIdFinal
    acrManagedIdentityResourceId: acrManagedIdentityResourceIdFinal
    appConfigEndpoint: appConfig.outputs.endpoint
    keyVaultResourceId: keyVault.outputs.keyVaultResourceId
    keyVaultUri: keyVault.outputs.keyVaultUri
    frontendImage: frontendImage
    backendImage: backendImage
  }
  dependsOn: [
    appConfig
    keyVault
  ]
}

resource kv 'Microsoft.KeyVault/vaults@2024-12-01-preview' existing = {
  name: keyVault.outputs.keyVaultName
}

// Grant pipeline identity Key Vault Administrator (to populate secrets)
resource kvRolePipeline 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, pipelinePrincipalId, 'Key Vault Administrator')
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74463')
    principalId: pipelinePrincipalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [keyVault]
}

// Grant App Service (user-assigned identity) access to Key Vault — same identity used by frontend and backend for ACR pull
resource roleAssignmentAcrIdentity 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(acrManagedIdentityPrincipalId)) {
  name: guid(kv.id, acrManagedIdentityPrincipalId, 'Key Vault Secrets User')
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: acrManagedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [appService, keyVault]
}

// --- Outputs for pipeline (T4, T6, T7) ---
output keyVaultName string = keyVault.outputs.keyVaultName
output appConfigEndpoint string = appConfig.outputs.endpoint
output appConfigStoreName string = appConfig.outputs.storeName
output postgresHost string = postgres.outputs.host
output postgresDatabaseName string = postgres.outputs.databaseName
output mongoConnectionStringPrefix string = mongo.outputs.connectionStringPrefix
output mongoClusterName string = mongo.outputs.clusterName
output searchEndpoint string = search.outputs.endpoint
output searchName string = search.outputs.searchName
output openaiEndpoint string = openAI.outputs.endpoint
output openaiName string = openAI.outputs.openaiName
output storageAccountName string = storage.outputs.storageAccountName
output storageResourceId string = storage.outputs.storageResourceId
output frontendAppName string = appService.outputs.frontendAppName
output backendAppName string = appService.outputs.backendAppName
