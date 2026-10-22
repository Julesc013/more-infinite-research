# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$OutputRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$testRoot = ''
$ownedTestRoot = $false
$script:ordinaryCandidateStubSourceVersion = '4.7.0'
$script:ordinaryCandidateStubScope = 'nine-target'
$script:ordinaryCandidateStubTargets = @()
$script:ordinaryCandidateReaderCalls = [Collections.Generic.List[string]]::new()
$checks = 0

function Assert-MIROrdinaryCandidateTest {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if (-not $Condition) { throw "[mir-ordinary-candidate-test-$Code]" }
  $script:checks++
}

function Assert-MIROrdinaryCandidateRefusal {
  param([Parameter(Mandatory)][scriptblock]$Action,[Parameter(Mandatory)][string]$Expected,[Parameter(Mandatory)][string]$Code)
  $actual = ''
  try { & $Action } catch { $actual = [string]$_.Exception.Message }
  Assert-MIROrdinaryCandidateTest -Condition $actual.StartsWith($Expected,[StringComparison]::Ordinal) -Code $Code
}

function Resolve-MIROrdinaryCandidateTestRoot {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$RequestedPath = '',
    [switch]$AllowExisting
  )
  $repoRoot = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
  $allowedRoots = @(
    [IO.Path]::GetFullPath((Join-Path $repoRoot 'build/test-results')).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar),
    [IO.Path]::GetFullPath((Join-Path $repoRoot 'build/tmp')).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
  )
  $requested = if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
    Join-Path $allowedRoots[0] ('mir-ordinary-candidate-' + [guid]::NewGuid().ToString('N'))
  } else { $RequestedPath }
  $full = [IO.Path]::GetFullPath($requested).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
  $contained = $false
  foreach ($allowed in $allowedRoots) {
    if ($full.StartsWith($allowed + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
      $contained = $true
      break
    }
  }
  if (-not $contained) { throw '[mir-ordinary-candidate-test-output-containment]' }

  $ancestor = $full
  while ($true) {
    if (Test-Path -LiteralPath $ancestor) {
      $item = Get-Item -LiteralPath $ancestor -Force
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw '[mir-ordinary-candidate-test-output-reparse]'
      }
    }
    $parent = Split-Path -Parent $ancestor
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $ancestor) { break }
    $ancestor = $parent
  }
  if (-not $AllowExisting -and (Test-Path -LiteralPath $full)) {
    throw '[mir-ordinary-candidate-test-output-existing]'
  }
  return $full
}

function Get-MIR42ExactFourTargetCandidate {
  param([string]$RepoRoot,[string]$CandidateManifestPath,[switch]$AllowCurrentCandidateToolingDescendant)
  if (-not $AllowCurrentCandidateToolingDescendant) { throw '[ordinary-candidate-test-missing-current-descendant-switch]' }
  $script:ordinaryCandidateReaderCalls.Add([string]$CandidateManifestPath)
  return [pscustomobject][ordered]@{
    identity = [pscustomobject][ordered]@{
      path = $CandidateManifestPath
      sha256 = (Get-FileHash -LiteralPath $CandidateManifestPath -Algorithm SHA256).Hash.ToUpperInvariant()
      record = [pscustomobject][ordered]@{ record_sha256 = ('A' * 64) }
    }
    source = [pscustomobject][ordered]@{ commit=('b' * 40);tree=('c' * 40);package_source_sha256=('D' * 64) }
    source_version = $script:ordinaryCandidateStubSourceVersion
    scope = $script:ordinaryCandidateStubScope
    targets = @($script:ordinaryCandidateStubTargets)
  }
}

function Write-MIROrdinaryCandidateTestArchive {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$DistributionVersion,
    [Parameter(Mandatory)][string]$FactorioLine,
    [Parameter(Mandatory)][string]$BaseMinimum,
    [string]$InfoVersion = $DistributionVersion
  )
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
  $zip = [IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Create)
  try {
    $root = 'more-infinite-research_' + $DistributionVersion
    $info = [ordered]@{name='more-infinite-research';version=$InfoVersion;factorio_version=$FactorioLine;dependencies=@('base >= ' + $BaseMinimum)} | ConvertTo-Json -Compress
    foreach ($entryData in @(@{name="$root/info.json";text=$info},@{name="$root/control.lua";text='return true'})) {
      $writer = [IO.StreamWriter]::new($zip.CreateEntry([string]$entryData.name).Open(),[Text.UTF8Encoding]::new($false))
      try { $writer.Write([string]$entryData.text) } finally { $writer.Dispose() }
    }
  } finally { $zip.Dispose() }
}

