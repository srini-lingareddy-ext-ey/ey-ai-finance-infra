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

@description('Client secret from the Entra app registration. Required for Easy Auth: App Service only accepts this via an app setting referenced by authsettingsV2 (cannot be omitted for that path).')
@secure()
param microsoftIdentityClientSecret string = ''

@description('Public base URL of the frontend (e.g. https://eyaifinance-mypoc.azurewebsites.net). Required with client ID + tenant to enable auth; used as WEBAPP_PUBLIC_BASE_URL only when Easy Auth is off (app-managed auth).')
param frontendPublicBaseUrl string = ''

var appServicePlanName = 'asp-${pocSlug}'
// Default hostnames: https://eyaifinance-<pocSlug>.azurewebsites.net and https://eyaifinance-backend-<pocSlug>.azurewebsites.net
var frontendName = 'eyaifinance-${pocSlug}'
var backendName = 'eyaifinance-backend-${pocSlug}'
var sharedAppSettings = [ { name: 'AZURE_APP_CONFIGURATION_CONNECTION', value: appConfigEndpoint }, { name: 'KEY_VAULT_URI', value: keyVaultUri } ]

var microsoftAuthEnabled = !empty(microsoftIdentityClientId) && !empty(microsoftIdentityTenantId) && !empty(frontendPublicBaseUrl)
// Easy Auth (Microsoft provider) needs a client secret and an app setting name referenced by authsettingsV2.
var easyAuthEnabled = microsoftAuthEnabled && !empty(microsoftIdentityClientSecret)
var entraClientSecretSettingName = 'MICROSOFT_PROVIDER_CLIENT_SECRET'
// Use cloud-specific login root (public Azure → Microsoft Entra sign-in endpoint).
var entraLoginRoot = endsWith(environment().authentication.loginEndpoint, '/')
  ? substring(environment().authentication.loginEndpoint, 0, length(environment().authentication.loginEndpoint) - 1)
  : environment().authentication.loginEndpoint
var microsoftAuthority = '${entraLoginRoot}/${microsoftIdentityTenantId}/v2.0'
// Issuer URL expected by App Service Easy Auth / Entra v2 (same tenant segment as authority).
var entraOpenIdIssuer = microsoftAuthority
var backendPublicBaseUrl = 'https://${backendName}.azurewebsites.net'
// Easy Auth: client ID + issuer live in authsettingsV2 only. Azure still requires the client secret as an app setting (see clientSecretSettingName).
// If you use app-managed auth instead (no secret / no Easy Auth), expose id + tenant + authority + public URL to the container here.
var microsoftAuthCoreAppSettings = [
  { name: 'MICROSOFT_PROVIDER_CLIENT_ID', value: microsoftIdentityClientId }
  { name: 'MICROSOFT_PROVIDER_TENANT_ID', value: microsoftIdentityTenantId }
  { name: 'MICROSOFT_PROVIDER_AUTHORITY', value: microsoftAuthority }
]
var microsoftAuthSecretAppSettings = !empty(microsoftIdentityClientSecret)
  ? [
      { name: entraClientSecretSettingName, value: microsoftIdentityClientSecret }
    ]
  : []
var microsoftIdentityFrontendAppSettings = easyAuthEnabled
  ? microsoftAuthSecretAppSettings
  : (microsoftAuthEnabled
      ? concat(
          microsoftAuthCoreAppSettings,
          [
            { name: 'WEBAPP_PUBLIC_BASE_URL', value: frontendPublicBaseUrl }
          ]
        )
      : [])
var microsoftIdentityBackendAppSettings = easyAuthEnabled
  ? microsoftAuthSecretAppSettings
  : (microsoftAuthEnabled
      ? concat(
          microsoftAuthCoreAppSettings,
          [
            { name: 'WEBAPP_PUBLIC_BASE_URL', value: backendPublicBaseUrl }
          ]
        )
      : [])
var frontendAppSettings = concat(sharedAppSettings, microsoftIdentityFrontendAppSettings)
var backendAppSettings = concat(sharedAppSettings, microsoftIdentityBackendAppSettings)

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
      appSettings: backendAppSettings
      healthCheckPath: '/api/health'
    }
    clientCertEnabled: false
    clientCertMode: 'Optional'
  }
}

// App Service Authentication (Easy Auth) — Microsoft Entra ID. Register redirect URIs on the app registration:
// https://<frontend-default-host>/.auth/login/aad/callback and https://<backend-default-host>/.auth/login/aad/callback
resource frontendAuthSettingsV2 'Microsoft.Web/sites/config@2024-11-01' = if (easyAuthEnabled) {
  parent: appServiceFrontend
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureActiveDirectory'
      excludedPaths: [
        '/api/health'
      ]
    }
    httpSettings: {
      requireHttps: true
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: microsoftIdentityClientId
          clientSecretSettingName: entraClientSecretSettingName
          openIdIssuer: entraOpenIdIssuer
        }
      }
    }
  }
}

resource backendAuthSettingsV2 'Microsoft.Web/sites/config@2024-11-01' = if (easyAuthEnabled) {
  parent: appServiceBackend
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      requireAuthentication: false
      unauthenticatedClientAction: 'AllowAnonymous'
      excludedPaths: [
        '/api/health'
      ]
    }
    httpSettings: {
      requireHttps: true
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: microsoftIdentityClientId
          clientSecretSettingName: entraClientSecretSettingName
          openIdIssuer: entraOpenIdIssuer
        }
      }
    }
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
