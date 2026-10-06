Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../mir/application/release/readiness/Common.ps1')
. (Join-Path $PSScriptRoot '../../mir/application/release/readiness/ResourceGovernor.ps1')
. (Join-Path $PSScriptRoot 'ImmutableInputStaging.ps1')
. (Join-Path $PSScriptRoot 'MIR4DistributionIdentity.ps1')

# These adapters retain the existing governor and lease authorities. They own
# one probe's total new-output budget, not a second scheduler or package writer.
function Resolve-MIRNativeProbeDependencyInputs {
  param(
    [AllowEmptyString()][string]$StageRoot='',
    [Parameter(Mandatory)][Collections.IDictionary]$ExpectedArchives,
    [string[]]$LocalModLibraryDirs=@()
  )
  if($ExpectedArchives.Count -lt 1 -or $ExpectedArchives.Count -gt 32 -or $LocalModLibraryDirs.Count -gt 8){throw '[mir-native-probe-dependency-input-budget]'}
  $rows=[ordered]@{}
  foreach($entry in $ExpectedArchives.GetEnumerator()){
    $name=[string]$entry.Key;$expected=[string]$entry.Value
    if($name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*[.]zip$' -or $expected -cnotmatch '^[0-9A-F]{64}$'){throw '[mir-native-probe-dependency-identity]'}
    $path=if($StageRoot){Join-Path $StageRoot (Join-Path 'mods' $name)}else{''};$kind='exact-preserved-stage'
    if(-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)){
      $path='';$kind='verified-local-dependency-library'
      foreach($directory in $LocalModLibraryDirs){
        $candidate=Join-Path $directory $name
        if(Test-Path -LiteralPath $candidate -PathType Leaf){$path=$candidate;break}
      }
    }
    if(-not $path){throw "[mir-native-probe-dependency-missing] $name"}
    $file=Get-Item -LiteralPath $path -Force
    Assert-MIRImmutableInputDirectory -Path $file.DirectoryName -Context 'Native probe immutable source directory'
    if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-MIRImmutableInputSha256 -Path $file.FullName) -cne $expected){throw "[mir-native-probe-dependency-hash] $name"}
    $rows[$name]=[ordered]@{source_path=$file.FullName;file_name=$name;expected_sha256=$expected;provenance_kind=$kind}
  }
  return $rows
}

