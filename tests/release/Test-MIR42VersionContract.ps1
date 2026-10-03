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
[pscustomobject]@{status='passed';targets=9;assertions=$assertions;source_4_2_0_suffix='00';source_4_2_1_suffix='01';mismatched_source_patch_rejected=$true;historical_leading_zero_retained=$true} | ConvertTo-Json
