// App Service plan + frontend + backend for POC. Uses shared ACR managed identity for image pull; App Config + Key Vault refs.
param pocSlug string
param location string
param acrManagedIdentityResourceId string
@description('Client ID (applicationId) of the user-assigned managed identity used for ACR pull. Required for acrUseManagedIdentityCreds.')
param acrManagedIdentityClientId string
@description('App Configuration read-only connection string: Endpoint=https://...;Id=...;Secret=...')
@secure()
param appConfigConnectionString string
param keyVaultUri string
param frontendImage string
param backendImage string
param sku string = 'P1v3'

@description('Microsoft Entra (Azure AD) app registration — application (client) ID for end-user sign-in in the frontend. Leave empty to skip auth-related app settings.')
param microsoftIdentityClientId string = ''

@description('Microsoft Entra tenant ID (directory) for that app registration.')
param microsoftIdentityTenantId string = ''

@description('Client secret from the Entra app registration. Required for Easy Auth (authsettingsV2). Deploy POC always supplies this; leave empty only for manual app-managed auth without platform Easy Auth.')
@secure()
param microsoftIdentityClientSecret string = ''

@description('Public base URL of the frontend (e.g. https://eyaifinance-mypoc.azurewebsites.net). Required with client ID + tenant to enable auth; used as WEBAPP_PUBLIC_BASE_URL only when Easy Auth is off (app-managed auth).')
param frontendPublicBaseUrl string = ''

@description('Azure HTTP health probe path for the frontend. Default /api/health; use / if the app has no API health route.')
param frontendHealthCheckPath string = '/api/health'

@description('Azure HTTP health probe path for the backend. Default /health — probe sends GET with no Authorization header; allow anonymous GET on this path in the API. Pass empty string only to omit the platform probe (manual/az override).')
param backendHealthCheckPath string = '/health'

@description('Backend-only: Postgres host FQDN. When host, database, user, and postgresPassword are all set, the backend gets POSTGRES_* app settings.')
param postgresHost string = ''

@description('Backend-only: Postgres database name.')
param postgresDatabaseName string = ''

@description('Backend-only: Postgres login user (Citus default is citus).')
param postgresUser string = ''

@description('Backend-only: Postgres port.')
param postgresPort string = '5432'

@description('Backend-only: Postgres password stored as plain app setting POSTGRES_PASSWORD (not a Key Vault reference). Empty = omit POSTGRES_* block.')
@secure()
param postgresPassword string = ''

@description('Backend-only: Compact JSON array of two JSON strings for OPENAI_ACCOUNT_EUS2, e.g. ["account-name","api-key"]. Empty = omit. Stored as a plain app setting (key visible in portal to authorized users).')
@secure()
param openAiAccountEus2Json string = ''

@description('Backend-only: MongoDB connection string for app setting MONGO_CONN_STR. Empty = omit.')
@secure()
param mongoConnStr string = ''

@description('Backend-only: POC Blob Storage full connection string for app setting STORAGE_ACCOUNT (account key). Empty = omit. Stored as plain app setting value in ARM (like POSTGRES_PASSWORD); visible to authorized portal users.')
@secure()
param storageConnectionString string = ''

@description('Backend-only: optional app setting OPENAI_ACCOUNT_EUS2_LEGACY (e.g. JSON or connection string). Empty = omit.')
@secure()
param openAiAccountEus2Legacy string = ''

@description('Backend-only: optional app setting OPENAI_ACCOUNT_WUS. Empty = omit.')
@secure()
param openAiAccountWus string = ''

@description('Backend-only: optional app setting OPENAI_ACCOUNT_WUS3. Empty = omit.')
@secure()
param openAiAccountWus3 string = ''

@description('Backend-only: optional app setting SEARCH_ACCOUNT. Empty = omit.')
@secure()
param searchAccount string = ''

