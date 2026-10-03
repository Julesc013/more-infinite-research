Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../../mir/application/release/readiness/Common.ps1')
. (Join-Path $PSScriptRoot '../../mir/application/release/readiness/ResourceGovernor.ps1')
. (Join-Path $PSScriptRoot 'ImmutableInputStaging.ps1')

# These adapters retain the existing governor and lease authorities. They own
# one probe's total new-output budget, not a second scheduler or package writer.
function Resolve-MIRNativeProbeDependencyInputs {
  param(
    [Parameter(Mandatory)][string]$StageRoot,
    [Parameter(Mandatory)][Collections.IDictionary]$ExpectedArchives,
    [string[]]$LocalModLibraryDirs=@()
  )
  if($ExpectedArchives.Count -lt 1 -or $ExpectedArchives.Count -gt 32 -or $LocalModLibraryDirs.Count -gt 8){throw '[mir-native-probe-dependency-input-budget]'}
  $rows=[ordered]@{}
  foreach($entry in $ExpectedArchives.GetEnumerator()){
    $name=[string]$entry.Key;$expected=[string]$entry.Value
    if($name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*[.]zip$' -or $expected -cnotmatch '^[0-9A-F]{64}$'){throw '[mir-native-probe-dependency-identity]'}
    $path=Join-Path $StageRoot (Join-Path 'mods' $name);$kind='exact-preserved-stage'
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){
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
    [ValidateRange(1,3600)][int]$TimeoutSeconds=120
  )
  $remaining=Get-MIRNativeProbeRemainingOutputBytes -Context $Context
  $Context.process_index++
  $prefix=Join-Path $Context.root ('process-'+$Context.process_index)
  try {
    $result=Invoke-MIR441MonitoredProcess -FilePath $FilePath -Arguments $Arguments -WorkRoot $Context.root `
      -Policy $Context.policy -EstimatedPeakBytes $remaining -ExpectedPeakMemoryBytes $Context.peak_memory_bytes `
      -LedgerPath ($prefix+'.resources.jsonl') -StdoutPath ($prefix+'.stdout.txt') -StderrPath ($prefix+'.stderr.txt') `
      -TimeoutSeconds $TimeoutSeconds
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

function New-MIRNativeProbeTargetPackage {
  param(
    [Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$RepoRoot,
    [ValidateSet('F210-TIN-OBS','F210-CURRENT-BA-FINAL-ROUTES-OBSERVER')][string]$CandidatePrefix='F210-TIN-OBS'
  )
  $null=Get-MIRNativeProbeRemainingOutputBytes -Context $Context
  $driver=Join-Path $Context.root 'materialize.ps1'
  $receipt=Join-Path $Context.root 'materialized-package.json'
  $driverText=@'
param([string]$RepoRoot,[string]$OutputRoot,[string]$CandidateId,[string]$ReceiptPath)
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/mir/application/package/TargetMaterializer.ps1')
$record=New-MIR4TargetPackage -RepoRoot $RepoRoot -Target f210 -CandidateId $CandidateId -SourceVersion '4.2.1' -DistributionVersion '4.2.21001' -OutputRoot $OutputRoot
[IO.File]::WriteAllText($ReceiptPath,($record | ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
'@
  [IO.File]::WriteAllText($driver,$driverText,[Text.UTF8Encoding]::new($false))
  $output=[IO.Path]::GetRelativePath($RepoRoot,(Join-Path $Context.root 'packages')).Replace('\','/')
  $run=Invoke-MIRNativeProbeProcess -Context $Context -FilePath (Get-Command pwsh).Source -TimeoutSeconds 180 `
    -Arguments @('-NoProfile','-File',$driver,'-RepoRoot',$RepoRoot,'-OutputRoot',$output,
      '-CandidateId',($CandidatePrefix+'-'+[guid]::NewGuid().ToString('N').Substring(0,8).ToUpperInvariant()),'-ReceiptPath',$receipt)
  if(-not (Test-Path -LiteralPath $receipt -PathType Leaf)) { throw '[mir-native-probe-package-receipt]' }
  return Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json -Depth 30
}
