// Key Vault for POC. Pipeline populates secrets. No secrets created in Bicep.
// RBAC: pass pipelinePrincipalId to grant Key Vault Administrator so the workflow can populate secrets.
param pocSlug string
param location string
@description('Optional. Principal (object) ID of the pipeline identity — granted Key Vault Administrator when set.')
param pipelinePrincipalId string = ''

// Key Vault names are globally unique; suffix ensures uniqueness across subscriptions/tenants
var vaultName = 'kv-${pocSlug}-poc'

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
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
  }
}

var kvAdminRoleId = '00482a5a-887f-4fb3-b363-3b7fe8e74463'
resource kvRolePipeline 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(pipelinePrincipalId)) {
  name: guid(resourceGroup().id, vaultName, pipelinePrincipalId, kvAdminRoleId)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvAdminRoleId)
    principalId: pipelinePrincipalId
    principalType: 'ServicePrincipal'
  }
}

output keyVaultName string = vault.name
output keyVaultResourceId string = vault.id
output keyVaultUri string = 'https://${vault.name}.vault.azure.net/'