# Current player candidates are read against the existing package/materializer
# authorities. This validates supplied bytes without writing another package.
function Assert-MIRNativeProbeF210Candidate([bool]$Condition,[string]$Message) {
  if(-not $Condition){throw "[mir-native-probe-f210-candidate] $Message"}
}
function Read-MIRNativeProbeCurrentCandidate {
  param([string]$Repository,[string]$Archive,[string]$ReceiptPath,
    [ValidateSet('f210','f200')][string]$Target='f210')
  Assert-MIRNativeProbeF210Candidate (-not [string]::IsNullOrWhiteSpace($Archive) -and -not [string]::IsNullOrWhiteSpace($ReceiptPath)) 'supply candidate and canonical materialization receipt'
  $candidate = (Resolve-Path -LiteralPath $Archive).Path
  $receipt = Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json -Depth 30 -DateKind String
  Assert-MIRNativeProbeF210Candidate (($receipt | ConvertTo-Json -Depth 30) | Test-Json -SchemaFile (Join-Path $Repository 'spec/schemas/mir4-package-composition-result-v1.schema.json')) 'candidate materialization schema differs'
  Assert-MIRNativeProbeF210Candidate (Test-MIR4BootstrapRecordHash -Record $receipt) 'candidate materialization record hash differs'
  $identity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $Repository -Target $Target -SourceVersion '4.2.1'
  Assert-MIRNativeProbeF210Candidate ($receipt.status -ceq 'passed-canonical-package-authority-materialization' -and $receipt.target -ceq $Target -and $receipt.source_version -ceq $identity.source_version -and $receipt.distribution_version -ceq $identity.distribution_version) 'candidate materialization identity differs'
  Assert-MIRNativeProbeF210Candidate ($receipt.package_source_sha256 -ceq (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $Repository)) 'candidate source fingerprint differs'
  Assert-MIRNativeProbeF210Candidate ((Resolve-Path -LiteralPath $receipt.archive_path).Path -ceq $candidate -and [IO.Path]::GetFileName($candidate) -ceq $identity.package_name) 'candidate archive path or filename differs'
  foreach ($invariant in @('all_source_hashes_verified','all_output_hashes_verified','version_identity_verified','canonical_package_authority')) {
    Assert-MIRNativeProbeF210Candidate ([bool]$receipt.invariants.$invariant) "candidate invariant differs: $invariant"
  }
  $inventory = Get-MIR4ArchiveInventory -Path $candidate
  Assert-MIRNativeProbeF210Candidate ($inventory.archive_sha256 -ceq $receipt.archive_sha256 -and $inventory.content_sha256 -ceq $receipt.content_sha256 -and $inventory.entry_count -eq $receipt.entry_count) 'candidate archive inventory differs'
  $zip = [IO.Compression.ZipFile]::OpenRead($candidate)
  try {
    Assert-MIRNativeProbeF210Candidate (@($zip.Entries | Where-Object {-not $_.FullName.StartsWith($identity.distribution_root+'/',[StringComparison]::Ordinal) -or $_.FullName -match '/(?:tests|fixtures|docs|[.]mir|[.]codex|[.]github|build|dist)/'}).Count -eq 0) 'candidate root or exclusions differ'
    $entry = $zip.GetEntry($identity.distribution_root+'/info.json')
    Assert-MIRNativeProbeF210Candidate ($null -ne $entry -and $entry.Length -le 64KB) 'candidate info differs'
    $reader = [IO.StreamReader]::new($entry.Open())
    try {$info = $reader.ReadToEnd() | ConvertFrom-Json} finally {$reader.Dispose()}
    $line=if($Target -ceq 'f200'){'2.0'}else{'2.1'}
    Assert-MIRNativeProbeF210Candidate ($info.name -ceq 'more-infinite-research' -and $info.version -ceq $identity.distribution_version -and $info.factorio_version -ceq $line) 'candidate metadata differs'
    $state = Get-MIR4TargetMaterializerState -RepoRoot $Repository -Target $Target
    $selection = Get-MIR4TargetMaterializationBindings -State $state
    Assert-MIRNativeProbeF210Candidate ($receipt.source_manifest_sha256 -ceq $state.manifest.record_sha256 -and $receipt.target_overlay_sha256 -ceq $state.composition.record_sha256) 'candidate composition authority differs'
    Assert-MIRNativeProbeF210Candidate ($zip.Entries.Count -eq $selection.bindings.Count) 'candidate package membership differs'
    foreach ($binding in $selection.bindings) {
      $member = @($zip.Entries | Where-Object FullName -CEQ ($identity.distribution_root+'/'+$binding.output_path))
      Assert-MIRNativeProbeF210Candidate ($member.Count -eq 1) "candidate binding missing or duplicated: $($binding.output_path)"
      # Metadata is checked above; these authored presentation files are
      # rewritten by the existing patch-identity writer. Runtime bytes retain
      # their exact current materializer binding, without building another ZIP.
      if ($binding.output_path -in @('info.json','changelog.txt','README.md')) {continue}
      Assert-MIRNativeProbeF210Candidate ($member[0].Length -eq $binding.output_bytes) "candidate binding size differs: $($binding.output_path)"
      $stream = $member[0].Open()
      try {$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))} finally {$stream.Dispose()}
      Assert-MIRNativeProbeF210Candidate ($hash -ceq $binding.output_sha256) "candidate binding hash differs: $($binding.output_path)"
    }
  } finally {$zip.Dispose()}
  return [pscustomobject]@{path=$candidate;receipt=$receipt}
}
function Read-MIRNativeProbeF210CurrentCandidate([string]$Repository,[string]$Archive,[string]$ReceiptPath) {
  Read-MIRNativeProbeCurrentCandidate -Repository $Repository -Archive $Archive -ReceiptPath $ReceiptPath -Target f210
}
function New-MIRNativeProbeResourceContext {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$OutputRoot,
    [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB=0,
    [ValidateRange(1,2048)][int]$MaxNewOutputMiB=120
  )
  $path=if([IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot } else { Join-Path $RepoRoot $OutputRoot }
  $output=Resolve-MIR441RecoveryScratchPath -Path ([IO.Path]::GetFullPath($path))
  if($ExpectedPeakMemoryMiB -le 0) { throw '[mir441-resource-peak-budget-required] Declare the native probe peak memory budget.' }
  $policy=[pscustomobject]@{minimum_free_ram_gib=4}
  $peak=[int64]$ExpectedPeakMemoryMiB*1MB
  $writes=[int64]$MaxNewOutputMiB*1MB
  $null=Assert-MIR441ResourceAdmission -Policy $policy -WorkRoot $output -EstimatedPeakBytes $writes -ExpectedPeakMemoryBytes $peak
  [pscustomobject]@{
    root=Join-Path $output ([guid]::NewGuid().ToString('N'))
    policy=$policy;peak_memory_bytes=$peak;max_new_output_bytes=$writes
    shared_alias_bytes=0L;process_index=0;result_reserve_bytes=64KB
    alias_paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    aliases=[Collections.Generic.List[object]]::new()
    runs=[Collections.Generic.List[object]]::new()
  }
}

function Add-MIRNativeProbeImmutableLease {
  param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Lease)
  if(-not $Lease.record.Contains('require_hard_links') -or -not $Lease.record.require_hard_links) {
    throw '[mir-native-probe-strict-lease-required]'
  }
  $receipt=Get-MIRImmutableInputLeaseReceipt -Lease $Lease
  foreach($leaseInput in $receipt.inputs) {
    $stage=Resolve-MIR441RecoveryScratchPath -Path ([string]$leaseInput.stage_path)
    if(-not (Test-MIR441PathContained -Root $Context.root -Path $stage) -or
      $Context.alias_paths.Contains($stage) -or $leaseInput.staging_mode -cne 'hardlink' -or
      (Get-MIRImmutableInputFileIdentity -Path $leaseInput.source_path) -cne (Get-MIRImmutableInputFileIdentity -Path $stage)) {
      throw '[mir-native-probe-shared-alias-identity]'
    }
    [void]$Context.alias_paths.Add($stage)
    $Context.aliases.Add([pscustomobject]@{stage_path=$stage;source_path=[string]$leaseInput.source_path;file_identity=Get-MIRImmutableInputFileIdentity -Path $stage;bytes=[int64](Get-Item -LiteralPath $stage).Length})
    # Only proved, leased aliases are excluded from logical tree totals.
    # A generated candidate's original file is still counted in the row.
    $Context.shared_alias_bytes += [int64](Get-Item -LiteralPath $stage).Length
  }
}

