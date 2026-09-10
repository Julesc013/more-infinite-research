# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')

$recordRelative = 'spec/programmes/evidence/synthesis-2026-09-10/a02-component-reconciliation.json'
$proofRelative = 'spec/programmes/evidence/synthesis-2026-09-10/a02-current-source-materializer-proof.json'
$schemaPath = Join-Path $repo 'spec/schemas/mir4-a02-component-reconciliation-v1.schema.json'
$stableCommit = 'f458598732e9583a9d086032ebfbe9ffb747d130'
$retainedCommit = '3683369ba00cfbdd7f8872a5a1b24f0d59f31062'

function Stop-A02Test {
  param([bool]$Condition, [string]$Code)
  if (-not $Condition) { throw "[$Code]" }
}

function Invoke-A02TestGit {
  param([Parameter(Mandatory)][string[]]$Arguments)
  $result = @(& git -C $repo @Arguments)
  if ($LASTEXITCODE -ne 0) { throw "[mir4-a02-test-git] $($Arguments -join ' ')" }
  return $result
}

function Get-A02TestBlob {
  param([string]$Commit, [string]$Path)
  return [string](@(Invoke-A02TestGit -Arguments @('rev-parse', "$Commit`:$Path"))[0])
}

function ConvertTo-A02Clone {
  param($Value)
  return (($Value | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100 -DateKind String)
}

function Test-A02RecordContract {
  param([Parameter(Mandatory)]$Record)
  $json = $Record | ConvertTo-Json -Depth 100
  Stop-A02Test ($json | Test-Json -SchemaFile $schemaPath) 'mir4-a02-schema'
  Stop-A02Test (Test-MIR4BootstrapRecordHash -Record $Record) 'mir4-a02-selfhash'

  $delivery = Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/programmes/inputs/synthesis-2026-09-05/COMPONENT_DELIVERY.json') | ConvertFrom-Json -Depth 100 -DateKind String
  $expectedIds = @($delivery.components | ForEach-Object { [string]$_.id })
  $actualIds = @($Record.components | ForEach-Object { [string]$_.id })
  Stop-A02Test ($actualIds.Count -eq 34 -and @($actualIds | Sort-Object -Unique).Count -eq 34) 'mir4-a02-component-cardinality'
  Stop-A02Test ((@($actualIds | Sort-Object) -join '|') -ceq (@($expectedIds | Sort-Object) -join '|')) 'mir4-a02-unknown-or-missing-component'
  Stop-A02Test ((@($Record.component_inventory.ids | Sort-Object) -join '|') -ceq (@($expectedIds | Sort-Object) -join '|')) 'mir4-a02-unbound-inventory'

  $proofPath = Join-Path $repo $proofRelative
  $proofRaw = Get-Content -Raw -LiteralPath $proofPath
  $proof = $proofRaw | ConvertFrom-Json -Depth 100 -DateKind String
  Stop-A02Test ($proofRaw | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-current-source-materializer-proof-v1.schema.json')) 'mir4-a02-proof-schema'
  Stop-A02Test (Test-MIR4BootstrapRecordHash -Record $proof) 'mir4-a02-proof-selfhash'
  Stop-A02Test ([string]$Record.materializer_proof.record_sha256 -ceq [string]$proof.record_sha256) 'mir4-a02-proof-binding'
  $proofTargets = @($proof.targets | Sort-Object target)
  Stop-A02Test ($proofTargets.Count -eq 4 -and (@($proofTargets.target) -join '|') -ceq 'f100|f110|f200|f210') 'mir4-a02-proof-targets'

  $manifest = Get-Content -Raw -LiteralPath (Join-Path $repo 'src/mod/package-source.json') | ConvertFrom-Json -Depth 100 -DateKind String
  $sourcePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($binding in @($manifest.bindings)) { [void]$sourcePaths.Add([string]$binding.source_path) }
  foreach ($component in @($Record.components)) {
    Stop-A02Test (@($component.canonical_owned_paths).Count -gt 0) 'mir4-a02-unbound-component'
    Stop-A02Test ([bool]$component.assessment.assessed -and [bool]$component.assessment.complete -and -not [bool]$component.assessment.unresolved) 'mir4-a02-not-assessed-complete'
    Stop-A02Test (-not [bool]$component.admitted_by_this_review -and -not [bool]$component.graduated -and -not [bool]$component.player_authority -and -not [bool]$component.package_trace.player_authority) 'mir4-a02-graduation'
    foreach ($owned in @($component.canonical_owned_paths)) {
      Stop-A02Test ([string]$owned.path -match '^[A-Za-z0-9._/-]+$' -and [string]$owned.path -notmatch '(^|/)\.\.(/|$)') 'mir4-a02-owned-path-shape'
      Stop-A02Test ([string]$owned.stable_blob -ceq (Get-A02TestBlob -Commit $stableCommit -Path ([string]$owned.path))) 'mir4-a02-stable-blob'
      Stop-A02Test ([string]$owned.retained_blob -ceq (Get-A02TestBlob -Commit $retainedCommit -Path ([string]$owned.path))) 'mir4-a02-retained-blob'
      Stop-A02Test ([string]$owned.stable_blob -ceq [string]$owned.retained_blob -and [string]$owned.retained_delta -ceq 'unchanged') 'mir4-a02-cross-branch-blob-mismatch'
      Stop-A02Test (-not $sourcePaths.Contains([string]$owned.path)) 'mir4-a02-package-exclusion'
    }
    $excluded = @($component.package_trace.excluded_owned_paths | Sort-Object)
    $owned = @($component.canonical_owned_paths | ForEach-Object { [string]$_.path } | Sort-Object)
    Stop-A02Test (($excluded -join '|') -ceq ($owned -join '|')) 'mir4-a02-exclusion-trace'
    Stop-A02Test ([string]$component.cross_branch_delta.status -ceq 'unchanged' -and [int]$component.cross_branch_delta.compared_owned_path_count -eq $owned.Count -and [int]$component.cross_branch_delta.changed_owned_path_count -eq 0 -and [string]$component.semantic_disposition -ceq 'unchanged') 'mir4-a02-semantic-disposition'
    if ([string]$component.package_trace.mode -ceq 'package-excluded-governs-source-overlay-zip') {
      Stop-A02Test ((@($component.package_trace.target_overlays | Sort-Object) -join '|') -ceq 'targets/f100/overlay.json|targets/f110/overlay.json|targets/f200/overlay.json|targets/f210/overlay.json') 'mir4-a02-overlay-trace'
      Stop-A02Test ([string]$component.package_trace.source_manifest -ceq 'src/mod/package-source.json' -and [string]$component.package_trace.materializer_proof -ceq $proofRelative) 'mir4-a02-governor-flow-binding'
      Stop-A02Test ((@($component.package_trace.target_archives.target | Sort-Object) -join '|') -ceq 'f100|f110|f200|f210') 'mir4-a02-zip-trace'
      foreach ($archive in @($component.package_trace.target_archives)) {
        $match = @($proofTargets | Where-Object { [string]$_.target -ceq [string]$archive.target })
        Stop-A02Test ($match.Count -eq 1 -and [string]$archive.archive_sha256 -ceq [string]$match[0].archive_a -and [string]$archive.content_sha256 -ceq [string]$match[0].content_sha256 -and [int]$archive.entry_count -eq [int]$match[0].entry_count) 'mir4-a02-zip-proof-binding'
      }
    } elseif ([string]$component.package_trace.mode -ceq 'package-excluded') {
    } else { throw '[mir4-a02-trace-mode]' }
  }
  Stop-A02Test ([bool]$Record.authorities.all_components_assessed) 'mir4-a02-global-assessment'
  foreach ($name in @('blanket_graduation','player_mutation_authorized','prototype_write_authorized','setting_mutation_authorized','persistent_state_mutation_authorized','migration_authorized','public_support_claim_authorized','release_authority','publication_authorized')) {
    Stop-A02Test (-not [bool]$Record.authorities.$name) 'mir4-a02-global-graduation'
  }
}

function Assert-A02RejectedMutation {
  param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Mutate, [Parameter(Mandatory)]$Source)
  $candidate = ConvertTo-A02Clone -Value $Source
  & $Mutate $candidate
  $candidate.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $candidate
  $rejected = $false
  try { Test-A02RecordContract -Record $candidate }
  catch { $rejected = $true }
  Stop-A02Test $rejected "mir4-a02-negative-$Name"
}

$recordPath = Join-Path $repo $recordRelative
$recordRaw = Get-Content -Raw -LiteralPath $recordPath
$record = $recordRaw | ConvertFrom-Json -Depth 100 -DateKind String
Test-A02RecordContract -Record $record

Assert-A02RejectedMutation -Name 'unknown-component' -Source $record -Mutate { param($r) $r.components[0].id = 'unknown-component' }
Assert-A02RejectedMutation -Name 'duplicate-component' -Source $record -Mutate { param($r) $r.components[1].id = [string]$r.components[0].id }
Assert-A02RejectedMutation -Name 'missing-component' -Source $record -Mutate { param($r) $r.components = @($r.components | Select-Object -Skip 1) }
Assert-A02RejectedMutation -Name 'unbound-component' -Source $record -Mutate { param($r) $r.components[0].canonical_owned_paths = @() }
Assert-A02RejectedMutation -Name 'not-assessed-complete' -Source $record -Mutate { param($r) $r.components[0].assessment.assessed = $false }
Assert-A02RejectedMutation -Name 'graduation' -Source $record -Mutate { param($r) $r.components[0].graduated = $true }
Assert-A02RejectedMutation -Name 'fake-direct-package-inclusion' -Source $record -Mutate {
  param($r)
  $governor = @($r.components | Where-Object { [string]$_.package_trace.mode -ceq 'package-excluded-governs-source-overlay-zip' })[0]
  $governor.package_trace = [pscustomobject][ordered]@{
    mode = 'source-overlay-zip'
    source_manifest = 'src/mod/package-source.json'
    target_overlays = @('targets/f210/overlay.json','targets/f200/overlay.json','targets/f110/overlay.json','targets/f100/overlay.json')
    materializer_proof = $proofRelative
    target_archives = @($governor.package_trace.target_archives)
    player_authority = $false
  }
}
Assert-A02RejectedMutation -Name 'altered-retained-blob' -Source $record -Mutate { param($r) $r.components[0].canonical_owned_paths[0].retained_blob = ('0' * 40) }
Assert-A02RejectedMutation -Name 'semantic-disposition-mismatch' -Source $record -Mutate { param($r) $r.components[0].semantic_disposition = 'changed' }

# The verifier must not regenerate the materializer proof or overwrite the
# append-only reconciliation record. Capture both tracked projections around
# -Check so a future writer regression is observable here.
$beforeRecord = [IO.File]::ReadAllText($recordPath)
$beforeProof = [IO.File]::ReadAllText((Join-Path $repo $proofRelative))
& (Join-Path $repo 'tools/commands/mir4/Write-MIR4A02Reconciliation.ps1') -RepoRoot $repo -Check | Out-Null
Stop-A02Test ($beforeRecord -ceq [IO.File]::ReadAllText($recordPath) -and $beforeProof -ceq [IO.File]::ReadAllText((Join-Path $repo $proofRelative))) 'mir4-a02-check-wrote-evidence'

Write-Output 'MIR4 A02 reconciles all 34 retained components with immutable blob, route/exclusion, and non-graduation evidence.'
