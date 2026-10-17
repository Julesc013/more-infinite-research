# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1')

function Assert-MIR42PreflightTest([bool]$Condition,[string]$Code) { if (-not $Condition) { throw "[$Code]" } }
function New-MIR42PreflightTestZip {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Target,[switch]$IncludeForbidden,[string]$SourceVersion='4.2.0')
  $lines = [ordered]@{f210='2.1';f200='2.0';f110='1.1';f100='1.0';f017='0.17';f016='0.16';f015='0.15';f014='0.14';f013='0.13'}
  $codes = [ordered]@{f210='210';f200='200';f110='110';f100='100';f017='017';f016='016';f015='015';f014='014';f013='013'}
  $version = [string](Get-MIR42ReleaseTargetIdentity -RepoRoot $repo -Target $Target -SourceVersion $SourceVersion).distribution_version
  $package = Join-Path $Root "stage/more-infinite-research_$version"
  New-Item -ItemType Directory -Force -Path $package | Out-Null
  $info = [ordered]@{name='more-infinite-research';version=$version;factorio_version=$lines[$Target];title='Test'}
  [IO.File]::WriteAllText((Join-Path $package 'info.json'),($info | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $package 'data.lua'),'return {}',[Text.UTF8Encoding]::new($false))
  if ($IncludeForbidden) { New-Item -ItemType Directory -Force -Path (Join-Path $package 'docs') | Out-Null; [IO.File]::WriteAllText((Join-Path $package 'docs/private.md'),'no',[Text.UTF8Encoding]::new($false)) }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = Join-Path $Root "more-infinite-research_$version.zip"
  [IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $Root 'stage'),$zip,[IO.Compression.CompressionLevel]::Optimal,$false)
  return $zip
}

