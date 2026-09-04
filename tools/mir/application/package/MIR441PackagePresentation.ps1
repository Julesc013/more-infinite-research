Set-StrictMode -Version Latest

if (-not (Get-Command Get-MIR4ReleaseNarrativeMaterialV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../release/ReleaseNarratives.ps1')
}

function Get-MIR441PackagePresentationFactsV1 {
  [ordered]@{
    f210=[ordered]@{factorio='2.1 experimental';floor='2.1.8';version='4.1.21000';role='current experimental target';extra='The release proof uses the latest installed official Steam experimental build and binds its exact executable. Any engine update requires a fresh API-opportunity review and complete F210 requalification.'}
    f200=[ordered]@{factorio='2.0';floor='2.0.77';version='4.1.20000';role='maintained stable target';extra='The release proof is locked to the governed Factorio 2.0.77 executable. A same-version binary with a different digest is not interchangeable.'}
    f110=[ordered]@{factorio='1.1';floor='1.1';version='4.1.11000';role='supplemental LTS target';extra='This reduced target is qualified independently on Factorio 1.1.110; modern-target evidence is never substituted.'}
    f100=[ordered]@{factorio='1.0';floor='1.0';version='4.1.10000';role='supplemental historical LTS target';extra='This reduced target is qualified independently on Factorio 1.0.0; modern-target evidence is never substituted.'}
  }
}

function Get-MIR441PackageReadmeV1 {
  param([Parameter(Mandatory)]$Fact)
  return @"
# More Infinite Research

More Infinite Research adds configurable infinite productivity and bonus research while rejecting research streams that cannot be generated safely for the active target and mod set.

This package is MIR $($Fact.version), the $($Fact.role) for Factorio $($Fact.factorio). It requires base >= $($Fact.floor).

## What MIR provides

- Configurable infinite productivity and direct-effect research.
- Stable technology identifiers and lossless save migration across supported upgrades.
- Target-aware recipe, science, laboratory, ownership, prerequisite, and maximum-level validation.
- Explicit omission of capabilities that the selected Factorio line cannot implement safely.
- Deterministic packages generated from one canonical source plus governed target overlays.

## Target qualification

$($Fact.extra)

MIR 4.1 changes repository, package, documentation, test, and release authority without adding broad new gameplay semantics. The package is qualified by fresh load, direct 4.0-to-4.1 upgrade, two reloads, governed-state assertions, deterministic reconstruction, and independent verification.

## Configuration

Startup settings control admitted research families, costs, effects, science selection, ownership, and maximum levels. Changing startup settings can reconcile generated technologies when a save reloads. Keep a save backup before changing a large mod set or changing many startup settings together.

## Support

Report issues at https://github.com/Julesc013/more-infinite-research/issues and include the MIR version, exact Factorio version, mod list, startup settings, and relevant log excerpt.
"@.Replace("`r`n","`n")
}

function Get-MIR441PackagePresentationV1 {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('f210','f200','f110','f100')][string]$Target,
    [Parameter(Mandatory)][string]$SourceVersion
  )
  if ($SourceVersion -cne '4.1.0') { throw "[mir441-package-presentation-version] $SourceVersion" }
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $facts=Get-MIR441PackagePresentationFactsV1
  $fact=$facts[$Target]
  $narrative=Get-MIR4ReleaseNarrativeMaterialV1 -RepoRoot $repo -PlanPath 'releases/governance/MIR4-Source-Changelog-PlanV1.json'
  $entry=[string]$narrative.outputs["$Target/changelog.txt"].text
  $baselinePath=Join-Path $repo "targets/$Target/generation/changelog.txt.template"
  $baseline=[IO.File]::ReadAllText($baselinePath).Replace("`r`n","`n")
  if ($baseline -match "(?m)^Version:\s+4[.]1[.]") { throw "[mir441-package-presentation-baseline-mutated] $Target" }
  $readme=Get-MIR441PackageReadmeV1 -Fact $fact
  $changelog=$entry+$baseline
  return [pscustomobject][ordered]@{
    target=$Target;source_version=$SourceVersion;distribution_version=[string]$fact.version
    readme=$readme;changelog=$changelog
    readme_sha256=Get-MIR4Sha256Bytes -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($readme))
    changelog_sha256=Get-MIR4Sha256Bytes -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($changelog))
  }
}

function Write-MIR441PackagePresentationV1 {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('f210','f200','f110','f100')][string]$Target,
    [Parameter(Mandatory)][string]$SourceVersion,
    [Parameter(Mandatory)][string]$PackageRoot
  )
  $presentation=Get-MIR441PackagePresentationV1 -RepoRoot $RepoRoot -Target $Target -SourceVersion $SourceVersion
  $utf8=[Text.UTF8Encoding]::new($false)
  [IO.File]::WriteAllBytes((Join-Path $PackageRoot 'README.md'),$utf8.GetBytes(([string]$presentation.readme)))
  [IO.File]::WriteAllBytes((Join-Path $PackageRoot 'changelog.txt'),$utf8.GetBytes(([string]$presentation.changelog)))
  foreach($name in @('README.md','changelog.txt')){
    $path=Join-Path $PackageRoot $name
    $expected=if($name-ceq'README.md'){[string]$presentation.readme_sha256}else{[string]$presentation.changelog_sha256}
    if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash-cne$expected){throw "[mir441-package-presentation-write] $Target/$name"}
  }
  return $presentation
}
