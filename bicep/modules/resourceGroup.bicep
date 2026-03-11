// Resource group for client onboarding. Deploy at subscription scope (not resource group).
// Run: az deployment sub create --location <region> --template-file bicep/modules/resourceGroup.bicep
targetScope = 'subscription'

param pocSlug string
param location string

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${pocSlug}-poc'
  location: location
}

output name string = rg.name
output resourceGroupLocation string = rg.location
