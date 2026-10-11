Set-StrictMode -Version Latest

# A narrow native consumer for the current performance patch. It uses the
# repository's direct-library transaction and creates only selection, config,
# log, save, and result files under the caller-owned output root.
. (Join-Path $PSScriptRoot '../compatibility/LibraryActivation.ps1')
. (Join-Path $PSScriptRoot 'NativeProbeResources.ps1')

function Assert-MIRDirectLibraryStartupMeasurement {
  param([bool]$Condition,[string]$Code)
  if(-not $Condition){throw "[mir-direct-startup-$Code]"}
}

function Get-MIRDirectLibraryStartupArchive {
  param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$LibraryDirectory)
  $library=(Resolve-Path -LiteralPath $LibraryDirectory).Path
  $path=(Resolve-Path -LiteralPath $Archive).Path
  Assert-MIRLibraryPath $path
  Assert-MIRDirectLibraryStartupMeasurement ([IO.Path]::GetDirectoryName($path) -ceq $library) 'archive-not-in-selected-library'
  $zip=[IO.Compression.ZipFile]::OpenRead($path)
  try {
    $entries=@($zip.Entries|Where-Object {$_.FullName -match '^[^/]+/info[.]json$'})
    Assert-MIRDirectLibraryStartupMeasurement ($entries.Count -eq 1 -and $entries[0].Length -le 64KB) 'archive-metadata'
    $reader=[IO.StreamReader]::new($entries[0].Open())
    try {$info=$reader.ReadToEnd()|ConvertFrom-Json -AsHashtable} finally {$reader.Dispose()}
  } finally {$zip.Dispose()}
  Assert-MIRDirectLibraryStartupMeasurement ([string]$info.name -ceq 'more-infinite-research') 'archive-name'
  Assert-MIRDirectLibraryStartupMeasurement ([string]$info.version -match '^4[.]2[.]\d{5}$') 'archive-version'
  Assert-MIRDirectLibraryStartupMeasurement ([IO.Path]::GetFileName($path) -ceq ('more-infinite-research_'+[string]$info.version+'.zip')) 'archive-filename'
  [pscustomobject][ordered]@{path=$path;name=[string]$info.name;version=[string]$info.version;sha256=Get-MIRImmutableInputSha256 -Path $path}
}