function Get-MIRNativeProbeRemainingOutputBytes {
  param([Parameter(Mandatory)]$Context,[switch]$IncludeResultReserve)
  foreach($alias in $Context.aliases) {
    if(-not (Test-Path -LiteralPath $alias.stage_path -PathType Leaf) -or
      -not (Test-Path -LiteralPath $alias.source_path -PathType Leaf) -or
      ((Get-Item -LiteralPath $alias.stage_path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or
      (Get-MIRImmutableInputFileIdentity -Path $alias.stage_path) -cne $alias.file_identity -or
      (Get-MIRImmutableInputFileIdentity -Path $alias.source_path) -cne $alias.file_identity -or
      [int64](Get-Item -LiteralPath $alias.stage_path).Length -ne $alias.bytes) {
      throw '[mir-native-probe-shared-alias-identity]'
    }
  }
  $usage=Get-MIR441TreeUsage -Path $Context.root
  if(-not $usage.complete) { throw '[mir441-resource-output-scan-incomplete]' }
  $newBytes=[int64]$usage.bytes-[int64]$Context.shared_alias_bytes
  if($newBytes -lt 0) { throw '[mir-native-probe-shared-alias-missing]' }
  $remaining=[int64]$Context.max_new_output_bytes-$newBytes
  if(-not $IncludeResultReserve) { $remaining-=[int64]$Context.result_reserve_bytes }
  if($remaining -le 0) { throw '[mir441-resource-output-budget]' }
  return $remaining
}

function Invoke-MIRNativeProbeProcess {
  param(
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string[]]$Arguments,
    [ValidateRange(1,3600)][int]$TimeoutSeconds=120,
    [scriptblock]$CompletionPredicate
  )
  $remaining=Get-MIRNativeProbeRemainingOutputBytes -Context $Context
  $Context.process_index++
  $prefix=Join-Path $Context.root ('process-'+$Context.process_index)
  try {
    $result=Invoke-MIR441MonitoredProcess -FilePath $FilePath -Arguments $Arguments -WorkRoot $Context.root `
      -Policy $Context.policy -EstimatedPeakBytes $remaining -ExpectedPeakMemoryBytes $Context.peak_memory_bytes `
      -LedgerPath ($prefix+'.resources.jsonl') -StdoutPath ($prefix+'.stdout.txt') -StderrPath ($prefix+'.stderr.txt') `
      -TimeoutSeconds $TimeoutSeconds -CompletionPredicate $CompletionPredicate
    $null=Get-MIRNativeProbeRemainingOutputBytes -Context $Context
  } catch {
    $Context.runs.Add([pscustomobject]@{index=$Context.process_index;status='interrupted';ledger=($prefix+'.resources.jsonl');stdout=($prefix+'.stdout.txt');stderr=($prefix+'.stderr.txt');error=$_.Exception.Message})
    throw
  }
  $Context.runs.Add([pscustomobject]@{index=$Context.process_index;status='passed';ledger=($prefix+'.resources.jsonl');stdout=($prefix+'.stdout.txt');stderr=($prefix+'.stderr.txt');result=$result})
  return $Context.runs[$Context.runs.Count-1]
}

function Write-MIRNativeProbeResult {
  param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Record)
  $json=($Record | ConvertTo-Json -Depth 30)+"`n"
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json)
  $remaining=Get-MIRNativeProbeRemainingOutputBytes -Context $Context -IncludeResultReserve
  if($bytes.Length -ge $remaining) { throw '[mir441-resource-output-budget]' }
  [IO.File]::WriteAllBytes((Join-Path $Context.root 'result.json'),$bytes)
}

function Invoke-MIRNativeProbeFactorioProcess {
  param(
    [Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string[]]$Arguments,
    [ValidateRange(1,3600)][int]$TimeoutSeconds=120,
    [scriptblock]$CompletionPredicate
  )
  if($Arguments.Count -lt 1 -or $Arguments.Count -gt 128){throw '[mir-native-probe-argument-budget]'}
  $payload=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $Arguments -Compress))
  if($payload.Length -gt 16KB){throw '[mir-native-probe-argument-budget]'}
  $null=Get-MIRNativeProbeRemainingOutputBytes -Context $Context
  $driver=Join-Path $Context.root 'factorio-driver.ps1'
  # Steam identifiers exist only in this owned child. The shared governor
  # measures/cancels the complete PowerShell plus native-engine process tree.
  # Arguments cross this boundary as data, never interpolated shell commands.
  $driverText=@'
