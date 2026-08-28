# Canonical package-excluded W08 offline-drill application ABI.
function Get-MIR4W08OfflineAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  if($null-eq(Get-Command Get-MIR4W08Authority -CommandType Function -ErrorAction SilentlyContinue)){. (Join-Path $PSScriptRoot 'AssuranceScale.ps1')}
  return Get-MIR4W08Authority -RepoRoot $RepoRoot
}

function Assert-MIR4W08DrillDescendant {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Path)
  $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
  $full=[IO.Path]::GetFullPath($Path)
  if(-not($full+[IO.Path]::DirectorySeparatorChar).StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)){throw "[mir4-w08-drill-boundary] $full"}
  return $full
}

function Write-MIR4W08CanonicalJson {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
  if($null-eq(Get-Command ConvertTo-MIRCPCanonicalJson -CommandType Function -ErrorAction SilentlyContinue)){throw '[mir4-w08-canonicalizer-unavailable]'}
  $parent=Split-Path -Parent $Path;if(-not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
  [IO.File]::WriteAllText($Path,(ConvertTo-MIRCPCanonicalJson -Value $Value)+"`n",[Text.UTF8Encoding]::new($false))
}

function New-MIR4W08DeterministicZip {
  param([Parameter(Mandatory)][Collections.IDictionary]$Entries,[Parameter(Mandatory)][string]$OutputPath)
  Add-Type -AssemblyName System.IO.Compression
  $parent=Split-Path -Parent $OutputPath;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
  $stream=[IO.MemoryStream]::new()
  try{
    $archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    try{
      foreach($name in @($Entries.Keys|ForEach-Object{[string]$_}|Sort-Object -CaseSensitive)){
        if($name.StartsWith('/')-or$name.StartsWith('\')-or$name.Contains('..')-or$name.Contains('\')-or[string]::IsNullOrWhiteSpace($name)){throw "[mir4-w08-drill-entry] $name"}
        $entry=$archive.CreateEntry($name,[IO.Compression.CompressionLevel]::NoCompression);$entry.LastWriteTime=[datetimeoffset]'1980-01-01T00:00:00Z'
        $target=$entry.Open();try{$bytes=if($Entries[$name]-is[byte[]]){$Entries[$name]}else{[Text.UTF8Encoding]::new($false).GetBytes([string]$Entries[$name])};$target.Write($bytes,0,$bytes.Length)}finally{$target.Dispose()}
      }
    }finally{$archive.Dispose()}
    [IO.File]::WriteAllBytes($OutputPath,$stream.ToArray())
  }finally{$stream.Dispose()}
  return [pscustomobject][ordered]@{sha256=(Get-MIR4W08FileSha256 $OutputPath);bytes=(Get-Item -LiteralPath $OutputPath).Length;entry_count=$Entries.Count}
}

function Test-MIR4W08DummyQualificationPlan {
  param([Parameter(Mandatory)]$Plan)
  $map=@{};foreach($task in @($Plan.tasks)){$id=[string]$task.id;if($map.ContainsKey($id)){throw '[mir4-w08-drill-plan-duplicate]'};$map[$id]=$task}
  $remaining=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);foreach($id in $map.Keys){[void]$remaining.Add($id)}
  $order=@()
  while($remaining.Count){
    foreach($id in @($remaining)){foreach($dependency in @($map[$id].depends_on)){if(-not$map.ContainsKey([string]$dependency)){throw '[mir4-w08-drill-plan-missing-dependency]'}}}
    $ready=@($remaining|Where-Object{$id=$_;@($map[$id].depends_on|Where-Object{$remaining.Contains([string]$_)}).Count-eq 0}|Sort-Object)
    if(-not$ready.Count){throw '[mir4-w08-drill-plan-cycle]'}
    foreach($id in $ready){$order+=$id;[void]$remaining.Remove($id)}
  }
  return [pscustomobject][ordered]@{status='passed';task_count=$map.Count;topological_order=$order;execution_authorized=$false}
}

function New-MIR4W08NonProductionProof {
  param([Parameter(Mandatory)][string]$ArtifactSha256,[Parameter(Mandatory)][string]$ManifestSha256,[Parameter(Mandatory)][string]$RepoRoot)
  Import-MIR4W08ControlPlane -RepoRoot $RepoRoot
  $material=[ordered]@{authority_id='mir4-w08-non-production-proof-authority-v1';algorithm='fixture-sha256-proof-v1';artifact_sha256=$ArtifactSha256;manifest_sha256=$ManifestSha256;scope='offline-drill-only'}
  return [pscustomobject][ordered]@{kind='MIR4W08NonProductionProofV1';schema=1;material=$material;proof_sha256=(Get-MIRCPSha256Object -Value $material);cryptographic_signature=$false;production_authority=$false}
}

function Test-MIR4W08NonProductionProof {
  param([Parameter(Mandatory)]$Proof,[Parameter(Mandatory)][string]$ArtifactSha256,[Parameter(Mandatory)][string]$ManifestSha256,[Parameter(Mandatory)][string]$RepoRoot)
  $expected=New-MIR4W08NonProductionProof -ArtifactSha256 $ArtifactSha256 -ManifestSha256 $ManifestSha256 -RepoRoot $RepoRoot
  return [pscustomobject][ordered]@{status=$(if([string]$Proof.proof_sha256-ceq[string]$expected.proof_sha256-and-not[bool]$Proof.cryptographic_signature-and-not[bool]$Proof.production_authority){'passed'}else{'failed'});verifier='fixture-sha256-proof-v1';production_signature_verified=$false}
}

function Invoke-MIR4W08DummyPublisher {
  param(
    [Parameter(Mandatory)][string]$DrillRoot,[Parameter(Mandatory)][string]$PackagePath,
    [Parameter(Mandatory)]$Manifest,[Parameter(Mandatory)][string]$DestinationId
  )
  if($DestinationId-notmatch'^[a-z0-9][a-z0-9.-]{0,63}$'){throw '[mir4-w08-publisher-destination]'}
  $root=[IO.Path]::GetFullPath($DrillRoot);$inbox=Join-Path $root 'inbox';$verified=Join-Path $root 'verified';$outbox=Join-Path $root 'outbox';$receipt=Join-Path $root 'receipt'
  foreach($path in @($inbox,$verified,$outbox,$receipt)){Assert-MIR4W08DrillDescendant -Root $root -Path $path|Out-Null;if(-not(Test-Path -LiteralPath $path)){New-Item -ItemType Directory -Force -Path $path|Out-Null}}
  $package=Assert-MIR4W08DrillDescendant -Root $inbox -Path $PackagePath
  if(-not(Test-Path -LiteralPath $package -PathType Leaf)){throw '[mir4-w08-publisher-package-missing]'}
  $actual=Get-MIR4W08FileSha256 $package
  if($actual-cne[string]$Manifest.archive_sha256){throw '[mir4-w08-publisher-verify-before-transfer]'}
  $manifestSha=Get-MIRCPSha256Object -Value $Manifest
  $transferId=Get-MIRCPSha256Object -Value ([ordered]@{archive_sha256=$actual;destination_id=$DestinationId;manifest_sha256=$manifestSha})
  $verifiedPath=Join-Path $verified ([IO.Path]::GetFileName($package));[IO.File]::Copy($package,$verifiedPath,$true)
  if((Get-MIR4W08FileSha256 $verifiedPath)-cne$actual){throw '[mir4-w08-publisher-verified-copy]'}
  $destination=Join-Path $outbox "$DestinationId.bin";$disposition='transferred'
  if(Test-Path -LiteralPath $destination -PathType Leaf){if((Get-MIR4W08FileSha256 $destination)-cne$actual){throw '[mir4-w08-publisher-conflicting-transfer]'};$disposition='reconciled-idempotent'}else{[IO.File]::Copy($verifiedPath,$destination,$false)}
  if((Get-MIR4W08FileSha256 $destination)-cne$actual){throw '[mir4-w08-publisher-post-transfer-verify]'}
  $record=[pscustomobject][ordered]@{kind='MIR4W08DummyPublisherReceiptV1';schema=1;transfer_id=$transferId;destination_id=$DestinationId;archive_sha256=$actual;manifest_sha256=$manifestSha;verified_before_transfer=$true;disposition=$disposition;build_authorized=$false;mutation_authorized=$false;network_calls=0;production_authority=$false}
  $receiptPath=Join-Path $receipt "$transferId.json"
  if(Test-Path -LiteralPath $receiptPath){$existing=Get-Content -Raw -LiteralPath $receiptPath|ConvertFrom-Json -Depth 30;if([string]$existing.transfer_id-cne$transferId-or[string]$existing.archive_sha256-cne$actual){throw '[mir4-w08-publisher-receipt-conflict]'}}else{Write-MIR4W08CanonicalJson -Path $receiptPath -Value $record}
  return $record
}

function Invoke-MIR4W08OfflineDrill {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$SourceIdentity,[string]$OutputRoot='build/mir4/m4c02-assurance-scale/drill')
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$authority=Get-MIR4W08OfflineAuthority -RepoRoot $repo
  $buildBoundary=Join-Path $repo 'build/mir4';$root=Assert-MIR4W08DrillDescendant -Root $buildBoundary -Path (Join-Path $repo $OutputRoot)
  if(Test-Path -LiteralPath $root){[IO.Directory]::Delete($root,$true)};New-Item -ItemType Directory -Path $root -Force|Out-Null
  $fixtureRoot=Join-Path $repo ([string]$authority.fixtures);$snapshot=Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'offline/repository-snapshot.json')|ConvertFrom-Json -Depth 30
  if(-not[bool]$snapshot.non_production){throw '[mir4-w08-drill-repository-fixture]'}
  $restored=Join-Path $root 'restored-repository';$restoredRows=@()
  foreach($file in @($snapshot.files|Sort-Object path)){
    $path=[string]$file.path;if($path.StartsWith('/')-or$path.StartsWith('\')-or$path.Contains('..')){throw '[mir4-w08-drill-restore-path]'}
    $target=Assert-MIR4W08DrillDescendant -Root $restored -Path (Join-Path $restored $path);$parent=Split-Path -Parent $target;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
    [IO.File]::WriteAllText($target,[string]$file.content,[Text.UTF8Encoding]::new($false));$restoredRows+=[ordered]@{path=$path;sha256=(Get-MIR4W08FileSha256 $target)}
  }
  $repository=[ordered]@{status='passed-dummy-fixture-only';files=$restoredRows;source_repository_access=$false}

  $payloadPath=Join-Path $fixtureRoot 'offline/dummy-payload.txt';$payloadBytes=[IO.File]::ReadAllBytes($payloadPath)
  $packagePath=Join-Path $root 'constructed/dummy-mir4-package.zip';$package=New-MIR4W08DeterministicZip -Entries ([ordered]@{'manifest.json'='{"kind":"MIR4W08DummyPackageV1","production":false}`n';'payload/dummy-payload.txt'=$payloadBytes}) -OutputPath $packagePath
  $packageRepeat=New-MIR4W08DeterministicZip -Entries ([ordered]@{'manifest.json'='{"kind":"MIR4W08DummyPackageV1","production":false}`n';'payload/dummy-payload.txt'=$payloadBytes}) -OutputPath (Join-Path $root 'constructed/dummy-mir4-package-repeat.zip')
  if([string]$package.sha256-cne[string]$packageRepeat.sha256){throw '[mir4-w08-drill-package-nondeterministic]'}

  $plan=Get-Content -Raw -LiteralPath (Join-Path $fixtureRoot 'offline/qualification-plan.json')|ConvertFrom-Json -Depth 30;$qualification=Test-MIR4W08DummyQualificationPlan $plan
  $manifest=[pscustomobject][ordered]@{kind='MIR4W08DummyPublisherManifestV1';schema=1;archive_name='dummy-mir4-package.zip';archive_sha256=[string]$package.sha256;bytes=[int64]$package.bytes;entry_count=[int]$package.entry_count;non_production=$true;source_fixture='fixtures/mir4-assurance-scale-v1/offline/dummy-payload.txt'}
  $manifestSha=Get-MIRCPSha256Object -Value $manifest;$proof=New-MIR4W08NonProductionProof -ArtifactSha256 $package.sha256 -ManifestSha256 $manifestSha -RepoRoot $repo;$proofCheck=Test-MIR4W08NonProductionProof -Proof $proof -ArtifactSha256 $package.sha256 -ManifestSha256 $manifestSha -RepoRoot $repo
  if([string]$proofCheck.status-cne'passed'){throw '[mir4-w08-drill-proof-verifier]'}
  $seal=[pscustomobject][ordered]@{kind='MIR4W08NonProductionSealRehearsalV1';schema=1;archive_sha256=[string]$package.sha256;manifest_sha256=$manifestSha;proof_sha256=[string]$proof.proof_sha256;production=$false;release_authority=$false}

  $publisherRoot=Join-Path $root 'publisher';$inbox=Join-Path $publisherRoot 'inbox';New-Item -ItemType Directory -Force -Path $inbox|Out-Null;$inboxPackage=Join-Path $inbox 'dummy-mir4-package.zip';[IO.File]::Copy($packagePath,$inboxPackage,$true)
  $outbox=Join-Path $publisherRoot 'outbox';New-Item -ItemType Directory -Force -Path $outbox|Out-Null;[IO.File]::Copy($packagePath,(Join-Path $outbox 'offline-file-target.bin'),$true)
  $publisher=Invoke-MIR4W08DummyPublisher -DrillRoot $publisherRoot -PackagePath $inboxPackage -Manifest $manifest -DestinationId 'offline-file-target'
  if([string]$publisher.disposition-cne'reconciled-idempotent'){throw '[mir4-w08-drill-uncertain-transfer-reconciliation]'}

  $capsuleEntries=[ordered]@{'dummy-package.zip'=[IO.File]::ReadAllBytes($packagePath);'manifest.json'=(ConvertTo-MIRCPCanonicalJson -Value $manifest)+"`n";'non-production-proof.json'=(ConvertTo-MIRCPCanonicalJson -Value $proof)+"`n";'publisher-receipt.json'=(ConvertTo-MIRCPCanonicalJson -Value $publisher)+"`n";'seal-rehearsal.json'=(ConvertTo-MIRCPCanonicalJson -Value $seal)+"`n"}
  $capsulePath=Join-Path $root 'capsule/mir4-w08-offline-drill-capsule.zip';$capsule=New-MIR4W08DeterministicZip -Entries $capsuleEntries -OutputPath $capsulePath
  $distributionRows=@();foreach($channel in @('local-file','lan-file')){$target=Join-Path $root "distribution/$channel/mir4-w08-offline-drill-capsule.zip";$parent=Split-Path -Parent $target;New-Item -ItemType Directory -Force -Path $parent|Out-Null;[IO.File]::Copy($capsulePath,$target,$true);$distributionRows+=[ordered]@{channel=$channel;transport='filesystem-copy-simulation';sha256=(Get-MIR4W08FileSha256 $target);network_calls=0;status='passed'}}
  $record=[pscustomobject][ordered]@{
    kind='MIR4OfflineDrillResultV1';schema=1;programme_id=[string]$authority.programme_id;wave='W08';maturity='developer-preview';source_identity=$SourceIdentity
    confinement=[ordered]@{fixture_root='fixtures/mir4-assurance-scale-v1';output_root=$OutputRoot.Replace('\','/');network='denied-no-network-capability';network_calls=0;real_source_access=$false;real_candidate_access=$false;credential_access=$false;production_key_access=$false}
    repository_restoration=$repository;package_construction=[ordered]@{status='passed-dummy-fixture-only';archive_sha256=[string]$package.sha256;bytes=[int64]$package.bytes;entry_count=[int]$package.entry_count;deterministic_repetition=$true;player_package=$false}
    qualification_planning=$qualification;signing_verifier=[ordered]@{status=[string]$proofCheck.status;algorithm='fixture-sha256-proof-v1';production_cryptographic_signature=$false;proof_sha256=[string]$proof.proof_sha256}
    seal_rehearsal=$seal;release_capsule=[ordered]@{status='passed-non-production';sha256=[string]$capsule.sha256;bytes=[int64]$capsule.bytes;entry_count=[int]$capsule.entry_count;production=$false}
    distribution=$distributionRows;publisher=[ordered]@{roots=@($authority.dummy_publisher_roots);forbidden_capabilities=@($authority.dummy_publisher_forbidden_capabilities);verified_before_transfer=[bool]$publisher.verified_before_transfer;uncertain_transfer_disposition=[string]$publisher.disposition;build_authorized=$false;mutation_authorized=$false;network_calls=0;production_authority=$false}
    operations=@($authority.offline_drill_operations|ForEach-Object{[ordered]@{id=[string]$_;status='passed-non-production-fixture-only'}})
    status='passed-non-production-offline-drill';package_visible=$false;public_release_proof=$false;source_freeze_authorized=$false;production_signing_or_sealing_authorized=$false;promotion_or_tag_authorized=$false;publication_authorized=$false;record_sha256=''
  }
  return Add-MIR4W08RecordSha256 $record
}
