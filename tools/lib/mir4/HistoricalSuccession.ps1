function Get-MIR4W09RepoRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Get-MIR4W09RecordSha256 {
  param([Parameter(Mandatory)]$Record)
  $material = [ordered]@{}
  foreach ($property in $Record.PSObject.Properties) {
    if ($property.Name -ne 'record_sha256') { $material[$property.Name] = $property.Value }
  }
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4PlatformCanonicalJson $material))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') }
  finally { $sha.Dispose() }
}

function Add-MIR4W09RecordSha256 {
  param([Parameter(Mandatory)]$Record)
  $Record.record_sha256 = Get-MIR4W09RecordSha256 -Record $Record
  return $Record
}

function Get-MIR4W09Authority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4W09RepoRoot -RepoRoot $RepoRoot
  $path = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Historical-Succession-ProgrammeV1.json'
  $authority = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ([int]$authority.schema -ne 1 -or [string]$authority.kind -cne 'MIR4HistoricalSuccessionProgrammeV1') { throw '[mir4-w09-authority-schema]' }
  foreach ($flag in @('package_visible','semantic_authority','target_policy_authority','museum_admission_authority','rights_or_custody_authority','player_package_mutation_authorized','prototype_write_authorized','runtime_state_mutation_authorized','migration_execution_authorized','source_freeze_authorized','production_signing_or_sealing_authorized','promotion_or_tag_authorized','network_or_upload_authorized','publication_authorized')) {
    if ([bool]$authority.$flag) { throw "[mir4-w09-authority-boundary] $flag" }
  }
  if (@($authority.historical_targets).Count -ne 6 -or @($authority.museum_targets).Count -ne 7) { throw '[mir4-w09-authority-target-count]' }
  foreach ($relative in @($authority.imports)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo ([string]$relative)) -PathType Leaf)) { throw "[mir4-w09-authority-input] $relative" }
  }
  return $authority
}

function Get-MIR4W09InputDescriptor {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RelativePath)
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-w09-input-missing] $RelativePath" }
  return [ordered]@{path=$RelativePath;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
}

function Get-MIR4W09ArchiveDescriptor {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RelativePath,[AllowNull()][string]$ExpectedSha256)
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [ordered]@{path=$RelativePath;status='missing';bytes=$null;sha256=$null;expected_sha256=$ExpectedSha256;hash_match=$false}
  }
  $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  return [ordered]@{path=$RelativePath;status=$(if($ExpectedSha256 -and $actual -cne $ExpectedSha256){'present-hash-mismatch'}else{'present-exact'});bytes=(Get-Item -LiteralPath $path).Length;sha256=$actual;expected_sha256=$ExpectedSha256;hash_match=([string]::IsNullOrWhiteSpace($ExpectedSha256) -or $actual -ceq $ExpectedSha256)}
}

function Get-MIR4W09EngineObservation {
  param([Parameter(Mandatory)][string]$FactorioLine,[AllowNull()][string]$ExpectedSha256,[AllowNull()][string]$ExpectedVersion)
  $relative = "preserved-installation:$FactorioLine/bin/x64/factorio.exe"
  $path = "D:\Programs\Factorio\$FactorioLine\bin\x64\factorio.exe"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [ordered]@{installation_id="factorio-$FactorioLine";binary_locator=$relative;status='missing-exact-engine';version=$ExpectedVersion;sha256=$null;expected_sha256=$ExpectedSha256;hash_match=$false;workstation_path_embedded=$false}
  }
  $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  $match = (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) -and $actual -ceq $ExpectedSha256
  return [ordered]@{installation_id="factorio-$FactorioLine";binary_locator=$relative;status=$(if($match){'available-exact-hash'}else{'available-hash-mismatch-or-unlocked'});version=$ExpectedVersion;sha256=$actual;expected_sha256=$ExpectedSha256;hash_match=$match;workstation_path_embedded=$false}
}

