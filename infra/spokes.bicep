targetScope = 'subscription'

@description('Azure region for spoke resource groups')
param location string = 'eastus2'

@description('Session identifier stamped on every spoke RG as a tag')
param sessionId string

@description('Number of participant slots (1–30)')
@minValue(1)
@maxValue(30)
param slotCount int = 30

var slots = [
  'user01', 'user02', 'user03', 'user04', 'user05',
  'user06', 'user07', 'user08', 'user09', 'user10',
  'user11', 'user12', 'user13', 'user14', 'user15',
  'user16', 'user17', 'user18', 'user19', 'user20',
  'user21', 'user22', 'user23', 'user24', 'user25',
  'user26', 'user27', 'user28', 'user29', 'user30',
]

resource spokeRgs 'Microsoft.Resources/resourceGroups@2023-07-01' = [for slot in take(slots, slotCount): {
  name: '${slot}-rg'
  location: location
  tags: {
    cohort: sessionId
    slot: slot
    purpose: 'workshop-spoke'
  }
}]

output spokeRgNames array = [for slot in take(slots, slotCount): '${slot}-rg']
