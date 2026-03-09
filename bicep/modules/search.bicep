// Azure AI Search for POC. Guide: templates/searchTemplate.bicep
param pocSlug string
param location string

var searchName = 'search-${pocSlug}'

resource searchService 'Microsoft.Search/searchServices@2025-05-01' = {
  name: searchName
  location: location
  sku: {
    name: 'standard'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    computeType: 'Default'
    publicNetworkAccess: 'Enabled'
    networkRuleSet: {
      ipRules: []
      bypass: 'None'
    }
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    disableLocalAuth: false
    authOptions: {
      apiKeyOnly: {}
    }
    dataExfiltrationProtections: []
    semanticSearch: 'standard'
  }
}

output endpoint string = 'https://${searchService.name}.search.windows.net'
output searchName string = searchService.name
