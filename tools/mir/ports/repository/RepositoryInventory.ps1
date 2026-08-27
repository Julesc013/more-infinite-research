function Assert-MIR4RepositoryInventoryPortV1 {
  param([Parameter(Mandatory)]$Inventory)
  if ([int]$Inventory.schema -ne 1 -or [string]$Inventory.kind -cne 'MIR4RepositoryInventoryV1') { throw '[mir4-repository-inventory-port-schema]' }
  foreach ($name in @('tracked','untracked','ignored','external','summary','deletion_authorized')) {
    if ($null -eq $Inventory.PSObject.Properties[$name]) { throw "[mir4-repository-inventory-port-field] $name" }
  }
  if ([bool]$Inventory.deletion_authorized) { throw '[mir4-repository-inventory-port-deletion-authority]' }
  return $Inventory
}
