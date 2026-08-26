if (-not (Get-Command Get-MIR4T12RecordDigest -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'ExactProcessIR.ps1')
}
if (-not (Get-Command Invoke-FactorioProcess -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../validation/FactorioProcess.ps1')
}

function Get-MIR4T13Authority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $path=Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Release-Compatibility-Canaries-T13V1.json'
  $value=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100
  if([int]$value.schema-ne 1-or[string]$value.kind-cne'MIR4ReleaseCompatibilityCanariesT13V1'-or[string]$value.work_package-cne'T13'-or@($value.canaries).Count-ne[int]$value.required_canary_count){throw '[mir4-t13-authority]'}
  foreach($flag in @('semantic_authority','player_mutation_authorized','prototype_write_authorized','automatic_synthesis_authorized','public_support_claim_authorized','source_freeze_authorized','signing_or_sealing_authorized','promotion_authorized','publication_authorized','package_visible')){if([bool]$value.$flag){throw "[mir4-t13-authority-boundary] $flag"}}
  $ids=@($value.canaries.id);if(@($ids|Sort-Object -Unique -CaseSensitive).Count-ne$ids.Count){throw '[mir4-t13-canary-id-unique]'}
  $captures=@($value.canaries.capture_ids|ForEach-Object{$_});if(@($captures|Sort-Object -Unique -CaseSensitive).Count-ne[int]$value.required_capture_count){throw '[mir4-t13-capture-closure]'}
  $value
}

function Write-MIR4T13Json {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
  $parent=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
  [IO.File]::WriteAllText($Path,(ConvertTo-MIR4ProcessIRCanonicalJson $Value)+"`n",[Text.UTF8Encoding]::new($false))
}

function Add-MIR4T13Digest {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Domain)
  $Value.digest=Get-MIR4T12RecordDigest -Value $Value -Domain $Domain
  $Value
}

function Get-MIR4T13PortableLogSha256 {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string[]]$PrivateRoots)
  $text=if(Test-Path -LiteralPath $Path -PathType Leaf){[IO.File]::ReadAllText($Path)}else{''}
  foreach($root in @($PrivateRoots|Where-Object{-not[string]::IsNullOrWhiteSpace($_)}|Sort-Object Length -Descending)){$text=$text.Replace($root,'[PRIVATE_ROOT]',[StringComparison]::OrdinalIgnoreCase)}
  $text=[regex]::Replace($text,'(?m)^\s*\d+(?:\.\d+)?\s+','')
  $text=$text.Replace("`r`n","`n").Replace("`r","`n").Normalize([Text.NormalizationForm]::FormC)
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes($text)
  'sha256:'+([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant())
}

function Invoke-MIR4T13Reload {
  param(
    [Parameter(Mandatory)][string]$EnginePath,
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$CaptureId,
    [Parameter(Mandatory)][int]$Ordinal,
    [Parameter(Mandatory)][int]$TimeoutSeconds,
    [Parameter(Mandatory)][int]$MaximumSeconds
  )
  $engine=(Resolve-Path -LiteralPath $EnginePath).Path;$run=(Resolve-Path -LiteralPath $RunRoot).Path
  $save=(Resolve-Path -LiteralPath (Join-Path $run "saves/$CaptureId.zip")).Path
  $config=(Resolve-Path -LiteralPath (Join-Path $run 'mir-compat-config.ini')).Path
  $mods=(Resolve-Path -LiteralPath (Join-Path $run 'mods')).Path
  $log=Join-Path $run 'factorio-current.log';$stderr=Join-Path $run 'factorio-current.log.err'
  $before=(Get-FileHash -Algorithm SHA256 -LiteralPath $save).Hash
  $arguments=@('--config',$config,'--no-log-rotation','--disable-audio','--mod-directory',$mods,'--benchmark',$save,'--benchmark-ticks','1','--benchmark-runs','1','--benchmark-sanitize')
  $timer=[Diagnostics.Stopwatch]::StartNew();$code=Invoke-FactorioProcess -FilePath $engine -Arguments $arguments -TimeoutMs ($TimeoutSeconds*1000);$timer.Stop()
  $after=(Get-FileHash -Algorithm SHA256 -LiteralPath $save).Hash
  $duration=[Math]::Round($timer.Elapsed.TotalSeconds,6)
  $passed=($code-eq 0-and$before-ceq$after-and$duration-le$MaximumSeconds)
  [pscustomobject][ordered]@{
    ordinal=$Ordinal;status=$(if($passed){'passed'}else{'failed'});exit_code=$code;duration_seconds=$duration;maximum_seconds=$MaximumSeconds
    save_sha256='sha256:'+$after;save_byte_identical=($before-ceq$after)
    portable_log_sha256=Get-MIR4T13PortableLogSha256 -Path $log -PrivateRoots @($run,(Split-Path -Parent $engine))
    portable_stderr_sha256=Get-MIR4T13PortableLogSha256 -Path $stderr -PrivateRoots @($run,(Split-Path -Parent $engine))
    raw_log_published=$false;private_paths_published=$false
  }
}

