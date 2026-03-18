// App Service plan + frontend + backend for POC. Uses shared ACR managed identity for image pull; App Config + Key Vault refs.
param pocSlug string
param location string
param acrManagedIdentityResourceId string
@description('Client ID (applicationId) of the user-assigned managed identity used for ACR pull. Required for acrUseManagedIdentityCreds.')
param acrManagedIdentityClientId string
param appConfigEndpoint string
param keyVaultUri string
param frontendImage string
param backendImage string
param sku string = 'P1v3'

var appServicePlanName = 'asp-${pocSlug}'
var frontendName = 'frontend-${pocSlug}'
var backendName = 'backend-${pocSlug}'
var sharedAppSettings = [ { name: 'AZURE_APP_CONFIGURATION_CONNECTION', value: appConfigEndpoint }, { name: 'KEY_VAULT_URI', value: keyVaultUri } ]

resource appServicePlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: appServicePlanName
  location: location
  properties: { reserved: true }
  sku: { name: sku }
  kind: 'linux'
}

resource appServiceFrontend 'Microsoft.Web/sites@2024-11-01' = {
  name: frontendName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${acrManagedIdentityResourceId}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: frontendImage
      http20Enabled: true
      minTlsVersion: '1.3'
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: acrManagedIdentityClientId
      appSettings: sharedAppSettings
      healthCheckPath: '/api/health'
    }
    clientCertEnabled: false
    clientCertMode: 'Optional'
  }
}

resource appServiceBackend 'Microsoft.Web/sites@2024-11-01' = {
  name: backendName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${acrManagedIdentityResourceId}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: backendImage
      http20Enabled: true
      minTlsVersion: '1.3'
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: acrManagedIdentityClientId
      appSettings: sharedAppSettings
      healthCheckPath: '/api/health'
    }
    clientCertEnabled: false
    clientCertMode: 'Optional'
  }
}

resource frontendConfig 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: appServiceFrontend
  name: 'web'
  properties: {
    http20Enabled: true
    minTlsVersion: '1.3'
  }
}

resource backendConfig 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: appServiceBackend
  name: 'web'
  properties: {
    http20Enabled: true
    minTlsVersion: '1.3'
  }
}

output frontendAppName string = appServiceFrontend.name
output backendAppName string = appServiceBackend.name
