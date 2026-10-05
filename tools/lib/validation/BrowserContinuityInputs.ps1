Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NativeProbeResources.ps1')

function Get-MIRBrowserContinuityReadmeSha256 {
  param([string]$RepositoryRoot,[ValidateSet('f210','f200')][string]$Target,[ValidateSet('4.2.0','4.2.1')][string]$SourceVersion,[string]$ReadmePath)
  . (Join-Path $RepositoryRoot 'tools/mir/application/package/TargetMaterializer.ps1')
  $Target=$Target.ToLowerInvariant()
  $state=Get-MIR4TargetMaterializerState -RepoRoot $RepositoryRoot -Target $Target
  $binding=@((Get-MIR4TargetMaterializationBindings -State $state).bindings|Where-Object output_path -CEQ 'README.md')
  if($binding.Count-ne 1-or [IO.Path]::GetFullPath($ReadmePath)-ine [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $binding[0].source_path))){throw '[mir-browser-continuity-readme-authority]'}
  $bytes=Read-MIR4CanonicalSourceBindingBytes -State $state -Binding $binding[0]
  if($SourceVersion-ceq'4.2.1'){
    $identity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $Target.Substring(1) -SourceMinor 2 -SourcePatch 1
    $bytes=Get-MIR4PrivatePatchPackageReadmeBytes -ReadmeBytes $bytes -DistributionVersion $identity.distribution_version
  }
  Get-MIR4Sha256Bytes -Bytes $bytes
}

