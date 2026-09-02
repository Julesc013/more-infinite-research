# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
. (Join-Path $repo 'tools/mir/domain/canonicalization/CanonicalJsonV1.ps1')
. (Join-Path $repo 'tools/mir/application/release/ReleaseNarratives.ps1')

function Assert-MIR4NarrativeTestV1([bool]$Condition,[string]$Code,[string]$Detail='') { if (-not $Condition) { throw "[$Code] $Detail" } }

$packageBefore = Get-MIRPackageSourceFingerprint -RepoRoot $repo
$cases = @(
  [ordered]@{plan='fixtures/release/m41-03/plans/historical-4.0.0.json';name='historical-4.0.0';outputs=12;targets=@('F210','F200','F110','F100')},
  [ordered]@{plan='fixtures/release/m41-03/plans/synthetic-f210-patch.json';name='synthetic-patch';outputs=6;targets=@('F210')},
  [ordered]@{plan='fixtures/release/m41-03/plans/synthetic-multi-target-minor.json';name='synthetic-minor';outputs=10;targets=@('F210','F200','F110')}
)

foreach ($case in $cases) {
  $root = "build/results/validation/m41-03/$($case.name)"
  $record = Invoke-MIR4ReleaseNarrativesV1 -RepoRoot $repo -PlanPath $case.plan -OutputRoot $root -Command render
  [void](Invoke-MIR4ReleaseNarrativesV1 -RepoRoot $repo -PlanPath $case.plan -OutputRoot $root -Command check)
  Assert-MIR4NarrativeTestV1 (@($record.outputs).Count -eq $case.outputs) 'mir4-release-narrative-output-count' $case.name
  Assert-MIR4NarrativeTestV1 ((@($record.outputs | Where-Object surface -eq 'factorio-changelog').target -join '|') -ceq ($case.targets -join '|')) 'mir4-release-narrative-target-filter' $case.name
  Assert-MIR4NarrativeTestV1 (@($record.transition_gate.Values | Where-Object { [bool]$_ }).Count -eq 0) 'mir4-release-narrative-firewall' $case.name
  Assert-MIR4NarrativeTestV1 ([string]$record.result_digest -ceq (Get-MIR4ReleaseNarrativeResultDigestV1 -Record $record)) 'mir4-release-narrative-digest' $case.name
}

$historicalRoot = Join-Path $repo 'build/results/validation/m41-03/historical-4.0.0'
$historicalGitHub = [IO.File]::ReadAllText((Join-Path $historicalRoot 'github-release.md'))
Assert-MIR4NarrativeTestV1 ($historicalGitHub -notmatch '(?m)^# ' -and $historicalGitHub -notmatch 'Whole-Platform Genesis|\[[A-Z0-9_]+\]') 'mir4-release-narrative-historical-public-copy'
$historicalSource = [IO.File]::ReadAllText((Join-Path $historicalRoot 'CHANGELOG.md'))
Assert-MIR4NarrativeTestV1 ($historicalSource -notmatch '(?m)^## Unreleased$' -and $historicalSource -match '(?m)^## \[4\.0\.0\] - 2026-08-30$') 'mir4-release-narrative-source-released-view'
foreach ($target in @('f210','f200','f110','f100')) {
  $factorio = [IO.File]::ReadAllText((Join-Path $historicalRoot "$target/changelog.txt"))
  Assert-MIR4NarrativeTestV1 ($factorio -match ('(?m)^' + [regex]::Escape('-' * 99) + '$') -and -not $factorio.Contains("`t")) 'mir4-release-narrative-factorio-grammar' $target
}

$patchRoot = Join-Path $repo 'build/results/validation/m41-03/synthetic-patch'
Assert-MIR4NarrativeTestV1 (-not (Test-Path -LiteralPath (Join-Path $patchRoot 'f200'))) 'mir4-release-narrative-no-unchanged-package'
Assert-MIR4NarrativeTestV1 (([IO.File]::ReadAllText((Join-Path $patchRoot 'CHANGELOG.md'))) -match '(?m)^## Unreleased$') 'mir4-release-narrative-source-unreleased-view'

