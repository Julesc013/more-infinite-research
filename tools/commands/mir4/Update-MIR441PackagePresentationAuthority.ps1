[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [switch]$Check
)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/mir/application/release/ReleaseNarratives.ps1')

$narrative = Get-MIR4ReleaseNarrativeMaterialV1 -RepoRoot $repo -PlanPath 'releases/governance/MIR4-Source-Changelog-PlanV1.json'

$targetFacts=[ordered]@{
  f210=[ordered]@{factorio='2.1 experimental';floor='2.1.8';version='4.1.21000';role='current experimental target';extra='The release proof uses the latest installed official Steam experimental build and binds its exact executable. Any engine update requires a fresh API-opportunity review and complete F210 requalification.'}
  f200=[ordered]@{factorio='2.0';floor='2.0.77';version='4.1.20000';role='maintained stable target';extra='The release proof is locked to the governed Factorio 2.0.77 executable. A same-version binary with a different digest is not interchangeable.'}
  f110=[ordered]@{factorio='1.1';floor='1.1';version='4.1.11000';role='supplemental LTS target';extra='This reduced target is qualified independently on Factorio 1.1.110; modern-target evidence is never substituted.'}
  f100=[ordered]@{factorio='1.0';floor='1.0';version='4.1.10000';role='supplemental historical LTS target';extra='This reduced target is qualified independently on Factorio 1.0.0; modern-target evidence is never substituted.'}
}

function Get-MIR441PackageReadme([string]$Target,$Fact){
  @"
# More Infinite Research

More Infinite Research adds configurable infinite productivity and bonus research while rejecting research streams that cannot be generated safely for the active target and mod set.

This package is MIR $($Fact.version), the $($Fact.role) for Factorio $($Fact.factorio). It requires `base >= $($Fact.floor)`.

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

$manifestPath=Join-Path $repo 'src/mod/package-source.json'
$manifest=Get-Content -Raw -LiteralPath $manifestPath|ConvertFrom-Json -Depth 100 -DateKind String
foreach($target in $targetFacts.Keys){
  $fact=$targetFacts[$target]
  $readmePath=Join-Path $repo "targets/$target/generation/README.md.template"
  $changelogPath=Join-Path $repo "targets/$target/generation/changelog.txt.template"
  $readme=Get-MIR441PackageReadme -Target $target -Fact $fact
  $currentChangelog=[IO.File]::ReadAllText($changelogPath).Replace("`r`n","`n")
  $entry=[string]$narrative.outputs["$target/changelog.txt"].text
  $currentPrefix="---------------------------------------------------------------------------------------------------`nVersion: $($fact.version)`n"
  if($currentChangelog.StartsWith($currentPrefix,[StringComparison]::Ordinal)){
    $marker="---------------------------------------------------------------------------------------------------`n"
    $next=$currentChangelog.IndexOf($marker,$marker.Length,[StringComparison]::Ordinal)
    if($next-lt0){throw "[mir441-package-changelog-history] $target"}
    $expectedChangelog=$entry+$currentChangelog.Substring($next)
  }else{$expectedChangelog=$entry+$currentChangelog}
  if($Check){
    if([IO.File]::ReadAllText($readmePath).Replace("`r`n","`n")-cne$readme){throw "[mir441-package-readme-stale] $target"}
    if($currentChangelog-cne$expectedChangelog){throw "[mir441-package-changelog-stale] $target"}
  }else{
    [IO.File]::WriteAllText($readmePath,$readme,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($changelogPath,$expectedChangelog,[Text.UTF8Encoding]::new($false))
  }
  foreach($name in @('README.md','changelog.txt')){
    $sourcePath="targets/$target/generation/$name.template"
    $full=Join-Path $repo $sourcePath
    $item=Get-Item -LiteralPath $full;$hash=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()
    $bindings=@($manifest.bindings|Where-Object{[string]$_.source_path-ceq$sourcePath-and[string]$_.output_path-ceq$name})
    if($bindings.Count-ne1){throw "[mir441-package-binding] $sourcePath"}
    $binding=$bindings[0]
    if($Check){if([int64]$binding.source_bytes-ne$item.Length-or[string]$binding.source_sha256-cne$hash-or[int64]$binding.output_bytes-ne$item.Length-or[string]$binding.output_sha256-cne$hash){throw "[mir441-package-binding-stale] $sourcePath"}}
    else{$binding.source_bytes=[int64]$item.Length;$binding.source_sha256=$hash;$binding.output_bytes=[int64]$item.Length;$binding.output_sha256=$hash}
    $overlayPath=Join-Path $repo "targets/$target/overlay.json";$overlay=Get-Content -Raw -LiteralPath $overlayPath|ConvertFrom-Json -Depth 100 -DateKind String
    $operations=@($overlay.operations|Where-Object{[string]$_.source_path-ceq$sourcePath-and[string]$_.path-ceq$name})
    if($operations.Count-ne1){throw "[mir441-package-overlay-operation] $sourcePath"}
    if($Check){if([int64]$operations[0].expected_bytes-ne$item.Length-or[string]$operations[0].expected_sha256-cne$hash){throw "[mir441-package-overlay-stale] $sourcePath"}}
    else{
      $operations[0].expected_bytes=[int64]$item.Length;$operations[0].expected_sha256=$hash
      $overlay.record_sha256='';$overlay.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $overlay
      [IO.File]::WriteAllText($overlayPath,(($overlay|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n"),[Text.UTF8Encoding]::new($false))
    }
  }
}

if(-not$Check){
  $manifest.record_sha256='';$manifest.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $manifest
  [IO.File]::WriteAllText($manifestPath,(($manifest|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n"),[Text.UTF8Encoding]::new($false))
  $authorityPath=Join-Path $repo 'targets/package-authority.json';$authority=Get-Content -Raw -LiteralPath $authorityPath|ConvertFrom-Json -Depth 100 -DateKind String
  $authority.source_manifest.record_sha256=[string]$manifest.record_sha256;$authority.record_sha256='';$authority.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $authority
  [IO.File]::WriteAllText($authorityPath,(($authority|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n"),[Text.UTF8Encoding]::new($false))
}

if($Check){
  $stored=Get-Content -Raw -LiteralPath $manifestPath|ConvertFrom-Json -Depth 100 -DateKind String
  if(-not(Test-MIR4BootstrapRecordHash -Record $stored)){throw '[mir441-package-manifest-hash]'}
  foreach($target in $targetFacts.Keys){$overlay=Get-Content -Raw -LiteralPath (Join-Path $repo "targets/$target/overlay.json")|ConvertFrom-Json -Depth 100 -DateKind String;if(-not(Test-MIR4BootstrapRecordHash -Record $overlay)){throw "[mir441-package-overlay-hash] $target"}}
  $authority=Get-Content -Raw -LiteralPath (Join-Path $repo 'targets/package-authority.json')|ConvertFrom-Json -Depth 100 -DateKind String
  if(-not(Test-MIR4BootstrapRecordHash -Record $authority)-or[string]$authority.source_manifest.record_sha256-cne[string]$stored.record_sha256){throw '[mir441-package-authority-hash]'}
}

[pscustomobject][ordered]@{status='MIR-4.1-PACKAGE-PRESENTATION-AUTHORITY-PASSED';targets=@($targetFacts.Keys);check=[bool]$Check;publication_authorized=$false}
