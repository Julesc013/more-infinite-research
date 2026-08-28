function Test-MIR4ReleaseDag {
  param([Parameter(Mandatory)]$Dag)
  if ([string]$Dag.kind -cne 'MIR4ReleaseDagV0' -or [int]$Dag.schema -ne 0) { throw '[mir4-release-dag-identity]' }
  $nodes = @($Dag.nodes)
  $ids = @($nodes | ForEach-Object { [string]$_.id })
  if ($ids.Count -ne @($ids | Sort-Object -Unique).Count) { throw '[mir4-release-dag-duplicate-node]' }
  $byId = @{}; foreach ($node in $nodes) { $byId[[string]$node.id] = $node }
  foreach ($node in $nodes) {
    foreach ($dependency in @($node.depends_on | ForEach-Object { [string]$_ } | Where-Object { $_ })) { if (-not $byId.ContainsKey($dependency)) { throw "[mir4-release-dag-missing-dependency] $($node.id):$dependency" } }
    if ([string]$node.mutation -in @('sign','seal','promote','tag','publish','delete') -and [string]$node.authorization -ne 'separate-production-go-no-go') {
      throw "[mir4-release-dag-production-boundary] $($node.id)"
    }
  }
  $visiting = @{}; $visited = @{}
  function Visit-MIR4ReleaseNode([string]$Id) {
    if ($visiting[$Id]) { throw "[mir4-release-dag-cycle] $Id" }
    if ($visited[$Id]) { return }
    $visiting[$Id] = $true
    foreach ($dependency in @($byId[$Id].depends_on | ForEach-Object { [string]$_ } | Where-Object { $_ })) { Visit-MIR4ReleaseNode $dependency }
    $visiting.Remove($Id); $visited[$Id] = $true
  }
  foreach ($id in $ids) { Visit-MIR4ReleaseNode $id }
  return $true
}