function Get-MIR4W09RuntimeObservation {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$EvidenceRoot)
  $relative = "$EvidenceRoot/$Target/runtime-proof.json".Replace('\','/')
  $path = Join-Path $RepoRoot $relative
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [ordered]@{status='not-run';evidence=$null;sha256=$null;fresh_for_source=$false;public_support_claim=$false}
  }
  $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ([string]$record.target -cne $Target -or [string]$record.status -cne 'passed' -or [bool]$record.public_support_claim) { throw "[mir4-w09-runtime-receipt] $Target" }
  return [ordered]@{status='passed-private-exact-engine';evidence=$relative;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;fresh_for_source=$false;public_support_claim=$false;admission_status=[string]$record.admission_status}
}

function Get-MIR4W09MuseumRuntimeObservation {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$FactorioLine,[Parameter(Mandatory)][string]$ExpectedEngineSha256,[Parameter(Mandatory)][string]$ExpectedBaseSha256)
  $root=Join-Path $RepoRoot "build/museum-runtime/$FactorioLine"
  $proofs=@(Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'runtime-proof.json' -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending)
  foreach($proofFile in $proofs){
    $proof=Get-Content -Raw -LiteralPath $proofFile.FullName|ConvertFrom-Json -Depth 100
    if([string]$proof.status-cne'passed'-or[string]$proof.factorio-cne$FactorioLine){continue}
    if([string]$proof.binary_sha256-cne$ExpectedEngineSha256-or[string]$proof.base_data_sha256-cne$ExpectedBaseSha256){throw "[mir4-w09-museum-runtime-identity] $FactorioLine"}
    return [ordered]@{status='passed-private-exact-engine';evidence=[IO.Path]::GetRelativePath($RepoRoot,$proofFile.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $proofFile.FullName -Algorithm SHA256).Hash;binary_sha256=[string]$proof.binary_sha256;base_data_sha256=[string]$proof.base_data_sha256;configuration_isolation=$(if($proof.PSObject.Properties['configuration_isolation']){[string]$proof.configuration_isolation}else{'isolated-write-data'});fresh_for_source=$false;public_support_claim=$false}
  }
  $logs=@(Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'factorio-current.log' -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending)
  $displayBlocked=@($logs|Where-Object{(Get-Content -Raw -LiteralPath $_.FullName)-match'(?i)failed to create display'}).Count-gt 0
  return [ordered]@{status=$(if($displayBlocked){'blocked-noninteractive-display'}else{'not-run-w09'});evidence=$null;sha256=$null;binary_sha256=$null;base_data_sha256=$null;configuration_isolation=$null;fresh_for_source=$false;public_support_claim=$false}
}

function New-MIR4W09SourceIdentity {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$SourceIdentity)
  $repo = Get-MIR4W09RepoRoot -RepoRoot $RepoRoot
  if ($null -eq $SourceIdentity) {
    $SourceIdentity = [pscustomobject][ordered]@{commit=(& git -C $repo rev-parse HEAD).Trim();tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()}
  }
  $fingerprint = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  return [ordered]@{commit=[string]$SourceIdentity.commit;tree=[string]$SourceIdentity.tree;programme_id='M4C02-09-24H';source_version='4.0.0';package_source_sha256=$fingerprint}
}