var appServicePlanName = 'asp-${pocSlug}'
// Default hostnames: https://eyaifinance-<pocSlug>.azurewebsites.net and https://eyaifinance-backend-<pocSlug>.azurewebsites.net
var frontendName = 'eyaifinance-${pocSlug}'
var backendName = 'eyaifinance-backend-${pocSlug}'
// Backend FRONTEND_URL: matches frontendPublicBaseUrl when set (Deploy POC); else default hostname (public Azure App Service suffix; suffixes.webSites is not on environment().suffixes in Bicep).
var frontendDefaultSiteUrl = 'https://${frontendName}.azurewebsites.net'
var backendFrontendUrl = !empty(frontendPublicBaseUrl) ? frontendPublicBaseUrl : frontendDefaultSiteUrl
var backendFrontendUrlAppSettings = [
  { name: 'FRONTEND_URL', value: backendFrontendUrl }
]
var azureAppConfigConnectionStringQuoted = '"${appConfigConnectionString}"'
var sharedAppSettings = [ { name: 'AZURE_APP_CONFIG_CONNECTION_STRING', value: azureAppConfigConnectionStringQuoted }, { name: 'KEY_VAULT_URI', value: keyVaultUri } ]

var microsoftAuthEnabled = !empty(microsoftIdentityClientId) && !empty(microsoftIdentityTenantId) && !empty(frontendPublicBaseUrl)
// Easy Auth (Microsoft provider) needs a client secret and an app setting name referenced by authsettingsV2.
var easyAuthEnabled = microsoftAuthEnabled && !empty(microsoftIdentityClientSecret)
var entraClientSecretSettingName = 'MICROSOFT_PROVIDER_CLIENT_SECRET'
// Use cloud-specific login root (public Azure → Microsoft Entra sign-in endpoint).
var entraLoginEndpoint = environment().authentication.loginEndpoint
var entraLoginRoot = length(entraLoginEndpoint) > 0 && endsWith(entraLoginEndpoint, '/')
  ? substring(entraLoginEndpoint, 0, length(entraLoginEndpoint) - 1)
  : entraLoginEndpoint
var microsoftAuthority = '${entraLoginRoot}/${microsoftIdentityTenantId}/v2.0'
// Issuer URL expected by App Service Easy Auth / Entra v2 (same tenant segment as authority).
var entraOpenIdIssuer = microsoftAuthority
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
// Require token tid to match this tenant (portal “Tenant requirement” → allow only issuer tenant). See Microsoft Learn: WEBSITE_AUTH_AAD_ALLOWED_TENANTS.
var easyAuthAllowedTenantsAppSetting = {
  name: 'WEBSITE_AUTH_AAD_ALLOWED_TENANTS'
  value: microsoftIdentityTenantId
}
var microsoftIdentityFrontendAppSettings = easyAuthEnabled
  ? concat(microsoftAuthSecretAppSettings, [easyAuthAllowedTenantsAppSetting])
  : (microsoftAuthEnabled
      ? concat(
          microsoftAuthCoreAppSettings,
          [
            { name: 'WEBAPP_PUBLIC_BASE_URL', value: frontendPublicBaseUrl }
          ]
        )
      : [])
var frontendAppSettings = concat(sharedAppSettings, microsoftIdentityFrontendAppSettings)

var injectBackendPostgresSettings = !empty(postgresHost) && !empty(postgresDatabaseName) && !empty(postgresUser) && !empty(postgresPassword)
var backendPostgresAppSettings = injectBackendPostgresSettings
  ? [
      { name: 'POSTGRES_HOST', value: postgresHost }
      { name: 'POSTGRES_DB', value: postgresDatabaseName }
      { name: 'POSTGRES_USER', value: postgresUser }
      { name: 'POSTGRES_PORT', value: postgresPort }
      { name: 'POSTGRES_PASSWORD', value: postgresPassword }
    ]
  : []
var backendOpenAiEus2AppSettings = !empty(openAiAccountEus2Json)
  ? [
      { name: 'OPENAI_ACCOUNT_EUS2', value: openAiAccountEus2Json }
    ]
  : []
var backendMongoAppSettings = !empty(mongoConnStr)
  ? [
      { name: 'MONGO_CONN_STR', value: mongoConnStr }
    ]
  : []
var backendStorageConnectionAppSettings = !empty(storageConnectionString)
  ? [
      { name: 'STORAGE_ACCOUNT', value: storageConnectionString }
    ]
  : []
var backendOpenAiLegacyAppSettings = !empty(openAiAccountEus2Legacy)
  ? [
      { name: 'OPENAI_ACCOUNT_EUS2_LEGACY', value: openAiAccountEus2Legacy }
    ]
  : []
