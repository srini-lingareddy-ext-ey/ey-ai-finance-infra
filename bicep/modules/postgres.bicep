// PostgreSQL (Citus server group) for POC.
@secure()
param administratorLoginPassword string
param pocSlug string
param location string = 'eastus'
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

var clusterName = 'pg-${pocSlug}'

resource serverGroup 'Microsoft.DBforPostgreSQL/serverGroupsv2@2023-03-02-preview' = {
  name: clusterName
  location: location
  tags: {}
  properties: {
    administratorLoginPassword: administratorLoginPassword
    coordinatorServerEdition: coordinatorServerEdition
    coordinatorVCores: coordinatorVCores
    coordinatorStorageQuotaInMb: coordinatorStorageQuotaInMb
    enableShardsOnCoordinator: enableShardsOnCoordinator
    nodeCount: nodeCount
    nodeServerEdition: nodeServerEdition
    nodeVCores: nodeVCores
    nodeStorageQuotaInMb: nodeStorageQuotaInMb
    enableHa: enableHa
    coordinatorEnablePublicIpAccess: coordinatorEnablePublicIpAccess
    nodeEnablePublicIpAccess: nodeEnablePublicIpAccess
    citusVersion: citusVersion
    postgresqlVersion: postgresqlVersion
    preferredPrimaryZone: availabilityZone
  }
}

resource firewallAllowAll 'Microsoft.DBforPostgreSQL/serverGroupsv2/firewallRules@2023-03-02-preview' = {
  parent: serverGroup
  name: 'AllowAll'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

resource firewallAzureServices 'Microsoft.DBforPostgreSQL/serverGroupsv2/firewallRules@2023-03-02-preview' = {
  parent: serverGroup
  name: 'AllowAllAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output host string = serverGroup.properties.fullyQualifiedDomainName
output databaseName string = 'citus'
