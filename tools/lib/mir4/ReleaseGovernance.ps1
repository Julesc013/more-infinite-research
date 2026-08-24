$script:MIR4ArchiveEnvironmentVariable = 'MIR_ARCHIVE_HOME'
$script:MIR4PublisherEnvironmentVariable = 'MIR_PUBLISHER_HOME'
$script:MIR4ArchiveSubroots = @(
  'source-bundles',
  'target-packages',
  'release-capsules',
  'proof-objects',
  'publication-receipts',
  'recovery-material',
  'predecessor-custody',
  'rights-custody-metadata'
)
$script:MIR4PublisherSubroots = @(
  'sealed-packages',
  'public-release-records',
  'public-signing-material',
  'seal-verifier',
  'publication-clients',
  'credential-authority'
)
$script:MIR4PublisherForbiddenNames = @(
  '.git',
  'src',
  'source',
  'compiler',
  'package-builder',
  'package-materializer',
  'staging',
  'private-key',
  'id_ed25519'
)

function Resolve-MIR4GovernanceRoot {
  param(
    [AllowEmptyString()][string]$Path,
    [Parameter(Mandatory)][string]$EnvironmentVariable,
    [Parameter(Mandatory)][string]$LocalProfileDefault,
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Code
  )
  $environmentValue = [Environment]::GetEnvironmentVariable($EnvironmentVariable)
  $source = 'explicit-parameter'
  $candidate = $Path
  if ([string]::IsNullOrWhiteSpace($candidate)) {
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
      $candidate = $environmentValue
      $source = "environment:$EnvironmentVariable"
    } else {
      $candidate = $LocalProfileDefault
      $source = 'local-profile-default'
    }
  }
  if ([string]::IsNullOrWhiteSpace($candidate) -or -not [IO.Path]::IsPathRooted($candidate)) {
    throw "[$Code] A resolved absolute external root is required."
  }
  $actual = [IO.Path]::GetFullPath($candidate).TrimEnd('\')
  $repo = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
  if ($actual.Equals($repo, [StringComparison]::OrdinalIgnoreCase) -or
      $actual.StartsWith($repo + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "[$Code] External release custody must remain outside the repository: $actual"
  }
  return [pscustomobject][ordered]@{ path=$actual; source=$source; environment_variable=$EnvironmentVariable }
}

function Test-MIR4ReleaseGovernanceAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $authorityPath = Join-Path $repo '.mir/releases/governance/mir4/release-governance.json'
  $signersPath = Join-Path $repo '.mir/releases/governance/mir4/allowed-signers.json'
  foreach ($path in @($authorityPath, $signersPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "[mir4-governance-authority-missing] $path"
    }
  }
  $authority = Get-Content -Raw -LiteralPath $authorityPath | ConvertFrom-Json
  $signers = Get-Content -Raw -LiteralPath $signersPath | ConvertFrom-Json
  if ([int]$authority.schema -ne 1 -or [string]$authority.kind -cne 'MIR4ReleaseGovernanceV1') {
    throw '[mir4-governance-schema] Release governance authority is not V1.'
  }
  if ([string]$authority.programme_id -cne 'M4C02-09-24H') {
    throw '[mir4-governance-programme] Release governance programme changed.'
  }
  if ([bool]$authority.secret_values_present -or [bool]$signers.secret_values_present) {
    throw '[mir4-governance-secret-recorded] Tracked governance records claim secret material.'
  }
  if ([string]$authority.signing_authority.algorithm -cne 'ssh-ed25519' -or
      -not [bool]$authority.signing_authority.dedicated -or
      [bool]$authority.signing_authority.reused) {
    throw '[mir4-governance-signing-authority] Signing separation changed.'
  }
  $requiredNamespaces = @('mir4-source', 'mir4-target', 'mir4-ledger')
  if ((@($authority.signing_authority.namespaces | Sort-Object) -join '|') -cne (@($requiredNamespaces | Sort-Object) -join '|')) {
    throw '[mir4-governance-namespaces] Signing namespaces changed.'
  }
  if ((@($authority.archive.subroots | Sort-Object) -join '|') -cne (@($script:MIR4ArchiveSubroots | Sort-Object) -join '|')) {
    throw '[mir4-governance-archive-roots] Governed archive roots changed.'
  }
  if ([string]$authority.archive.environment_variable -cne $script:MIR4ArchiveEnvironmentVariable -or
      [string]$authority.publisher.environment_variable -cne $script:MIR4PublisherEnvironmentVariable) {
    throw '[mir4-governance-logical-root] Archive or publisher logical root changed.'
  }
  foreach ($row in @($authority.archive, $authority.publisher)) {
    if (-not [IO.Path]::IsPathRooted([string]$row.local_profile_default)) {
      throw '[mir4-governance-local-profile-default] Local profile defaults must be absolute.'
    }
  }
  foreach ($transition in @('source_freeze','candidate_allocation','production_signing','production_seal','promotion_to_main','tagging','publication')) {
    if (-not [bool]$authority.prohibited_transitions.$transition) {
      throw "[mir4-governance-prohibited-transition] $transition"
    }
  }
  if ([string]$authority.state -eq 'BLOCKED-HUMAN-SECRET-INPUT') {
    if (@($signers.rows).Count -ne 0 -or $null -ne $authority.signing_authority.public_key -or $null -ne $authority.signing_authority.fingerprint) {
      throw '[mir4-governance-blocked-key-state] Blocked authority contains signer material.'
    }
  } elseif ([string]$authority.state -eq 'RELEASE-GOVERNANCE-READY') {
    if (@($signers.rows).Count -lt 3) { throw '[mir4-governance-signers-incomplete]' }
  } else {
    throw '[mir4-governance-state] Unknown governance state.'
  }
  return $authority
}

