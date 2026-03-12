// POC core stack (resource-group scope): all resources except App Services.
// Invoked by main.bicep. After deploy, populate Key Vault, then deploy poc-stack-appservices.bicep.
targetScope = 'resourceGroup'

@description('POC identifier used in resource names (e.g. mypoc).')
param pocSlug string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('App choice: aifinance or aifinance-next.')
@allowed(['aifinance', 'aifinance-next'])
param appChoice string = 'aifinance-next'

@description('Principal ID of the user-assigned managed identity (for Key Vault Secrets User role on POC Key Vault).')
param acrManagedIdentityPrincipalId string = ''

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

// Not used by core; allow same parameters file as main.bicep / poc-stack-appservices.
param frontendImage string = ''
param backendImage string = ''

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

module openAI 'modules/openAI.bicep' = {
  name: 'openAI'
  params: {
    pocSlug: pocSlug
    location: location
    openAIDeployments: openAIDeployments
  }
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

// Grant App Service (user-assigned identity) access to Key Vault — used by frontend/backend when poc-stack-appservices is deployed
resource roleAssignmentAcrIdentity 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(acrManagedIdentityPrincipalId)) {
  name: guid(kv.id, acrManagedIdentityPrincipalId, 'Key Vault Secrets User')
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: acrManagedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [keyVault]
}

// --- Outputs for pipeline and for poc-stack-appservices ---
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output appConfigEndpoint string = appConfig.outputs.endpoint
output appConfigStoreName string = appConfig.outputs.storeName
output postgresHost string = postgres.outputs.host
output postgresDatabaseName string = postgres.outputs.databaseName
output openaiEndpoint string = openAI.outputs.endpoint
output openaiName string = openAI.outputs.openaiName
