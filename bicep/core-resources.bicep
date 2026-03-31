// Deployed into an existing resource group. Contains all POC modules.
// Invoked from main.bicep with scope set to the resource group.

@secure()
param administratorLoginPassword string
@secure()
param mongoAdministratorLoginPassword string
param pocSlug string
param location string = 'eastus'
param openAIDeployments array = []
param pocAppConfigKeyValues array = []
@description('When false, skip Azure OpenAI account deployment.')
param deployAzureOpenAi bool = false

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
param blobContainerNames array = []

module keyVault 'modules/keyVault.bicep' = {
  name: 'keyVault'
  params: {
    pocSlug: pocSlug
    location: location
  }
}

module openAI 'modules/openAI.bicep' = if (deployAzureOpenAi) {
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

module mongo 'modules/mongo.bicep' = {
  name: 'mongo'
  params: {
    pocSlug: pocSlug
    location: location
    administratorLoginPassword: mongoAdministratorLoginPassword
  }
}

module blobStorage 'modules/blobStorage.bicep' = {
  name: 'blobStorage'
  params: {
    pocSlug: pocSlug
    location: location
    containerNames: blobContainerNames
  }
}

output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output openaiEndpoint string = deployAzureOpenAi ? openAI.outputs.endpoint : ''
output openaiName string = deployAzureOpenAi ? openAI.outputs.openaiName : ''
output appConfigEndpoint string = appConfiguration.outputs.endpoint
output appConfigStoreName string = appConfiguration.outputs.storeName
output postgresHost string = postgres.outputs.host
output postgresDatabaseName string = postgres.outputs.databaseName
output mongoHost string = mongo.outputs.host
output mongoClusterName string = mongo.outputs.clusterName
output mongoAdministratorLogin string = mongo.outputs.administratorLogin
output storageAccountName string = blobStorage.outputs.storageAccountName