function Test-MIR4PublisherInventory {
  param([Parameter(Mandatory)][string]$PublisherHome)
  if (-not (Test-Path -LiteralPath $PublisherHome -PathType Container)) {
    return [pscustomobject][ordered]@{ exists=$false; forbidden=@(); files=0; directories=0 }
  }
  $items = @(Get-ChildItem -LiteralPath $PublisherHome -Force -Recurse -ErrorAction Stop)
  $forbidden = @(
    foreach ($item in $items) {
      $name = [string]$item.Name
      $relative = [IO.Path]::GetRelativePath($PublisherHome, $item.FullName).Replace('\','/')
      if ($name -in $script:MIR4PublisherForbiddenNames -or
          $name -match '(?i)(private[_-]?key|id_ed25519|package[_-]?builder|materializer)' -or
          $relative -match '(?i)(^|/)(prototypes|migrations|scripts|tools/lib/mir4)(/|$)') {
        $relative
      }
    }
  )
  return [pscustomobject][ordered]@{
    exists=$true
    forbidden=@($forbidden | Sort-Object -Unique)
    files=@($items | Where-Object { -not $_.PSIsContainer }).Count
    directories=@($items | Where-Object { $_.PSIsContainer }).Count
  }
}

function Initialize-MIR4ReleaseGovernanceLayout {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [AllowEmptyString()][string]$ArchiveHome='',
    [AllowEmptyString()][string]$PublisherHome=''
  )
  $authority = Test-MIR4ReleaseGovernanceAuthority -RepoRoot $RepoRoot
  $archiveResolution = Resolve-MIR4GovernanceRoot -Path $ArchiveHome -EnvironmentVariable ([string]$authority.archive.environment_variable) -LocalProfileDefault ([string]$authority.archive.local_profile_default) -RepoRoot $RepoRoot -Code 'mir4-governance-archive-path'
  $publisherResolution = Resolve-MIR4GovernanceRoot -Path $PublisherHome -EnvironmentVariable ([string]$authority.publisher.environment_variable) -LocalProfileDefault ([string]$authority.publisher.local_profile_default) -RepoRoot $RepoRoot -Code 'mir4-governance-publisher-path'
  $archive = $archiveResolution.path
  $publisher = $publisherResolution.path
  if ($archive.Equals($publisher, [StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-governance-root-separation]' }
  foreach ($path in @($archive, $publisher)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
  foreach ($name in $script:MIR4ArchiveSubroots) { New-Item -ItemType Directory -Force -Path (Join-Path $archive $name) | Out-Null }
  foreach ($name in $script:MIR4PublisherSubroots) { New-Item -ItemType Directory -Force -Path (Join-Path $publisher $name) | Out-Null }
  $marker = [ordered]@{
    schema=1
    kind='MIR4ExternalGovernanceLayoutV1'
    programme_id=[string]$authority.programme_id
    state=[string]$authority.state
    signing_material_present=$false
    credentials_present=$false
    source_freeze_authorized=$false
    publication_authorized=$false
  }
  $json = ($marker | ConvertTo-Json -Depth 10) + "`n"
  [IO.File]::WriteAllText((Join-Path $archive 'rights-custody-metadata\mir4-governance-layout.json'), $json, [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $publisher 'public-release-records\mir4-governance-layout.json'), $json, [Text.UTF8Encoding]::new($false))
  return Get-MIR4ReleaseGovernanceReadiness -RepoRoot $RepoRoot -ArchiveHome $archive -PublisherHome $publisher
}

function Get-MIR4ReleaseGovernanceReadiness {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [AllowEmptyString()][string]$ArchiveHome='',
    [AllowEmptyString()][string]$PublisherHome=''
  )
  $authority = Test-MIR4ReleaseGovernanceAuthority -RepoRoot $RepoRoot
  $archiveResolution = Resolve-MIR4GovernanceRoot -Path $ArchiveHome -EnvironmentVariable ([string]$authority.archive.environment_variable) -LocalProfileDefault ([string]$authority.archive.local_profile_default) -RepoRoot $RepoRoot -Code 'mir4-governance-archive-path'
  $publisherResolution = Resolve-MIR4GovernanceRoot -Path $PublisherHome -EnvironmentVariable ([string]$authority.publisher.environment_variable) -LocalProfileDefault ([string]$authority.publisher.local_profile_default) -RepoRoot $RepoRoot -Code 'mir4-governance-publisher-path'
  $archive = $archiveResolution.path
  $publisher = $publisherResolution.path
  if ($archive.Equals($publisher, [StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-governance-root-separation]' }
  $archiveRows = @(
    foreach ($name in $script:MIR4ArchiveSubroots) {
      [ordered]@{ name=$name; exists=(Test-Path -LiteralPath (Join-Path $archive $name) -PathType Container) }
    }
  )
  $publisherRows = @(
    foreach ($name in $script:MIR4PublisherSubroots) {
      [ordered]@{ name=$name; exists=(Test-Path -LiteralPath (Join-Path $publisher $name) -PathType Container) }
    }
  )
  $inventory = Test-MIR4PublisherInventory -PublisherHome $publisher
  $layoutReady = @($archiveRows | Where-Object { -not $_.exists }).Count -eq 0 -and
    @($publisherRows | Where-Object { -not $_.exists }).Count -eq 0 -and
    @($inventory.forbidden).Count -eq 0
  $classification = if (-not $layoutReady) { 'CHANGES-REQUESTED' } elseif ([string]$authority.state -eq 'BLOCKED-HUMAN-SECRET-INPUT') { 'BLOCKED-HUMAN-SECRET-INPUT' } else { 'ACCEPTED-RELEASE-GOVERNANCE' }
  return [pscustomobject][ordered]@{
    schema=1
    kind='MIR4ReleaseGovernanceReadinessV1'
    programme_id=[string]$authority.programme_id
    classification=$classification
    authority_state=[string]$authority.state
    archive=[ordered]@{home=$archive;resolution_source=$archiveResolution.source;environment_variable=$archiveResolution.environment_variable;roots=$archiveRows}
    publisher=[ordered]@{home=$publisher;resolution_source=$publisherResolution.source;environment_variable=$publisherResolution.environment_variable;roots=$publisherRows;inventory=$inventory}
    ledger=[ordered]@{branch=[string]$authority.ledger.branch;state=[string]$authority.ledger.status}
    protected_secret_input_available=([string]$authority.state -ne 'BLOCKED-HUMAN-SECRET-INPUT')
    source_freeze_authorized=$false
    candidate_allocation_authorized=$false
    production_signing_authorized=$false
    publication_authorized=$false
  }
}