$root = Join-Path $repo ("build/test-results/mir42-four-target-preflight-" + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $zips = [ordered]@{}
  foreach ($target in @('f210','f200','f110','f100')) { $zips[$target] = New-MIR42PreflightTestZip -Root (Join-Path $root $target) -Target $target }
  $historicalZips = @{}
  foreach ($target in @('f017','f016','f015','f014','f013')) { $historicalZips[$target] = New-MIR42PreflightTestZip -Root (Join-Path $root $target) -Target $target }
  $historicalInputs = @(Get-MIR42HistoricalZipInputs -HistoricalZips $historicalZips)
  Assert-MIR42PreflightTest ((@($historicalInputs.target) -join '|') -ceq 'f017|f016|f015|f014|f013') 'mir42-preflight-historical-input-order'
  $historicalIdentity = Get-MIR42ReleaseTargetIdentity -RepoRoot $repo -Target f017
  Assert-MIR42PreflightTest (([string]$historicalIdentity.target_record_record_sha256 -match '^[A-Fa-f0-9]{64}$') -and ([string]$historicalIdentity.target_record_file_sha256 -match '^[A-Fa-f0-9]{64}$') -and ([string]$historicalIdentity.target_record_record_sha256 -cne [string]$historicalIdentity.target_record_file_sha256)) 'mir42-preflight-historical-record-hash-contract'
  foreach ($input in $historicalInputs) {
    $archive = Get-MIR42FourTargetArchiveInput -RepoRoot $repo -Target ([string]$input.target) -Path ([string]$input.path)
    Assert-MIR42PreflightTest ([string]$archive.target_id -ceq ('factorio-' + [string]$archive.factorio_line) -and [string]$archive.distribution_version -match '^4[.]2[.]0(?:17|16|15|14|13)00$') "mir42-preflight-historical-identity-$($input.target)"
  }
  $partialHistoricalRejected = $false
  try { Get-MIR42HistoricalZipInputs -HistoricalZips @{f017=$historicalZips.f017;f016=$historicalZips.f016;f015=$historicalZips.f015;f014=$historicalZips.f014} | Out-Null } catch { $partialHistoricalRejected = $_.Exception.Message -match 'mir42-preflight-historical-target-set' }
  Assert-MIR42PreflightTest $partialHistoricalRejected 'mir42-preflight-historical-partial-rejected'
  $unknownHistoricalRejected = $false
  try { Get-MIR42HistoricalZipInputs -HistoricalZips @{f017=$historicalZips.f017;f016=$historicalZips.f016;f015=$historicalZips.f015;f014=$historicalZips.f014;f999=$historicalZips.f013} | Out-Null } catch { $unknownHistoricalRejected = $_.Exception.Message -match 'mir42-preflight-historical-target-set' }
  Assert-MIR42PreflightTest $unknownHistoricalRejected 'mir42-preflight-historical-unknown-rejected'
  $head = (& git -C $repo rev-parse HEAD).Trim()
  $result = (& (Join-Path $repo 'tools/commands/release/Invoke-MIR42FourTargetReleasePreflight.ps1') -RepoRoot $repo -FinalSourceCommit $head -F210Zip $zips.f210 -F200Zip $zips.f200 -F110Zip $zips.f110 -F100Zip $zips.f100 -HistoricalZips $historicalZips -OutputRoot (Join-Path $root 'result')) | ConvertFrom-Json -Depth 20 -DateKind String
  Assert-MIR42PreflightTest ([string]$result.status -ceq 'MIR-4.2-NINE-TARGET-TECHNICAL-READINESS-NOT-READY') 'mir42-preflight-status'
  $candidateText = Get-Content -Raw -LiteralPath $result.candidate_manifest
  $candidate = $candidateText | ConvertFrom-Json -Depth 100 -DateKind String
  $readinessText = Get-Content -Raw -LiteralPath $result.technical_readiness
  $readiness = $readinessText | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR42PreflightTest ($candidateText | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir42-four-target-candidate-manifest-v1.schema.json')) 'mir42-preflight-candidate-schema'
  Assert-MIR42PreflightTest ($readinessText | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir42-four-target-technical-readiness-v1.schema.json')) 'mir42-preflight-readiness-schema'
  Assert-MIR42PreflightTest ((Test-MIR4BootstrapRecordHash -Record $candidate) -and (Test-MIR4BootstrapRecordHash -Record $readiness)) 'mir42-preflight-self-hashes'
  Assert-MIR42PreflightTest ((@($candidate.targets.target) -join '|') -ceq 'f210|f200|f110|f100|f017|f016|f015|f014|f013') 'mir42-preflight-target-order'
  Assert-MIR42PreflightTest ((@($candidate.targets.distribution_version) -join '|') -ceq '4.2.21000|4.2.20000|4.2.11000|4.2.10000|4.2.01700|4.2.01600|4.2.01500|4.2.01400|4.2.01300') 'mir42-preflight-versions'
  Assert-MIR42PreflightTest ([string]$candidate.archive_source_provenance -ceq 'unproven-by-zip-inputs' -and $null -eq $candidate.candidate_id -and -not [bool]$candidate.release_transition_authorized) 'mir42-preflight-no-candidate-allocation'
  Assert-MIR42PreflightTest (@($readiness.target_qualification | Where-Object status -ne 'not-run').Count -eq 0 -and @($readiness.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -eq 0 -and -not [bool]$readiness.production_authorized) 'mir42-preflight-gates-closed'
  $legacyResult = (& (Join-Path $repo 'tools/commands/release/Invoke-MIR42FourTargetReleasePreflight.ps1') -RepoRoot $repo -FinalSourceCommit $head -F210Zip $zips.f210 -F200Zip $zips.f200 -F110Zip $zips.f110 -F100Zip $zips.f100 -OutputRoot (Join-Path $root 'result-four')) | ConvertFrom-Json -Depth 20 -DateKind String
  $legacyCandidate = Get-Content -Raw -LiteralPath $legacyResult.candidate_manifest | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIR42PreflightTest ([string]$legacyResult.status -ceq 'MIR-4.2-FOUR-TARGET-TECHNICAL-READINESS-NOT-READY' -and @($legacyCandidate.targets).Count -eq 4 -and [string]$legacyCandidate.status -ceq 'MIR-4.2-FOUR-TARGET-CANDIDATE-INPUTS-BOUND-UNQUALIFIED') 'mir42-preflight-four-target-contract-retained'
  $sourceRejected = $false
  try { Invoke-MIR42FourTargetReleasePreflight -RepoRoot $repo -FinalSourceCommit ('0' * 40) -F210Zip $zips.f210 -F200Zip $zips.f200 -F110Zip $zips.f110 -F100Zip $zips.f100 -OutputRoot (Join-Path $root 'source-mismatch-result') | Out-Null } catch { $sourceRejected = $_.Exception.Message -match 'mir42-preflight-final-source-commit' }
  Assert-MIR42PreflightTest $sourceRejected 'mir42-preflight-final-source-rejected'
  $bad = New-MIR42PreflightTestZip -Root (Join-Path $root 'bad') -Target f100 -IncludeForbidden
  $rejected = $false
  try { Invoke-MIR42FourTargetReleasePreflight -RepoRoot $repo -FinalSourceCommit $head -F210Zip $zips.f210 -F200Zip $zips.f200 -F110Zip $zips.f110 -F100Zip $bad -OutputRoot (Join-Path $root 'bad-result') | Out-Null } catch { $rejected = $_.Exception.Message -match 'mir42-preflight-package-excluded-entry' }
  Assert-MIR42PreflightTest $rejected 'mir42-preflight-package-excluded-rejected'

  foreach ($target in @('f210','f200','f110','f100','f017','f016','f015','f014','f013')) {
    $currentZip = New-MIR42PreflightTestZip -Root (Join-Path $root ('450-'+$target)) -Target $target -SourceVersion '4.5.0'
    $currentArchive = Get-MIR42FourTargetArchiveInput -RepoRoot $repo -Target $target -Path $currentZip -SourceVersion '4.5.0'
    Assert-MIR42PreflightTest ($currentArchive.distribution_version -ceq ('4.5.'+$target.Substring(1)+'00') -and $currentArchive.package_excluded_entries_absent) "mir45-preflight-current-archive-$target"
    $wrongVersionRejected = $false
    try { Get-MIR42FourTargetArchiveInput -RepoRoot $repo -Target $target -Path $currentZip -SourceVersion '4.4.2' | Out-Null } catch { $wrongVersionRejected = $_.Exception.Message -match 'mir42-preflight-package-root' }
    Assert-MIR42PreflightTest $wrongVersionRejected "mir45-preflight-refuses-cross-version-archive-$target"
  }

  # 4.4.2 published its exact V9 construction record, retaining its original
  # unqualified fields. Synthetic API metadata exercises that distinct input
  # format without promoting it to a final manifest or transferring a waiver.
  $published442 = Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath (Join-Path $repo 'fixtures/release-inputs/mir450-published-442-r24-construction.json') -CandidateSourceVersion '4.5.0'
  $published442Contract = Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion '4.5.0'
  $published442Assets = [Collections.Generic.List[object]]::new()
  $published442Assets.Add([pscustomobject]@{id=1;name=$published442Contract.manifest_name;size=$published442.bytes;digest=('sha256:'+$published442.sha256.ToLowerInvariant());state='uploaded'})
  foreach ($target in $published442.manifest.targets) {
    $published442Assets.Add([pscustomobject]@{id=($published442Assets.Count+1);name=('more-infinite-research_'+$target.distribution_version+'.zip');size=$target.asset.bytes;digest=('sha256:'+$target.asset.sha256.ToLowerInvariant());state='uploaded'})
  }
  while ($published442Assets.Count -lt 18) {
    $published442Assets.Add([pscustomobject]@{id=($published442Assets.Count+1);name=('synthetic-support-'+$published442Assets.Count);size=1;digest=('sha256:'+('a'*64));state='uploaded'})
  }
  $published442Metadata = [pscustomobject]@{
    id=415194452;tag_name='v4.4.2';target_commitish='fe385332f778e1c79a0ad930140fe6e4defdb17a'
    draft=$false;prerelease=$false;immutable=$false;assets=@($published442Assets)
  }
  $published442Rows = @(Assert-MIR42PublishedMaintenancePredecessorMetadata -PinnedManifest $published442 -ReleaseMetadata $published442Metadata -CandidateSourceVersion '4.5.0')
  Assert-MIR42PreflightTest ($published442Rows.Count -eq 9 -and
    $published442Rows[1].target -ceq 'f200' -and $published442Rows[1].version -ceq '4.4.20002' -and
    $published442Rows[1].sha256 -ceq '9467A82FC0DE73CB520C987A54A778B7278F0ADFD0315100D539FDAB843B5B58' -and
    $published442Rows[1].content_sha256 -ceq '8E83FB18BEECFCA8F6DC58B318D93522BE2501D9E12C4538679ECCFD2D0442B6' -and
    $published442Rows[1].entry_count -eq 340) 'mir45-published442-exact-construction-inventory'
  Assert-MIR42PreflightTest ($published442.manifest.kind -ceq 'MIR42FourTargetDeterministicCandidateManifestV9' -and
    $published442.manifest.qualification -ceq 'not-performed' -and
    $published442.manifest.tagging -ceq 'not-performed' -and -not $published442.manifest.publication_authorized) 'mir45-published442-no-inherited-acceptance'
  # Independently exercise the parsed-record acceptance boundary. Recompute the
  # inner record hash so each refusal depends on the forbidden inherited claim,
  # rather than merely detecting a stale self-hash. The frozen fixture is untouched.
  foreach ($claim in @('qualification','technical_seal','signing','tagging','publication_authorized')) {
    $badPinned = $published442 | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    $badPinned.manifest.$claim = if ($claim -ceq 'publication_authorized') { $true } else { 'performed' }
    $badPinned.manifest.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $badPinned.manifest
    $rejected = $false
    try { Assert-MIR42PublishedMaintenancePredecessorMetadata -PinnedManifest $badPinned -ReleaseMetadata $published442Metadata -CandidateSourceVersion '4.5.0' | Out-Null } catch { $rejected = $_.Exception.Message -match 'mir42-maintenance-predecessor-release-metadata' }
    Assert-MIR42PreflightTest $rejected ('mir45-published442-inherited-claim-rejected-'+$claim)
  }
  foreach ($mutation in @('release-id','source-commit','draft','immutable','manifest-digest','package-digest','superseded-release','superseded-source')) {
    $badMetadata = $published442Metadata | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    switch ($mutation) {
      'release-id' { $badMetadata.id++ }
      'source-commit' { $badMetadata.target_commitish = '0'*40 }
      'draft' { $badMetadata.draft = $true }
      'immutable' { $badMetadata.immutable = $true }
      'manifest-digest' { $badMetadata.assets[0].digest = 'sha256:'+('0'*64) }
      'package-digest' { $badMetadata.assets[2].digest = 'sha256:'+('0'*64) }
      'superseded-release' { $badMetadata.id = 414958467 }
      'superseded-source' { $badMetadata.target_commitish = '69b39bb1f933341af95b9fbee4139ca88885d5f4' }
    }
    $rejected = $false
    try { Assert-MIR42PublishedMaintenancePredecessorMetadata -PinnedManifest $published442 -ReleaseMetadata $badMetadata -CandidateSourceVersion '4.5.0' | Out-Null } catch { $rejected = $_.Exception.Message -match 'mir42-maintenance-predecessor' }
    Assert-MIR42PreflightTest $rejected ('mir45-published442-rejected-'+$mutation)
  }
  $tampered442 = Join-Path $root 'tampered-published442-construction.json'
  [IO.File]::WriteAllBytes($tampered442, [IO.File]::ReadAllBytes($published442.path) + [byte[]]@(32))
  $rejected = $false
  try { Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath $tampered442 -CandidateSourceVersion '4.5.0' | Out-Null } catch { $rejected = $_.Exception.Message -match 'mir42-maintenance-predecessor-frozen-manifest' }
  Assert-MIR42PreflightTest $rejected 'mir45-published442-raw-manifest-rejected'

  # Exercise the published-reader custody switch without a release API call.
  # Archive identities remain checked by the real reader; these controlled
  # inputs prove it accepts only an exact complete direct-library map and keeps
  # the former adjacent-fixture and single-target modes available.
  $allZips = @{}
  foreach ($target in $zips.Keys) { $allZips[$target] = [IO.Path]::GetFullPath($zips[$target]) }
  foreach ($target in $historicalZips.Keys) { $allZips[$target] = [IO.Path]::GetFullPath($historicalZips[$target]) }
  $readerRows = @(
    foreach ($target in @('f210','f200','f110','f100','f017','f016','f015','f014','f013')) {
      [pscustomobject]@{target=$target;version=('4.2.'+$target.Substring(1)+'02');filename=('published-'+$target+'.zip');bytes=1;sha256=($target.PadRight(64,'A').Substring(0,64));content_sha256=(('C' * 64) -join '');entry_count=1;github_asset_id=1;github_digest=('sha256:'+($target.PadRight(64,'A').Substring(0,64)).ToLowerInvariant())}
    }
  )
  $adjacent = @{}
  foreach ($row in $readerRows) { $adjacent[[string]$row.target] = [IO.Path]::GetFullPath((Join-Path $root ([string]$row.filename))) }
  $readerFunctions = @{}
  foreach ($name in @('Get-MIR42PublishedMaintenancePredecessorContract','Read-MIR42PublishedMaintenancePredecessorManifest','Assert-MIR42PublishedMaintenancePredecessorMetadata','Get-MIR42FourTargetArchiveInput')) {
    $readerFunctions[$name] = (Get-Item -LiteralPath ('function:'+$name)).ScriptBlock
  }
  $hadGitFunction = Test-Path -LiteralPath 'function:git'
  if ($hadGitFunction) { $readerFunctions.git = (Get-Item -LiteralPath 'function:git').ScriptBlock }
  try {
    $script:readerExpectedPaths = $allZips
    $script:readerAdjacentPaths = $adjacent
    $script:readerRows = $readerRows
    Set-Item -LiteralPath function:Get-MIR42PublishedMaintenancePredecessorContract -Value {
      param($CandidateSourceVersion)
      [pscustomobject]@{source_tag='v4.2.2';source_version='4.2.2'}
    }
    Set-Item -LiteralPath function:Read-MIR42PublishedMaintenancePredecessorManifest -Value {
      param($ManifestPath,$CandidateSourceVersion)
      [pscustomobject]@{path=$ManifestPath;sha256=(('D' * 64) -join '');bytes=1;manifest=[pscustomobject]@{source=[pscustomobject]@{commit=(('A' * 40) -join '');tree=(('B' * 40) -join '')}}}
    }
    Set-Item -LiteralPath function:Assert-MIR42PublishedMaintenancePredecessorMetadata -Value {
      param($PinnedManifest,$ReleaseMetadata,$CandidateSourceVersion)
      return @($script:readerRows)
    }
    Set-Item -LiteralPath function:Get-MIR42FourTargetArchiveInput -Value {
      param($RepoRoot,$Target,$Path,$SourceVersion)
      $full = [IO.Path]::GetFullPath($Path)
      $expected = @($script:readerExpectedPaths[[string]$Target],$script:readerAdjacentPaths[[string]$Target])
      $row = @($script:readerRows | Where-Object { [string]$_.target -ceq $Target })[0]
      $valid = $expected -contains $full
      [pscustomobject]@{archive=[pscustomobject]@{path=$full;sha256=$(if($valid){[string]$row.sha256}else{(('E' * 64) -join '')});bytes=$(if($valid){1}else{2})};content_sha256=$(if($valid){(('C' * 64) -join '')}else{(('F' * 64) -join '')});entry_count=1}
    }
    Set-Item -LiteralPath function:git -Value {
      param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
      $joined = $Arguments -join ' '
      $global:LASTEXITCODE = 0
      if ($joined -match 'ls-remote') { return @(((('C' * 40) -join '')+"`trefs/tags/v4.2.2"),((('A' * 40) -join '')+"`trefs/tags/v4.2.2^{}")) }
      if ($joined.Contains('^{tree}')) { return (('B' * 40) -join '') }
      if ($joined.Contains('^{}')) { return (('A' * 40) -join '') }
      return (('C' * 40) -join '')
    }
    $readerManifest = Join-Path $root 'frozen-published.json'
    $direct = Get-MIR42PublishedMaintenancePredecessorInputs -RepoRoot $repo -ManifestPath $readerManifest -ReleaseMetadata ([pscustomobject]@{id=1}) -CandidateSourceVersion '4.2.3' -ArchiveBindings $allZips
    Assert-MIR42PreflightTest ((@($direct.targets.target) -join '|') -ceq 'f210|f200|f110|f100|f017|f016|f015|f014|f013') 'mir42-preflight-direct-library-bindings-complete'
    Assert-MIR42PreflightTest (@($direct.targets | Where-Object { [string]$_.path -cne [string]$allZips[[string]$_.target] }).Count -eq 0) 'mir42-preflight-direct-library-bindings-paths'
    $adjacentResult = Get-MIR42PublishedMaintenancePredecessorInputs -RepoRoot $repo -ManifestPath $readerManifest -ReleaseMetadata ([pscustomobject]@{id=1}) -CandidateSourceVersion '4.2.3'
    Assert-MIR42PreflightTest (@($adjacentResult.targets | Where-Object { [string]$_.path -cne [string]$adjacent[[string]$_.target] }).Count -eq 0) 'mir42-preflight-adjacent-custody-retained'
    $selectedResult = Get-MIR42PublishedMaintenancePredecessorInputs -RepoRoot $repo -ManifestPath $readerManifest -ReleaseMetadata ([pscustomobject]@{id=1}) -CandidateSourceVersion '4.2.3' -SelectedTarget f210 -SelectedArchivePath $allZips.f210
    Assert-MIR42PreflightTest (@($selectedResult.targets).Count -eq 1 -and [string]$selectedResult.targets[0].path -ceq [string]$allZips.f210) 'mir42-preflight-selected-custody-retained'
    foreach ($case in @('partial','extra','wrong','relative')) {
      $bindings = @{}
      foreach ($target in $allZips.Keys) { $bindings[$target] = $allZips[$target] }
      $code = switch ($case) {
        'partial' { $bindings = @{f210=$allZips.f210}; 'mir42-maintenance-predecessor-archive-bindings-targets' }
        'extra' { $bindings.f999 = $allZips.f210; 'mir42-maintenance-predecessor-archive-bindings-targets' }
        'wrong' { $bindings.f200 = $allZips.f210; 'mir42-maintenance-predecessor-local-custody' }
        'relative' { $bindings.f200 = 'published-f200.zip'; 'mir42-maintenance-predecessor-archive-bindings-path' }
      }
      $rejected = $false
      try { Get-MIR42PublishedMaintenancePredecessorInputs -RepoRoot $repo -ManifestPath $readerManifest -ReleaseMetadata ([pscustomobject]@{id=1}) -CandidateSourceVersion '4.2.3' -ArchiveBindings $bindings | Out-Null } catch { $rejected = $_.Exception.Message -match $code }
      Assert-MIR42PreflightTest $rejected ('mir42-preflight-direct-library-'+$case+'-rejected')
    }
    $rejected = $false
    try { Get-MIR42PublishedMaintenancePredecessorInputs -RepoRoot $repo -ManifestPath $readerManifest -ReleaseMetadata ([pscustomobject]@{id=1}) -CandidateSourceVersion '4.2.3' -SelectedTarget f210 -SelectedArchivePath $allZips.f210 -ArchiveBindings $allZips | Out-Null } catch { $rejected = $_.Exception.Message -match 'mir42-maintenance-predecessor-archive-bindings-mode' }
    Assert-MIR42PreflightTest $rejected 'mir42-preflight-direct-library-mixed-mode-rejected'
  } finally {
    foreach ($name in @('Get-MIR42PublishedMaintenancePredecessorContract','Read-MIR42PublishedMaintenancePredecessorManifest','Assert-MIR42PublishedMaintenancePredecessorMetadata','Get-MIR42FourTargetArchiveInput')) { Set-Item -LiteralPath ('function:'+$name) -Value $readerFunctions[$name] }
    if ($hadGitFunction) { Set-Item -LiteralPath function:git -Value $readerFunctions.git } else { Remove-Item -LiteralPath function:git -ErrorAction SilentlyContinue }
  }
  Write-Host '[ok] MIR 4.2 nine-target preflight binds exact archive inputs and keeps all qualification and release gates closed.'
} finally {
  if (Test-Path -LiteralPath $root) {
    $resolvedRoot = (Resolve-Path -LiteralPath $root).Path
    $null = Assert-MIR4DescendantPath -Root (Join-Path $repo 'build') -Path $resolvedRoot
    $null = Assert-MIR4NoReparseAncestors -Root $repo -Path $resolvedRoot
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
  }
}
