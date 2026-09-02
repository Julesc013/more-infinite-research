# MIR4-CANONICAL-EXECUTABLE-TEST
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/package/GoldenTargetBaselines.ps1')

function Assert-MIR4Golden([bool]$Condition,[string]$Id,[string]$Detail='') {
  if (-not $Condition) { throw "[$Id] $Detail" }
}

$packageBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
$path = Join-Path $repo 'spec/distribution/mir4-golden-four-target-baseline-v1.json'
$schema = Join-Path $repo 'spec/schemas/mir4-golden-four-target-baseline-v1.schema.json'
$record = Write-MIR4GoldenTargetBaseline -RepoRoot $repo -Check
$text = Get-Content -Raw -LiteralPath $path
Assert-MIR4Golden ($text | Test-Json -SchemaFile $schema) 'mir4-golden-schema'
Assert-MIR4Golden (Test-MIR4BootstrapRecordHash -Record ($text | ConvertFrom-Json -Depth 100 -DateKind String)) 'mir4-golden-self-hash'

$expected = [ordered]@{
  f210=@('4.0.21000','38541A7ED0A4181811A1E94231FF58A1268F91E7B89C7CA3D9D5F682242094B1','CA72A8045654FFDC8630D54567F6D04A1B40BA5682ED06E7FACCF2772A2660ED',305)
  f200=@('4.0.20000','5C0E299D78C4EE545958448DAE48D87BE5FE1B959875D4CB93A264D95D3DB0AE','5163E45530CB9B4DAEAC27166279809933750C605BA6E3EC785A0267B9428A1F',303)
  f110=@('4.0.11000','BE63F76255068BAC1BA891B9C9331E4EA943538A37808DFF546E5B1A3ECEB62D','B3DAA35E6E72741D8054C4EC22435CC8216CB6A5E2566D10CF9E3B934E3FF682',174)
  f100=@('4.0.10000','EA495B37C0B91F0728226290CDAEFDF4BBD3C1DBA7D0997AAF5E5107FE79AD3F','1ABDA788DE4B287A48AB0B8787C8F7826256E4ECAB7085C3A6FDDD1E9DF145B2',174)
}
Assert-MIR4Golden (@($record.targets).Count -eq 4) 'mir4-golden-target-count'
foreach ($target in @($record.targets)) {
  $row = $expected[[string]$target.target]
  Assert-MIR4Golden ([string]$target.distribution_version -ceq $row[0]) 'mir4-golden-version' ([string]$target.target)
  Assert-MIR4Golden ([string]$target.archive.sha256 -ceq $row[1]) 'mir4-golden-archive' ([string]$target.target)
  Assert-MIR4Golden ([string]$target.archive.content_sha256 -ceq $row[2]) 'mir4-golden-content' ([string]$target.target)
  Assert-MIR4Golden ([int]$target.archive.entry_count -eq $row[3] -and @($target.entries).Count -eq $row[3]) 'mir4-golden-entries' ([string]$target.target)
  Assert-MIR4Golden (@($target.identity_surface.lifecycle_entrypoints).Count -ge 4) 'mir4-golden-lifecycle' ([string]$target.target)
  Assert-MIR4Golden (@($target.identity_surface.state_namespaces).Count -eq 1) 'mir4-golden-state-namespace' ([string]$target.target)
  Assert-MIR4Golden ([string]$target.runtime_proof.fresh_load_reload_upgrade_replay -ceq 'required-before-package-authority-cutover') 'mir4-golden-runtime-boundary' ([string]$target.target)
  $tracked = & git -C $repo ls-files --error-unmatch -- ([string]$target.archive.path) 2>$null
  Assert-MIR4Golden ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($tracked -join ''))) 'mir4-golden-archive-tracked' ([string]$target.target)
}

$classification = $record.classification
Assert-MIR4Golden (@($classification.common).Count -eq 89) 'mir4-golden-common-count'
Assert-MIR4Golden (@($classification.families.modern).Count -eq 202) 'mir4-golden-modern-count'
Assert-MIR4Golden (@($classification.families.legacy).Count -eq 81) 'mir4-golden-legacy-count'
$overlayCounts = [ordered]@{f210=14;f200=12;f110=4;f100=4}
foreach ($targetKey in $overlayCounts.Keys) {
  Assert-MIR4Golden (@($classification.targets.$targetKey).Count -eq $overlayCounts[$targetKey]) 'mir4-golden-overlay-count' $targetKey
  $family = if ($targetKey -in @('f210','f200')) { @($classification.families.modern) } else { @($classification.families.legacy) }
  $materialized = @($classification.common) + $family + @($classification.targets.$targetKey)
  $baseline = @($record.targets | Where-Object { [string]$_.target -ceq $targetKey })[0]
  Assert-MIR4Golden ($materialized.Count -eq @($baseline.entries).Count) 'mir4-golden-reconstruction-count' $targetKey
  $expectedRows = @($baseline.entries | ForEach-Object { "$($_.path)|$($_.bytes)|$($_.sha256)" } | Sort-Object)
  $actualRows = @($materialized | ForEach-Object { "$($_.path)|$($_.bytes)|$($_.sha256)" } | Sort-Object)
  Assert-MIR4Golden (($expectedRows -join [string][char]10) -ceq ($actualRows -join [string][char]10)) 'mir4-golden-reconstruction-parity' $targetKey
}
Assert-MIR4Golden (@($record.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0) 'mir4-golden-transition-firewall'
Assert-MIR4Golden ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-golden-package-mutation'

[pscustomobject][ordered]@{status='passed';targets=4;common=89;modern_family=202;legacy_family=81;target_overlays=$overlayCounts;record_sha256=[string]$record.record_sha256;package_source_sha256=$packageBefore;package_visible_delta=@();runtime_replay_required=$true;release_transition_authority=$false} | ConvertTo-Json -Depth 10