function Test-MIR4T13UpgradeMatrix {
  param([Parameter(Mandatory)]$Authority,[Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$Path)
  $expected=$Authority.target_upgrades.$Target;$matrix=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json -Depth 100
  if([string]$matrix.kind-cne'mir-upgrade-matrix'-or[string]$matrix.status-cne'passed'-or
    ([string]$matrix.factorio.binary_sha256).ToUpperInvariant()-cne[string]$expected.engine_sha256-or
    [string]$matrix.baseline.version-cne[string]$expected.baseline_version-or([string]$matrix.baseline.archive_sha256).ToUpperInvariant()-cne[string]$expected.baseline_sha256-or
    [string]$matrix.candidate.version-cne[string]$expected.candidate_version-or([string]$matrix.candidate.archive_sha256).ToUpperInvariant()-cne[string]$expected.candidate_sha256){throw "[mir4-t13-upgrade-identity] $Target"}
  $required=@($expected.required_archetypes);if(($required-join'|')-cne(@($matrix.required_archetypes)-join'|')){throw "[mir4-t13-upgrade-archetypes] $Target"}
  foreach($row in @($matrix.rows)){if([string]$row.status-cne'passed'-or'upgraded-save-reload-passed'-notin@($row.assertions)-or'upgraded-save-second-reload-passed'-notin@($row.assertions)){throw "[mir4-t13-upgrade-reload] $Target/$($row.id)"}}
  [pscustomobject][ordered]@{target=$Target;status='passed';engine_sha256='sha256:'+([string]$expected.engine_sha256).ToLowerInvariant();baseline=[ordered]@{version=[string]$expected.baseline_version;sha256='sha256:'+([string]$expected.baseline_sha256).ToLowerInvariant()};candidate=[ordered]@{version=[string]$expected.candidate_version;sha256='sha256:'+([string]$expected.candidate_sha256).ToLowerInvariant()};archetypes=@($matrix.rows.id);matrix_sha256='sha256:'+(Get-MIR4T12FileSha256 $Path);first_reload_asserted=$true;second_reload_asserted=$true;scope='MIR-owned target transition shared by exact environment canaries'}
}

function New-MIR4T13CaptureRecord {
  param([Parameter(Mandatory)]$Authority,[Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)]$Lock,[Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$EnginePath)
  if([string]$Snapshot.capture_id-cne[string]$Lock.capture-or[string]$Snapshot.environment_lock_digest-cne[string]$Lock.digest-or[string]$Snapshot.digest-cne(Get-MIR4T12RecordDigest $Snapshot)){throw "[mir4-t13-capture-binding] $($Snapshot.capture_id)"}
  Test-MIR4EnvironmentLockV1 -Lock $Lock|Out-Null
  $target=[string]$Snapshot.target;$expected=$Authority.target_upgrades.$target
  if(([string]$Lock.engine.executable_sha256).ToLowerInvariant()-cne('sha256:'+([string]$expected.engine_sha256).ToLowerInvariant())-or([string]$Lock.mir.package_sha256).ToLowerInvariant()-cne('sha256:'+([string]$expected.candidate_sha256).ToLowerInvariant())){throw "[mir4-t13-lock-target-identity] $($Snapshot.capture_id)"}
  $save=(Resolve-Path -LiteralPath (Join-Path $RunRoot "saves/$($Snapshot.capture_id).zip")).Path
  $reloads=@();foreach($ordinal in 1..([int]$Authority.lifecycle.required_reload_runs)){$reloads+=Invoke-MIR4T13Reload -EnginePath $EnginePath -RunRoot $RunRoot -CaptureId ([string]$Snapshot.capture_id) -Ordinal $ordinal -TimeoutSeconds ([int]$Authority.lifecycle.timeout_seconds) -MaximumSeconds ([int]$Authority.lifecycle.maximum_reload_seconds)}
  if(@($reloads|Where-Object status -cne 'passed').Count){throw "[mir4-t13-reload] $($Snapshot.capture_id)"}
  $recipes=@($Snapshot.observations.recipe|Where-Object{$_}|Sort-Object -Unique -CaseSensitive)
  $technologies=@($Snapshot.observations.unlocks|ForEach-Object{$_}|Where-Object{$_}|Sort-Object -Unique -CaseSensitive)
  $owners=@($Snapshot.observations.productivity_owners|ForEach-Object{$_}|Where-Object{$_}|Sort-Object -Unique -CaseSensitive)
  $record=[pscustomobject][ordered]@{
    schema=1;kind='MIR4T13ExactCaptureCanaryV1';capture_id=[string]$Snapshot.capture_id;target=$target;scenario_id=[string]$Snapshot.scenario_id
    environment_lock=[ordered]@{digest=[string]$Lock.digest;engine=$Lock.engine;mir=$Lock.mir;mods=@($Lock.mods);startup_settings=@($Lock.startup_settings)}
    exact_fact_capture=[ordered]@{snapshot_digest=[string]$Snapshot.digest;processir_digest=[string]$Snapshot.process_ir.digest;process_count=@($Snapshot.process_ir.processes).Count;recipe_count=$recipes.Count;technology_unlock_count=$technologies.Count;productivity_owner_count=$owners.Count;classification_counts=$Snapshot.classification_counts;terminal_disposition=[string]$Snapshot.process_ir.terminal_disposition;terminal_fact_authority_preserved=[bool]$Snapshot.terminal_fact_authority_preserved}
    lifecycle=[ordered]@{clean_load=[ordered]@{status='passed';authority='T12 exact engine create-save capture';save_sha256='sha256:'+(Get-MIR4T12FileSha256 $save);snapshot_digest=[string]$Snapshot.digest};reloads=$reloads;first_reload_passed=$true;second_reload_passed=$true;save_byte_identical=$true}
    performance=[ordered]@{scope='create-save plus one-tick benchmark reloads for the affected exact closure';reload_seconds=@($reloads.duration_seconds);maximum_observed_reload_seconds=(@($reloads.duration_seconds)|Measure-Object -Maximum).Maximum;budget_seconds=[int]$Authority.lifecycle.maximum_reload_seconds;within_budget=$true}
    support_assessment=[ordered]@{status='qualified-exact-release-canary-input';scope='exact locked environment only';processir_terminal_disposition=[string]$Snapshot.process_ir.terminal_disposition;automatic_synthesis_authorized=$false;public_claim_authorized=$false}
    diagnostics=@();diagnostic_registry=[string]$Authority.diagnostic_registry;diagnostic_order='severity-code-path'
    raw_logs_published=$false;private_paths_published=$false;package_visible=$false;digest=''
  }
  Add-MIR4T13Digest -Value $record -Domain 'mir4:t13-capture:1'|Out-Null;$record
}

function New-MIR4T13CanaryRecord {
  param([Parameter(Mandatory)]$Authority,[Parameter(Mandatory)]$Definition,[Parameter(Mandatory)][hashtable]$CaptureMap,[Parameter(Mandatory)][hashtable]$UpgradeMap,[Parameter(Mandatory)]$SourceIdentity)
  $captures=@();foreach($id in @($Definition.capture_ids)){$key=[string]$id;if(-not$CaptureMap.ContainsKey($key)){throw "[mir4-t13-canary-capture] $key"};$captures+=$CaptureMap[$key]}
  $targets=@($captures.target|Sort-Object -Unique -CaseSensitive);$upgrades=@();foreach($target in $targets){if(-not$UpgradeMap.ContainsKey([string]$target)){throw "[mir4-t13-canary-upgrade] $target"};$upgrades+=$UpgradeMap[[string]$target]}
  $record=[pscustomobject][ordered]@{
    schema=1;kind='MIR4ReleaseCompatibilityCanaryV1';work_package='T13';canary_id=[string]$Definition.id;name=[string]$Definition.name;source_identity=$SourceIdentity
    targets=$targets;subjects=@($Definition.subjects);capture_ids=@($Definition.capture_ids);captures=@($captures|ForEach-Object{[ordered]@{capture_id=$_.capture_id;target=$_.target;environment_lock_digest=$_.environment_lock.digest;snapshot_digest=$_.exact_fact_capture.snapshot_digest;capture_digest=$_.digest;lifecycle_status='passed';processir_terminal_disposition=$_.exact_fact_capture.terminal_disposition}})
    target_upgrades=$upgrades;support_statement=[string]$Definition.support_statement;claim_level='exact-locked-release-canary-input';target_disposition='qualified-exact-release-canary';limitations=@($Definition.limitations);expiry_triggers=@($Authority.common_expiry_triggers);compatibility_authorities=@($Definition.compatibility_authorities)
    diagnostics=@();all_clean_loads_passed=$true;all_first_reloads_passed=$true;all_second_reloads_passed=$true;all_performance_within_budget=$true;exact_environment_only=$true;release_qualification_input=$true;public_support_claim_authorized=$false;release_transition_authorized=$false;package_visible=$false;digest=''
  }
  Add-MIR4T13Digest -Value $record -Domain 'mir4:release-canary:1'|Out-Null;$record
}

function Test-MIR4T13Reference {
  param([Parameter(Mandatory)][string]$RepoRoot,[string]$ReferenceRoot='sdk/preview/mir4/reference/t13')
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$root=Join-Path $repo $ReferenceRoot
  $manifest=Get-Content -Raw -LiteralPath (Join-Path $root 'MIR4_T13_MANIFEST.json')|ConvertFrom-Json -Depth 100
  if([string]$manifest.kind-cne'MIR4T13ManifestV1'-or-not$manifest.complete-or[int]$manifest.canary_count-ne 8-or[int]$manifest.capture_count-ne 11){throw '[mir4-t13-reference-manifest]'}
  foreach($file in @($manifest.files)){$path=Join-Path $root ([string]$file.path);if(-not(Test-Path -LiteralPath $path)-or('sha256:'+(Get-MIR4T12FileSha256 $path))-cne[string]$file.sha256){throw "[mir4-t13-reference-file] $($file.path)"}}
  $receipt=Get-Content -Raw -LiteralPath (Join-Path $root 'MIR4_T13_RECEIPT.json')|ConvertFrom-Json -Depth 100
  if([string]$receipt.digest-cne(Get-MIR4T12RecordDigest -Value $receipt -Domain 'mir4:t13-receipt:1')-or[string]$receipt.status-cne'completed-machine-work'-or-not$receipt.package_source_unchanged-or-not$receipt.f200_k2so_archive_custody_complete){throw '[mir4-t13-reference-receipt]'}
  foreach($file in Get-ChildItem -LiteralPath (Join-Path $root 'canaries') -File -Filter '*.json'){$record=Get-Content -Raw -LiteralPath $file.FullName|ConvertFrom-Json -Depth 100;if([string]$record.digest-cne(Get-MIR4T12RecordDigest -Value $record -Domain 'mir4:release-canary:1')-or[string]$record.target_disposition-cne'qualified-exact-release-canary'-or$record.public_support_claim_authorized-or$record.release_transition_authorized){throw "[mir4-t13-reference-canary] $($file.Name)"}}
  $lock=Get-Content -Raw -LiteralPath (Join-Path $root 'supplements/f200-k2so.lock.json')|ConvertFrom-Json -Depth 100;Test-MIR4EnvironmentLockV1 -Lock $lock|Out-Null
  $snapshot=Get-Content -Raw -LiteralPath (Join-Path $root 'supplements/f200-k2so.snapshot.json')|ConvertFrom-Json -Depth 100;if([string]$snapshot.digest-cne(Get-MIR4T12RecordDigest $snapshot)-or[string]$snapshot.environment_lock_digest-cne[string]$lock.digest){throw '[mir4-t13-f200-k2so-supplement]'}
  [pscustomobject][ordered]@{status='passed';canary_count=8;capture_count=11;package_visible=$false}
}
