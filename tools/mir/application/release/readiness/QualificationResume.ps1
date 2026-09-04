Set-StrictMode -Version Latest

function Get-MIR441ValidatedTargetCheckpoint {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Source,
    [Parameter(Mandatory)]$Engine,
    [Parameter(Mandatory)]$Candidate
  )
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
  $record=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json -Depth 100 -DateKind String
  if([string]$record.status-cne'passed'-or
     [string]$record.source.commit-cne[string]$Source.commit-or[string]$record.source.tree-cne[string]$Source.tree-or
     [string]$record.engine.version-cne[string]$Engine.version-or[string]$record.engine.binary_sha256-cne[string]$Engine.binary_sha256-or
     [string]$record.candidate.archive.sha256-cne[string]$Candidate.asset.sha256-or
     [string]$record.candidate.content_sha256-cne[string]$Candidate.content_sha256-or
     [int]$record.candidate.entry_count-ne[int]$Candidate.entry_count){throw '[mir441-qualification-resume-target]'}
  return $record
}

function Get-MIR441ValidatedFreshCheckpoint {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$SummaryPath,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)]$Source,
    [Parameter(Mandatory)]$Engine,
    [Parameter(Mandatory)]$Candidate
  )
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
  try{
    $record=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json -Depth 100 -DateKind String
    $summaryIdentity=Get-MIR441FileIdentity -Path $SummaryPath -RelativePath (Split-Path -Leaf $SummaryPath)
    $summary=Get-Content -Raw -LiteralPath $SummaryPath|ConvertFrom-Json -Depth 100 -DateKind String
    if([string]$record.kind-cne'MIR441FreshQualificationCheckpointV1'-or[string]$record.status-cne'passed'-or[string]$record.name-cne$Name-or
       [string]$record.source.commit-cne[string]$Source.commit-or[string]$record.source.tree-cne[string]$Source.tree-or
       [string]$record.engine.version-cne[string]$Engine.version-or[string]$record.engine.binary_sha256-cne[string]$Engine.binary_sha256-or
       [string]$record.candidate.archive_sha256-cne[string]$Candidate.asset.sha256-or[string]$record.candidate.content_sha256-cne[string]$Candidate.content_sha256-or
       [string]$record.summary.sha256-cne[string]$summaryIdentity.sha256-or[int64]$record.summary.bytes-ne[int64]$summaryIdentity.bytes-or
       [string]$summary.status-cne'passed'-or[string]$summary.git_commit-cne[string]$Source.commit-or[bool]$summary.package_source_git_dirty-or[bool]$summary.validation_harness_git_dirty-or
       [string]$summary.factorio_binary_version-cne[string]$Engine.version-or
       [string]$summary.validation_package_sha256-cne[string]$Candidate.asset.sha256-or[string]$summary.validation_package_content_sha256-cne[string]$Candidate.content_sha256-or
       [string]$record.result.status-cne'passed'){throw 'mismatch'}
    return $record
  }catch{throw "[mir441-qualification-resume-fresh] $Name"}
}

function Write-MIR441FreshCheckpoint {
  param([string]$Path,[string]$Name,$Source,$Engine,$Candidate,$SummaryIdentity,$Result)
  $record=[pscustomobject][ordered]@{
    schema=1;kind='MIR441FreshQualificationCheckpointV1';status='passed';name=$Name;source=$Source
    engine=[ordered]@{version=[string]$Engine.version;binary_sha256=[string]$Engine.binary_sha256}
    candidate=[ordered]@{archive_sha256=[string]$Candidate.asset.sha256;content_sha256=[string]$Candidate.content_sha256}
    summary=$SummaryIdentity;result=$Result
  }
  Write-MIR441Json -Value $record -Path $Path
  return $record
}

function Get-MIR441ValidatedUpgradeCheckpoint {
  param([string]$Path,[string]$SummaryPath,$Source,$Engine,$Candidate,[string]$PredecessorSha256)
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
  try{
    $record=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json -Depth 100 -DateKind String
    $summaryIdentity=Get-MIR441FileIdentity -Path $SummaryPath -RelativePath 'upgrade-matrix.json'
    $summary=Get-Content -Raw -LiteralPath $SummaryPath|ConvertFrom-Json -Depth 100 -DateKind String
    if([string]$record.kind-cne'MIR441UpgradeQualificationCheckpointV1'-or[string]$record.status-cne'passed'-or
       [string]$record.source.commit-cne[string]$Source.commit-or[string]$record.source.tree-cne[string]$Source.tree-or
       [string]$record.engine.version-cne[string]$Engine.version-or[string]$record.engine.binary_sha256-cne[string]$Engine.binary_sha256-or
       [string]$record.candidate.archive_sha256-cne[string]$Candidate.asset.sha256-or[string]$record.candidate.content_sha256-cne[string]$Candidate.content_sha256-or
       [string]$record.predecessor_sha256-cne$PredecessorSha256-or[string]$record.summary.sha256-cne[string]$summaryIdentity.sha256-or
       [string]$summary.status-cne'passed'-or@($summary.rows|Where-Object{[string]$_.status-cne'passed'}).Count-ne0-or[int]$summary.expanded_roots_retained-ne0){throw 'mismatch'}
    return $record
  }catch{throw '[mir441-qualification-resume-upgrade]'}
}

function Write-MIR441UpgradeCheckpoint {
  param([string]$Path,$Source,$Engine,$Candidate,[string]$PredecessorSha256,$SummaryIdentity,$Result,[double]$DurationSeconds)
  $record=[pscustomobject][ordered]@{
    schema=1;kind='MIR441UpgradeQualificationCheckpointV1';status='passed';source=$Source
    engine=[ordered]@{version=[string]$Engine.version;binary_sha256=[string]$Engine.binary_sha256}
    candidate=[ordered]@{archive_sha256=[string]$Candidate.asset.sha256;content_sha256=[string]$Candidate.content_sha256}
    predecessor_sha256=$PredecessorSha256;summary=$SummaryIdentity;result=$Result;duration_seconds=$DurationSeconds
  }
  Write-MIR441Json -Value $record -Path $Path
  return $record
}
