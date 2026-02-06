// OpenCost Custom Role Definition Module
// Creates a custom Azure role for OpenCost to access pricing APIs

targetScope = 'subscription'

@description('Name of the custom role')
param roleName string

@description('Subscription ID')
param subscriptionId string

// Custom Role Definition
resource openCostRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(roleName, subscriptionId)
  properties: {
    roleName: roleName
    description: 'Rate Card query role for OpenCost'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Compute/virtualMachines/vmSizes/read'
          'Microsoft.Resources/subscriptions/locations/read'
          'Microsoft.Resources/providers/read'
          'Microsoft.ContainerService/containerServices/read'
          'Microsoft.Commerce/RateCard/read'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
    assignableScopes: [
      '/subscriptions/${subscriptionId}'
    ]
  }
}

// Outputs
output roleDefinitionId string = openCostRole.id
output roleName string = openCostRole.properties.roleName