$minorRoot = Join-Path $repo 'build/results/validation/m41-03/synthetic-minor'
$minorGitHub = [IO.File]::ReadAllText((Join-Path $minorRoot 'github-release.md'))
$minorManifest = [IO.File]::ReadAllText((Join-Path $minorRoot 'release-manifest.json'))
Assert-MIR4NarrativeTestV1 ($minorGitHub -notmatch 'Reorganized synthetic contributor documentation' -and $minorGitHub -notmatch 'sensitive validation boundary|Sensitive reproducer') 'mir4-release-narrative-surface-filtering'
Assert-MIR4NarrativeTestV1 ($minorGitHub -match [regex]::Escape($script:MIR4NarrativeRedaction) -and $minorManifest -match [regex]::Escape($script:MIR4NarrativeRedaction)) 'mir4-release-narrative-security-redaction'
Assert-MIR4NarrativeTestV1 (-not (Test-Path -LiteralPath (Join-Path $minorRoot 'f100'))) 'mir4-release-narrative-no-omitted-package'
Assert-MIR4NarrativeTestV1 (([IO.File]::ReadAllText((Join-Path $minorRoot 'CHANGELOG.md'))) -match 'Reorganized synthetic contributor documentation') 'mir4-release-narrative-repository-source-view'

$facadeRoot = 'build/results/validation/m41-03/facade'
$facade = & (Join-Path $repo 'tools/mir.ps1') mir4 release-narratives render --plan 'fixtures/release/m41-03/plans/synthetic-f210-patch.json' --output $facadeRoot 2>&1 | Out-String
Assert-MIR4NarrativeTestV1 ($facade -match 'MIR4ReleaseNarrativeResultV1') 'mir4-release-narrative-facade'

$sourceProjection = Update-MIR4SourceChangelogV1 -RepoRoot $repo -PlanPath 'releases/governance/MIR4-Source-Changelog-PlanV1.json' -Check
$sourceText = [IO.File]::ReadAllText((Join-Path $repo 'CHANGELOG.md'))
Assert-MIR4NarrativeTestV1 ([string]$sourceProjection.status -ceq 'current' -and $sourceText -match '(?m)^## Unreleased$' -and $sourceText -match '(?m)^## \[4\.0\.0\] - 2026-08-30$') 'mir4-source-changelog-current'
Assert-MIR4NarrativeTestV1 ($sourceText -match 'complete physical and executable foundation') 'mir4-source-changelog-accepted-inventory'
$changelogEol = (& git -C $repo check-attr eol -- CHANGELOG.md 2>&1) -join "`n"
Assert-MIR4NarrativeTestV1 ($LASTEXITCODE -eq 0 -and $changelogEol -cmatch 'CHANGELOG\.md:\s+eol:\s+lf$') 'mir4-source-changelog-eol'

$bad = Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/release/m41-03/changes/synthetic-f210-patch.json') | ConvertFrom-Json -Depth 100
$bad.target_dispositions[0].disposition = 'unknown'
try { Assert-MIR4NarrativeFragmentV1 -Fragment $bad; throw '[mir4-release-narrative-unknown-accepted]' } catch { Assert-MIR4NarrativeTestV1 ($_.Exception.Message -match 'unknown-target') 'mir4-release-narrative-unknown-blocks-freeze' }

$badPlan = Get-Content -Raw -LiteralPath (Join-Path $repo 'fixtures/release/m41-03/plans/synthetic-f210-patch.json') | ConvertFrom-Json -Depth 100
$badPlan.targets[0].package_action = 'unchanged-no-package'
$badPlanPath = Join-Path $repo 'build/results/validation/m41-03/bad-plan.json'
[IO.File]::WriteAllText($badPlanPath,(($badPlan|ConvertTo-Json -Depth 100)+"`n"),[Text.UTF8Encoding]::new($false))
try { Get-MIR4ReleaseNarrativeMaterialV1 -RepoRoot $repo -PlanPath ([IO.Path]::GetRelativePath($repo,$badPlanPath).Replace('\\','/')) | Out-Null; throw '[mir4-release-narrative-affected-target-accepted]' } catch { Assert-MIR4NarrativeTestV1 ($_.Exception.Message -match 'affected-target-without-package') 'mir4-release-narrative-affected-target-requires-package' }

Assert-MIR4NarrativeTestV1 ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -ceq $packageBefore) 'mir4-release-narrative-package-source-delta'
Write-Host '[ok] MIR 4 M41-03 canonical change and release narrative fixed point passed'
