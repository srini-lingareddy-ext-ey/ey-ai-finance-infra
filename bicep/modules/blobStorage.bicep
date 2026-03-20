// Storage account (Blob) for POC. Parameterized container list.
param pocSlug string
param location string
param containerNames array = []
param sku string = 'Standard_LRS'

// Storage account name: 3-24 chars, lowercase letters and numbers only (no hyphens). Pattern: st-<pocSlug>-poc + unique suffix (Azure names are globally unique).
var sanitizedSlug = replace(pocSlug, '-', '')
var storageAccountName = 'st${take(sanitizedSlug, 8)}poc${take(uniqueString(resourceGroup().id), 11)}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: sku
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

// Blob soft-delete + container soft-delete.
// Azure requires blob deleteRetentionPolicy.days > restorePolicy.days when PITR is on (strict >).
// Defaults often use 7d for both → "Blob Delete Retention policy days should be longer than Point In Time Restore policy days".
// We disable PITR and use 14d blob soft-delete so redeploys succeed even if the account retained PITR at 6–7d.
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    restorePolicy: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 14
      allowPermanentDelete: false
    }
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