function ConvertTo-MIR4ToolingCatalogueJsonV1 {
  param([Parameter(Mandatory)]$Value)
  return $Value | ConvertTo-Json -Depth 100 -Compress
}

function Get-MIR4ToolingCatalogueDigestV1 {
  param([Parameter(Mandatory)]$Value)
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-MIR4ToolingCatalogueJsonV1 -Value $Value))
  return 'sha256:' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-MIR4TestCohortV1 {
  param([Parameter(Mandatory)][string]$Id,[Parameter(Mandatory)][AllowEmptyString()][string]$Command)
  $value = ($Id + ' ' + $Command).ToLowerInvariant()
  if ($value -match 'compat|historical|backport|museum') { return 'compatibility-historical' }
  if ($value -match 'runtime|upgrade|performance|factorio') { return 'runtime-upgrade' }
  if ($value -match 'compiler|technology|settings|balance|architecture') { return 'compiler-static' }
  if ($value -match 'release|tooling|governance|branch|docs|supply-chain|seal|publication') { return 'tooling-release' }
  return 'package-repository'
}

function Get-MIR4TestProofCatalogueV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $registryRelative = 'validation/tests.yml'
  $registry = Get-Content -Raw -LiteralPath (Join-Path $repo $registryRelative) | ConvertFrom-Json -Depth 100
  $rows = @()
  foreach ($test in @($registry.tests | Sort-Object id)) {
    $command = if ($test.PSObject.Properties['command']) { [string]$test.command } else { '' }
    if ($command -match 'validation[/\\]tests[/\\]') { throw "[mir4-test-catalogue-compatibility-command] $($test.id)" }
    $implementation = if ([string]::IsNullOrWhiteSpace($command)) { 'assurance-orchestrator' } else { (($command -split '\s+')[0] -replace '^\./','') }
    if (-not [string]::IsNullOrWhiteSpace($command) -and $implementation -notmatch '^(?:tests|scripts|tools)/') {
      throw "[mir4-test-catalogue-entrypoint] $($test.id): $implementation"
    }
    $rows += [pscustomobject][ordered]@{
      id = [string]$test.id
      proposition = "The governed test '$($test.id)' passes for its exact selected inputs."
      cohort = Get-MIR4TestCohortV1 -Id ([string]$test.id) -Command $command
      kind = [string]$test.kind
      layer = [string]$test.layer
      command = $command
      canonical_implementation = $implementation
      target_scope = if ([bool]$test.requires_factorio) { 'exact-selected-factorio-target' } else { 'portable' }
      freshness = 'exact-input-fingerprint'
      evaluator_abi = if ([string]::IsNullOrWhiteSpace($command)) { 'mir-assurance-orchestrator/v1' } else { 'powershell-exit-code/v1' }
      result_schema = 'mir-assurance-evidence/v1'
      exit_behavior = 'zero-pass-nonzero-fail'
      requires_factorio = [bool]$test.requires_factorio
      inputs = if ($test.PSObject.Properties['inputs']) { @($test.inputs | Where-Object { $null -ne $_ }) } else { @() }
      matrix = if ($test.PSObject.Properties['matrix']) { $test.matrix } else { $null }
    }
  }
  if (@($rows | Group-Object id | Where-Object Count -ne 1).Count -ne 0) { throw '[mir4-test-catalogue-duplicate-id]' }
  $cohorts = [ordered]@{}
  foreach ($name in @('package-repository','tooling-release','runtime-upgrade','compiler-static','compatibility-historical')) {
    $cohorts[$name] = @($rows | Where-Object cohort -ceq $name).Count
    if ([int]$cohorts[$name] -lt 1) { throw "[mir4-test-catalogue-empty-cohort] $name" }
  }
  $record = [ordered]@{
    schema = 1
    kind = 'MIR4TestProofCatalogueV1'
    state = 'M42-01-CANONICAL'
    registry = $registryRelative
    executable_authority_root = 'tests'
    compatibility_root = 'validation/tests'
    test_count = $rows.Count
    tests = $rows
    summary = [ordered]@{
      cohorts = $cohorts
      canonical_test_commands = @($rows | Where-Object canonical_implementation -match '^tests/').Count
      aggregate_commands = @($rows | Where-Object canonical_implementation -match '^(?:scripts|tools)/').Count
      orchestrated_runtime = @($rows | Where-Object canonical_implementation -ceq 'assurance-orchestrator').Count
      compatibility_selected = 0
      duplicate_test_ids = 0
    }
    transition_gate = [ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
    digest = ''
  }
  $material = [ordered]@{}
  foreach ($entry in $record.GetEnumerator()) { if ([string]$entry.Key -cne 'digest') { $material[$entry.Key] = $entry.Value } }
  $record.digest = Get-MIR4ToolingCatalogueDigestV1 -Value $material
  return [pscustomobject]$record
}

