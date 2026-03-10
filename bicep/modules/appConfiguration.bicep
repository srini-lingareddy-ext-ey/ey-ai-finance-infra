// App Configuration store for POC. POC-specific key-values from parameter.
param pocSlug string
param location string
param pocAppConfigKeyValues array = []

var storeName = 'appconfig-${pocSlug}'

resource configurationStore 'Microsoft.AppConfiguration/configurationStores@2025-02-01-preview' = {
  name: storeName
  location: location
  sku: {
    name: 'standard'
  }
  properties: {
    encryption: {}
    disableLocalAuth: false
    softDeleteRetentionInDays: 7
    defaultKeyValueRevisionRetentionPeriodInSeconds: 2592000
    enablePurgeProtection: false
    dataPlaneProxy: {
      authenticationMode: 'Pass-through'
      privateLinkDelegation: 'Disabled'
    }
    telemetry: {}
  }
}

resource keyValues 'Microsoft.AppConfiguration/configurationStores/keyValues@2025-02-01-preview' = [for (kv, i) in pocAppConfigKeyValues: {
  parent: configurationStore
  name: kv.key
  properties: {
    value: kv.value
    contentType: coalesce(kv.contentType, 'application/json')
  }
}]

output endpoint string = configurationStore.properties.endpoint
output storeName string = configurationStore.name
