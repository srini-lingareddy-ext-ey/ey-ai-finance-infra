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

@description('Microsoft Entra (Azure AD) app registration — application (client) ID for end-user sign-in in the frontend. Leave empty to skip auth-related app settings.')
param microsoftIdentityClientId string = ''

@description('Microsoft Entra tenant ID (directory) for that app registration.')
param microsoftIdentityTenantId string = ''

@description('Optional client secret for confidential-client flows (e.g. server-side token exchange). Leave empty for public SPA-only config.')
@secure()
param microsoftIdentityClientSecret string = ''

@description('Public base URL of the frontend (e.g. https://eyaifinance-mypoc.azurewebsites.net). Used for OAuth redirect URI registration hints and app configuration.')
param frontendPublicBaseUrl string = ''

var appServicePlanName = 'asp-${pocSlug}'
// Default hostnames: https://eyaifinance-<pocSlug>.azurewebsites.net and https://eyaifinance-backend-<pocSlug>.azurewebsites.net
var frontendName = 'eyaifinance-${pocSlug}'
var backendName = 'eyaifinance-backend-${pocSlug}'
var sharedAppSettings = [ { name: 'AZURE_APP_CONFIGURATION_CONNECTION', value: appConfigEndpoint }, { name: 'KEY_VAULT_URI', value: keyVaultUri } ]

var microsoftAuthEnabled = !empty(microsoftIdentityClientId) && !empty(microsoftIdentityTenantId) && !empty(frontendPublicBaseUrl)
// Use cloud-specific login root (public Azure → Microsoft Entra sign-in endpoint).
var entraLoginRoot = endsWith(environment().authentication.loginEndpoint, '/')
  ? substring(environment().authentication.loginEndpoint, 0, length(environment().authentication.loginEndpoint) - 1)
  : environment().authentication.loginEndpoint
var microsoftAuthority = '${entraLoginRoot}/${microsoftIdentityTenantId}/v2.0'
var frontendMicrosoftAuthSettings = microsoftAuthEnabled ? concat(
  [
    { name: 'MICROSOFT_PROVIDER_CLIENT_ID', value: microsoftIdentityClientId }
    { name: 'MICROSOFT_PROVIDER_TENANT_ID', value: microsoftIdentityTenantId }
    { name: 'MICROSOFT_PROVIDER_AUTHORITY', value: microsoftAuthority }
    { name: 'WEBAPP_PUBLIC_BASE_URL', value: frontendPublicBaseUrl }
    // No NEXT_PUBLIC_* here: this stack uses container images; Next (and similar) inlines public env at image
    // build time. Runtime App Service settings are for server-side / non-bundled code — pass build args in CI for client bundles.
  ],
  !empty(microsoftIdentityClientSecret)
    ? [
        { name: 'MICROSOFT_PROVIDER_CLIENT_SECRET', value: microsoftIdentityClientSecret }
      ]
    : []
) : []
var frontendAppSettings = concat(sharedAppSettings, frontendMicrosoftAuthSettings)

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
      appSettings: frontendAppSettings
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
