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

@description('Client ID of the user-assigned managed identity acr-managed-identity (used for ACR image pull). Get with: az identity show --ids <acr-managed-identity-resource-id> --query clientId -o tsv')
param acrManagedIdentityClientId string

// Central ACR identity (acr-managed-identity in rg-eyaifin-acr) — hardcoded for this subscription.
var acrManagedIdentityResourceIdFinal = '/subscriptions/08d343af-2a3c-4f13-86a5-d9bde4948ae8/resourceGroups/rg-eyaifin-acr/providers/Microsoft.ManagedIdentity/userAssignedIdentities/acr-managed-identity'
var keyVaultUri = 'https://${keyVaultName}${environment().suffixes.keyvaultDns}/'

module appService 'modules/appService.bicep' = {
  name: 'appService'
  params: {
    pocSlug: pocSlug
    location: location
    acrManagedIdentityResourceId: acrManagedIdentityResourceIdFinal
    appConfigEndpoint: appConfigEndpoint
    keyVaultUri: keyVaultUri
    frontendImage: frontendImage
    backendImage: backendImage
    acrManagedIdentityClientId: acrManagedIdentityClientId
  }
}

output frontendAppName string = appService.outputs.frontendAppName
output backendAppName string = appService.outputs.backendAppName