function New-MIR4PackageSuccessionWitnessV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$SourceIdentity)
  $repo = Get-MIR4W09RepoRoot -RepoRoot $RepoRoot
  $authority = Get-MIR4W09Authority -RepoRoot $repo
  $release = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/records/3.2.11.json') | ConvertFrom-Json -Depth 100
  $witness = $authority.succession_witness
  if ([string]$release.release -cne [string]$witness.published_predecessor_release -or [string]$release.package.source_commit -cne [string]$witness.published_predecessor_commit -or [string]$release.package.source_tree -cne [string]$witness.published_predecessor_tree -or [string]$release.package.source_sha256 -cne [string]$witness.published_predecessor_package_source_sha256) { throw '[mir4-w09-predecessor-identity-drift]' }
  if ([string]$SourceIdentity.package_source_sha256 -cne [string]$witness.current_mir4_package_source_sha256) { throw '[mir4-w09-current-package-source-drift]' }
  if (@($witness.changed_package_roots | Sort-Object -Unique).Count -ne 14) { throw '[mir4-w09-succession-root-count]' }
  & git -C $repo cat-file -e "$([string]$witness.introducing_commit)^{commit}" 2>$null
  if ($LASTEXITCODE -ne 0) { throw '[mir4-w09-introducing-commit-missing]' }
  $record = [pscustomobject][ordered]@{
    kind='MIR4PackageSuccessionWitnessV1';schema=1
    published_predecessor=[ordered]@{release=[string]$release.release;candidate_id=[string]$release.candidate_id;commit=[string]$release.package.source_commit;tree=[string]$release.package.source_tree;package_source_sha256=[string]$release.package.source_sha256;archive_sha256=[string]$release.package.archive_sha256;evidence_valid_for_predecessor=$true}
    current_mir4=[ordered]@{source_version='4.0.0';commit=[string]$SourceIdentity.commit;tree=[string]$SourceIdentity.tree;package_source_sha256=[string]$SourceIdentity.package_source_sha256;candidate_id='M4C02-09-24H';publication_authorized=$false}
    introducing_commit=[string]$witness.introducing_commit;changed_package_roots=@($witness.changed_package_roots)
    evidence_disposition=[ordered]@{c35='valid-for-immutable-3.2.11-only';c35_revoked=$false;transferable_to_mir4=$false;reason='package-source-fingerprint-mismatch';inherited_w02_evidence='candidate-target-evaluator-abi-bound-revalidation-required';active_revocation_ledger_changed=$false}
    append_only=$true;prior_release_evidence_mutated=$false;digest=''
  }
  return Add-MIR4PlatformDigest $record
}

