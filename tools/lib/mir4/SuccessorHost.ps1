function Write-MIR4W09SyntheticArchive {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$OutputPath)
  $repo=Get-MIR4W09RepoRoot -RepoRoot $RepoRoot
  $files=@('fixtures/mir4-historical-succession-v1/reconstruction/info.json','fixtures/mir4-historical-succession-v1/reconstruction/manifest.json')
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath)|Out-Null
  Add-Type -AssemblyName System.IO.Compression
  $stream=[IO.File]::Open($OutputPath,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try{
    $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    try{
      $rows=@()
      foreach($relative in @($files|Sort-Object)){
        $path=Join-Path $repo $relative;$bytes=[IO.File]::ReadAllBytes($path)
        $rows+=[ordered]@{path=$relative;bytes=$bytes.Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
        $entry=$zip.CreateEntry("mir4-synthetic-successor-proof/$($relative.Replace('\','/'))",[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime=[DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
        $target=$entry.Open();try{$target.Write($bytes,0,$bytes.Length)}finally{$target.Dispose()}
      }
      $manifest=[pscustomobject][ordered]@{schema=1;kind='MIR4SyntheticSuccessorReconstructionManifestV1';source_version='4.0.0';candidate_id='M4C02-09-24H';target='f300';maturity='synthetic-fixture';files=$rows;package_visible=$false;publication_authorized=$false;digest=''}
      Add-MIR4PlatformDigest $manifest|Out-Null
      $manifestBytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4PlatformCanonicalJson $manifest)+"`n")
      $manifestEntry=$zip.CreateEntry('mir4-synthetic-successor-proof/RECONSTRUCTION-MANIFEST.json',[IO.Compression.CompressionLevel]::Optimal)
      $manifestEntry.LastWriteTime=[DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
      $target=$manifestEntry.Open();try{$target.Write($manifestBytes,0,$manifestBytes.Length)}finally{$target.Dispose()}
    }finally{$zip.Dispose()}
  }finally{$stream.Dispose()}
  return [ordered]@{path=[IO.Path]::GetRelativePath($repo,$OutputPath).Replace('\','/');bytes=(Get-Item -LiteralPath $OutputPath).Length;sha256=(Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash;entry_count=3}
}

function Test-MIR4W09SensitivePropertyName {
  param([AllowNull()]$Value)
  if($null-eq$Value-or$Value-is[string]-or$Value-is[ValueType]){return $false}
  if($Value-is[Collections.IDictionary]){
    foreach($key in @($Value.Keys)){
      if([string]$key-match'(?i)credential|private[_-]?signing|secret|save[_-]?data|mutable[_-]?runtime[_-]?state[_-]?values'){return $true}
      if(Test-MIR4W09SensitivePropertyName -Value $Value[$key]){return $true}
    }
    return $false
  }
  if($Value-is[pscustomobject]){
    foreach($property in @($Value.PSObject.Properties)){
      if([string]$property.Name-match'(?i)credential|private[_-]?signing|secret|save[_-]?data|mutable[_-]?runtime[_-]?state[_-]?values'){return $true}
      if(Test-MIR4W09SensitivePropertyName -Value $property.Value){return $true}
    }
    return $false
  }
  if($Value-is[Collections.IEnumerable]){foreach($item in $Value){if(Test-MIR4W09SensitivePropertyName -Value $item){return $true}}}
  return $false
}

function New-MIR4SuccessorHostResultV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$SourceIdentity,[string]$OutputRoot='build/mir4/m4c02-historical-succession')
  $repo=Get-MIR4W09RepoRoot -RepoRoot $RepoRoot
  $authority=Get-MIR4W09Authority -RepoRoot $repo
  $source=New-MIR4W09SourceIdentity -RepoRoot $repo -SourceIdentity $SourceIdentity
  $fixtureRoot='fixtures/mir4-historical-succession-v1'
  $hostFixture=Get-Content -Raw -LiteralPath (Join-Path $repo "$fixtureRoot/successor-host.json")|ConvertFrom-Json -Depth 100
  $index=Get-Content -Raw -LiteralPath (Join-Path $repo "$fixtureRoot/offline-module-index.json")|ConvertFrom-Json -Depth 100
  $providerFixture=Get-Content -Raw -LiteralPath (Join-Path $repo "$fixtureRoot/external-provider.json")|ConvertFrom-Json -Depth 100
  $proofFixture=Get-Content -Raw -LiteralPath (Join-Path $repo "$fixtureRoot/proof-replay.json")|ConvertFrom-Json -Depth 100
  if([bool]$hostFixture.production_host-or[bool]$hostFixture.public_support_claim-or[bool]$index.network_registry_required){throw '[mir4-w09-successor-fixture-boundary]'}

  $reference=New-MIR4ReferenceExtensionV1 -RepoRoot $repo
  $closureA=Resolve-MIR4ExtensionClosureV1 -RepoRoot $repo -Extensions @($reference) -Target f210
  $closureB=Resolve-MIR4ExtensionClosureV1 -RepoRoot $repo -Extensions @($reference) -Target f210
  if((ConvertTo-MIR4PlatformCanonicalJson $closureA)-cne(ConvertTo-MIR4PlatformCanonicalJson $closureB)-or-not[bool]$closureA.complete){throw '[mir4-w09-extension-closure-determinism]'}
  $indexRows=@(
    foreach($entry in @($index.entries|Sort-Object extension_id)){
      $path=Join-Path $repo ([string]$entry.source);if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw '[mir4-w09-offline-index-source]'}
      $bytes=(Get-Item -LiteralPath $path).Length;if($bytes-gt[int]$entry.max_bytes){throw '[mir4-w09-offline-index-budget]'}
      [ordered]@{extension_id=[string]$entry.extension_id;source=[string]$entry.source;trust=[string]$entry.trust;bytes=$bytes;max_bytes=[int]$entry.max_bytes;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;within_budget=$true}
    }
  )
  $moduleIndex=[ordered]@{kind='MIR4OfflineModuleIndexResultV1';schema=1;entries=$indexRows;stable_order=$true;reviewed_only=(@($indexRows|Where-Object trust -ne 'repository-reviewed').Count-eq 0);network_calls=0;network_registry_required=$false;status='passed-local-only'}

  $contracts=New-MIR4TargetContractSet -RepoRoot $repo;$baseProvider=@($contracts.targets|Where-Object target -eq f210)[0]
  $input=[pscustomobject][ordered]@{kind='MIR4SyntheticProviderProjectionInputV1';owned=[pscustomobject][ordered]@{distribution_version='0.0.0';factorio_version='0.0';package_root='fixture';capability_omissions=@()};unowned=$providerFixture.unowned}
  $projectedA=Invoke-MIR4TargetProviderProjection -Provider $baseProvider -InputRecord $input -OwnedChanges $providerFixture.owned_changes
  $projectedB=Invoke-MIR4TargetProviderProjection -Provider $baseProvider -InputRecord $projectedA -OwnedChanges $providerFixture.owned_changes
  if((ConvertTo-MIR4PlatformCanonicalJson $projectedA)-cne(ConvertTo-MIR4PlatformCanonicalJson $projectedB)-or[string]$projectedA.unowned.sentinel-cne'must-survive'){throw '[mir4-w09-provider-law]'}
  $negative=[pscustomobject]@{};Add-Member -InputObject $negative -MemberType NoteProperty -Name ([string]$providerFixture.negative_unowned_write) -Value 'forbidden'
  $negativeRejected=$false;try{Invoke-MIR4TargetProviderProjection -Provider $baseProvider -InputRecord $input -OwnedChanges $negative|Out-Null}catch{if($_.Exception.Message.StartsWith('[mir4-target-provider-unowned-write]')){$negativeRejected=$true}else{throw}}
  if(-not$negativeRejected){throw '[mir4-w09-provider-negative-accepted]'}
  $lawResults=Test-MIR4TargetProviderLaws -RepoRoot $repo
  $externalProvider=[ordered]@{kind='MIR4ExternalTargetProviderConformanceV1';schema=1;target=[string]$providerFixture.target;factorio_line=[string]$providerFixture.factorio_line;distribution_version=[string]$providerFixture.distribution_version;abi_source_target='f210-fixture-adapter';deterministic=$true;idempotent=$true;unowned_fields_preserved=$true;forbidden_write_rejected=$true;all_registered_provider_laws_passed=[bool]$lawResults.passed;law_result_digest=[string]$lawResults.digest;production_consumer=$false;status='passed-synthetic-only'}

  $continuity=New-MIR4ContinuityBundle -RepoRoot $repo -Providers $null -SourceIdentity $source -CandidateZip $null -RuntimeStateMatrix $null -MigrationGraphMatrix $null
  $copy=$continuity|ConvertTo-Json -Depth 100 -Compress|ConvertFrom-Json -Depth 100
  $continuityText=ConvertTo-MIR4PlatformCanonicalJson $copy
  $requiredRedactions=@('mutable-runtime-state-values','player-identities','save-data','credentials','private-signing-material','raw-prototype-objects','unbounded-diagnostics')
  if($continuityText-cne(ConvertTo-MIR4PlatformCanonicalJson $continuity)-or-not[bool]$continuity.redaction_manifest.complete-or@($requiredRedactions|Where-Object{$_-notin@($continuity.redaction_manifest.excluded)}).Count-or(Test-MIR4W09SensitivePropertyName -Value $continuity)){throw '[mir4-w09-continuity-import]'}
  $continuityImport=[ordered]@{kind='MIR4SyntheticContinuityImportV1';schema=1;source_kind=[string]$continuity.kind;source_digest=[string]$continuity.digest;target_count=[int]$continuity.target_count;copied=$true;redaction_complete=[bool]$continuity.redaction_manifest.complete;runtime_state_mutated=$false;migration_executed=$false;future_host_claim=$false;status='passed-data-only-fixture'}

  $transport=New-MIR4TargetTransportPlanV1 -RepoRoot $repo
  $extensionTransport=[ordered]@{kind='MIR4SyntheticExtensionTransportConformanceV1';schema=1;source_plan_digest=[string]$transport.digest;source_target_count=@($transport.targets).Count;synthetic_target=[string]$hostFixture.target;synthetic_transport=[string]$hostFixture.transport;payload='canonical-json-data-only';callbacks=$false;prototype_write=$false;runtime_mutation=$false;production_transport_claim=$false;status='passed-synthetic-only'}

  $proofRecord=[pscustomobject][ordered]@{kind='MIR4SuccessorProofReplayMaterialV1';schema=1;facts=@($proofFixture.facts|Sort-Object id);digest=''};Add-MIR4PlatformDigest $proofRecord|Out-Null
  $repeat=[pscustomobject][ordered]@{kind='MIR4SuccessorProofReplayMaterialV1';schema=1;facts=@($proofFixture.facts|Sort-Object id);digest=''};Add-MIR4PlatformDigest $repeat|Out-Null
  $tampered=[pscustomobject][ordered]@{kind='MIR4SuccessorProofReplayMaterialV1';schema=1;facts=@($proofFixture.facts|ForEach-Object{if([string]$_.id-eq[string]$proofFixture.tamper.id){[ordered]@{id=[string]$_.id;value=[string]$proofFixture.tamper.value}}else{$_}}|Sort-Object id);digest=''};Add-MIR4PlatformDigest $tampered|Out-Null
  if([string]$proofRecord.digest-cne[string]$repeat.digest-or[string]$proofRecord.digest-ceq[string]$tampered.digest-or@($proofRecord.facts).Count-ne[int]$proofFixture.expected_fact_count){throw '[mir4-w09-proof-replay]'}
  $proofReplay=[ordered]@{kind='MIR4SuccessorProofReplayResultV1';schema=1;fact_count=@($proofRecord.facts).Count;digest=[string]$proofRecord.digest;repeat_digest=[string]$repeat.digest;deterministic=$true;tamper_digest=[string]$tampered.digest;tamper_rejected=$true;external_proof_claim=$false;status='passed-synthetic-only'}

  $output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot));$allowed=[IO.Path]::GetFullPath((Join-Path $repo 'build/mir4')).TrimEnd('\')+'\'
  if(-not($output+'\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw "[mir4-w09-output-boundary] $output"}
  $archiveA=Write-MIR4W09SyntheticArchive -RepoRoot $repo -OutputPath (Join-Path $output 'reconstruction/synthetic-successor-A.zip')
  $archiveB=Write-MIR4W09SyntheticArchive -RepoRoot $repo -OutputPath (Join-Path $output 'reconstruction/synthetic-successor-B.zip')
  if([string]$archiveA.sha256-cne[string]$archiveB.sha256){throw '[mir4-w09-reconstruction-nondeterministic]'}
  $reconstruction=[ordered]@{kind='MIR4SyntheticPackageReconstructionResultV1';schema=1;target=[string]$hostFixture.target;source_version='4.0.0';candidate_id='M4C02-09-24H';package_root='mir4-synthetic-successor-proof';builds=@($archiveA,$archiveB);deterministic=$true;player_package=$false;production_candidate=$false;publication_authorized=$false;status='passed-synthetic-only'}

  $witness=New-MIR4PackageSuccessionWitnessV1 -RepoRoot $repo -SourceIdentity $source
  $inputs=@('.mir/releases/waves/mir4-r0/MIR4-Historical-Succession-ProgrammeV1.json','.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json','.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json','.mir/releases/waves/mir4-r0/MIR4-Module-Ecosystem-ProgrammeV1.json','.mir/releases/waves/mir4-r0/MIR4-Assurance-Scale-ProgrammeV1.json','.mir/releases/records/3.2.11.json')|ForEach-Object{Get-MIR4W09InputDescriptor -RepoRoot $repo -RelativePath $_}
  $blockers=@($authority.mandatory_blockers)+@('BLOCKED-MISSING-EXACT-ENGINE-f018','BLOCKED-FUTURE-INDEPENDENT-PRODUCTION-HOST')
  $record=[pscustomobject][ordered]@{kind='MIR4SuccessorHostResultV1';schema=1;programme_id='M4C02-09-24H';wave='W09';maturity='developer-preview-shadow';source_identity=$source;input_authorities=@($inputs);host=[ordered]@{id=[string]$hostFixture.host_id;version=[string]$hostFixture.host_version;target=[string]$hostFixture.target;capabilities=@($hostFixture.capabilities);synthetic=$true;production_host=$false;public_support_claim=$false;manifest_conformance='passed'};module_index=$moduleIndex;extension_closure=[ordered]@{kind=[string]$closureA.kind;digest=[string]$closureA.digest;complete=[bool]$closureA.complete;deterministic=$true;order=@($closureA.order);independent_production_consumer_status='BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER'};external_target_provider=$externalProvider;continuity_import=$continuityImport;extension_transport=$extensionTransport;proof_replay=$proofReplay;package_reconstruction=$reconstruction;succession_witness=$witness;blockers=@($blockers|Sort-Object -Unique);status='partial-with-bounded-blockers';package_visible=$false;public_release_proof=$false;semantic_authority=$false;target_policy_authority=$false;runtime_state_mutation_authorized=$false;migration_execution_authorized=$false;source_freeze_authorized=$false;production_signing_or_sealing_authorized=$false;publication_authorized=$false;record_sha256=''}
  return Add-MIR4W09RecordSha256 $record
}
