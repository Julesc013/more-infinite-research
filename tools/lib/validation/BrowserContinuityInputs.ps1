Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NativeProbeResources.ps1')
. (Join-Path $PSScriptRoot '../compatibility/FactorioRunner.ps1')

function Get-MIRBrowserContinuityReadmeSha256 {
  param([string]$RepositoryRoot,[ValidateSet('f210','f200')][string]$Target,[ValidateSet('4.2.0','4.2.1','4.2.2')][string]$SourceVersion,[string]$ReadmePath)
  . (Join-Path $RepositoryRoot 'tools/mir/application/package/TargetMaterializer.ps1')
  $Target=$Target.ToLowerInvariant()
  $state=Get-MIR4TargetMaterializerState -RepoRoot $RepositoryRoot -Target $Target
  $binding=@((Get-MIR4TargetMaterializationBindings -State $state).bindings|Where-Object output_path -CEQ 'README.md')
  if($binding.Count-ne 1-or [IO.Path]::GetFullPath($ReadmePath)-ine [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $binding[0].source_path))){throw '[mir-browser-continuity-readme-authority]'}
  $bytes=Read-MIR4CanonicalSourceBindingBytes -State $state -Binding $binding[0]
  if($SourceVersion-cin@('4.2.1','4.2.2')){
    $identity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $Target.Substring(1) -SourceMinor 2 -SourcePatch ([int]$SourceVersion.Split('.')[2])
    $bytes=Get-MIR4PrivatePatchPackageReadmeBytes -ReadmeBytes $bytes -DistributionVersion $identity.distribution_version -SourceVersion $SourceVersion
  }
  Get-MIR4Sha256Bytes -Bytes $bytes
}

function Read-MIRBrowserContinuityJson {
  param([string]$Path,[switch]$LeaseReceipts,[switch]$DocumentOnly)
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
      }elseif(-not$DocumentOnly){$record.owner_started_utc=$document.RootElement.GetProperty('owner_started_utc').GetString()}
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
  if(-not $Parameters.LibraryDirectory){throw '[mir-browser-continuity-direct-inputs-required]'}
  $Parameters.LibraryDirectory=(Resolve-Path -LiteralPath ([string]$Parameters.LibraryDirectory)).Path
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
  $record=Read-MIRBrowserContinuityJson -Path $receipt -DocumentOnly
  if($Parameters.Operation-ceq'PrepareInputs'){
    if($record.kind-cne'MIRBrowserContinuityPreparedInputsV1'-or$record.status-cne'prepared-not-native-tested'-or$record.factorio_processes-ne0-or$record.target-cne$Parameters.Target){throw '[mir-browser-continuity-prepared-receipt]'}
    foreach($archive in $record.archives){
      if(-not(Test-MIR441PathContained -Root (Join-Path $context.root 'worker') -Path $archive.path)-or(Get-MIRImmutableInputSha256 $archive.path)-cne$archive.sha256){throw '[mir-browser-continuity-prepared-archive]'}
    }
    Write-MIRNativeProbeResult -Context $context -Record ([ordered]@{kind=$record.kind;status=$record.status;receipt=$receipt;receipt_sha256=(Get-FileHash $receipt).Hash;whole_process_tree=$run;factorio_processes=0;archives=$record.archives})
    Write-Output "MIR_BROWSER_CONTINUITY_PREPARED_RESULT=$(Join-Path $context.root 'result.json')"
    return
  }
  $expectedStages=if($Parameters.StageLimit -ceq 'Full'){@('initial','save-reload','configuration-change','removal','readd')}else{@('initial')}
  $expectedStatus=if($Parameters.StageLimit -ceq 'Full'){'passed'}else{'checkpointed'}
  if($record.source.harness_sha256 -cne $job.harness_sha256 -or $record.status -cne $expectedStatus -or
    $record.source_version -cne $Parameters.SourceVersion -or $record.target.key -cne $Parameters.Target.ToUpperInvariant() -or
    $record.input_mode -cne $Parameters.InputMode -or $record.candidate.archive_sha256 -cne $job.candidate_archive_sha256 -or
    (@($record.stages.stage)-join'|') -cne ($expectedStages-join'|') -or @($record.library_input_receipts).Count -ne $(if($Parameters.StageLimit -ceq 'Full'){4}else{1})){throw '[mir-browser-continuity-worker-receipt-binding]'}
  $phases=if($Parameters.StageLimit-ceq'Full'){@('initial','configured','removed','readded')}else{@('initial')}
  if((@($record.library_input_receipts.phase)-join'|')-cne($phases-join'|')){throw '[mir-browser-continuity-worker-phases]'}
  foreach($inputReceipt in $record.library_input_receipts){Assert-MIRBrowserContinuityTerminalReceipt -Receipt $inputReceipt -JobRoot (Join-Path $context.root 'worker')}
  $result=[ordered]@{kind='MIRBrowserContinuityGovernedRunV2';status=$record.status;receipt=$receipt;receipt_sha256=(Get-FileHash -LiteralPath $receipt -Algorithm SHA256).Hash;whole_process_tree=$run;library_input_receipts=$record.library_input_receipts;archive_bytes_discounted=0;release_qualification=$false}
  # Library archives are inputs, not output-tree aliases.
  Write-MIRNativeProbeResult -Context $context -Record $result
  Write-Output "MIR_BROWSER_PERSONAL_STATE_CONTINUITY_RECEIPT=$receipt"
  Write-Output "MIR_BROWSER_CONTINUITY_GOVERNED_RESULT=$(Join-Path $context.root 'result.json')"
}

