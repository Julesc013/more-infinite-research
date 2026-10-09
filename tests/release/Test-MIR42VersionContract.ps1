# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/validation/MIR4DistributionIdentity.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/TargetMaterializer.ps1')
$assertions = 0
foreach ($code in @('210','200','110','100','017','016','015','014','013')) {
  foreach ($patch in @(0,1,2)) {
    $expected = "4.2.$code$($patch.ToString('D2'))"
    $identity = New-MIR4DistributionIdentityProjection -DistributionTargetCode $code -SourceMinor 2 -SourcePatch $patch -DistributionVersion $expected
    if ($identity.source_version -cne "4.2.$patch" -or $identity.distribution_version -cne $expected -or
        $identity.package_name -cne "more-infinite-research_$expected.zip" -or
        $identity.distribution_tag -cne "dist/f$code/v$expected") { throw "[mir42-version-mapping] $code/$patch" }
    $assertions++
    $decoded = ConvertFrom-MIR4DistributionComponent -EncodedComponentText $identity.encoded_component_text
    if ($decoded.distribution_target_code -cne $code -or $decoded.source_patch -ne $patch) { throw "[mir42-version-roundtrip] $code/$patch" }
    $assertions++
  }
  $rejected = $false
  try { New-MIR4DistributionIdentityProjection -DistributionTargetCode $code -SourceMinor 2 -SourcePatch 0 -DistributionVersion "4.2.${code}01" | Out-Null }
  catch { $rejected = $_.Exception.Message.StartsWith('[mir4-distribution-source-patch]') }
  if (-not $rejected) { throw "[mir42-version-mismatch-accepted] $code" }
  $assertions++
  if ($code -in @('210','200','110','100')) {
    $rejected = $false
    try { Resolve-MIR4CanonicalPackageIdentity -RepoRoot $RepoRoot -Target "f$code" -SourceVersion '4.2.0' -DistributionVersion "4.2.${code}01" | Out-Null }
    catch { $rejected = $_.Exception.Message.StartsWith('[mir4-package-distribution-projection]') }
    if (-not $rejected) { throw "[mir42-materializer-mismatch-accepted] $code" }
    $assertions++
  }
}
foreach ($tag in @('v4.2.0','v4.2.1','v4.2.2')) {
  $manifest=[pscustomobject]@{kind='MIR42FinalReleaseManifestV1';source_tag=$tag}
  if ((Get-MIR4FinalManifestSourceVersion $manifest) -cne $tag.Substring(1)) { throw '[mir42-canonical-source-tag]' }
  $assertions++
}
$stableJson='{"kind":"MIR42FinalReleaseManifestV1","source_tag":"v4.2.0-stable","canonical_source_tag":"v4.2.0","source":{"commit":"6d19c874ea7d026d297865b96aa1b2b0916e9e61"},"source_tag_exception":{"tag":"v4.2.0-stable","scope":"this 4.2.0 publication only","changes_numeric_version":false},"version_contract":{"source_version":"4.2.0","source_patch":0}}'
$stable=$stableJson|ConvertFrom-Json
if ((Get-MIR4FinalManifestSourceVersion $stable) -cne '4.2.0') { throw '[mir42-stable-tag-numeric-version]' }
$assertions++
foreach ($case in @('different-source','different-patch','numeric-exception','future-stable-tag','rc-final-tag','noncanonical-patch')) {
  $probe=$stableJson|ConvertFrom-Json
  switch ($case) {
    'different-source' {$probe.source.commit='0'*40}
    'different-patch' {$probe.version_contract.source_patch=1}
    'numeric-exception' {$probe.source_tag_exception.changes_numeric_version=$true}
    'future-stable-tag' {$probe.source_tag='v4.2.1-stable'}
    'rc-final-tag' {$probe.source_tag='v4.2.0-rc.1'}
    'noncanonical-patch' {$probe.source_tag='v4.2.00'}
  }
  $rejected=$false
  try {Get-MIR4FinalManifestSourceVersion $probe|Out-Null} catch {$rejected=$_.Exception.Message.StartsWith('[mir4-release-source-version]')}
  if (-not $rejected) { throw "[mir42-stable-tag-exception-widened] $case" }
  $assertions++
}
# Exercise the actual package metadata writer with tiny files. Source 4.2.1
# remains the compatibility default; a caller must explicitly request 4.2.2.
$root = Join-Path $RepoRoot ('build/test-results/mir42-version-' + [guid]::NewGuid().ToString('N'))
$utf8 = [Text.UTF8Encoding]::new($false)
$lines = @{'210'='2.1';'200'='2.0';'110'='1.1';'100'='1.0';'017'='0.17';'016'='0.16';'015'='0.15';'014'='0.14';'013'='0.13'}
try {
  foreach ($code in @('210','200','110','100','017','016','015','014','013')) {
    $tree = Join-Path $root $code
    [void](New-Item -ItemType Directory -Force -Path $tree)
    $infoPath = Join-Path $tree 'info.json'
    $historyPath = Join-Path $tree 'changelog.txt'
    $readmePath = Join-Path $tree 'README.md'
    $info = @{name='more-infinite-research';version="4.2.${code}00";factorio_version=$lines[$code];title='Preserved title'}
    $history = "---------------------------------------------------------------------------------------------------`nVersion: 4.2.${code}01`n  Fixes:`n    - Preserved previous maintenance notes.`n"
    $readme = "# Preserved catalogue`n`nSettings, examples and troubleshooting.`n"
    [IO.File]::WriteAllText($infoPath, ($info | ConvertTo-Json), $utf8)
    [IO.File]::WriteAllText($historyPath, $history, $utf8)
    [IO.File]::WriteAllText($readmePath, $readme, $utf8)
    $before = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash | ForEach-Object Hash)
    $rejected = $false
    try { Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion "4.2.${code}02" | Out-Null }
    catch { $rejected = $_.Exception.Message -match 'source-patch' }
    $after = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash | ForEach-Object Hash)
    if (-not $rejected -or ($before -join '|') -cne ($after -join '|')) { throw '[mir422-implicit-patch-change]' }
    $assertions++
    Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion "4.2.${code}02" -SourceVersion '4.2.2'
    $written = Get-Content -Raw -LiteralPath $infoPath | ConvertFrom-Json
    $writtenHistory = [IO.File]::ReadAllText($historyPath)
    if ($written.version -cne "4.2.${code}02" -or $written.title -cne $info.title -or
        -not $writtenHistory.Contains("Version: 4.2.${code}02`n") -or -not $writtenHistory.Contains('source 4.2.2.') -or
        -not $writtenHistory.EndsWith($history, [StringComparison]::Ordinal) -or
        [IO.File]::ReadAllText($readmePath) -cne "MIR 4.2.${code}02, source 4.2.2.`n`n$readme") { throw '[mir422-package-metadata]' }
    $assertions++
    $before = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash | ForEach-Object Hash)
    Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion "4.2.${code}02" -SourceVersion '4.2.2'
    $after = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash | ForEach-Object Hash)
    if (($before -join '|') -cne ($after -join '|')) { throw '[mir422-package-metadata-not-idempotent]' }
    $assertions++
    $rejected = $false
    try { Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion "4.2.${code}01" -SourceVersion '4.2.2' | Out-Null }
    catch { $rejected = $_.Exception.Message -match 'source-patch' }
    $after = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash | ForEach-Object Hash)
    if (-not $rejected -or ($before -join '|') -cne ($after -join '|')) { throw '[mir422-wrong-patch-mutated-input]' }
    $assertions++
  }
} finally {
  if (Test-Path -LiteralPath $root) {
    $resolved = (Resolve-Path -LiteralPath $root).Path
    $null = Assert-MIR4DescendantPath -Root (Join-Path $RepoRoot 'build') -Path $resolved
    $null = Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path $resolved
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}
[pscustomobject]@{status='passed';targets=9;assertions=$assertions;source_4_2_0_suffix='00';source_4_2_1_suffix='01';source_4_2_2_suffix='02';mismatched_source_patch_rejected=$true;historical_leading_zero_retained=$true;one_time_source_tag_bound=$true;factorio_processes=0;candidate_qualification='not-performed'} | ConvertTo-Json
