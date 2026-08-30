. (Join-Path $PSScriptRoot '../migration/AppendOnlyAuthorityMigration.ps1')
. (Join-Path $PSScriptRoot '../targets/TargetKeyMigration.ps1')
. (Join-Path $PSScriptRoot 'TechnologyAcceptance.ps1')

$script:MIR4TechnologyAcceptanceMigrationAuthorityPath='governance/repository/migrations/technology-acceptance-tooling-v1.json'
$script:MIR4TechnologyAcceptanceMigrationAuthoritySchemaPath='contracts/repository/mir4-technology-acceptance-migration-authority-v1.schema.json'
$script:MIR4TechnologyAcceptanceMigrationProofPath='assurance/repository/technology-acceptance-tooling-v1.json'
$script:MIR4TechnologyAcceptanceMigrationProofSchemaPath='contracts/repository/mir4-technology-acceptance-migration-proof-v1.schema.json'
$script:MIR4TechnologyAcceptanceMigrationReceiptPath='releases/migrations/MIR4-Technology-Acceptance-Tooling-MigrationV1.json'
$script:MIR4TechnologyAcceptanceMigrationReceiptSchemaPath='contracts/repository/mir4-technology-acceptance-migration-receipt-v1.schema.json'
$script:MIR4TechnologyAcceptanceMigrationReceiptSha256='011AC795CBB9FBC850E5821D367F1D57264DB79A16540694B4AD4771EB38E879'
$script:MIR4TechnologyAcceptancePredecessorReceiptPath='releases/migrations/MIR4-Whole-Platform-Tooling-MigrationV1.json'
$script:MIR4TechnologyAcceptancePredecessorReceiptSha256='4DEFD2256070F627031AC39FB244619E5E7E1949061DED5F89CF438D810F4B78'
$script:MIR4TechnologyAcceptanceParityDigestV1='sha256:c856a429b8f8bad9609bdfa9e508035e52ed4e0fdc4c09a2cac778aa37315eda'

function Get-MIR4TechnologyAcceptanceMigrationAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4TechnologyAcceptanceMigrationAuthorityPath -SchemaPath $script:MIR4TechnologyAcceptanceMigrationAuthoritySchemaPath)){
    throw '[mir4-technology-acceptance-migration-authority-schema]'
  }
  $authority=Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4TechnologyAcceptanceMigrationAuthorityPath
  if([string]$authority.predecessor_receipt.path-cne$script:MIR4TechnologyAcceptancePredecessorReceiptPath-or
     [string]$authority.predecessor_receipt.sha256-cne$script:MIR4TechnologyAcceptancePredecessorReceiptSha256){
    throw '[mir4-technology-acceptance-migration-predecessor-authority]'
  }
  if(@($authority.writers).Count-ne1-or[string]$authority.writers[0].path-cne'tools/mir/application/technology/TechnologyAcceptanceMigration.ps1'){
    throw '[mir4-technology-acceptance-migration-single-writer]'
  }
  $finalPaths=@($authority.path_map|ForEach-Object{[string]$_.final_path})
  if(@($finalPaths|Sort-Object -Unique).Count-ne$finalPaths.Count){throw '[mir4-technology-acceptance-migration-duplicate-final-path]'}
  if(@($authority.release_transition_authority.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-ne0){
    throw '[mir4-technology-acceptance-migration-release-authority]'
  }
  return $authority
}

function Get-MIR4TechnologyAcceptanceMigrationProofPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  if(-not(Test-MIR4RepositoryJsonSchemaV1 -RepoRoot $repo -Path $script:MIR4TechnologyAcceptanceMigrationProofPath -SchemaPath $script:MIR4TechnologyAcceptanceMigrationProofSchemaPath)){
    throw '[mir4-technology-acceptance-migration-proof-schema]'
  }
  return Get-MIR4RepositoryJsonV1 -RepoRoot $repo -Path $script:MIR4TechnologyAcceptanceMigrationProofPath
}

function Test-MIR4TechnologyAcceptanceCompatibilityForwarderV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $path='tools/lib/mir4/TechnologyAcceptance.ps1'
  $text=[IO.File]::ReadAllText((Join-Path $repo $path)).Replace('\','/')
  if($text-cnotmatch'MIR4-TECHNOLOGY-ACCEPTANCE-COMPATIBILITY-LIBRARY'-or
     $text-cnotmatch[regex]::Escape('mir/application/technology/TechnologyAcceptance.ps1')-or
     $text.Split([char]10).Count-gt4){
    throw "[mir4-technology-acceptance-compatibility-forwarder] $path"
  }
  return $true
}

function Test-MIR4TechnologyAcceptanceDeclaredConsumersV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $bindings=[ordered]@{
    'tools/commands/mir4/New-MIR4TechnologyAcceptanceQueue.ps1'='tools/mir/application/technology/TechnologyAcceptance.ps1'
    'tests/platform/Test-MIR4WholePlatform.ps1'='tools/mir/application/technology/TechnologyAcceptance.ps1'
    'tests/technology/Test-MIR4TechnologyAcceptance.ps1'='tools/mir/application/technology/TechnologyAcceptance.ps1'
    'tools/lib/mir4/PlatformPreview.ps1'='tools/mir/application/technology/TechnologyAcceptance.ps1'
    '.mir/modules.yml'='tools/mir/application/technology/TechnologyAcceptance.ps1'
    '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json'='tools/mir/application/technology/TechnologyAcceptance.ps1'
  }
  foreach($entry in $bindings.GetEnumerator()){
    $text=[IO.File]::ReadAllText((Join-Path $repo ([string]$entry.Key))).Replace('\','/')
    if($text-cnotmatch[regex]::Escape([string]$entry.Value)){throw "[mir4-technology-acceptance-consumer-final-path] $($entry.Key)"}
  }
  return $true
}