function New-MIR4HistoricalMuseumMatrixV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[AllowNull()]$SourceIdentity,[string]$HistoricalBuildRoot='build/mir4/historical-private',[string]$RuntimeEvidenceRoot='build/mir4/m4c02-historical-succession/runtime')
  $repo = Get-MIR4W09RepoRoot -RepoRoot $RepoRoot
  $authority = Get-MIR4W09Authority -RepoRoot $repo
  $source = New-MIR4W09SourceIdentity -RepoRoot $repo -SourceIdentity $SourceIdentity
  $registry = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json') | ConvertFrom-Json -Depth 100
  $historicalAuthority = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Historical-Private-Candidate-AuthorizationV1.json') | ConvertFrom-Json -Depth 100
  $museum = Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/museum-targets.json') | ConvertFrom-Json -Depth 100
  $policyByTarget = @{}; foreach($row in @($registry.support_policy)){$policyByTarget[[string]$row.target]=$row}
  $identityByTarget = @{}; foreach($row in @($registry.identities)){$identityByTarget[[string]$row.target]=$row}
  $historicalByTarget = @{}; foreach($row in @($historicalAuthority.targets)){$historicalByTarget[[string]$row.target_key]=$row}

  $historicalRows = @(
    foreach($target in @($authority.historical_targets)) {
      $row=$historicalByTarget[[string]$target];$identity=$identityByTarget[[string]$target];$policy=$policyByTarget[[string]$target]
      $expectedEngine = if($row.engine.PSObject.Properties['sha256']){[string]$row.engine.sha256}else{$null}
      $engine = Get-MIR4W09EngineObservation -FactorioLine ([string]$row.factorio_line) -ExpectedSha256 $expectedEngine -ExpectedVersion ([string]$row.engine.version)
      $archive = Get-MIR4W09ArchiveDescriptor -RepoRoot $repo -RelativePath ([string]$row.predecessor_archive) -ExpectedSha256 ([string]$row.predecessor_archive_sha256)
      $snapshotPath=[string]$row.predecessor_snapshot;$snapshotStatus='missing';$snapshotSha=$null
      if(Test-Path -LiteralPath (Join-Path $repo $snapshotPath) -PathType Leaf){$snapshotSha=(Get-FileHash -LiteralPath (Join-Path $repo $snapshotPath) -Algorithm SHA256).Hash;$snapshotStatus='present-record-bound'}
      $manifestRelative="$HistoricalBuildRoot/manifests/$target.json".Replace('\','/');$manifestPath=Join-Path $repo $manifestRelative
      if(Test-Path -LiteralPath $manifestPath -PathType Leaf){$manifest=Get-Content -Raw -LiteralPath $manifestPath|ConvertFrom-Json -Depth 100;$candidate=[ordered]@{status=[string]$manifest.status;manifest=$manifestRelative;manifest_sha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash;archive=[string]$manifest.distribution.path;archive_sha256=[string]$manifest.distribution.sha256;source_version='4.0.0';candidate_id='M4C02-09-24H';package_root="more-infinite-research_$([string]$row.distribution_version)";source_commit=[string]$source.commit;source_tree=[string]$source.tree;publication_authorized=$false}}else{$candidate=[ordered]@{status='not-materialized';manifest=$manifestRelative;manifest_sha256=$null;archive=$null;archive_sha256=$null;source_version='4.0.0';candidate_id='M4C02-09-24H';package_root="more-infinite-research_$([string]$row.distribution_version)";source_commit=[string]$source.commit;source_tree=[string]$source.tree;publication_authorized=$false}}
      $runtime=Get-MIR4W09RuntimeObservation -RepoRoot $repo -Target ([string]$target) -EvidenceRoot $RuntimeEvidenceRoot
      $blockers=@();if(-not$archive.hash_match){$blockers+='BLOCKED-PREDECESSOR-ARCHIVE-IDENTITY'};if(-not$engine.hash_match){$blockers+=$(if($target-eq'f018'){'BLOCKED-MISSING-EXACT-ENGINE'}else{'BLOCKED-EXACT-ENGINE-IDENTITY'})};if($candidate.status-eq'not-materialized'){$blockers+='BLOCKED-CANDIDATE-NOT-MATERIALIZED'};if($runtime.status-eq'not-run'){$blockers+='BLOCKED-FRESH-EXACT-RUNTIME-NOT-RUN'}
      [ordered]@{target=[string]$target;factorio_line=[string]$identity.factorio_line;distribution_version=[string]$identity.distribution_version;maturity='private-experimental';registry_disposition=[string]$policy.disposition;predecessor=[ordered]@{release=[string]$row.predecessor_release;archive=$archive;snapshot=[ordered]@{path=$snapshotPath;status=$snapshotStatus;record_sha256=[string]$row.predecessor_snapshot_record_sha256;file_sha256=$snapshotSha}};candidate=$candidate;engine=$engine;runtime=$runtime;rights_custody=[ordered]@{status='private-local-evaluation-only';redistribution_authorized=$false;public_support_authorized=$false;authority='MIR4-Historical-Private-Candidate-AuthorizationV1'};blockers=@($blockers|Sort-Object -Unique)}
    }
  )

  $museumRows = @(
    foreach($museumTarget in @($museum.targets)) {
      $code=([string]$museumTarget.factorio).Replace('.','').PadLeft(3,'0');$target="f$code";$identity=$identityByTarget[$target];$policy=$policyByTarget[$target]
      $engine=Get-MIR4W09EngineObservation -FactorioLine ([string]$museumTarget.factorio) -ExpectedSha256 ([string]$museumTarget.binary_sha256) -ExpectedVersion ([string]$museumTarget.exact_patch)
      $archiveRelative="dist/more-infinite-research_$([string]$museumTarget.version).zip";$archive=Get-MIR4W09ArchiveDescriptor -RepoRoot $repo -RelativePath $archiveRelative -ExpectedSha256 $null
      $runtime=Get-MIR4W09MuseumRuntimeObservation -RepoRoot $repo -FactorioLine ([string]$museumTarget.factorio) -ExpectedEngineSha256 ([string]$museumTarget.binary_sha256) -ExpectedBaseSha256 ([string]$museumTarget.base_data_sha256)
      $blockers=@('BLOCKED-MUSEUM-RIGHTS-CUSTODY-RESTORE-CLOSURE');if(-not$engine.hash_match){$blockers+='BLOCKED-EXACT-ENGINE-IDENTITY'};if(-not$archive.hash_match){$blockers+='BLOCKED-MUSEUM-ARCHIVE-MISSING'};if([string]$runtime.status-eq'blocked-noninteractive-display'){$blockers+='BLOCKED-NONINTERACTIVE-DISPLAY'}elseif([string]$runtime.status-ne'passed-private-exact-engine'){$blockers+='BLOCKED-FRESH-EXACT-RUNTIME-NOT-RUN'}
      [ordered]@{target=$target;factorio_line=[string]$identity.factorio_line;distribution_version=[string]$identity.distribution_version;maturity='blocked-museum-inventory';registry_disposition=[string]$policy.disposition;candidate=[ordered]@{status='immutable-mir3-museum-archive-inventory-only';archive=$archive;mir4_materialization_authorized=$false;source_version='4.0.0';candidate_id='M4C02-09-24H';package_root=$null;source_commit=[string]$source.commit;source_tree=[string]$source.tree;publication_authorized=$false};engine=$engine;runtime=$runtime;rights_custody=[ordered]@{status='incomplete-initial-classification';local_retention_observed=$engine.hash_match;redistribution_authorized=$false;mirror_receipts_complete=$false;restore_closure_complete=$false;public_support_authorized=$false;authority='.mir/releases/terminal/MIR-3-MUSEUM-INDEX.json'};blockers=@($blockers|Sort-Object -Unique)}
    }
  )
  $inputs=@('.mir/releases/waves/mir4-r0/MIR4-Historical-Succession-ProgrammeV1.json','.mir/releases/waves/mir4-r0/MIR4-Target-RegistryV6.json','.mir/releases/waves/mir4-r0/MIR4-Historical-Private-Candidate-AuthorizationV1.json','.mir/museum-targets.json','.mir/releases/terminal/MIR-3-MUSEUM-INDEX.json')|ForEach-Object{Get-MIR4W09InputDescriptor -RepoRoot $repo -RelativePath $_}
  $allBlockers=@($historicalRows.blockers+$museumRows.blockers|ForEach-Object{@($_)}|Sort-Object -Unique)
  $record=[pscustomobject][ordered]@{kind='MIR4HistoricalMuseumMatrixV1';schema=1;programme_id='M4C02-09-24H';wave='W09';maturity='developer-preview-shadow';source_identity=$source;input_authorities=@($inputs);historical_targets=$historicalRows;museum_targets=$museumRows;summary=[ordered]@{historical_count=$historicalRows.Count;museum_count=$museumRows.Count;exact_engine_available_count=@($historicalRows.engine+$museumRows.engine|Where-Object hash_match).Count;historical_runtime_pass_count=@($historicalRows.runtime|Where-Object status -eq 'passed-private-exact-engine').Count;museum_runtime_pass_count=@($museumRows.runtime|Where-Object status -eq 'passed-private-exact-engine').Count;museum_admitted_count=0;public_products=0};blockers=$allBlockers;status='partial-with-bounded-blockers';package_visible=$false;public_release_proof=$false;target_policy_authority=$false;museum_admission_authority=$false;rights_or_custody_authority=$false;source_freeze_authorized=$false;production_signing_or_sealing_authorized=$false;publication_authorized=$false;record_sha256=''}
  return Add-MIR4W09RecordSha256 $record
}