function Get-MIR4WorkflowPurposeCatalogueV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $purpose = @{
    'action-transport-smoke.yml'='ci';'assurance-backport.yml'='qualification';'assurance-full.yml'='qualification';
    'assurance-promotion.yml'='release';'assurance-scheduled.yml'='nightly';'assurance-targeted.yml'='qualification';
    'branch-policy.yml'='governance';'control-plane-v5.yml'='qualification';'emergency-package.yml'='release';
    'extended-compat-audit.yml'='qualification';'mir4-independent-verification.yml'='qualification';
    'mir4-preview-assets.yml'='qualification';'mir4-promotion.yml'='release';'mir4-public-readback.yml'='release';
    'mir4-release-seal.yml'='release';'mir4-restore-drill.yml'='release';'mir4-source-freeze.yml'='release';
    'mir4-target-build.yml'='release';'mir4-target-publication.yml'='release';'mir4-target-qualification.yml'='qualification';
    'release-candidate.yml'='release';'validate.yml'='ci'
  }
  $rows = @()
  $workflowRoot = Join-Path $repo '.github/workflows'
  foreach ($file in @(Get-ChildItem -LiteralPath $workflowRoot -File -Filter '*.yml' | Sort-Object Name)) {
    if (-not $purpose.ContainsKey($file.Name)) { throw "[mir4-workflow-purpose-unclassified] $($file.Name)" }
    $text = Get-Content -Raw -LiteralPath $file.FullName
    $name = [regex]::Match($text,'(?m)^name:\s*(.+)$').Groups[1].Value.Trim()
    $invocation = if ($text.Contains('./tools/mir.ps1')) { 'public-mir-cli' }
      elseif ($file.Name -ceq 'assurance-full.yml') { 'reusable-workflow' }
      elseif ($file.Name -ceq 'control-plane-v5.yml') { 'private-reusable-workflow' }
      elseif ($file.Name -ceq 'action-transport-smoke.yml') { 'github-action-contract' }
      elseif ($file.Name -ceq 'mir4-target-publication.yml') { 'confined-publisher-client' }
      elseif ($file.Name -ceq 'branch-policy.yml') { 'canonical-governance-test' }
      elseif ($file.Name -ceq 'extended-compat-audit.yml') { 'compatibility-audit-adapter' }
      else { 'unknown' }
    if ($invocation -ceq 'unknown') { throw "[mir4-workflow-invocation-unclassified] $($file.Name)" }
    $rows += [pscustomobject][ordered]@{
      file = '.github/workflows/' + $file.Name
      name = $name
      purpose = $purpose[$file.Name]
      surface = if ($file.Name -ceq 'control-plane-v5.yml') { 'private-reusable' } else { 'public' }
      invocation = $invocation
      sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
    }
  }
  if ($rows.Count -ne $purpose.Count) { throw '[mir4-workflow-purpose-missing-file]' }
  $publicPurposes = @($rows | Where-Object surface -ceq 'public' | Select-Object -ExpandProperty purpose -Unique | Sort-Object)
  if (($publicPurposes -join ',') -cne 'ci,governance,nightly,qualification,release') { throw "[mir4-workflow-public-purposes] $($publicPurposes -join ',')" }
  foreach ($required in @(@{file='validate.yml';name='MIR'},@{file='branch-policy.yml';name='Branch Policy'})) {
    $row = @($rows | Where-Object file -ceq ('.github/workflows/' + $required.file))
    if ($row.Count -ne 1 -or [string]$row[0].name -cne $required.name) { throw "[mir4-workflow-stable-check] $($required.file)" }
  }
  foreach ($phaseFile in @('mir4-independent-verification.yml','mir4-preview-assets.yml','mir4-promotion.yml','mir4-public-readback.yml','mir4-release-seal.yml','mir4-restore-drill.yml','mir4-source-freeze.yml','mir4-target-build.yml','mir4-target-qualification.yml')) {
    $text = Get-Content -Raw -LiteralPath (Join-Path $workflowRoot $phaseFile)
    if ($text -notmatch '\./tools/mir\.ps1\s+mir4\s+release-engine\s+phase' -or $text -match 'Invoke-MIR4ReleaseWorkflow') {
      throw "[mir4-workflow-release-engine-route] $phaseFile"
    }
  }
  $publisher = Get-Content -Raw -LiteralPath (Join-Path $workflowRoot 'mir4-target-publication.yml')
  if ($publisher -match 'actions/checkout@|tools/mir\.ps1.*\bbuild\b|Build-MIR') { throw '[mir4-workflow-publisher-can-build]' }
  foreach ($row in @($rows | Where-Object purpose -in @('ci','qualification','nightly'))) {
    $text = Get-Content -Raw -LiteralPath (Join-Path $repo $row.file)
    if ($text -match 'MIR_PUBLISHER|PUBLICATION_TOKEN|MOD_PORTAL_API_KEY|SIGNING_KEY') { throw "[mir4-workflow-secret-boundary] $($row.file)" }
  }
  $counts = [ordered]@{}
  foreach ($name in @('ci','qualification','release','nightly','governance')) { $counts[$name] = @($rows | Where-Object purpose -ceq $name).Count }
  $record = [ordered]@{
    schema = 1
    kind = 'MIR4WorkflowPurposeCatalogueV1'
    state = 'M42-01-CANONICAL'
    public_purposes = @('ci','qualification','release','nightly','governance')
    workflow_count = $rows.Count
    workflows = $rows
    summary = [ordered]@{purposes=$counts;unclassified=0;stable_required_checks=@('MIR','Branch Policy');publisher_can_build=$false;release_phase_public_cli_routes=9}
    transition_gate = [ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
    digest = ''
  }
  $material = [ordered]@{}
  foreach ($entry in $record.GetEnumerator()) { if ([string]$entry.Key -cne 'digest') { $material[$entry.Key] = $entry.Value } }
  $record.digest = Get-MIR4ToolingCatalogueDigestV1 -Value $material
  return [pscustomobject]$record
}

