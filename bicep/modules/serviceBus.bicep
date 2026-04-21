// Azure Service Bus namespace (Standard by default) with default network rules, Root SAS policy, and queues.
// Namespace names are globally unique: sbn-<slug>-<suffix> (6–50 chars; letters, numbers, hyphens).
param pocSlug string
param location string

@description('Service Bus SKU. Standard matches the exported template; Premium requires different capacity/partition settings.')
@allowed([
  'Standard'
  'Premium'
])
param skuName string = 'Standard'

@description('Zone-redundant namespace (Azure regions that support it).')
param zoneRedundant bool = true

@description('Public network access for the namespace.')
@allowed([
  'Enabled'
  'Disabled'
  'SecuredByPerimeter'
])
param publicNetworkAccess string = 'Enabled'

@description('When true, SAS key authentication is disabled (Entra-only).')
param disableLocalAuth bool = false

@description('Queue names to create under the namespace (same settings per queue as the exported template).')
param queueNames array = [
  'genai-response-archive'
]

@description('Optional resource tags (cost center, environment, etc.).')
param tags object = {}

var sanitizedSlug = replace(replace(replace(toLower(pocSlug), '_', '-'), ' ', '-'), '.', '-')
var slugSegment = length(trim(sanitizedSlug)) > 0 ? take(sanitizedSlug, 28) : 'poc'
var namespaceName = 'sbn-${slugSegment}-${take(uniqueString(resourceGroup().id, pocSlug), 11)}'

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2025-05-01-preview' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuName
  }
  properties: {
    platformCapabilities: {
      confidentialCompute: {
        mode: 'Disabled'
      }
    }
    geoDataReplication: {
      maxReplicationLagDurationInSeconds: 0
      locations: [
        {
          locationName: location
          roleType: 'Primary'
        }
      ]
    }
    premiumMessagingPartitions: 0
    minimumTlsVersion: '1.2'
    publicNetworkAccess: publicNetworkAccess
    disableLocalAuth: disableLocalAuth
    zoneRedundant: zoneRedundant
  }
}

resource rootManageSharedAccessKey 'Microsoft.ServiceBus/namespaces/authorizationRules@2025-05-01-preview' = {
  parent: serviceBusNamespace
  name: 'RootManageSharedAccessKey'
  properties: {
    rights: [
      'Listen'
      'Manage'
      'Send'
    ]
  }
}

resource networkRuleSetDefault 'Microsoft.ServiceBus/namespaces/networkRuleSets@2025-05-01-preview' = {
  parent: serviceBusNamespace
  name: 'default'
  properties: {
    publicNetworkAccess: publicNetworkAccess
    defaultAction: 'Allow'
    virtualNetworkRules: []
    ipRules: []
    trustedServiceAccessEnabled: false
  }
}

resource queues 'Microsoft.ServiceBus/namespaces/queues@2025-05-01-preview' = [for queueName in queueNames: {
  parent: serviceBusNamespace
  name: string(queueName)
  properties: {
    maxMessageSizeInKilobytes: 256
    lockDuration: 'PT5M'
    maxSizeInMegabytes: 5120
    requiresDuplicateDetection: false
    requiresSession: false
    defaultMessageTimeToLive: 'P10675199DT2H48M5.4775807S'
    deadLetteringOnMessageExpiration: false
    enableBatchedOperations: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    maxDeliveryCount: 10
    status: 'Active'
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    enablePartitioning: true
    enableExpress: false
  }
}]

output serviceBusNamespaceName string = serviceBusNamespace.name
output serviceBusNamespaceId string = serviceBusNamespace.id
output serviceBusEndpoint string = '${serviceBusNamespace.name}.servicebus.windows.net'
