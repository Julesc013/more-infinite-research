# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/validation/MIR4DistributionIdentity.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
$assertions = 0
foreach ($code in @('210','200','110','100','017','016','015','014','013')) {
  foreach ($patch in @(0,1)) {
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
foreach ($tag in @('v4.2.0','v4.2.1')) {
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
[pscustomobject]@{status='passed';targets=9;assertions=$assertions;source_4_2_0_suffix='00';source_4_2_1_suffix='01';mismatched_source_patch_rejected=$true;historical_leading_zero_retained=$true;one_time_source_tag_bound=$true} | ConvertTo-Json