function Update-MIR4ToolingCatalogueV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][ValidateSet('tests','workflows')][string]$Catalogue,[switch]$Check)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if ($Catalogue -ceq 'tests') {
    $record = Get-MIR4TestProofCatalogueV1 -RepoRoot $repo
    $relative = 'assurance/catalog/tests.json'
    $schema = 'contracts/repository/mir4-test-proof-catalogue-v1.schema.json'
  } else {
    $record = Get-MIR4WorkflowPurposeCatalogueV1 -RepoRoot $repo
    $relative = 'governance/automation/mir4-workflow-purposes-v1.json'
    $schema = 'contracts/repository/mir4-workflow-purpose-catalogue-v1.schema.json'
  }
  $path = Join-Path $repo $relative
  $json = (($record | ConvertTo-Json -Depth 100) + [string][char]10).Replace(([string][char]13+[char]10),[string][char]10).Replace([string][char]13,[string][char]10)
  if ($Check) {
    $actual = if (Test-Path -LiteralPath $path) { (Get-Content -Raw -LiteralPath $path).Replace(([string][char]13+[char]10),[string][char]10) } else { '' }
    if ($actual -cne $json) { throw "[mir4-tooling-catalogue-stale] $relative" }
    if (-not ((Get-Content -Raw -LiteralPath $path) | Test-Json -SchemaFile (Join-Path $repo $schema))) { throw "[mir4-tooling-catalogue-schema] $relative" }
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllText($path,$json,[Text.UTF8Encoding]::new($false))
  }
  return $record
}
