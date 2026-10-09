# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/mir/domain/canonicalization/CanonicalJsonV1.ps1')
. (Join-Path $repo 'tools/mir/application/release/ReleaseNarratives.ps1')

function Assert-MIR42NarrativeTest([bool]$Condition, [string]$Code) {
  if (-not $Condition) { throw "[$Code]" }
}

$planPath = 'fixtures/release/m42-nine-narratives/plans/synthetic-nine-target.json'
$outputRoot = 'build/results/validation/m42-nine-narratives/synthetic-nine-target'
$packageBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
$record = Invoke-MIR4ReleaseNarrativesV1 -RepoRoot $repo -PlanPath $planPath -OutputRoot $outputRoot -Command render
[void](Invoke-MIR4ReleaseNarrativesV1 -RepoRoot $repo -PlanPath $planPath -OutputRoot $outputRoot -Command check)
$targets = @(Get-MIR4NarrativeTargetsV2)

Assert-MIR42NarrativeTest ([int]$record.schema -eq 2 -and [string]$record.kind -ceq 'MIR4ReleaseNarrativeResultV2' -and [string]$record.renderer_abi -ceq (Get-MIR4NarrativeAbiV2)) 'mir42-narrative-result-contract'
Assert-MIR42NarrativeTest (@($record.outputs).Count -eq 22) 'mir42-narrative-output-count'
Assert-MIR42NarrativeTest ((@($record.outputs | Where-Object surface -eq 'factorio-changelog').target -join '|') -ceq ($targets -join '|')) 'mir42-narrative-target-order'
Assert-MIR42NarrativeTest ((@($record.outputs | Where-Object surface -eq 'mod-portal').target -join '|') -ceq ($targets -join '|')) 'mir42-narrative-portal-target-order'
Assert-MIR42NarrativeTest (@($record.transition_gate.Values | Where-Object { [bool]$_ }).Count -eq 0) 'mir42-narrative-transition-firewall'
Assert-MIR42NarrativeTest ([string]$record.result_digest -ceq (Get-MIR4ReleaseNarrativeResultDigestV1 -Record $record)) 'mir42-narrative-result-digest'
foreach ($target in $targets) {
  $folder = $target.ToLowerInvariant()
  $changelog = [IO.File]::ReadAllText((Join-Path $repo "$outputRoot/$folder/changelog.txt"))
  $portal = [IO.File]::ReadAllText((Join-Path $repo "$outputRoot/$folder/mod-portal.md"))
  Assert-MIR42NarrativeTest ($changelog.Contains('synthetic nine-target release narrative coverage') -and $portal.Contains('synthetic nine-target release narrative coverage')) "mir42-narrative-target-copy-$target"
}

$fragment = Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/release/m42-nine-narratives/changes/synthetic-nine-target.json') | ConvertFrom-Json -Depth 100
$fragment.target_dispositions[8].disposition = 'unknown'
try { Assert-MIR4NarrativeFragmentV1 -Fragment $fragment -TargetSet $targets; throw '[mir42-narrative-unknown-accepted]' }
catch { Assert-MIR42NarrativeTest ($_.Exception.Message -match 'unknown-target') 'mir42-narrative-unknown-rejected' }
$fragment.target_dispositions[8].disposition = 'affected'
$fragment.target_dispositions[8].target = 'F014'
try { Assert-MIR4NarrativeFragmentV1 -Fragment $fragment -TargetSet $targets; throw '[mir42-narrative-duplicate-accepted]' }
catch { Assert-MIR42NarrativeTest ($_.Exception.Message -match 'target-closure') 'mir42-narrative-duplicate-rejected' }

$plan = Get-Content -Raw -LiteralPath (Join-Path $repo $planPath) | ConvertFrom-Json -Depth 100
$plan.targets[8].factorio_line = '0.14'
$badPlanPath = Join-Path $repo 'build/results/validation/m42-nine-narratives/bad-plan.json'
[void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $badPlanPath))
[IO.File]::WriteAllText($badPlanPath, (($plan | ConvertTo-Json -Depth 100) + "`n"), [Text.UTF8Encoding]::new($false))
try { Get-MIR4ReleaseNarrativeMaterialV1 -RepoRoot $repo -PlanPath ([IO.Path]::GetRelativePath($repo, $badPlanPath).Replace('\', '/')) | Out-Null; throw '[mir42-narrative-wrong-line-accepted]' }
catch { Assert-MIR42NarrativeTest ($_.Exception.Message -match 'nine-target-order') 'mir42-narrative-wrong-line-rejected' }

Assert-MIR42NarrativeTest ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir42-narrative-package-source-delta'
Write-Host '[ok] MIR 4.2 nine-target release narrative rendering passed'
