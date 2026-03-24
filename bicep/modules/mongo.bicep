// Microsoft.DocumentDB cluster module; invoked from core-resources.bicep.
@secure()
param administratorLoginPassword string
param pocSlug string
param location string = 'eastus'
param administratorLogin string = 'mongoadmin'
param computeTier string = 'M10'
param storageSizeGb int = 32
param shardCount int = 1
param serverVersion string = '8.0'
@allowed([
  'Disabled'
  'SameZone'
  'ZoneRedundantPreferred'
])
param highAvailabilityTargetMode string = 'Disabled'
@allowed([
  'Disabled'
  'Enabled'
])
param publicNetworkAccess string = 'Enabled'

// Name: 3–40 chars, lowercase alphanumeric and single hyphens between segments (no consecutive hyphens).
var clusterName = 'mongo-${pocSlug}-poc'

resource cluster 'Microsoft.DocumentDB/mongoClusters@2025-09-01' = {
  name: clusterName
  location: location
  tags: {}
  properties: {
    createMode: 'Default'
    administrator: {
      userName: administratorLogin
      password: administratorLoginPassword
    }
    serverVersion: serverVersion
    sharding: {
      shardCount: shardCount
    }
    storage: {
      sizeGb: storageSizeGb
    }
    highAvailability: {
      targetMode: highAvailabilityTargetMode
    }
    compute: {
      tier: computeTier
    }
    publicNetworkAccess: publicNetworkAccess
  }
}

resource firewallAllowAll 'Microsoft.DocumentDB/mongoClusters/firewallRules@2025-09-01' = {
  parent: cluster
  name: 'AllowAll'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

resource firewallAzureServices 'Microsoft.DocumentDB/mongoClusters/firewallRules@2025-09-01' = {
  parent: cluster
  name: 'AllowAllAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output host string = '${cluster.name}.mongocluster.cosmos.azure.com'
output clusterName string = cluster.name
output clusterResourceId string = cluster.id
output administratorLogin string = administratorLogin
@secure()
output connectionString string = cluster.properties.connectionString