function New-MIROrdinaryCandidateTestRows {
  param([Parameter(Mandatory)][string]$Root,[string]$F210Minimum='2.1.23')
  $spec = @(
    @{target='f210';line='2.1';minimum=$F210Minimum},@{target='f200';line='2.0';minimum='2.0.77'},
    @{target='f110';line='1.1';minimum='1.1.110'},@{target='f100';line='1.0';minimum='1.0.0'},
    @{target='f017';line='0.17';minimum='0.17.79'},@{target='f016';line='0.16';minimum='0.16.51'},
    @{target='f015';line='0.15';minimum='0.15.40'},@{target='f014';line='0.14';minimum='0.14.23'},
    @{target='f013';line='0.13';minimum='0.13.20'}
  )
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($item in $spec) {
    $distribution = '4.7.' + $item.target.Substring(1) + '00'
    $archive = Join-Path $Root ('more-infinite-research_' + $distribution + '.zip')
    Write-MIROrdinaryCandidateTestArchive -Path $archive -DistributionVersion $distribution -FactorioLine $item.line -BaseMinimum $item.minimum
    $inventory = Get-MIR4ArchiveInventory -Path $archive
    $rows.Add([pscustomobject][ordered]@{
      target=$item.target;distribution_version=$distribution;archive_path=$archive
      archive_sha256=[string]$inventory.archive_sha256;content_sha256=[string]$inventory.content_sha256;entry_count=[int]$inventory.entry_count
    })
  }
  return @($rows.ToArray())
}

