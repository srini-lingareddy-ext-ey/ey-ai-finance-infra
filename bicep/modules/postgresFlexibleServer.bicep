// Azure Database for PostgreSQL — Flexible Server (Microsoft.DBforPostgreSQL/flexibleServers).
// Use this for new deployments and migrations off Azure Cosmos DB for PostgreSQL (serverGroupsv2 / Citus),
// which is being retired in favor of Flexible Server.
@description('Short POC identifier; used in default server name pgflex-<pocSlug>-poc.')
param pocSlug string

@description('Azure region for the server.')
param location string = resourceGroup().location

@description('Administrator login (cannot be azure_superuser, azure_pg_admin, admin, root, guest, or public).')
param administratorLogin string = 'citus'

@secure()
@description('Administrator password.')
param administratorLoginPassword string

@description('PostgreSQL major version.')
@allowed([
  '11'
  '12'
  '13'
  '14'
  '15'
  '16'
  '17'
])
param postgresqlVersion string = '16'

@description('Flexible Server SKU name (e.g. Burstable Standard_B2s, GeneralPurpose Standard_D2s_v3).')
param skuName string = 'Standard_B2s'

@description('SKU tier: Burstable, GeneralPurpose, or MemoryOptimized.')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param skuTier string = 'Burstable'

@description('Allocated storage in GiB (32–16384 depending on tier).')
@minValue(32)
@maxValue(16384)
param storageSizeGB int = 128

@description('Backup retention in days (7–35).')
@minValue(7)
@maxValue(35)
param backupRetentionDays int = 7

@allowed([
  'Disabled'
  'Enabled'
])
@description('Geo-redundant backup (Enabled only in supported regions).')
param geoRedundantBackup string = 'Disabled'

@allowed([
  'Disabled'
  'SameZone'
  'ZoneRedundant'
])
@description('High availability mode.')
param highAvailabilityMode string = 'Disabled'

@allowed([
  'Disabled'
  'Enabled'
])
@description('Public network access. Use Disabled with private networking (requires delegated subnet — deploy separately).')
param publicNetworkAccess string = 'Enabled'

@allowed([
  'Disabled'
  'Enabled'
])
@description('Microsoft Entra authentication (optional). Password auth remains available when Enabled.')
param activeDirectoryAuth string = 'Disabled'

@allowed([
  'Disabled'
  'Enabled'
])
#disable-next-line secure-secrets-in-params // Bicep linter false positive: ARM passwordAuth is not a secret value
param passwordAuth string = 'Enabled'

@description('Logical database to create (in addition to built-in postgres). Default citus matches legacy Citus coordinator DB name for app compatibility.')
param databaseName string = 'citus'

@description('When true, create firewall rule 0.0.0.0–255.255.255.255 (dev/POC only).')
param enableAllowAllIPv4FirewallRule bool = true

@description('When true, create Azure services firewall rule (0.0.0.0/0.0.0.0 pattern).')
param enableAllowAzureServicesFirewallRule bool = true

@description('Optional availability zone for the primary (e.g. 1, 2, 3). Leave empty for Azure to choose.')
param availabilityZone string = ''

@description('Comma-separated extension names for server parameter azure.extensions (allow-list before CREATE EXTENSION). Default includes citext for init.sql compatibility.')
param azureExtensions string = 'citext'

var serverName = 'pgflex-${pocSlug}-poc'

resource flexibleServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: serverName
  location: location
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: union({
    version: postgresqlVersion
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    storage: {
      storageSizeGB: storageSizeGB
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: geoRedundantBackup
    }
    network: {
      publicNetworkAccess: publicNetworkAccess
    }
    highAvailability: {
      mode: highAvailabilityMode
    }
    authConfig: {
      activeDirectoryAuth: activeDirectoryAuth
      passwordAuth: passwordAuth
    }
  }, !empty(availabilityZone) ? { availabilityZone: availabilityZone } : {})
}

resource azureExtensionsConfig 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: flexibleServer
  name: 'azure.extensions'
  properties: {
    value: azureExtensions
    source: 'user-override'
  }
}

resource appDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: flexibleServer
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource firewallAllowAll 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = if (enableAllowAllIPv4FirewallRule && publicNetworkAccess == 'Enabled') {
  parent: flexibleServer
  name: 'AllowAllIPv4'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

resource firewallAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = if (enableAllowAzureServicesFirewallRule && publicNetworkAccess == 'Enabled') {
  parent: flexibleServer
  name: 'AllowAllAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

@description('FQDN for PostgreSQL connections (sslmode=require).')
output host string = flexibleServer.properties.fullyQualifiedDomainName

@description('Flexible Server resource name.')
output serverName string = flexibleServer.name

@description('Administrator login.')
output administratorLogin string = administratorLogin

@description('Application database name created on the server.')
output databaseName string = appDatabase.name

@description('PostgreSQL port (always 5432 for Flexible Server).')
output port string = '5432'

@description('Resource ID of the flexible server.')
output flexibleServerId string = flexibleServer.id
