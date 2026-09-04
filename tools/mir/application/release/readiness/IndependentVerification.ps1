Set-StrictMode -Version Latest

if (-not (Get-Command Get-MIRZipContentFingerprint -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../../../../lib/validation/PackageIdentity.ps1')
}

function Test-MIR441ForbiddenPackageRelativePath {
  param([Parameter(Mandatory)][string]$Path)
  $normalized=$Path.Replace('\','/').TrimStart('/')
  $top=($normalized.Split('/')[0])
  return $top-match'(?i)^(?:\.git|\.github|\.mir|tests?|scripts?|docs?|build|dist|evidence|governance|contracts)$'
}

function Get-MIR441ZipObservation {
  param([Parameter(Mandatory)][string]$Path)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip=[IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entries=@($zip.Entries|Where-Object{-not[string]::IsNullOrEmpty($_.Name)})
    $roots=@($entries|ForEach-Object{([string]$_.FullName).Split('/')[0]}|Sort-Object -Unique)
    if($roots.Count-ne1){throw '[mir441-independent-package-root]'}
    $rootPrefix="$($roots[0])/"
    $forbidden=@($entries|Where-Object{
      $relative=([string]$_.FullName).Substring($rootPrefix.Length)
      Test-MIR441ForbiddenPackageRelativePath -Path $relative
    })
    if($forbidden.Count-ne0){throw "[mir441-independent-package-membership] $([string]$forbidden[0].FullName)"}
    $info=@($entries|Where-Object{[string]$_.FullName-ceq"$($roots[0])/info.json"})
    if($info.Count-ne1){throw '[mir441-independent-info-json]'}
    $reader=[IO.StreamReader]::new($info[0].Open(),[Text.UTF8Encoding]::new($false),$true)
    try{$metadata=$reader.ReadToEnd()|ConvertFrom-Json -Depth 30 -DateKind String}finally{$reader.Dispose()}
    return [pscustomobject][ordered]@{
      archive_sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
      content_sha256=Get-MIRZipContentFingerprint -Path $Path
      bytes=[int64](Get-Item -LiteralPath $Path).Length
      entry_count=$entries.Count
      root=[string]$roots[0]
      version=[string]$metadata.version
      factorio_version=[string]$metadata.factorio_version
    }
  } finally {$zip.Dispose()}
}

function Get-MIR441ResourceLedgerObservation {
  param([Parameter(Mandatory)][string]$Path)
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw '[mir441-independent-resource-ledger-missing]'}
  [int]$count=0;[int64]$minFree=[int64]::MaxValue;[int64]$maxWorkingSet=0
  $reader=[IO.File]::OpenText($Path)
  try {
    while(($line=$reader.ReadLine()) -ne $null){
      if([string]::IsNullOrWhiteSpace($line)){continue}
      $row=$line|ConvertFrom-Json -Depth 30 -DateKind String
      $count++;$minFree=[Math]::Min($minFree,[int64]$row.memory.free_bytes)
      if($null-ne$row.process){$maxWorkingSet=[Math]::Max($maxWorkingSet,[int64]$row.process.peak_working_set_bytes)}
    }
  } finally {$reader.Dispose()}
  if($count-eq0){throw '[mir441-independent-resource-ledger-empty]'}
  return [pscustomobject][ordered]@{samples=$count;minimum_free_memory_bytes=$minFree;maximum_process_working_set_bytes=$maxWorkingSet;identity=(Get-MIR441FileIdentity -Path $Path -RelativePath 'resource-ledger.jsonl')}
}

function Test-MIR441IndependentQualification {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$EvidenceRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $evidence=Assert-MIR441ExternalRoot -RepoRoot $repo -Path $EvidenceRoot -Name EvidenceRoot
  $contract=Get-MIR441ReleaseReadinessContract -RepoRoot $repo
  $source=Get-MIR441GitIdentity -RepoRoot $repo
  $candidate=Get-Content -Raw -LiteralPath (Join-Path $evidence 'candidate-manifest.json')|ConvertFrom-Json -Depth 100 -DateKind String
  $aggregate=Get-Content -Raw -LiteralPath (Join-Path $evidence 'qualification/aggregate.json')|ConvertFrom-Json -Depth 100 -DateKind String
  foreach($record in @($candidate,$aggregate)){
    if([string]$record.source.commit-cne[string]$source.commit-or[string]$record.source.tree-cne[string]$source.tree){throw '[mir441-independent-source-drift]'}
  }
  if([string]$candidate.status-cne'MIR-4.1.0-PRIVATE-FOUR-TARGET-CANDIDATE-BUILT-UNQUALIFIED'-or[string]$aggregate.status-cne'MIR-4.1.0-FOUR-TARGET-TECHNICAL-QUALIFICATION-PASSED'){throw '[mir441-independent-input-state]'}
  $rows=[Collections.Generic.List[object]]::new()
  foreach($target in @($contract.targets)){
    $id=[string]$target.target
    $candidateRows=@($candidate.targets|Where-Object{[string]$_.target-ceq$id})
    $qualificationRows=@($aggregate.targets|Where-Object{[string]$_.target-ceq$id})
    if($candidateRows.Count-ne1-or$qualificationRows.Count-ne1){throw "[mir441-independent-target-cardinality] $id"}
    $candidateRow=$candidateRows[0];$qualification=$qualificationRows[0]
    $assetPath=Join-Path $evidence "assets/$([string]$candidateRow.asset.path)"
    $archive=Get-MIR441ZipObservation -Path $assetPath
    if([string]$archive.archive_sha256-cne[string]$candidateRow.asset.sha256-or
       [int64]$archive.bytes-ne[int64]$candidateRow.asset.bytes-or
       [string]$archive.content_sha256-cne[string]$candidateRow.content_sha256-or
       [int]$archive.entry_count-ne[int]$candidateRow.entry_count-or
       [string]$archive.version-cne[string]$target.distribution_version){throw "[mir441-independent-candidate-identity] $id"}
    if([string]$qualification.status-cne'passed'-or[string]$qualification.candidate.archive.sha256-cne[string]$archive.archive_sha256-or
       [string]$qualification.candidate.content_sha256-cne[string]$archive.content_sha256-or[int]$qualification.candidate.entry_count-ne[int]$archive.entry_count){throw "[mir441-independent-qualification-identity] $id"}
    $engine=Get-MIR441TargetEngineIdentity -RepoRoot $repo -Target $target
    if([string]$qualification.engine.version-cne[string]$engine.version-or[string]$qualification.engine.binary_sha256-cne[string]$engine.binary_sha256){throw "[mir441-independent-engine-drift] $id"}
    if(@($qualification.fresh_loads).Count-eq0-or@($qualification.fresh_loads|Where-Object{[string]$_.status-cne'passed'}).Count-ne0-or
       -not[bool]$qualification.upgrade.first_reload-or-not[bool]$qualification.upgrade.second_reload){throw "[mir441-independent-runtime-state] $id"}
    $targetEvidence=Join-Path $evidence "qualification/$id"
    foreach($fresh in @($qualification.fresh_loads)){
      $path=Join-Path $targetEvidence ([string]$fresh.evidence.path)
      if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash-cne[string]$fresh.evidence.sha256){throw "[mir441-independent-fresh-evidence] $id/$([string]$fresh.name)"}
    }
    $upgradePath=Join-Path $targetEvidence ([string]$qualification.upgrade.evidence.path)
    if((Get-FileHash -LiteralPath $upgradePath -Algorithm SHA256).Hash-cne[string]$qualification.upgrade.evidence.sha256){throw "[mir441-independent-upgrade-evidence] $id"}
    $upgrade=Get-Content -Raw -LiteralPath $upgradePath|ConvertFrom-Json -Depth 100 -DateKind String
    if([string]$upgrade.status-cne'passed'-or@($upgrade.rows|Where-Object{[string]$_.status-cne'passed'}).Count-ne0){throw "[mir441-independent-upgrade-result] $id"}
    $ledger=Get-MIR441ResourceLedgerObservation -Path (Join-Path $targetEvidence 'resource-ledger.jsonl')
    if([int64]$ledger.minimum_free_memory_bytes-lt[int64]([double]$contract.resource_policy.hard_stop_free_ram_gib*1GB)){throw "[mir441-independent-resource-hard-stop] $id"}
    $rows.Add([pscustomobject][ordered]@{target=$id;distribution_version=[string]$target.distribution_version;archive=$archive;engine=$engine;fresh_scenarios=@($qualification.fresh_loads).Count;upgrade_archetypes=@($qualification.upgrade.archetypes);first_reload=$true;second_reload=$true;resource_ledger=$ledger;status='independently-verified'})
  }
  $result=[pscustomobject][ordered]@{
    schema=1;kind='MIR441IndependentQualificationV1';status='MIR-4.1.0-FOUR-TARGET-INDEPENDENT-VERIFICATION-PASSED'
    source=$source;targets=@($rows);all_targets_required=$true;cross_target_substitution=$false
    package_source_sha256=(Get-MIRPackageSourceFingerprint -RepoRoot $repo)
    verified_at=[DateTimeOffset]::UtcNow.ToString('o');human_playtest='pending';technical_seal='pending';tagging_authorized=$false;publication_authorized=$false
  }
  Write-MIR441Json -Value $result -Path (Join-Path $evidence 'independent-verification.json')
  return $result
}