param([Parameter(Mandatory)][string]$NativeExecutable,[Parameter(Mandatory)][string]$ArgumentsBase64)
$ErrorActionPreference='Stop'
$nativeArguments=[string[]]([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgumentsBase64)) | ConvertFrom-Json)
$env:SteamAppId='427520';$env:SteamGameId='427520'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
& $NativeExecutable @nativeArguments
exit $LASTEXITCODE
'@
  [IO.File]::WriteAllText($driver,$driverText,[Text.UTF8Encoding]::new($false))
  return Invoke-MIRNativeProbeProcess -Context $Context -FilePath (Get-Command pwsh).Source -TimeoutSeconds $TimeoutSeconds -CompletionPredicate $CompletionPredicate `
    -Arguments @('-NoProfile','-File',$driver,'-NativeExecutable',$FilePath,'-ArgumentsBase64',[Convert]::ToBase64String($payload))
}

function New-MIRNativeProbeTargetPackage {
  param(
    [Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$RepoRoot,
    [ValidateSet('F210-TIN-OBS','F210-CURRENT-BA-FINAL-ROUTES-OBSERVER','BROWSER')][string]$CandidatePrefix='F210-TIN-OBS',
    [ValidateSet('f210','f200')][string]$Target='f210'
  )
  $targetKey=$Target.ToLowerInvariant()
  if($CandidatePrefix -cne 'BROWSER' -and $targetKey -cne 'f210'){throw '[mir-native-probe-observer-target]'}
  $identity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $targetKey.Substring(1) -SourceMinor 2 -SourcePatch 1
  $prefix=if($CandidatePrefix -ceq 'BROWSER'){$targetKey.ToUpperInvariant()+'-BROWSER'}else{$CandidatePrefix}
  $null=Get-MIRNativeProbeRemainingOutputBytes -Context $Context
  $driver=Join-Path $Context.root 'materialize.ps1'
  $receipt=Join-Path $Context.root 'materialized-package.json'
  $driverText=@'
param([string]$RepoRoot,[string]$OutputRoot,[string]$CandidateId,[string]$ReceiptPath,[string]$Target,[string]$DistributionVersion)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/mir/application/package/TargetMaterializer.ps1')
$record=New-MIR4TargetPackage -RepoRoot $RepoRoot -Target $Target -CandidateId $CandidateId -SourceVersion '4.2.1' -DistributionVersion $DistributionVersion -OutputRoot $OutputRoot
[IO.File]::WriteAllText($ReceiptPath,($record | ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
'@
  [IO.File]::WriteAllText($driver,$driverText,[Text.UTF8Encoding]::new($false))
  $output=[IO.Path]::GetRelativePath($RepoRoot,(Join-Path $Context.root 'packages')).Replace('\','/')
  $run=Invoke-MIRNativeProbeProcess -Context $Context -FilePath (Get-Command pwsh).Source -TimeoutSeconds 180 `
    -Arguments @('-NoProfile','-File',$driver,'-RepoRoot',$RepoRoot,'-OutputRoot',$output,
      '-CandidateId',($prefix+'-'+[guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()),'-ReceiptPath',$receipt,
      '-Target',$targetKey,'-DistributionVersion',[string]$identity.distribution_version)
  if(-not (Test-Path -LiteralPath $receipt -PathType Leaf)) { throw '[mir-native-probe-package-receipt]' }
  return Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json -Depth 30
}
