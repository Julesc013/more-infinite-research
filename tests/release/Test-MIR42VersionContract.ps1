# MIR4-CANONICAL-EXECUTABLE-TEST
[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path)
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/validation/MIR4DistributionIdentity.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/TargetMaterializer.ps1')
$assertions = 0
# Every editable target keeps the published MIR 4 history, independently of
# the current package identity writer. A new release must not drop it again.
foreach ($code in @('210','200','110','100','017','016','015','014','013')) {
  $presentation = if ($code -cin @('210','200','110','100')) { "source/presentation/f$code" } else { "source/presentation/historical/f$code" }
  $historyText = [IO.File]::ReadAllText((Join-Path $RepoRoot "$presentation/changelog.txt.template"))
  $versions = @([regex]::Matches($historyText, '(?m)^Version:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })
  foreach ($release in @(@(5,2),@(5,1),@(5,0),@(4,2),@(4,1),@(4,0),@(3,0))) {
    $expectedVersion = '4.' + $release[0] + '.' + $code + ([int]$release[1]).ToString('D2')
    if (@($versions | Where-Object { $_ -ceq $expectedVersion }).Count -ne 1) { throw "[mir460-published-history-missing-or-duplicated] $expectedVersion" }
    $assertions++
  }
  $mir4Versions = @($versions | Where-Object { $_.StartsWith('4.', [StringComparison]::Ordinal) })
  $sortedMir4Versions = @($mir4Versions | Sort-Object { [version]$_ } -Descending)
  if (($mir4Versions -join '|') -cne ($sortedMir4Versions -join '|')) { throw "[mir460-published-history-order] f$code" }
  if (@($historyText -split '\r?\n' | Where-Object Length -gt 132).Count) { throw "[mir460-published-history-width] f$code" }
  $assertions += 2
}
foreach ($code in @('210','200','110','100','017','016','015','014','013')) {
  foreach ($patch in @(0,1,2,3)) {
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
foreach ($tag in @('v4.2.0','v4.2.1','v4.2.2','v4.2.3')) {
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
# These are the accepted minimums for the existing 4.6.0 target families.
# They make this host-only writer control realistic; they do not establish a
# native engine qualification.
$minimumBaseVersions = @{'210'='2.1.21';'200'='2.0.77';'110'='1.1.110';'100'='1.0.0';'017'='0.17.79';'016'='0.16.51';'015'='0.15.40';'014'='0.14.23';'013'='0.13.20'}
try {
  foreach ($code in @('210','200','110','100','017','016','015','014','013')) {
    $tree = Join-Path $root $code
    [void](New-Item -ItemType Directory -Force -Path $tree)
    $infoPath = Join-Path $tree 'info.json'
    $historyPath = Join-Path $tree 'changelog.txt'
    $readmePath = Join-Path $tree 'README.md'
    $info = @{name='more-infinite-research';version="4.2.${code}00";factorio_version=$lines[$code];dependencies=@("base >= $($minimumBaseVersions[$code])");title='Preserved title'}
    $history = "---------------------------------------------------------------------------------------------------`nVersion: 4.2.${code}01`n  Fixes:`n    - Preserved previous maintenance notes.`n"
    $readme = "# Preserved catalogue`n`nSettings, examples and troubleshooting.`n"
    [IO.File]::WriteAllText($infoPath, ($info | ConvertTo-Json), $utf8)
    [IO.File]::WriteAllText($historyPath, $history, $utf8)
    [IO.File]::WriteAllText($readmePath, $readme, $utf8)
    $before = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash | ForEach-Object Hash)
    $rejected = $false
    try { Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion "4.2.${code}02" | Out-Null }
    catch { $rejected = $_.Exception.Message -match 'source-identity' }
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
    catch { $rejected = $_.Exception.Message -match 'source-identity' }
    $after = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash | ForEach-Object Hash)
    if (-not $rejected -or ($before -join '|') -cne ($after -join '|')) { throw '[mir422-wrong-patch-mutated-input]' }
    $assertions++
    # Source 4.2.3 is a separate exact identity, never an increment of an
    # already rewritten private tree.
    $info.version="4.2.${code}00"
    [IO.File]::WriteAllText($infoPath, ($info | ConvertTo-Json), $utf8)
    [IO.File]::WriteAllText($historyPath, $history, $utf8)
    [IO.File]::WriteAllText($readmePath, $readme, $utf8)
    Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion "4.2.${code}03" -SourceVersion '4.2.3'
    $written = Get-Content -Raw -LiteralPath $infoPath | ConvertFrom-Json
    $writtenHistory = [IO.File]::ReadAllText($historyPath)
    if ($written.version -cne "4.2.${code}03" -or
        -not $writtenHistory.Contains("Version: 4.2.${code}03`n") -or -not $writtenHistory.Contains('source 4.2.3.') -or
        [IO.File]::ReadAllText($readmePath) -cne "MIR 4.2.${code}03, source 4.2.3.`n`n$readme") { throw '[mir423-package-metadata]' }
    $assertions++
    # Source 4.5.0 starts a new minor baseline.  The same authoritative writer
    # must update all public package-identity surfaces while refusing an
    # incompatible source-patch component before it can mutate the tree.
    $source450Baseline = "4.5.${code}00"
    $source450Version = "4.5.${code}00"
    $source450WrongPatch = "4.5.${code}01"
    $source450PriorVersion = "4.4.${code}02"
    $source450History = "---------------------------------------------------------------------------------------------------`nVersion: $source450PriorVersion`n  Changes:`n    - Preserved source-4.4 maintenance entry.`n"
    $info.version = $source450Baseline
    [IO.File]::WriteAllText($infoPath, ($info | ConvertTo-Json), $utf8)
    [IO.File]::WriteAllText($historyPath, $source450History, $utf8)
    [IO.File]::WriteAllText($readmePath, $readme, $utf8)
    Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion $source450Version -SourceVersion '4.5.0'
    $written = Get-Content -Raw -LiteralPath $infoPath | ConvertFrom-Json
    $writtenHistory = [IO.File]::ReadAllText($historyPath)
    if ($written.version -cne $source450Version -or $written.title -cne $info.title -or
        -not $writtenHistory.Contains("Version: $source450Version`n") -or -not $writtenHistory.Contains('source 4.5.0.') -or
        -not $writtenHistory.EndsWith($source450History, [StringComparison]::Ordinal) -or
        [IO.File]::ReadAllText($readmePath) -cne "MIR $source450Version, source 4.5.0.`n`n$readme") { throw '[mir450-package-metadata]' }
    $assertions++
    $before = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash | ForEach-Object Hash)
    $rejected = $false
    try { Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion $source450WrongPatch -SourceVersion '4.5.0' | Out-Null }
    catch { $rejected = $_.Exception.Message -match 'source-identity' }
    $after = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash | ForEach-Object Hash)
    if (-not $rejected -or ($before -join '|') -cne ($after -join '|')) { throw '[mir450-wrong-source-patch-mutated-input]' }
    $assertions++
    $rejected = $false
    try { Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion $source450Version -SourceVersion '4.5.1' | Out-Null }
    catch { $rejected = $_.Exception.Message -match 'source-(version|identity)' }
    $after = @(Get-ChildItem -LiteralPath $tree -File | Sort-Object Name | Get-FileHash | ForEach-Object Hash)
    if (-not $rejected -or ($before -join '|') -cne ($after -join '|')) { throw '[mir451-mismatched-source-patch-mutated-input]' }
    $assertions++
    $info.version = "4.6.${code}00"
    [IO.File]::WriteAllText($infoPath, ($info | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($historyPath, $source450History, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($readmePath, $readme, [Text.UTF8Encoding]::new($false))
    Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion "4.6.${code}00" -SourceVersion '4.6.0'
    $replacementHistory = [IO.File]::ReadAllText($historyPath)
    if (-not $replacementHistory.StartsWith("---------------------------------------------------------------------------------------------------`nVersion: 4.6.${code}00`n") -or
        -not $replacementHistory.EndsWith($source450History, [StringComparison]::Ordinal) -or
        -not $replacementHistory.Contains('Retain the research, settings, cap and save-continuity repairs')) { throw '[mir460-replacement-changelog-identity]' }
    if ($replacementHistory.Contains('Restore staged Aluminium, Gold, Tin and Titanium') -ne ($code -ceq '200')) { throw '[mir460-target-specific-material-claim]' }
    if ($replacementHistory.Contains('independently available replacement science recipe') -ne ($code -cin @('210','200','110','100'))) { throw '[mir460-target-specific-science-claim]' }
    if (@($replacementHistory.Split("`n") | Where-Object Length -gt 132).Count) { throw '[mir460-changelog-line-width]' }
    $identityBefore = (Get-FileHash -LiteralPath $historyPath).Hash
    Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion "4.6.${code}00" -SourceVersion '4.6.0'
    if ((Get-FileHash -LiteralPath $historyPath).Hash -cne $identityBefore) { throw '[mir460-repeated-write-duplicated-entry]' }
    $assertions += 5
    # The current-package writer authenticates its exact tested base floor
    # before changing any of its three authored members.  These are host-only
    # refusal/isolation checks, not native engine qualification.
    $validInfo = [IO.File]::ReadAllText($infoPath)
    foreach ($dependencyCase in @('missing','empty','duplicate')) {
      $probe = $validInfo | ConvertFrom-Json
      switch ($dependencyCase) {
        'missing' { [void]$probe.PSObject.Properties.Remove('dependencies') }
        'empty' { $probe.dependencies = @() }
        'duplicate' { $probe.dependencies = @("base >= $($minimumBaseVersions[$code])", "base >= $($minimumBaseVersions[$code])") }
      }
      # Keep the malformed member deliberately compact.  The former
      # write-before-validation implementation would have reformatted it
      # before refusing the base declaration; the current preflight must
      # preserve these exact bytes.
      [IO.File]::WriteAllText($infoPath, (($probe | ConvertTo-Json -Depth 20 -Compress) + "`n"), $utf8)
      $beforeMembers = @('info.json','changelog.txt','README.md' | ForEach-Object {
        (Get-FileHash -LiteralPath (Join-Path $tree $_) -Algorithm SHA256).Hash
      })
      $rejected = $false
      try { Write-MIR4PrivatePatchPackageIdentity -Tree $tree -DistributionVersion "4.6.${code}00" -SourceVersion '4.6.0' | Out-Null }
      catch { $rejected = $_.Exception.Message -match '\[mir4-private-patch-package-base-minimum\]' }
      $afterMembers = @('info.json','changelog.txt','README.md' | ForEach-Object {
        (Get-FileHash -LiteralPath (Join-Path $tree $_) -Algorithm SHA256).Hash
      })
      if (-not $rejected -or ($beforeMembers -join '|') -cne ($afterMembers -join '|')) {
        throw "[mir460-base-minimum-$dependencyCase-mutated-authored-members] $code"
      }
      $assertions++
    }
    [IO.File]::WriteAllText($infoPath, $validInfo, $utf8)
  }
} finally {
  if (Test-Path -LiteralPath $root) {
    $resolved = (Resolve-Path -LiteralPath $root).Path
    $null = Assert-MIR4DescendantPath -Root (Join-Path $RepoRoot 'build') -Path $resolved
    $null = Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path $resolved
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}
[pscustomobject]@{status='passed';targets=9;assertions=$assertions;source_4_2_0_suffix='00';source_4_2_1_suffix='01';source_4_2_2_suffix='02';source_4_2_3_suffix='03';source_4_5_0_suffix='00';mismatched_source_patch_rejected=$true;historical_leading_zero_retained=$true;one_time_source_tag_bound=$true;factorio_processes=0;candidate_qualification='not-performed'} | ConvertTo-Json
