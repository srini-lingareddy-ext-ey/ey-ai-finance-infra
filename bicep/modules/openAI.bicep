// Azure OpenAI for POC. Parameterized deployments.
param pocSlug string
param location string
param openAIDeployments array = []

var accountName = 'openai-${pocSlug}-poc'

resource openaiAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: accountName
  location: location
  sku: {
    name: 'S0'
  }
  kind: 'OpenAI'
  properties: {
    apiProperties: {}
    customSubDomainName: accountName
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    allowProjectManagement: false
    publicNetworkAccess: 'Enabled'
  }
}

resource defenderSettings 'Microsoft.CognitiveServices/accounts/defenderForAISettings@2025-06-01' = {
  parent: openaiAccount
  name: 'Default'
  properties: {
    state: 'Disabled'
  }
}

resource deployments 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = [for dep in openAIDeployments: {
  parent: openaiAccount
  name: dep.name
  sku: {
    name: dep.?skuName ?? 'GlobalStandard'
    capacity: dep.capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: dep.model
      version: dep.version
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    currentCapacity: dep.capacity
    raiPolicyName: 'Low'
  }
}]

output endpoint string = openaiAccount.properties.endpoint
output openaiName string = openaiAccount.name