function Assert-MIRDirectLibraryPublished422Manifest {
  param([Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$ExpectedSha256,[Parameter(Mandatory)]$PublishedArchive,[Parameter(Mandatory)][string]$Target)
  Assert-MIRDirectLibraryStartupMeasurement ($ExpectedSha256 -match '^[A-Fa-f0-9]{64}$') 'published-manifest-expected-hash'
  $path=(Resolve-Path -LiteralPath $ManifestPath).Path;$actual=Get-MIRImmutableInputSha256 -Path $path
  Assert-MIRDirectLibraryStartupMeasurement ($actual -ceq $ExpectedSha256.ToUpperInvariant()) 'published-manifest-hash'
  $manifest=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100 -DateKind String
  $sourceVersion=if($manifest.PSObject.Properties['release']){[string]$manifest.release.source_version}else{[string]$manifest.source_version}
  Assert-MIRDirectLibraryStartupMeasurement ($sourceVersion -ceq '4.2.2') 'published-manifest-release'
  $assets=@()
  if($manifest.PSObject.Properties['package_assets']){$assets=@($manifest.package_assets)}
  elseif($manifest.PSObject.Properties['targets']){$assets=@($manifest.targets)}
  elseif($manifest.PSObject.Properties['assets']){$assets=@($manifest.assets|Where-Object {[string]$_.target -ceq $Target})}
  $rows=@($assets|Where-Object {[string]$_.target -ceq $Target})
  Assert-MIRDirectLibraryStartupMeasurement ($rows.Count -eq 1) 'published-manifest-target'
  $row=$rows[0]
  Assert-MIRDirectLibraryStartupMeasurement ([string]$row.distribution_version -ceq [string]$PublishedArchive.version -and [string]$row.sha256 -ceq [string]$PublishedArchive.sha256) 'published-manifest-archive'
  return [pscustomobject][ordered]@{path=$path;sha256=$actual;source_version=$sourceVersion;source_commit=$(if($manifest.PSObject.Properties['source']){[string]$manifest.source.commit}else{''});source_tree=$(if($manifest.PSObject.Properties['source']){[string]$manifest.source.tree}else{''});target=$Target;archive_sha256=[string]$row.sha256}
}

function Get-MIRDirectLibraryStartupEngineIdentity {
  param([Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$EngineDataDirectory)
  $base=Get-Content -Raw -LiteralPath (Join-Path $EngineDataDirectory 'base/info.json')|ConvertFrom-Json -Depth 20
  $file=Get-Item -LiteralPath $FactorioBin
  [pscustomobject][ordered]@{path=$file.FullName;sha256=Get-MIRImmutableInputSha256 -Path $file.FullName;file_version=[string]$file.VersionInfo.FileVersion;product_version=[string]$file.VersionInfo.ProductVersion;base_version=[string]$base.version}
}

function Read-MIRDirectLibraryStartupProfile {
  param([Parameter(Mandatory)][string]$Path)
  $value=(Get-Content -Raw -LiteralPath $Path).TrimStart([char]0xFEFF)|ConvertFrom-Json -AsHashtable
  Assert-MIRDirectLibraryStartupMeasurement ($value.ContainsKey('mods') -and $value.mods -is [array]) 'profile-shape'
  $rows=@($value.mods)
  Assert-MIRDirectLibraryStartupMeasurement ($rows.Count -gt 0 -and @($rows|Group-Object name|Where-Object Count -gt 1).Count -eq 0) 'profile-rows'
  foreach($row in $rows){
    Assert-MIRDirectLibraryStartupMeasurement ($row.enabled -is [bool] -and (Test-MIRLibraryModName ([string]$row.name))) 'profile-row'
    if($row.enabled){Assert-MIRDirectLibraryStartupMeasurement ([string]$row.version -match '^\d+[.]\d+[.]\d+$') 'profile-version'}
  }
  Assert-MIRDirectLibraryStartupMeasurement (@($rows|Where-Object {$_.enabled -and $_.name -ceq 'base'}).Count -eq 1) 'profile-base'
  return @($rows|Where-Object {$_.name -cne 'more-infinite-research'})
}

function Write-MIRDirectLibraryStartupProfile {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object[]]$BaseRows,[AllowNull()]$MirArchive)
  $rows=[Collections.Generic.List[object]]::new()
  foreach($row in $BaseRows){$rows.Add([ordered]@{name=[string]$row.name;version=[string]$row.version;enabled=[bool]$row.enabled})}
  if($null -ne $MirArchive){$rows.Add([ordered]@{name='more-infinite-research';version=[string]$MirArchive.version;enabled=$true})}
  [IO.File]::WriteAllText($Path,([ordered]@{mods=@($rows)}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}

function Get-MIRDirectLibraryStartupArchiveHashes {
  param([Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$EngineDataDirectory,[Parameter(Mandatory)][object[]]$BaseRows,[AllowNull()]$MirArchive)
  $inventory=@(Get-MIRLibraryInventory -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory)
  $wanted=@($BaseRows|Where-Object enabled)
  if($null -ne $MirArchive){$wanted+=,[pscustomobject]@{name='more-infinite-research';version=[string]$MirArchive.version;enabled=$true}}
  $hashes=@{}
  foreach($row in $wanted){
    $matches=@($inventory|Where-Object {$_.name -ceq [string]$row.name -and $_.version -ceq [string]$row.version})
    Assert-MIRDirectLibraryStartupMeasurement ($matches.Count -eq 1) 'selected-archive-missing'
    if(-not $matches[0].builtin){$hashes[[IO.Path]::GetFileName([string]$matches[0].path)]=Get-MIRImmutableInputSha256 -Path ([string]$matches[0].path)}
  }
  return $hashes
}

function New-MIRDirectLibraryStartupConfig {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$EngineDataDirectory,[Parameter(Mandatory)][string]$WriteDataDirectory)
  $text="[path]`nread-data=$EngineDataDirectory`nwrite-data=$WriteDataDirectory`n`n[general]`nlocale=en`n`n[other]`nenable-new-mods=false`nenable-steam-networking=false`ndisable-blueprint-storage=true`n"
  [IO.File]::WriteAllText($Path,$text,[Text.UTF8Encoding]::new($false))
}

function Invoke-MIRDirectLibraryStartupSample {
  param(
    [Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$EngineDataDirectory,
    [Parameter(Mandatory)][object[]]$BaseRows,[Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$WriteDataRoot,[Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)]$Resources,[AllowNull()]$MirArchive,[ValidateRange(1,3600)][int]$TimeoutSeconds=300,[string]$ActiveModsObserver=''
  )
  [IO.Directory]::CreateDirectory($RunRoot)|Out-Null
  [IO.Directory]::CreateDirectory($WriteDataRoot)|Out-Null
  $profile=Join-Path $RunRoot 'selection.json';$config=Join-Path $RunRoot 'config.ini';$log=Join-Path $RunRoot 'factorio.log';$saveDirectory=Join-Path $RunRoot 'saves';$save=Join-Path $saveDirectory 'startup-ready.zip';$engineLog=Join-Path $WriteDataRoot 'factorio-current.log'
  [IO.Directory]::CreateDirectory($saveDirectory)|Out-Null
  Write-MIRDirectLibraryStartupProfile -Path $profile -BaseRows $BaseRows -MirArchive $MirArchive
  # The first sample and immediate warm-repeat samples for one selected
  # configuration share this private write-data root. Per-sample logs and
  # saves remain isolated in RunRoot, so a prior ready endpoint cannot be
  # mistaken for the successor's result.
  New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $EngineDataDirectory -WriteDataDirectory $WriteDataRoot
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -BaseRows $BaseRows -MirArchive $MirArchive
  $activation=$null
  try {
    $activation=Start-MIRLibraryActivation -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -ProfilePath $profile -ArchiveHashes $hashes -SettingsMode Defaults
    Add-MIRNativeProbeLibraryActivation -Context $Resources -Activation $activation
    Assert-MIRDirectLibraryStartupMeasurement (-not(Test-Path -LiteralPath $save)) 'ready-save-preexisting'
    # write-data is intentionally retained for this configuration's warm
    # repeat. The engine log is not: remove only this owned previous log so
    # every snapshot has a native invocation boundary from this run.
    if(Test-Path -LiteralPath $engineLog){Remove-Item -LiteralPath $engineLog -Force}
    $arguments=@('--config',$config,'--mod-directory',$activation.library,'--no-log-rotation','--disable-audio','--create',$save)
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $FactorioBin -Arguments $arguments
    $native=Invoke-MIRNativeProbeFactorioProcess -Context $Resources -FilePath $FactorioBin -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
    Assert-MIRDirectLibraryStartupMeasurement ($native.result.passed -and -not $native.result.timed_out -and $native.result.exit_code -eq 0) 'process-exit'
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $save -PathType Leaf) 'ready-save'
    # Factorio 2.0 writes its actual current log beneath write-data. Snapshot
    # it after process exit so the per-sample evidence survives the warm run.
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $engineLog -PathType Leaf) 'engine-current-log'
    [IO.File]::Copy($engineLog,$log,$true)
    $logText=Get-Content -Raw -LiteralPath $log
    Assert-MIRDirectLibraryStartupMeasurement ($logText -match '(?m)^\s*\d+[.]\d+ Factorio initialised\s*$') 'ready-initialised'
    Assert-MIRDirectLibraryStartupMeasurement ($logText -match ('(?m)^\s*\d+[.]\d+ Info Create[.]cpp:\d+: Creating new map '+[regex]::Escape($save)+'\s*$')) 'ready-create'
    $zip=[IO.Compression.ZipFile]::OpenRead($save)
    try {$mapEntries=@($zip.Entries|Where-Object {$_.FullName -match '(^|/)level(?:-init)?[.]dat$'});Assert-MIRDirectLibraryStartupMeasurement ($mapEntries.Count -eq 1) 'ready-save-map-data';$mapEntry=[string]$mapEntries[0].FullName} finally {$zip.Dispose()}
    $observerIdentity=$null
    if(-not [string]::IsNullOrWhiteSpace($ActiveModsObserver)){
      $observerRows=@($activation.selected|Where-Object {$_.name -ceq $ActiveModsObserver})
      Assert-MIRDirectLibraryStartupMeasurement ($observerRows.Count -eq 1) 'active-mods-observer-selection'
      $observer=$observerRows[0]
      Assert-MIRDirectLibraryStartupMeasurement (-not [bool]$observer.builtin -and [string]$observer.sha256 -match '^[A-Fa-f0-9]{64}$') 'active-mods-observer-identity'
      $observerIdentity=[ordered]@{name=[string]$observer.name;version=[string]$observer.version;archive=[IO.Path]::GetFileName([string]$observer.path);sha256=[string]$observer.sha256}
    }
    $loaded=@(Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -LatestInvocation -ActiveModsObserver $ActiveModsObserver)
    $initialised=[regex]::Matches($logText,'(?m)^\s*(?<seconds>\d+[.]\d+) Factorio initialised\s*$')|Select-Object -Last 1
    [pscustomobject][ordered]@{label=$Label;run_relative_path=[IO.Path]::GetRelativePath($Resources.root,$RunRoot).Replace('\','/');elapsed_seconds=[double]$native.result.duration_seconds;engine_log_initialised_seconds=[double]::Parse($initialised.Groups['seconds'].Value,[Globalization.CultureInfo]::InvariantCulture);exit_code=$native.result.exit_code;endpoint_class='headless-create-diagnostic';ready_endpoint='Factorio --create exits successfully after the actual current log records initialisation and map creation, with one initial map-data entry in the new save ZIP';ready_save=[IO.Path]::GetRelativePath($RunRoot,$save).Replace('\','/');ready_save_map_entry=$mapEntry;loaded_selection=$loaded;active_mods_observer=$observerIdentity;process_memory=[ordered]@{peak_working_set_bytes=[int64]$native.result.peak_working_set_bytes;peak_sampled_private_bytes=[int64]$native.result.peak_sampled_private_bytes;measurement='NativeProbeResources monitored process tree; values are not whole-system memory'};resource_ledger=[IO.Path]::GetRelativePath($Resources.root,$native.ledger).Replace('\','/');log=[IO.Path]::GetRelativePath($RunRoot,$log).Replace('\','/');engine_current_log=[IO.Path]::GetRelativePath($Resources.root,$engineLog).Replace('\','/')}
  } finally {
    if($null -ne $activation -and -not $activation.closed){Complete-MIRLibraryActivation -Activation $activation|Out-Null}
  }
}

function Invoke-MIRDirectLibraryStartupMeasurement {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$ProfileTemplatePath,
    [Parameter(Mandatory)][string]$Published422Archive,[Parameter(Mandatory)][string]$Published422ManifestPath,[Parameter(Mandatory)][string]$Published422ManifestSha256,
    [string]$CandidateArchive='',[string]$CandidateMaterializationArchive='',[string]$CandidateMaterializationReceiptPath='',[switch]$Preliminary,[Parameter(Mandatory)][string]$OutputRoot,
    [ValidateSet('f200','f210')][string]$Target='f200',[ValidateRange(0,5)][int]$WarmupRuns=1,[ValidateRange(1,25)][int]$MeasuredRuns=3,[ValidateRange(1,3600)][int]$TimeoutSeconds=300,
    [Parameter(Mandatory)][ValidateRange(1,8192)][int]$ExpectedPeakMemoryMiB,[ValidateRange(1,2048)][int]$MaxNewOutputMiB=120,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{40}$')][string]$SourceCommit,[string]$ActiveModsObserver=''
  )
  $repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
  $observedCommit=(& git -C $repo rev-parse HEAD).Trim().ToLowerInvariant()
  Assert-MIRDirectLibraryStartupMeasurement ($observedCommit -ceq $SourceCommit.ToLowerInvariant()) 'source-commit'
  $dirty=@(& git -C $repo status --porcelain).Count -gt 0
  $sourceObservation=[ordered]@{requested_commit=$SourceCommit.ToLowerInvariant();head_commit=$observedCommit;working_tree_dirty=$dirty}
  $engine=(Resolve-Path -LiteralPath $FactorioBin).Path;$library=(Resolve-Path -LiteralPath $LibraryDirectory).Path;$template=(Resolve-Path -LiteralPath $ProfileTemplatePath).Path
  $engineRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $engine));$data=Join-Path $engineRoot 'data'
  Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $data -PathType Container) 'engine-data'
  Assert-MIRDirectLibraryStartupMeasurement (-not(Test-Path -LiteralPath $OutputRoot)) 'output-exists'
  $engineIdentity=Get-MIRDirectLibraryStartupEngineIdentity -FactorioBin $engine -EngineDataDirectory $data
  $published=Get-MIRDirectLibraryStartupArchive -Archive $Published422Archive -LibraryDirectory $library;$code=$Target.Substring(1)
  Assert-MIRDirectLibraryStartupMeasurement ($published.version -ceq "4.2.${code}02") 'published-identity'
  $publishedManifest=Assert-MIRDirectLibraryPublished422Manifest -ManifestPath $Published422ManifestPath -ExpectedSha256 $Published422ManifestSha256 -PublishedArchive $published -Target $Target
  $hasCandidate=-not [string]::IsNullOrWhiteSpace($CandidateArchive)
  Assert-MIRDirectLibraryStartupMeasurement (($hasCandidate -and -not $Preliminary) -or (-not $hasCandidate -and $Preliminary)) 'candidate-mode'
  $candidate=$null;$candidateMaterialization=$null
  if($hasCandidate){
    Assert-MIRDirectLibraryStartupMeasurement (-not [string]::IsNullOrWhiteSpace($CandidateMaterializationArchive) -and -not [string]::IsNullOrWhiteSpace($CandidateMaterializationReceiptPath)) 'candidate-materialization-inputs'
    # NativeProbeResources owns receipt validation but deliberately does not
    # load the package materializer at module import time. The matched
    # candidate path needs that authoritative reader and its dependencies.
    . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
    $candidate=Get-MIRDirectLibraryStartupArchive -Archive $CandidateArchive -LibraryDirectory $library
    Assert-MIRDirectLibraryStartupMeasurement ($candidate.version -ceq "4.2.${code}03") 'candidate-identity'
    $candidateMaterialization=Read-MIRNativeProbeCurrentCandidate -Repository $repo -Archive $CandidateMaterializationArchive -ReceiptPath $CandidateMaterializationReceiptPath -Target $Target -SourceVersion '4.2.3'
    Assert-MIRDirectLibraryStartupMeasurement ([string]$candidateMaterialization.receipt.archive_sha256 -ceq [string]$candidate.sha256) 'candidate-materialization-archive'
  }
  $base=Read-MIRDirectLibraryStartupProfile -Path $template
  if(-not [string]::IsNullOrWhiteSpace($ActiveModsObserver)){
    Assert-MIRDirectLibraryStartupMeasurement (Test-MIRLibraryModName $ActiveModsObserver) 'active-mods-observer-name'
    Assert-MIRDirectLibraryStartupMeasurement (@($base|Where-Object {$_.enabled -and $_.name -ceq $ActiveModsObserver}).Count -eq 1) 'active-mods-observer-profile'
  }
  $templateSha=Get-MIRImmutableInputSha256 -Path $template
  $resources=$null;$records=$null;$currentLabel=''
  try {
    $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB -UseExactOutputRoot
    [IO.Directory]::CreateDirectory($resources.root)|Out-Null;$records=[Collections.Generic.List[object]]::new()
    $kinds=@([pscustomobject]@{label='without-mir';archive=$null},[pscustomobject]@{label='released-4.2.2';archive=$published})
    if($hasCandidate){$kinds+=,[pscustomobject]@{label='candidate-4.2.3';archive=$candidate}}
    $ordinals=@{};foreach($kind in $kinds){$ordinals[$kind.label]=0}
    # Rotate configurations by block and record the actual predecessor for
    # every first sample. A rotation can bring the same selection to the start
    # of the next block; do not call that a changed configuration.
    $previousSelection=$null
    for($block=1;$block-le($WarmupRuns+$MeasuredRuns);$block++){
    $offset=($block-1)%$kinds.Count
    for($position=0;$position-lt$kinds.Count;$position++){
      $kind=$kinds[($offset+$position)%$kinds.Count]
      $changed=if($null-eq$previousSelection){$null}else{[bool]($previousSelection-cne$kind.label)}
      $firstState=if($null-eq$previousSelection){'initial-selection'}elseif($changed){'changed-configuration'}else{'same-selection'}
      $samplePlan=@(
        [pscustomobject]@{cache_state=$firstState;prior_selection_label=$previousSelection;selection_changed=$changed},
        [pscustomobject]@{cache_state='warm-repeat';prior_selection_label=$kind.label;selection_changed=$false}
      )
      foreach($samplePlanRow in $samplePlan){
        $ordinals[$kind.label]++;$ordinal=$ordinals[$kind.label]
        $runRoot=Join-Path $resources.root ('runs/'+$kind.label+'/'+$ordinal+'/'+[string]$samplePlanRow.cache_state)
        $writeDataRoot=Join-Path $resources.root ('write-data/'+$kind.label)
        $currentLabel=[string]$kind.label
        $record=Invoke-MIRDirectLibraryStartupSample -FactorioBin $engine -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $base -RunRoot $runRoot -WriteDataRoot $writeDataRoot -Label $kind.label -Resources $resources -MirArchive $kind.archive -TimeoutSeconds $TimeoutSeconds -ActiveModsObserver $ActiveModsObserver
        $record|Add-Member -NotePropertyName sample -NotePropertyValue $ordinal
        $record|Add-Member -NotePropertyName measurement_block -NotePropertyValue $block
        $record|Add-Member -NotePropertyName configuration_order -NotePropertyValue ($position+1)
        $record|Add-Member -NotePropertyName cache_state -NotePropertyValue ([string]$samplePlanRow.cache_state)
        $record|Add-Member -NotePropertyName prior_selection_label -NotePropertyValue $samplePlanRow.prior_selection_label
        $record|Add-Member -NotePropertyName selection_changed -NotePropertyValue $samplePlanRow.selection_changed
        $record|Add-Member -NotePropertyName warmup -NotePropertyValue ($block -le $WarmupRuns)
        $records.Add($record)
      }
      $previousSelection=[string]$kind.label
    }
    }
    $inputs=[ordered]@{active_mods_observer=$(if([string]::IsNullOrWhiteSpace($ActiveModsObserver)){$null}else{[string]$ActiveModsObserver});published_422=[ordered]@{archive=$published;authenticated_manifest=$publishedManifest};candidate_423=$(if($hasCandidate){[ordered]@{archive=$candidate;materialization=[ordered]@{archive_path=$candidateMaterialization.path;archive_sha256=$candidateMaterialization.receipt.archive_sha256;receipt_path=$CandidateMaterializationReceiptPath;receipt_sha256=Get-MIRImmutableInputSha256 -Path $CandidateMaterializationReceiptPath;source_version=$candidateMaterialization.receipt.source_version;package_source_sha256=$candidateMaterialization.receipt.package_source_sha256;source_manifest_sha256=$candidateMaterialization.receipt.source_manifest_sha256}}}else{$null})}
    $result=[pscustomobject][ordered]@{schema=1;kind='MIRDirectLibraryStartupMeasurementV1';status='completed';mode=$(if($hasCandidate){'matched-three-input'}else{'preliminary-two-input'});target=$Target;source_observation=$sourceObservation;factorio=$engineIdentity;library=$library;profile_template_sha256=$templateSha;inputs=$inputs;endpoint_class='headless-create-diagnostic';resource_context=[ordered]@{expected_peak_memory_bytes=$resources.peak_memory_bytes;max_new_output_bytes=$resources.max_new_output_bytes;processes=@($resources.runs)};samples=@($records);library_controls_restored=(-not(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json')));measurement_notes=@('Elapsed time is native process start-to-exit time recorded by NativeProbeResources.','Peak process values are monitored process-tree samples, not whole-system memory.','Each selected configuration retains one private write-data root across blocks; per-sample logs and saves stay isolated.','Each first sample records its actual prior selection and whether it changed; immediate repeats are marked warm-repeat.','All configurations use the same selected archive library serially; controls are restored after every sample.')}
    Write-MIRNativeProbeResult -Context $resources -Record $result;return $result
  } catch {
    if($null-ne$resources){
      $failureInputs=[ordered]@{active_mods_observer=$(if([string]::IsNullOrWhiteSpace($ActiveModsObserver)){$null}else{[string]$ActiveModsObserver});published_422=[ordered]@{archive=$published;authenticated_manifest=$publishedManifest};candidate_423=$(if($hasCandidate -and $null-ne$candidate){[ordered]@{archive=$candidate;materialization=$candidateMaterialization}}else{$null})}
      $failure=[pscustomobject][ordered]@{schema=1;kind='MIRDirectLibraryStartupMeasurementV1';status='failed';mode=$(if($hasCandidate){'matched-three-input'}else{'preliminary-two-input'});target=$Target;source_observation=$sourceObservation;factorio=$engineIdentity;library=$library;profile_template_sha256=$templateSha;inputs=$failureInputs;current_label=$currentLabel;samples_so_far=$(if($null-ne$records){@($records)}else{@()});error=$_.Exception.Message;library_controls_restored=(-not(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json')));resource_context=[ordered]@{expected_peak_memory_bytes=$resources.peak_memory_bytes;max_new_output_bytes=$resources.max_new_output_bytes;processes=@($resources.runs)}}
      try{Write-MIRNativeProbeResult -Context $resources -Record $failure}catch{Write-Warning "[mir-direct-startup-failure-receipt] $($_.Exception.Message)"}
    }
    throw
  }
}