try {
  $testRoot = Resolve-MIROrdinaryCandidateTestRoot -RepoRoot $repo -RequestedPath $OutputRoot
  New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop | Out-Null
  $ownedTestRoot = $true
  $candidateManifest = Join-Path $testRoot 'candidate-manifest.json'
  [IO.File]::WriteAllText($candidateManifest, '{"fixture":"ordinary-candidate"}', [Text.UTF8Encoding]::new($false))
  . (Join-Path $repo 'tools/mir/application/release/readiness/OrdinaryCandidate.ps1')

  Assert-MIROrdinaryCandidateRefusal -Action { Resolve-MIROrdinaryCandidateTestRoot -RepoRoot $repo -RequestedPath $repo } -Expected '[mir-ordinary-candidate-test-output-containment]' -Code 'rejects-output-root-outside-private-build-roots'
  $preexisting = Join-Path (Join-Path $repo 'build/test-results') ('mir-ordinary-candidate-existing-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $preexisting -ErrorAction Stop | Out-Null
  try {
    Assert-MIROrdinaryCandidateRefusal -Action { Resolve-MIROrdinaryCandidateTestRoot -RepoRoot $repo -RequestedPath $preexisting } -Expected '[mir-ordinary-candidate-test-output-existing]' -Code 'rejects-preexisting-output-root'
  } finally {
    $safePreexisting = Resolve-MIROrdinaryCandidateTestRoot -RepoRoot $repo -RequestedPath $preexisting -AllowExisting
    Remove-Item -LiteralPath $safePreexisting -Force
  }

  $script:ordinaryCandidateStubTargets = New-MIROrdinaryCandidateTestRows -Root $testRoot
  $valid = Get-MIROrdinaryCandidateAssets -RepoRoot $repo -CandidateManifestPath $candidateManifest
  Assert-MIROrdinaryCandidateTest -Condition ($script:ordinaryCandidateReaderCalls.Count -eq 1 -and $valid.source_version -ceq '4.7.0' -and $valid.assets.Count -eq 9 -and -not $valid.release_authority -and $valid.final_acceptance -ceq 'not-performed') -Code 'valid-current-reader-and-no-release-authority'
  $f210 = @($valid.assets | Where-Object { $_.target -ceq 'f210' })
  $f100 = @($valid.assets | Where-Object { $_.target -ceq 'f100' })
  Assert-MIROrdinaryCandidateTest -Condition ($f210.Count -eq 1 -and $f210[0].base_minimum -ceq '2.1.23' -and $f210[0].label -ceq 'MIR 4.7.0 for Factorio 2.1.23' -and $f100.Count -eq 1 -and $f100[0].base_minimum -ceq '1.0.0' -and $f100[0].label -ceq 'MIR 4.7.0 for Factorio 1.0.0') -Code 'patch-minimum-labels-read-from-zip-metadata'

  $script:ordinaryCandidateStubSourceVersion = '4.6.0'
  Assert-MIROrdinaryCandidateRefusal -Action { Get-MIROrdinaryCandidateAssets -RepoRoot $repo -CandidateManifestPath $candidateManifest } -Expected '[mir-ordinary-candidate-source-version]' -Code 'rejects-derived-wrong-source-version'
  $script:ordinaryCandidateStubSourceVersion = '4.7.0'

  $script:ordinaryCandidateStubTargets = @($script:ordinaryCandidateStubTargets[0..7])
  Assert-MIROrdinaryCandidateRefusal -Action { Get-MIROrdinaryCandidateAssets -RepoRoot $repo -CandidateManifestPath $candidateManifest } -Expected '[mir-ordinary-candidate-target-set]' -Code 'rejects-incomplete-target-set'

  $script:ordinaryCandidateStubTargets = New-MIROrdinaryCandidateTestRows -Root $testRoot
  $changed = @($script:ordinaryCandidateStubTargets | Where-Object { $_.target -ceq 'f210' })[0]
  Write-MIROrdinaryCandidateTestArchive -Path $changed.archive_path -DistributionVersion $changed.distribution_version -FactorioLine '2.1' -BaseMinimum '2.1.23' -InfoVersion '4.7.21001'
  Assert-MIROrdinaryCandidateRefusal -Action { Get-MIROrdinaryCandidateAssets -RepoRoot $repo -CandidateManifestPath $candidateManifest } -Expected '[mir-ordinary-candidate-asset-identity] f210' -Code 'rejects-changed-archive-after-reader-binding'

  $script:ordinaryCandidateStubTargets = New-MIROrdinaryCandidateTestRows -Root $testRoot
  $metadataChanged = @($script:ordinaryCandidateStubTargets | ForEach-Object { $_ | Select-Object * })
  $metadataChanged[1].distribution_version = '4.7.20001'
  $script:ordinaryCandidateStubTargets = $metadataChanged
  Assert-MIROrdinaryCandidateRefusal -Action { Get-MIROrdinaryCandidateAssets -RepoRoot $repo -CandidateManifestPath $candidateManifest } -Expected '[mir-ordinary-candidate-info-identity] f200' -Code 'rejects-metadata-binding-drift'

  $script:ordinaryCandidateStubTargets = New-MIROrdinaryCandidateTestRows -Root $testRoot -F210Minimum '2.1'
  Assert-MIROrdinaryCandidateRefusal -Action { Get-MIROrdinaryCandidateAssets -RepoRoot $repo -CandidateManifestPath $candidateManifest } -Expected '[mir-ordinary-candidate-base-minimum] f210' -Code 'requires-patch-minimum-from-actual-metadata'

  [pscustomobject][ordered]@{
    kind='MIROrdinaryCandidateControlsV1'
    status='passed'
    assertions=$script:checks
    scope='synthetic archive and exact-reader boundary only; no real candidate, native, acceptance, or release authority'
  } | ConvertTo-Json -Depth 10
} finally {
  if ($ownedTestRoot -and -not [string]::IsNullOrWhiteSpace($testRoot) -and (Test-Path -LiteralPath $testRoot)) {
    $safeTestRoot = Resolve-MIROrdinaryCandidateTestRoot -RepoRoot $repo -RequestedPath $testRoot -AllowExisting
    Remove-Item -LiteralPath $safeTestRoot -Recurse -Force
  }
}
