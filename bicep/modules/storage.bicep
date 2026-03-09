// Storage account (Blob) for POC. Parameterized container list (guide: templates/storageTemplate.bicep).
param pocSlug string
param location string
param containerNames array = []
param sku string = 'Standard_LRS'

// Storage account name: 3-24 chars, lowercase letters and numbers only (no hyphens)
var storageAccountName = 'st${take(replace(pocSlug, '-', ''), 22)}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: sku
    tier: 'Standard'
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: { keyType: 'Account', enabled: true }
        blob: { keyType: 'Account', enabled: true }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
  sku: {
    name: sku
    tier: 'Standard'
  }
  properties: {
    containerDeleteRetentionPolicy: { enabled: true, days: 7 }
    deleteRetentionPolicy: { allowPermanentDelete: false, enabled: true, days: 7 }
  }
}

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = [for name in containerNames: {
  parent: blobService
  name: name
  properties: {
    publicAccess: 'None'
  }
}]

output storageAccountName string = storageAccount.name
output storageResourceId string = storageAccount.id