function Read-MIRBrowserContinuityJson {
  param([string]$Path,[switch]$LeaseReceipts)
  if((Get-Item -LiteralPath $Path).Length -gt 32MB){throw '[mir-browser-continuity-json-budget]'}
  $json=Get-Content -LiteralPath $Path -Raw
  $arguments=@{Depth=40};$preserves=(Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')
  if($preserves){$arguments.DateKind='String'}
  $record=$json|ConvertFrom-Json @arguments
  if(-not$preserves){
    $document=[Text.Json.JsonDocument]::Parse($json)
    try{
      if($LeaseReceipts){
        $rows=$document.RootElement.GetProperty('immutable_input_receipts');$index=0
        foreach($row in $rows.EnumerateArray()){
          foreach($name in @('started_utc','receipt_captured_utc','completed_utc')){$record.immutable_input_receipts[$index].$name=$row.GetProperty($name).GetString()}
          $index++
        }
      }else{$record.owner_started_utc=$document.RootElement.GetProperty('owner_started_utc').GetString()}
    }finally{$document.Dispose()}
  }
  $record
}

function Read-MIRBrowserContinuityOwnedJob {
  param([string]$RepositoryRoot,[string]$ScriptPath,[string]$RequestPath,[string]$RequestSha256)
  $path=Resolve-MIR441RecoveryScratchPath -Path $RequestPath
  if($RequestSha256 -cnotmatch '^[0-9A-F]{64}$' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $RequestSha256){throw '[mir-browser-continuity-owned-request-hash]'}
  $job=Read-MIRBrowserContinuityJson -Path $path
  $root=Resolve-MIR441RecoveryScratchPath -Path ([string]$job.root)
  $parent=Get-CimInstance Win32_Process -Filter "ProcessId=$PID"
  $owner=Get-Process -Id ([int]$job.owner_pid) -ErrorAction Stop
  try{
    if($job.schema -ne 1 -or $job.kind -cne 'MIRBrowserContinuityOwnedJobV1' -or
      [IO.Path]::GetFullPath($RepositoryRoot) -ine [string]$job.repository_root -or
      [IO.Path]::GetFullPath($ScriptPath) -ine [string]$job.script_path -or
      [int]$parent.ParentProcessId -ne [int]$job.owner_pid -or
      $owner.StartTime.ToUniversalTime().ToString('o') -cne [string]$job.owner_started_utc -or
      (Get-FileHash -LiteralPath $ScriptPath -Algorithm SHA256).Hash -cne [string]$job.harness_sha256 -or
      -not (Test-MIR441PathContained -Root $root -Path $path)) {throw '[mir-browser-continuity-owned-request-binding]'}
  }finally{$owner.Dispose()}
  $job
}

function Invoke-MIRBrowserContinuityGovernedRun {
  param([string]$RepositoryRoot,[string]$ScriptPath,[Collections.IDictionary]$Parameters,[string]$OutputRoot,[int]$ExpectedPeakMemoryMiB,[int]$MaxNewOutputMiB)
  & (Join-Path $RepositoryRoot 'tools/commands/workspace/Test-MIRDevelopmentHealth.ps1') -RepoRoot $RepositoryRoot -AsJson -MaxScanSeconds 3 -MaxEntriesPerRoot 2000|Out-Null
  $context=New-MIRNativeProbeResourceContext -RepoRoot $RepositoryRoot -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
  $archive=[string]$Parameters.CandidateArchive
  if(-not[IO.Path]::IsPathRooted($archive)){$archive=Join-Path $RepositoryRoot $archive}
  $Parameters.CandidateArchive=(Resolve-Path -LiteralPath $archive).Path
  if($Parameters.FactorioExe-and-not[IO.Path]::IsPathRooted([string]$Parameters.FactorioExe)){$Parameters.FactorioExe=(Resolve-Path -LiteralPath (Join-Path $RepositoryRoot ([string]$Parameters.FactorioExe))).Path}
  $dirty=@(&git -C $RepositoryRoot status --porcelain --untracked-files=no)
  if($LASTEXITCODE -ne 0 -or $dirty.Count){throw '[mir-browser-continuity-tracked-source-dirty]'}
  $owner=Get-Process -Id $PID
  try{$started=$owner.StartTime.ToUniversalTime().ToString('o')}finally{$owner.Dispose()}
  $job=[ordered]@{schema=1;kind='MIRBrowserContinuityOwnedJobV1';repository_root=$RepositoryRoot;script_path=$ScriptPath;harness_sha256=(Get-FileHash -LiteralPath $ScriptPath -Algorithm SHA256).Hash;owner_pid=$PID;owner_started_utc=$started;root=$context.root;parameters=$Parameters;candidate_archive_sha256=(Get-FileHash -LiteralPath ([string]$Parameters.CandidateArchive) -Algorithm SHA256).Hash}
  New-Item -ItemType Directory -Path $context.root -ErrorAction Stop|Out-Null
  $request=Join-Path $context.root 'owned-job.json'
  [IO.File]::WriteAllText($request,($job|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
  $arguments=@('-NoProfile','-File',$ScriptPath)
  foreach($entry in $Parameters.GetEnumerator()){$arguments+=@(('-'+[string]$entry.Key),([string]$entry.Value))}
  $arguments+=@('-OwnedJobPath',$request,'-OwnedJobSha256',(Get-FileHash -LiteralPath $request -Algorithm SHA256).Hash)
  $requestHandle=[IO.File]::Open($request,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try{$run=Invoke-MIRNativeProbeProcess -Context $context -FilePath (Get-Command pwsh).Source -Arguments $arguments -TimeoutSeconds 3600}finally{$requestHandle.Dispose()}
  $receipt=Join-Path $context.root 'worker/browser-personal-state-continuity-receipt.json'
  if(-not $run.result.passed -or -not(Test-Path -LiteralPath $receipt -PathType Leaf)){throw '[mir-browser-continuity-worker-receipt]'}
  $record=Read-MIRBrowserContinuityJson -Path $receipt -LeaseReceipts
  $expectedStages=if($Parameters.StageLimit -ceq 'Full'){@('initial','save-reload','configuration-change','removal','readd')}else{@('initial')}
  $expectedStatus=if($Parameters.StageLimit -ceq 'Full'){'passed'}else{'checkpointed'}
  if($record.source.harness_sha256 -cne $job.harness_sha256 -or $record.status -cne $expectedStatus -or
    $record.source_version -cne $Parameters.SourceVersion -or $record.target.key -cne $Parameters.Target.ToUpperInvariant() -or
    $record.input_mode -cne $Parameters.InputMode -or $record.candidate.archive_sha256 -cne $job.candidate_archive_sha256 -or
    (@($record.stages.stage)-join'|') -cne ($expectedStages-join'|') -or @($record.immutable_input_receipts).Count -ne $(if($Parameters.StageLimit -ceq 'Full'){4}else{1})){throw '[mir-browser-continuity-worker-receipt-binding]'}
  foreach($inputReceipt in $record.immutable_input_receipts){$null=Assert-MIRImmutableInputTerminalReceipt -Receipt $inputReceipt}
  $result=[ordered]@{kind='MIRBrowserContinuityGovernedRunV1';status=$record.status;receipt=$receipt;receipt_sha256=(Get-FileHash -LiteralPath $receipt -Algorithm SHA256).Hash;whole_process_tree=$run;immutable_input_receipts=$record.immutable_input_receipts;archive_bytes_discounted=0;release_qualification=$false}
  # All alias entries are charged conservatively in this lifecycle job.
  Write-MIRNativeProbeResult -Context $context -Record $result
  Write-Output "MIR_BROWSER_PERSONAL_STATE_CONTINUITY_RECEIPT=$receipt"
  Write-Output "MIR_BROWSER_CONTINUITY_GOVERNED_RESULT=$(Join-Path $context.root 'result.json')"
}

function New-MIRBrowserContinuityProfile {
  param([string]$JobRoot,[string]$Phase,[object[]]$Inputs,$PreviousProfile=$null)
  $root=Resolve-MIR441RecoveryScratchPath -Path $JobRoot
  if($Phase -cnotmatch '^[a-z][a-z-]{0,39}$'){throw '[mir-browser-continuity-profile-phase]'}
  if($null -ne $PreviousProfile -and -not $PreviousProfile.lease.closed){throw '[mir-browser-continuity-previous-profile-active]'}
  if($null -ne $PreviousProfile){$null=Assert-MIRImmutableInputTerminalReceipt -Receipt $PreviousProfile.lease.record}
  $run=Join-Path $root ('profiles/'+$Phase)
  if(Test-Path -LiteralPath $run){throw '[mir-browser-continuity-profile-preserved]'}
  New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
  $lease=$null
  try{
    $lease=New-MIRImmutableInputLease -RunRoot $run -StageDirectory (Join-Path $run 'mods') -Inputs $Inputs -RequireHardLinks
    if($null -ne $PreviousProfile){
      Assert-MIRImmutableInputDirectory -Path $PreviousProfile.mods -Context 'Browser continuity previous private settings directory'
      $source=Join-Path $PreviousProfile.mods 'mod-settings.dat';$target=Join-Path $lease.record.stage_directory 'mod-settings.dat'
      if(-not (Test-MIR441PathContained -Root $root -Path $source)){throw '[mir-browser-continuity-settings-boundary]'}
      if(Test-Path -LiteralPath $source -PathType Leaf){
        if((Get-Item -LiteralPath $source -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw '[mir-browser-continuity-settings-reparse]'}
        Move-Item -LiteralPath $source -Destination $target -ErrorAction Stop
      }
    }
    [pscustomobject]@{lease=$lease;mods=[string]$lease.record.stage_directory;phase=$Phase}
  }catch{
    if($null-ne$lease-and-not$lease.closed){try{$null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed}catch{Write-Warning $_.Exception.Message}}
    throw
  }
}
