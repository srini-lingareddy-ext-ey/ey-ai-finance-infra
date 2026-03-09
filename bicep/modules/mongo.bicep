// MongoDB (DocumentDB mongoClusters) for POC. Guide: templates/documentDBMongoTemplate.bicep
param pocSlug string
param location string = 'eastus'
param administratorUserName string = 'main'
param computeTier string = 'M30'
param storageSizeGb int = 256

var clusterName = 'mongo-${pocSlug}'

resource mongoCluster 'Microsoft.DocumentDB/mongoClusters@2025-04-01-preview' = {
  name: clusterName
  location: location
  properties: {
    administrator: {
      userName: administratorUserName
    }
    serverVersion: '8.0'
    compute: {
      tier: computeTier
    }
    storage: {
      sizeGb: storageSizeGb
      type: 'PremiumSSD'
    }
    sharding: {
      shardCount: 1
    }
    highAvailability: {
      targetMode: 'Disabled'
    }
    backup: {}
    publicNetworkAccess: 'Enabled'
    dataApi: {
      mode: 'Disabled'
    }
    authConfig: {
      allowedModes: ['NativeAuth']
    }
    createMode: 'Default'
  }
}

resource firewallAllowAll 'Microsoft.DocumentDB/mongoClusters/firewallRules@2025-04-01-preview' = {
  parent: mongoCluster
  name: 'AllowAll'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

resource firewallAzure 'Microsoft.DocumentDB/mongoClusters/firewallRules@2025-04-01-preview' = {
  parent: mongoCluster
  name: 'AllowAllAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource adminUser 'Microsoft.DocumentDB/mongoClusters/users@2025-04-01-preview' = {
  parent: mongoCluster
  name: administratorUserName
  properties: {}
}

output connectionStringPrefix string = 'mongodb://${administratorUserName}@${mongoCluster.name}.mongocluster.cosmos.azure.com'
output clusterName string = mongoCluster.name
