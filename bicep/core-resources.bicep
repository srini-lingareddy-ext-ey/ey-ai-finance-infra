// Deployed into an existing resource group. Contains all POC modules.
// Invoked from main.bicep with scope set to the resource group.

@description('Principal (object) ID of the pipeline identity — granted Key Vault Administrator so the workflow can populate secrets.')
param pipelinePrincipalId string

@secure()
param administratorLoginPassword string
param pocSlug string
param location string = 'eastus'
param openAIDeployments array = []
param pocAppConfigKeyValues array = []

// Optional Postgres overrides (match modules/postgres.bicep defaults)
param coordinatorVCores int = 2
param coordinatorStorageQuotaInMb int = 262144
param coordinatorServerEdition string = 'GeneralPurpose'
param enableShardsOnCoordinator bool = true
param nodeServerEdition string = 'MemoryOptimized'
param nodeVCores int = 4
param nodeStorageQuotaInMb int = 524288
param nodeCount int = 0
param enableHa bool = false
param coordinatorEnablePublicIpAccess bool = true
param nodeEnablePublicIpAccess bool = true
param availabilityZone string = '1'
param postgresqlVersion string = '16'
param citusVersion string = '12.1'

module keyVault 'modules/keyVault.bicep' = {
  name: 'keyVault'
  params: {
    pocSlug: pocSlug
    location: location
    pipelinePrincipalId: pipelinePrincipalId
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

module appConfiguration 'modules/appConfiguration.bicep' = {
  name: 'appConfiguration'
  params: {
    pocSlug: pocSlug
    location: location
    pocAppConfigKeyValues: pocAppConfigKeyValues
  }
}

module postgres 'modules/postgres.bicep' = {
  name: 'postgres'
  params: {
    pocSlug: pocSlug
    location: location
    administratorLoginPassword: administratorLoginPassword
    coordinatorVCores: coordinatorVCores
    coordinatorStorageQuotaInMb: coordinatorStorageQuotaInMb
    coordinatorServerEdition: coordinatorServerEdition
    enableShardsOnCoordinator: enableShardsOnCoordinator
    nodeServerEdition: nodeServerEdition
    nodeVCores: nodeVCores
    nodeStorageQuotaInMb: nodeStorageQuotaInMb
    nodeCount: nodeCount
    enableHa: enableHa
    coordinatorEnablePublicIpAccess: coordinatorEnablePublicIpAccess
    nodeEnablePublicIpAccess: nodeEnablePublicIpAccess
    availabilityZone: availabilityZone
    postgresqlVersion: postgresqlVersion
    citusVersion: citusVersion
  }
}

output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output openaiEndpoint string = openAI.outputs.endpoint
output openaiName string = openAI.outputs.openaiName
output appConfigEndpoint string = appConfiguration.outputs.endpoint
output appConfigStoreName string = appConfiguration.outputs.storeName
output postgresHost string = postgres.outputs.host
output postgresDatabaseName string = postgres.outputs.databaseName