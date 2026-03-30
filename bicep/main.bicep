// Creates the resource group (subscription scope) then deploys all modules into it.
// Run: az deployment sub create --location <region> --template-file bicep/main.bicep --parameters <params>
// (Resource group must be created at subscription scope; resources deploy into that RG.)

targetScope = 'subscription'

@secure()
param administratorLoginPassword string
@secure()
param mongoAdministratorLoginPassword string
param pocSlug string
param location string = 'eastus'
param openAIDeployments array = []
param pocAppConfigKeyValues array = []
@description('When false, skip Azure OpenAI (Cognitive Services) account; openaiName/openaiEndpoint outputs are empty.')
param deployAzureOpenAi bool = false

// Optional Postgres overrides (passed through to core-resources)
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

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${pocSlug}-poc'
  location: location
}

module mainResources 'core-resources.bicep' = {
  name: 'mainResources'
  scope: rg
  params: {
    pocSlug: pocSlug
    location: location
    administratorLoginPassword: administratorLoginPassword
    openAIDeployments: openAIDeployments
    pocAppConfigKeyValues: pocAppConfigKeyValues
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
    blobContainerNames: blobContainerNames
    mongoAdministratorLoginPassword: mongoAdministratorLoginPassword
    deployAzureOpenAi: deployAzureOpenAi
  }
}

output resourceGroupName string = rg.name
output resourceGroupLocation string = rg.location
output keyVaultName string = mainResources.outputs.keyVaultName
output keyVaultUri string = mainResources.outputs.keyVaultUri
output openaiEndpoint string = mainResources.outputs.openaiEndpoint
output openaiName string = mainResources.outputs.openaiName
output appConfigEndpoint string = mainResources.outputs.appConfigEndpoint
output appConfigStoreName string = mainResources.outputs.appConfigStoreName
output postgresHost string = mainResources.outputs.postgresHost
output postgresDatabaseName string = mainResources.outputs.postgresDatabaseName
output storageAccountName string = mainResources.outputs.storageAccountName
output mongoHost string = mainResources.outputs.mongoHost
output mongoClusterName string = mainResources.outputs.mongoClusterName
output mongoAdministratorLogin string = mainResources.outputs.mongoAdministratorLogin