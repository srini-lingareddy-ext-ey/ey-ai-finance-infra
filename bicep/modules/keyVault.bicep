// Key Vault for POC. Pipeline populates secrets (plan 5a). No secrets created in Bicep.
// Guide: templates/kvTemplate.bicep — simplified: Standard SKU, Allow network.
// RBAC: pipeline and App Service principals get roles from main.bicep.
param pocSlug string
param location string

var vaultName = 'kv-${pocSlug}'

resource vault 'Microsoft.KeyVault/vaults@2024-12-01-preview' = {
  name: vaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    accessPolicies: []
    enabledForDeployment: true
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    enablePurgeProtection: false
    publicNetworkAccess: 'Enabled'
  }
}

output keyVaultName string = vault.name
output keyVaultResourceId string = vault.id
output keyVaultUri string = 'https://${vault.name}.vault.azure.net/'
