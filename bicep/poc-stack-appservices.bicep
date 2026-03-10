// App Services only (resource-group scope). Deploy after poc-stack-core and after Key Vault is populated.
// Use outputs from the core deployment (or main.bicep) for keyVaultName and appConfigEndpoint.
targetScope = 'resourceGroup'

@description('POC identifier used in resource names (e.g. mypoc).')
param pocSlug string

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('App Configuration connection endpoint (from core deployment output).')
param appConfigEndpoint string

@description('Key Vault name in this resource group (from core deployment output).')
param keyVaultName string

@description('Frontend container image (e.g. DOCKER|registry.azurecr.io/image:tag).')
param frontendImage string

@description('Backend container image (e.g. DOCKER|registry.azurecr.io/image:tag).')
param backendImage string

// Central ACR and identity (creyaifinmain, acr-managed-identity in rg-eyaifin-acr) — hardcoded for this subscription.
var centralAcrResourceIdFinal = '/subscriptions/08d343af-2a3c-4f13-86a5-d9bde4948ae8/resourceGroups/rg-eyaifin-acr/providers/Microsoft.ContainerRegistry/registries/creyaifinmain'
var acrManagedIdentityResourceIdFinal = '/subscriptions/08d343af-2a3c-4f13-86a5-d9bde4948ae8/resourceGroups/rg-eyaifin-acr/providers/Microsoft.ManagedIdentity/userAssignedIdentities/acr-managed-identity'
var keyVaultResourceId = resourceId(resourceGroup().id, 'Microsoft.KeyVault/vaults', keyVaultName)
var keyVaultUri = 'https://${keyVaultName}.vault.azure.net/'

module appService 'modules/appService.bicep' = {
  name: 'appService'
  params: {
    pocSlug: pocSlug
    location: location
    centralAcrResourceId: centralAcrResourceIdFinal
    acrManagedIdentityResourceId: acrManagedIdentityResourceIdFinal
    appConfigEndpoint: appConfigEndpoint
    keyVaultResourceId: keyVaultResourceId
    keyVaultUri: keyVaultUri
    frontendImage: frontendImage
    backendImage: backendImage
  }
}

output frontendAppName string = appService.outputs.frontendAppName
output backendAppName string = appService.outputs.backendAppName