function Get-MIR4TechnologyAcceptanceFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('mir4-technology-acceptance-parity-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tempRoot|Out-Null
  try{
    $alternative=[ordered]@{
      alternative_id='emit:mir-parity';action='emit';disposition='materialize'
      design_fingerprint='design-parity';qualification_fingerprint='qualification-parity';qualification_decision='qualified'
      technology_design=[ordered]@{candidate_id='candidate/parity';technology_id='mir-parity';design_fingerprint='design-parity'}
    }
    $catalog=[ordered]@{
      schema=3;phase='final';mutation_authority=$false;selection_authority='deterministic-policy-v2'
      catalog_fingerprint='catalog-parity';selection_fingerprint='selection-parity'
      candidates=@([ordered]@{candidate_id='candidate/parity';alternatives=@($alternative)})
      current_selections=@([ordered]@{candidate_id='candidate/parity';alternative_id=$alternative.alternative_id;design_fingerprint=$alternative.design_fingerprint;qualification_fingerprint=$alternative.qualification_fingerprint})
    }
    $catalogPath=Join-Path $tempRoot 'catalog.json'
    $catalog|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $catalogPath -Encoding UTF8
    $queue=New-MIR4TechnologyAcceptanceQueue -RepoRoot $repo -CatalogPath $catalogPath -Target f210 -Ecosystem aai
    $invalidMessage=$null
    try{New-MIR4TechnologyAcceptanceQueue -RepoRoot $repo -CatalogPath $catalogPath -Target F210 -Ecosystem invalid|Out-Null}catch{$invalidMessage=$_.Exception.Message}
    $record=[ordered]@{
      target=[string]$queue.target
      legacy_target=[string]$queue.legacy_target
      ecosystem=[string]$queue.ecosystem
      candidate_count=[int]$queue.candidate_count
      acceptance_states=@($queue.entries|ForEach-Object{[string]$_.acceptance_state})
      required_records=@($queue.entries[0].required_records|ForEach-Object{[string]$_})
      mutation_authorized=[bool]$queue.mutation_authorized
      compatibility_claim_authorized=[bool]$queue.compatibility_claim_authorized
      publication_authorized=[bool]$queue.publication_authorized
      queue_sha256=[string]$queue.queue_sha256
      invalid_ecosystem_message=[string]$invalidMessage
    }
    return [pscustomobject][ordered]@{record=$record;digest=(Get-MIR4CanonicalDigestV1 -Value $record -Domain 'mir4:technology-acceptance-functional-parity:1')}
  }finally{Remove-Item -LiteralPath $tempRoot -Recurse -Force}
}

function Test-MIR4TechnologyAcceptanceFunctionalParityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $result=Get-MIR4TechnologyAcceptanceFunctionalParityV1 -RepoRoot $RepoRoot
  if([string]$result.record.target-cne'F210'-or[string]$result.record.legacy_target-cne'f210'-or
     [int]$result.record.candidate_count-ne1-or(@($result.record.acceptance_states)-join'|')-cne'awaiting-quality-and-review'-or
     [bool]$result.record.mutation_authorized-or[bool]$result.record.compatibility_claim_authorized-or[bool]$result.record.publication_authorized-or
     [string]$result.record.invalid_ecosystem_message-cnotmatch'^\[mir4-acceptance-ecosystem\]'){
    throw '[mir4-technology-acceptance-functional-shape-parity]'
  }
  if([string]$result.digest-cne$script:MIR4TechnologyAcceptanceParityDigestV1){throw '[mir4-technology-acceptance-functional-parity]'}
  return $result
}

function New-MIR4TechnologyAcceptanceMigrationReceiptV1 {
  throw '[mir4-technology-acceptance-migration-receipt-immutable]'
}

function Get-MIR4TechnologyAcceptanceMigrationReceiptTextV1 {
  throw '[mir4-technology-acceptance-migration-receipt-immutable]'
}

function Test-MIR4TechnologyAcceptanceHistoricalMigrationReceiptV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return Test-MIR4ImmutableMigrationReceiptV1 -RepoRoot $RepoRoot `
    -ReceiptPath $script:MIR4TechnologyAcceptanceMigrationReceiptPath `
    -ExpectedSha256 $script:MIR4TechnologyAcceptanceMigrationReceiptSha256 `
    -SchemaPath $script:MIR4TechnologyAcceptanceMigrationReceiptSchemaPath `
    -Kind 'MIR4TechnologyAcceptanceMigrationReceiptV1' `
    -DigestDomain 'mir4:technology-acceptance-migration-receipt:1' `
    -ErrorPrefix 'mir4-technology-acceptance-migration'
}

function Invoke-MIR4TechnologyAcceptanceMigrationProjectionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  if(-not$Check){throw '[mir4-technology-acceptance-migration-receipt-immutable]'}
  return Test-MIR4TechnologyAcceptanceHistoricalMigrationReceiptV1 -RepoRoot $RepoRoot
}
