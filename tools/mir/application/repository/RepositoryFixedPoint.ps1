. (Join-Path $PSScriptRoot '../../domain/repository/RepositoryFixedPoint.ps1')
. (Join-Path $PSScriptRoot '../../adapters/repository/GitRepositoryInventory.ps1')
. (Join-Path $PSScriptRoot '../../domain/canonicalization/CanonicalJsonV1.ps1')
. (Join-Path $PSScriptRoot '../../../lib/validation/PackageIdentity.ps1')
. (Join-Path $PSScriptRoot '../../../lib/mir4/PreFreezeRelease.ps1')

function Get-MIR4RepositoryFileSha256V1 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-MIR4RepositoryComponentHashModeV1 {
  param([Parameter(Mandatory)][string]$Path)
  return 'canonical-text-v1'
}

function Get-MIR4RepositoryComponentSha256V1 {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Mode)
  return Get-MIR4PreFreezeFileSha256 -Path $Path -Mode $Mode
}

function Invoke-MIR4RepositoryRootProjection {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authority = Get-MIR4RepositoryFixedPointAuthority -RepoRoot $repo
  foreach ($root in @($authority.visible_roots)) {
    $path = Join-Path $repo (([string]$root.path) + '/.mir-root.json')
    $json = (Get-MIR4RepositoryRootMarker -Root $root | ConvertTo-Json -Depth 20) + "`n"
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json.Replace("`r`n","`n"))
    if ($Check) {
      if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not [Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($path), [byte[]]$bytes)) {
        throw "[mir4-repository-root-projection-stale] $($root.path)"
      }
    } else {
      New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
      [IO.File]::WriteAllBytes($path, $bytes)
    }
  }
}

function Test-MIR4RepositoryCompatibilityForwardersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $contracts = @(
    [ordered]@{path='tools/lib/mir4/RepositoryFixedPoint.ps1';marker='MIR4-REPOSITORY-COMPATIBILITY-LIBRARY';target='mir/application/repository/RepositoryFixedPoint.ps1';max_lines=8},
    [ordered]@{path='tools/commands/mir4/Invoke-MIR4RepositoryFixedPoint.ps1';marker='MIR4-REPOSITORY-COMPATIBILITY-COMMAND';target='tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1';max_lines=16},
    [ordered]@{path='validation/tests/mir4/Test-MIR4RepositoryFixedPointW01.ps1';marker='MIR4-REPOSITORY-COMPATIBILITY-TEST';target='tests/repository/Test-MIR4RepositoryFixedPoint.ps1';max_lines=12}
  )
  foreach ($contract in $contracts) {
    $text = [IO.File]::ReadAllText((Join-Path $repo ([string]$contract.path)))
    if ($text -cnotmatch [regex]::Escape([string]$contract.marker) -or $text.Replace('\','/') -cnotmatch [regex]::Escape([string]$contract.target) -or $text.Split([char]10).Count -gt [int]$contract.max_lines) {
      throw "[mir4-repository-compatibility-forwarder] $($contract.path)"
    }
  }
  $facadeText = [IO.File]::ReadAllText((Join-Path $repo 'tools/mir.ps1')).Replace('\','/')
  $routerText = [IO.File]::ReadAllText((Join-Path $repo 'tools/mir/cli/Invoke-MIRCommandRouter.ps1')).Replace('\','/')
  $dispatcherText = [IO.File]::ReadAllText((Join-Path $repo 'tools/mir/cli/router/CommandDispatcher.ps1')).Replace('\','/')
  $mir4ApplicationText = [IO.File]::ReadAllText((Join-Path $repo 'tools/mir/cli/router/MIR4ApplicationCommands.ps1')).Replace('\','/')
  if ($facadeText -cnotmatch [regex]::Escape('tools/mir/cli/Invoke-MIRCommandRouter.ps1') -or
      $routerText -cnotmatch [regex]::Escape('Invoke-MIRCommandDispatch') -or
      $dispatcherText -cnotmatch [regex]::Escape('Invoke-MIR4CommandDispatch') -or
      $mir4ApplicationText -cnotmatch [regex]::Escape('tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1')) {
    throw '[mir4-repository-cli-canonical-route]'
  }
  return $true
}

$script:MIR4RepositoryMigrationReceiptSha256 = '5B188181285DB7F89E6F0CA91221F9028EEDF212CA62D5BEC2A56D59D3510D26'

function Test-MIR4RepositoryHistoricalMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo $script:MIR4RepositoryMigrationReceiptPath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw '[mir4-repository-migration-receipt-missing]' }
  if ((Get-MIR4RepositoryFileSha256V1 -Path $path) -cne $script:MIR4RepositoryMigrationReceiptSha256) {
    throw '[mir4-repository-migration-receipt-immutable-bytes]'
  }
  if (-not (Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4RepositoryMigrationReceiptPath -SchemaPath $script:MIR4RepositoryMigrationReceiptSchemaPath)) {
    throw '[mir4-repository-migration-receipt-schema]'
  }
  $receipt = Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4RepositoryMigrationReceiptPath
  $digest = Get-MIR4CanonicalDigestV1 -Value $receipt -Domain 'mir4:repository-migration-receipt:1' -OmitTopLevelDigest
  if ([string]$receipt.digest -cne $digest) { throw '[mir4-repository-migration-receipt-digest]' }
  if (@($receipt.release_transition_authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
    throw '[mir4-repository-migration-receipt-release-firewall]'
  }
  return $receipt
}

function Invoke-MIR4RepositoryMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  if (-not $Check) { throw '[mir4-repository-migration-receipt-immutable]' }
  return Test-MIR4RepositoryHistoricalMigrationReceiptV1 -RepoRoot $RepoRoot
}