function New-MIRBrowserContinuityProfile {
  param([string]$JobRoot,[string]$Phase,[object[]]$Inputs,[string]$LibraryDirectory,[string]$EngineDataDirectory,[string]$EngineVersion,$PreviousProfile=$null)
  $root=Resolve-MIR441RecoveryScratchPath -Path $JobRoot
  if($Phase -cnotmatch '^[a-z][a-z-]{0,39}$'){throw '[mir-browser-continuity-profile-phase]'}
  if(-not $LibraryDirectory-or-not $EngineDataDirectory-or$EngineVersion-cnotmatch '^\d+[.]\d+[.]\d+$'){throw '[mir-browser-continuity-direct-inputs-required] Supply the library and engine; populated profile staging is retired.'}
  if($null -ne $PreviousProfile -and -not $PreviousProfile.activation.closed){throw '[mir-browser-continuity-previous-profile-active]'}
  if($null -ne $PreviousProfile){Assert-MIRBrowserContinuityTerminalReceipt -Receipt $PreviousProfile.terminal -JobRoot $root}
  $definition=Join-Path $root ('selections/'+$Phase+'.json')
  if(Test-Path -LiteralPath $definition){throw '[mir-browser-continuity-profile-preserved]'}
  $rows=@([ordered]@{name='base';version=$EngineVersion;enabled=$true});$hashes=[ordered]@{}
  foreach($inputRow in $Inputs){
    $name=[string]$inputRow.file_name
    if([IO.Path]::GetFileName($name)-cne$name-or$name-cnotmatch '[.]zip$'-or$hashes.Contains($name)){throw '[mir-browser-continuity-input-name]'}
    $source=[string]$inputRow.source_path;$installed=Join-Path $LibraryDirectory $name
    Assert-MIRLibraryPath $source
    if((Get-MIRImmutableInputSha256 $source)-cne$inputRow.expected_sha256){throw '[mir-browser-continuity-source-hash]'}
    if(-not(Test-Path -LiteralPath $installed -PathType Leaf)){throw "[mir-browser-continuity-library-input-missing] Install the selected input once: $name"}
    Assert-MIRLibraryPath $installed
    $zip=[IO.Compression.ZipFile]::OpenRead($source)
    try{
      $infos=@($zip.Entries|Where-Object FullName -Match '^[^/]+/info[.]json$')
      if($infos.Count-ne1-or$infos[0].Length-gt64KB){throw '[mir-browser-continuity-input-info]'}
      $reader=[IO.StreamReader]::new($infos[0].Open());try{$info=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
      if($name-cne($info.name+'_'+$info.version+'.zip')){throw '[mir-browser-continuity-input-identity]'}
      if($inputRow.role-ceq'mir-candidate'){
        if((Get-MIRImmutableInputSha256 $installed)-cne$inputRow.expected_sha256){throw '[mir-browser-continuity-candidate-hash]'}
      }else{
        # Owned fixture ZIP compression/timestamps may differ. Bind every
        # member to the current prepared source instead of rebuilding inputs.
        $other=[IO.Compression.ZipFile]::OpenRead($installed)
        try{
          if($zip.Entries.Count-gt32-or$zip.Entries.Count-ne$other.Entries.Count){throw '[mir-browser-continuity-fixture-membership]'}
          foreach($entry in $zip.Entries){
            $match=$other.GetEntry($entry.FullName)
            if($null-eq$match-or$entry.Length-gt4MB-or$match.Length-ne$entry.Length){throw '[mir-browser-continuity-fixture-member]'}
            $left=$entry.Open();$right=$match.Open()
            try{$a=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($left));$b=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($right))}finally{$left.Dispose();$right.Dispose()}
            if($a-cne$b){throw '[mir-browser-continuity-fixture-source]'}
          }
        }finally{$other.Dispose()}
      }
      $rows+=,[ordered]@{name=[string]$info.name;version=[string]$info.version;enabled=$true}
      $hashes[$name]=Get-MIRImmutableInputSha256 $installed
    }finally{$zip.Dispose()}
  }
  [IO.Directory]::CreateDirectory((Split-Path -Parent $definition))|Out-Null
  [IO.File]::WriteAllText($definition,(@{mods=$rows}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $arguments=@{LibraryDirectory=$LibraryDirectory;EngineDataDirectory=$EngineDataDirectory;ProfilePath=$definition;ArchiveHashes=$hashes;SettingsMode='Defaults'}
  if($null-ne$PreviousProfile-and$PreviousProfile.terminal.settings.exists){$arguments.SettingsMode='File';$arguments.SettingsPath=$PreviousProfile.terminal.settings.path;$arguments.SettingsSha256=$PreviousProfile.terminal.settings.sha256}
  $activation=Start-MIRLibraryActivation @arguments
  [pscustomobject]@{activation=$activation;mods=$activation.library;phase=$Phase;root=$root;terminal=$null}
}

function Complete-MIRBrowserContinuityProfile {
  param([Parameter(Mandatory)]$Profile)
  Assert-MIRLibraryIdle
  Assert-MIRLibraryActivation -Activation $Profile.activation
  $settings=Read-MIRLibraryControl (Join-Path $Profile.mods 'mod-settings.dat')
  $snapshot=Join-Path $Profile.root ('controls/'+$Profile.phase+'-mod-settings.dat')
  if(Test-Path -LiteralPath $snapshot){throw '[mir-browser-continuity-settings-preserved]'}
  if($settings.exists){
    [IO.Directory]::CreateDirectory((Split-Path -Parent $snapshot))|Out-Null
    [IO.File]::WriteAllBytes($snapshot,[Convert]::FromBase64String($settings.bytes))
    if((Get-MIRImmutableInputSha256 $snapshot)-cne$settings.sha256){throw '[mir-browser-continuity-settings-readback]'}
  }
  $terminal=Complete-MIRLibraryActivation -Activation $Profile.activation
  $terminal.phase=$Profile.phase
  $terminal.settings=[ordered]@{exists=$settings.exists;path=if($settings.exists){$snapshot}else{''};sha256=$settings.sha256}
  $Profile.terminal=$terminal
  return $terminal
}

function Assert-MIRBrowserContinuityTerminalReceipt {
  param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)][string]$JobRoot)
  if($Receipt.status-cne'restored-direct-library-controls'-or$Receipt.dependency_payload_bytes_copied-ne0-or$Receipt.archive_links_created-ne0-or$Receipt.archive_extractions-ne0-or$Receipt.profile_sha256-cnotmatch'^[A-F0-9]{64}$'){throw '[mir-browser-continuity-direct-receipt]'}
  if($Receipt.phase-cnotmatch'^[a-z][a-z-]{0,39}$'){throw '[mir-browser-continuity-direct-phase]'}
  $definition=Read-MIRLibraryControl (Join-Path $JobRoot ('selections/'+$Receipt.phase+'.json'))
  if(-not$definition.exists-or$definition.sha256-cne$Receipt.profile_sha256){throw '[mir-browser-continuity-selection-custody]'}
  $requested=([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($definition.bytes))|ConvertFrom-Json).mods
  if(@($Receipt.selected|Group-Object name|Where-Object Count -NE 1).Count-or@($Receipt.selected|Where-Object name -CEQ 'base').Count-ne1){throw '[mir-browser-continuity-selected-inputs]'}
  $identities={param($rows) @($rows|Sort-Object name|ForEach-Object {$_.name+'@'+$_.version})-join '|'}
  if((& $identities $requested)-cne(& $identities $Receipt.selected)){throw '[mir-browser-continuity-selected-inputs]'}
  foreach($row in $Receipt.selected){if($row.sha256-cnotmatch'^[A-F0-9]{64}$'-or$row.bytes-le0){throw '[mir-browser-continuity-selected-inputs]'}}
  if($Receipt.settings.exists){
    $expected=Join-Path ([IO.Path]::GetFullPath($JobRoot)) ('controls/'+$Receipt.phase+'-mod-settings.dat')
    if([IO.Path]::GetFullPath($Receipt.settings.path)-cne$expected){throw '[mir-browser-continuity-settings-boundary]'}
    $settings=Read-MIRLibraryControl $expected
    if(-not$settings.exists-or$settings.sha256-cne$Receipt.settings.sha256){throw '[mir-browser-continuity-settings-custody]'}
  }elseif($Receipt.settings.path-or$Receipt.settings.sha256){throw '[mir-browser-continuity-absent-settings]'}
}