var backendOpenAiWusAppSettings = !empty(openAiAccountWus)
  ? [
      { name: 'OPENAI_ACCOUNT_WUS', value: openAiAccountWus }
    ]
  : []
var backendOpenAiWus3AppSettings = !empty(openAiAccountWus3)
  ? [
      { name: 'OPENAI_ACCOUNT_WUS3', value: openAiAccountWus3 }
    ]
  : []
var backendSearchAccountAppSettings = !empty(searchAccount)
  ? [
      { name: 'SEARCH_ACCOUNT', value: searchAccount }
    ]
  : []
var backendEntraAppSettings = !empty(microsoftIdentityClientId) && !empty(microsoftIdentityTenantId)
  ? [
      { name: 'AZURE_CLIENT_ID', value: microsoftIdentityClientId }
      { name: 'AZURE_TENANT_ID', value: microsoftIdentityTenantId }
    ]
  : []
var backendAppSettings = concat(
  sharedAppSettings,
  backendFrontendUrlAppSettings,
  backendPostgresAppSettings,
  backendMongoAppSettings,
  backendStorageConnectionAppSettings,
  backendOpenAiEus2AppSettings,
  backendOpenAiLegacyAppSettings,
  backendOpenAiWusAppSettings,
  backendOpenAiWus3AppSettings,
  backendSearchAccountAppSettings,
  backendEntraAppSettings
)

// Omit healthCheckPath when empty so Azure does not probe (JWT-only APIs often return 401 without Authorization).
var backendSiteConfigBase = {
  linuxFxVersion: backendImage
  http20Enabled: true
  minTlsVersion: '1.3'
  acrUseManagedIdentityCreds: true
  acrUserManagedIdentityID: acrManagedIdentityClientId
  appSettings: backendAppSettings
}
var backendSiteConfig = !empty(backendHealthCheckPath)
  ? union(backendSiteConfigBase, { healthCheckPath: backendHealthCheckPath })
  : backendSiteConfigBase

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
      healthCheckPath: frontendHealthCheckPath
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
    siteConfig: backendSiteConfig
    clientCertEnabled: false
    clientCertMode: 'Optional'
  }
}

// App Service Authentication (Easy Auth) — Microsoft Entra ID on the frontend only. Register redirect URI on the app registration:
// https://<frontend-default-host>/.auth/login/aad/callback
// Root-level login.tokenStore.enabled persists tokens server-side (portal “Token store” on).
resource frontendAuthSettingsV2 'Microsoft.Web/sites/config@2024-11-01' = if (easyAuthEnabled) {
  parent: appServiceFrontend
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      requireAuthentication: false
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureActiveDirectory'
      excludedPaths: [
        '/api/health'
        '/api/health/'
      ]
    }
    httpSettings: {
      requireHttps: true
    }
    // Token store is under root login (not identityProviders.azureActiveDirectory.login) — matches ARM / file-based auth schema.
    login: {
      tokenStore: {
        enabled: true
      }
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: microsoftIdentityClientId
          clientSecretSettingName: entraClientSecretSettingName
          openIdIssuer: entraOpenIdIssuer
        }
        // Request offline_access so Entra issues a refresh token; Easy Auth /.auth/refresh otherwise often returns 403.
        login: {
          loginParameters: [
            'scope=openid profile email offline_access'
          ]
        }
        // Portal “Authentication” → Microsoft Entra ID: token store enabled; no explicit allowed token audiences.
        // defaultAuthorizationPolicy.allowedApplications → “Allow requests only from this application itself” (appid/azp).
        // Tenant tid check: WEBSITE_AUTH_AAD_ALLOWED_TENANTS app setting. Issuer: tenant-specific openIdIssuer.
        validation: {
          defaultAuthorizationPolicy: {
            allowedApplications: [
              microsoftIdentityClientId
            ]
          }
        }
      }
    }
  }
}

// Keep App Service Authentication disabled on the backend (no Easy Auth / no Entra redirect on backend).
resource backendAuthSettingsV2Off 'Microsoft.Web/sites/config@2024-11-01' = {
  parent: appServiceBackend
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: false
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
