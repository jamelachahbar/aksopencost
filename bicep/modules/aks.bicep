// AKS Cluster Module
// Creates an Azure Kubernetes Service cluster with best practices

@description('Name of the AKS cluster')
param clusterName string

@description('Azure region for the cluster')
param location string

@description('Number of nodes in the default node pool')
param nodeCount int

@description('Size of the VMs in the default node pool')
param nodeVmSize string

@description('Kubernetes version (empty string = latest)')
param kubernetesVersion string

@description('Network plugin')
@allowed([
  'azure'
  'kubenet'
])
param networkPlugin string

@description('Network policy')
@allowed([
  'azure'
  'calico'
  'cilium'
])
param networkPolicy string

@description('Enable auto-scaling')
param enableAutoScaling bool

@description('Minimum node count for auto-scaling')
param minNodeCount int

@description('Maximum node count for auto-scaling')
param maxNodeCount int

@description('Tags for the cluster')
param tags object

// AKS Cluster
resource aks 'Microsoft.ContainerService/managedClusters@2023-10-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: clusterName
    kubernetesVersion: empty(kubernetesVersion) ? null : kubernetesVersion
    enableRBAC: true
    agentPoolProfiles: [
      {
        name: 'default'
        count: enableAutoScaling ? null : nodeCount
        vmSize: nodeVmSize
        osDiskSizeGB: 30
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        enableAutoScaling: enableAutoScaling
        minCount: enableAutoScaling ? minNodeCount : null
        maxCount: enableAutoScaling ? maxNodeCount : null
      }
    ]
    networkProfile: {
      networkPlugin: networkPlugin
      networkPolicy: networkPolicy
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
    }
  }
}

// Outputs
output clusterName string = aks.name
output clusterId string = aks.id
output clusterFqdn string = aks.properties.fqdn
output kubeletIdentityObjectId string = aks.properties.identityProfile.kubeletidentity.objectId
output identityPrincipalId string = aks.identity.principalId
