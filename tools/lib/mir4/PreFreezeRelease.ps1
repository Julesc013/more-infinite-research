Set-StrictMode -Version Latest

function Get-MIR4PreFreezeRepoRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Get-MIR4PreFreezeFileSha256 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [ValidateSet('raw-bytes','canonical-text-v1')][string]$Mode='raw-bytes'
  )
  if ($Mode -ceq 'raw-bytes') {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
  }
  $utf8 = [Text.UTF8Encoding]::new($false,$true)
  $text = $utf8.GetString([IO.File]::ReadAllBytes($Path))
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
  $canonical = $text.Replace("`r`n","`n").Replace("`r","`n").Normalize([Text.NormalizationForm]::FormC)
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($canonical)))
}

function Read-MIR4PreFreezeJson {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Kind
  )
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-prefreeze-input] Missing $RelativePath" }
  $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ([string]$record.kind -cne $Kind) { throw "[mir4-prefreeze-kind] $RelativePath" }
  return $record
}

function Test-MIR4RulesetSnapshot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $relative = '.mir/releases/governance/mir4/ruleset-snapshot-2026-08-24.json'
  $path = Join-Path $repo $relative
  $schema = Join-Path $repo 'spec/schemas/mir4-ruleset-snapshot-v1.schema.json'
  $json = Get-Content -Raw -LiteralPath $path
  if (-not ($json | Test-Json -SchemaFile $schema)) { throw '[mir4-ruleset-snapshot-schema]' }
  $snapshot = $json | ConvertFrom-Json -Depth 100
  $byName = @{}
  foreach ($row in @($snapshot.rulesets)) { $byName[[string]$row.name] = $row }

  $integrity = $byName['MIR4 4.0 release branch integrity']
  $pullRequest = $byName['MIR4 4.0 release branch pull request workflow']
  $tags = $byName['MIR4 immutable source and distribution tags']
  if ($null -eq $integrity -or $null -eq $pullRequest -or $null -eq $tags) { throw '[mir4-ruleset-required-set]' }
  if ('refs/heads/release/mir4-4.0.0' -notin @($integrity.includes) -or
      @('deletion','non_fast_forward','required_status_checks' | Where-Object { $_ -notin @($integrity.rule_types) }).Count -ne 0 -or
      @('branch-policy','verification-gate' | Where-Object { $_ -notin @($integrity.required_status_checks) }).Count -ne 0 -or
      @($integrity.bypass_actors).Count -ne 0 -or [string]$integrity.current_user_can_bypass -cne 'never') {
    throw '[mir4-ruleset-integrity]'
  }
  if ('refs/heads/release/mir4-4.0.0' -notin @($pullRequest.includes) -or
      (@($pullRequest.rule_types) -join ',') -cne 'pull_request' -or
      (@($pullRequest.allowed_merge_methods) -join ',') -cne 'merge' -or
      @($pullRequest.bypass_actors | Where-Object { [string]$_.bypass_mode -cne 'pull_request' }).Count -ne 0) {
    throw '[mir4-ruleset-pull-request]'
  }
  if (@('refs/tags/v4.*','refs/tags/dist/f*/v4.*' | Where-Object { $_ -notin @($tags.includes) }).Count -ne 0 -or
      @('update','deletion' | Where-Object { $_ -notin @($tags.rule_types) }).Count -ne 0 -or
      @($tags.bypass_actors).Count -ne 0 -or [string]$tags.current_user_can_bypass -cne 'never') {
    throw '[mir4-ruleset-tags]'
  }
  foreach ($property in $snapshot.negative_assertions.PSObject.Properties) {
    if ($property.Name -eq 'tag_bypass_actor_count') {
      if ([int]$property.Value -ne 0) { throw '[mir4-ruleset-negative-assertion]' }
    } elseif (-not [bool]$property.Value) { throw "[mir4-ruleset-negative-assertion] $($property.Name)" }
  }
  return $snapshot
}

function Test-MIR4PublisherAdmissionBindings {
  param([Parameter(Mandatory)][string]$WorkflowText)
  $fields = @('source_release_record','candidate_id','source_commit','source_tree','target_distribution_record_set','release_plan_digest','proof_root','seal_root')
  foreach ($field in $fields) {
    $pattern = '\[string\]\$admission\.' + [regex]::Escape($field) + '\s*-cne\s*''\$\{\{\s*inputs\.' + [regex]::Escape($field) + '\s*\}\}'''
    if ($WorkflowText -notmatch $pattern) {
      throw "[mir4-publisher-admission-binding-missing] $field"
    }
  }
  return $true
}

function Test-MIR4ProductionActionLock {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $relative = '.mir/releases/governance/mir4/github-actions-lock.json'
  $path = Join-Path $repo $relative
  $schema = Join-Path $repo 'spec/schemas/mir4-github-actions-lock-v1.schema.json'
  $json = Get-Content -Raw -LiteralPath $path
  if (-not ($json | Test-Json -SchemaFile $schema)) { throw '[mir4-actions-lock-schema]' }
  $lock = $json | ConvertFrom-Json -Depth 100
  $pins = @{}
  foreach ($action in @($lock.actions)) { $pins[[string]$action.action] = [string]$action.commit_sha }
  foreach ($relativeWorkflow in @($lock.production_workflows)) {
    $workflow = Join-Path $repo ([string]$relativeWorkflow)
    if (-not (Test-Path -LiteralPath $workflow -PathType Leaf)) { throw "[mir4-actions-workflow-missing] $relativeWorkflow" }
    $text = Get-Content -Raw -LiteralPath $workflow
    foreach ($match in [regex]::Matches($text, 'uses:\s*(actions/[A-Za-z0-9_-]+)@([A-Za-z0-9._-]+)')) {
      $actionName = [string]$match.Groups[1].Value
      $reference = [string]$match.Groups[2].Value
      if (-not $pins.ContainsKey($actionName) -or $reference -cne $pins[$actionName]) {
        throw "[mir4-actions-unpinned] $relativeWorkflow -> $actionName@$reference"
      }
    }
  }
  $publisher = Get-Content -Raw -LiteralPath (Join-Path $repo '.github/workflows/mir4-target-publication.yml')
  if ($publisher -match 'actions/checkout|Build-MIRPackage|mir4\s+platform\s+package' -or
      $publisher -notmatch 'permissions:\s*\{contents:\s*read\}' -or
      $publisher -notmatch 'seal-verifier/Test-MIR4PublicationAdmission\.ps1' -or
      $publisher -notmatch 'publication_authorized') {
    throw '[mir4-publisher-confinement]'
  }
  Test-MIR4PublisherAdmissionBindings -WorkflowText $publisher | Out-Null
  return $lock
}

function Test-MIR4PreFreezeAuthorities {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $schemas = [ordered]@{
    '.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json' = 'spec/schemas/mir4-post-readiness-merge-receipt-sol15-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json' = 'spec/schemas/mir4-pre-freeze-development-plan-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Release-Workflow-ContractV1.json' = 'spec/schemas/mir4-release-workflow-contract-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Release-Phase-Engine-ContractV1.json' = 'spec/schemas/mir4-release-phase-engine-contract-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T02-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t02-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T03-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t03-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T04-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t04-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T05-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t05-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Release-Fault-CorpusV1.json' = 'spec/schemas/mir4-release-fault-corpus-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T06-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t06-authority-evolution-receipt-v1.schema.json'
  }
  foreach ($entry in $schemas.GetEnumerator()) {
    $json = Get-Content -Raw -LiteralPath (Join-Path $repo $entry.Key)
    if (-not ($json | Test-Json -SchemaFile (Join-Path $repo $entry.Value))) { throw "[mir4-prefreeze-schema] $($entry.Key)" }
  }
  $receipt = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json' -Kind 'MIR4PostReadinessMergeReceiptSOL15V1'
  $authorityHashes = @{}
  foreach ($binding in @($receipt.authority_bindings)) {
    $authorityHashes[[string]$binding.path] = [string]$binding.sha256
  }
  $priorReceiptPath = '.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json'
  $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  foreach ($link in @(
    @{path='.mir/releases/waves/mir4-r0/MIR4-T02-Authority-Evolution-ReceiptV1.json';kind='MIR4T02AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T03-Authority-Evolution-ReceiptV1.json';kind='MIR4T03AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T04-Authority-Evolution-ReceiptV1.json';kind='MIR4T04AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T05-Authority-Evolution-ReceiptV1.json';kind='MIR4T05AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T06-Authority-Evolution-ReceiptV1.json';kind='MIR4T06AuthorityEvolutionReceiptV1'}
  )) {
    $evolution = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $link.path -Kind $link.kind
    if ([string]$evolution.predecessor_receipt.path -cne $priorReceiptPath -or
        [string]$evolution.predecessor_receipt.sha256 -cne $priorReceiptSha256) {
      throw "[mir4-prefreeze-evolution-predecessor] $($link.path)"
    }
    $evolvedPaths = @{}
    foreach ($binding in @($evolution.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path) -or [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-evolution-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $evolvedPaths[$path] = $true
    }
    foreach ($binding in @($evolution.current_authorities)) {
      $path = [string]$binding.path
      if ($authorityHashes.ContainsKey($path) -and [string]$authorityHashes[$path] -cne [string]$binding.sha256 -and
          -not $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-current-authority-evolution-missing] $path"
      }
      $authorityHashes[$path] = [string]$binding.sha256
    }
    foreach ($property in $evolution.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-evolution-transition] $($link.path):$($property.Name)" }
    }
    $priorReceiptPath = [string]$link.path
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  foreach ($binding in $authorityHashes.GetEnumerator()) {
    $full = Join-Path $repo ([string]$binding.Key)
    $currentBinding = @($evolution.current_authorities | Where-Object { [string]$_.path -ceq [string]$binding.Key })
    $hashMode = if ($currentBinding.Count -eq 1 -and $currentBinding[0].PSObject.Properties.Name -contains 'hash_mode') { [string]$currentBinding[0].hash_mode } else { 'raw-bytes' }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf) -or
        (Get-MIR4PreFreezeFileSha256 -Path $full -Mode $hashMode) -cne [string]$binding.Value) {
      throw "[mir4-prefreeze-current-authority-binding] $($binding.Key)"
    }
  }
  $review = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-PR152-Independent-Readiness-Acceptance-LUNAV1.json' -Kind 'MIR4IndependentReadinessAcceptanceLunaV1'
  if ([string]$review.verdict -cne 'ACCEPTED-RELEASE-READINESS' -or [bool]$review.maintainer_acceptance) {
    throw '[mir4-prefreeze-independent-review]'
  }
  return $receipt
}

function New-MIR4DoctorCheck {
  param([string]$Id,[string]$Stage,[string]$Status,[string]$Detail)
  return [pscustomobject][ordered]@{id=$Id;stage=$Stage;status=$Status;detail=$Detail}
}

function Get-MIR4ReleaseWorkflowMaturity {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $contract = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Release-Workflow-ContractV1.json' -Kind 'MIR4ReleaseWorkflowContractV1'
  $rows = @($contract.phases | ForEach-Object {
    $maturity = $_.maturity
    if ([bool]$maturity.workflow_dry_run_passed -and -not [bool]$maturity.workflow_executor_implemented) {
      throw "[mir4-workflow-maturity-order] $($_.id):dry-run-without-executor"
    }
    if ([bool]$maturity.workflow_production_rehearsal_passed -and -not [bool]$maturity.workflow_dry_run_passed) {
      throw "[mir4-workflow-maturity-order] $($_.id):rehearsal-without-dry-run"
    }
    if ([bool]$maturity.workflow_production_authorized -and -not [bool]$maturity.workflow_production_rehearsal_passed) {
      throw "[mir4-workflow-maturity-order] $($_.id):authorization-without-rehearsal"
    }
    [pscustomobject][ordered]@{
      phase = [string]$_.id
      workflow_registered = [bool]$maturity.workflow_registered
      workflow_fail_closed = [bool]$maturity.workflow_fail_closed
      workflow_executor_implemented = [bool]$maturity.workflow_executor_implemented
      workflow_dry_run_passed = [bool]$maturity.workflow_dry_run_passed
      workflow_production_rehearsal_passed = [bool]$maturity.workflow_production_rehearsal_passed
      workflow_production_authorized = [bool]$maturity.workflow_production_authorized
    }
  })
  if ($rows.Count -ne 10) { throw '[mir4-workflow-maturity-count]' }
  return $rows
}

function Get-MIR4ReleaseDoctor {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Explain)
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  . (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
  . (Join-Path $repo 'tools/lib/mir4/ReleaseGovernance.ps1')
  . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
  . (Join-Path $repo 'tools/lib/mir4/AssuranceScale.ps1')
  $checks = [Collections.Generic.List[object]]::new()
  $automatedIds = [Collections.Generic.List[string]]::new()
  function Add-AutomatedCheck([string]$Id,[scriptblock]$Test,[string]$Success) {
    $automatedIds.Add($Id)
    try {
      & $Test
      $checks.Add((New-MIR4DoctorCheck $Id 'automated' 'passed' $Success))
    } catch {
      $checks.Add((New-MIR4DoctorCheck $Id 'automated' 'failed' $_.Exception.Message))
    }
  }
  Add-AutomatedCheck 'authorities' { Test-MIR4PreFreezeAuthorities -RepoRoot $repo | Out-Null } 'Append-only receipt and bound authorities are current.'
  Add-AutomatedCheck 'rulesets' { Test-MIR4RulesetSnapshot -RepoRoot $repo | Out-Null } 'Release branch and v4 tag ruleset snapshot passes positive and negative checks.'
  Add-AutomatedCheck 'actions-lock' { Test-MIR4ProductionActionLock -RepoRoot $repo | Out-Null } 'Production Actions are pinned to the governed full SHAs.'
  Add-AutomatedCheck 'platform-maturity-authority' {
    $maturityPath = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Platform-Maturity-and-Publication-ContractV2.json'
    $maturity = Get-Content -Raw -LiteralPath $maturityPath | ConvertFrom-Json -Depth 100 -DateKind String
    $expected = @('mir4-api-sdk-v1-preview.zip','mir4-mep-v1-preview.zip','mir4-reference-extension-v1-preview.zip','mir4-inspector-v1-preview.zip')
    if (-not (Test-MIR4BootstrapRecordHash -Record $maturity) -or
        (@($maturity.developer_preview_assets | Sort-Object) -join '|') -cne (@($expected | Sort-Object) -join '|') -or
        [string]$maturity.v0_policy -cne 'migration-only-no-public-v0-assets' -or [bool]$maturity.publication_authorized) {
      throw '[mir4-doctor-platform-maturity-authority]'
    }
  } 'The superseding V2 maturity authority binds exactly the four V1 preview assets.'
  Add-AutomatedCheck 'release-governance' {
    Test-MIR4ReleaseGovernanceAuthority -RepoRoot $repo | Out-Null
  } 'Tracked release governance is internally consistent and every production transition remains prohibited.'
  Add-AutomatedCheck 'release-phase-engine-kernel' {
    . (Join-Path $repo 'tools/lib/mir4/ReleasePhaseEngine.ps1')
    . (Join-Path $repo 'tools/lib/mir4/ReleaseAdapters.ps1')
    . (Join-Path $repo 'tools/lib/mir4/ReleaseLifecycleAdapters.ps1')
    $engine = Get-MIR4ReleasePhaseContract -RepoRoot $repo
    $workflow = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Release-Workflow-ContractV1.json' -Kind 'MIR4ReleaseWorkflowContractV1'
    $implemented = @($workflow.phases | Where-Object { [bool]$_.maturity.workflow_executor_implemented })
    $dryRunPassed = @($workflow.phases | Where-Object { [bool]$_.maturity.workflow_dry_run_passed })
    if ([string]$engine.record.maturity -cne 'non-production-kernel' -or [bool]$engine.record.production_capable -or
        [bool]$engine.record.production_authorized -or [bool]$engine.record.release_transition_authorized -or
        -not [bool]$workflow.phase_engine.kernel_implemented -or -not [bool]$workflow.phase_engine.event_sourcing_implemented -or
        -not [bool]$workflow.phase_engine.idempotency_and_resume_tested -or [bool]$workflow.phase_engine.production_capable -or
        [bool]$workflow.phase_engine.production_authorized -or
        (@($implemented.id | Sort-Object) -join '|') -cne 'independent-verification|preview-assets|promotion|public-readback|release-seal|restore-drill|source-freeze|target-build|target-publication|target-qualification' -or
        (@($dryRunPassed.id | Sort-Object) -join '|') -cne 'independent-verification|preview-assets|promotion|public-readback|release-seal|restore-drill|source-freeze|target-build|target-publication|target-qualification') {
      throw '[mir4-doctor-release-phase-engine-kernel]'
    }
    foreach ($phase in @('source-freeze','target-build','target-qualification','preview-assets','independent-verification','release-seal','promotion','target-publication','public-readback','restore-drill')) {
      $adapter = Get-MIR4ReleasePhaseAdapter -RepoRoot $repo -Phase $phase
      if ([bool]$adapter.descriptor.production_capable -or @($adapter.descriptor.required_ports | Where-Object { $_ -in @('sign','publish') }).Count -ne 0) {
        throw "[mir4-doctor-release-adapter-boundary] $phase"
      }
    }
  } 'The event-sourced phase kernel and all ten T03-T05 release lifecycle rehearsal adapters are implemented and dry-run tested while production signing and publication ports remain disabled.'
  Add-AutomatedCheck 'external-custody-layout' {
    $readiness = Get-MIR4ReleaseGovernanceReadiness -RepoRoot $repo
    if ([string]$readiness.classification -ceq 'CHANGES-REQUESTED' -or @($readiness.publisher.inventory.forbidden).Count -ne 0) {
      throw '[mir4-doctor-external-custody-layout]'
    }
  } 'External archive and publisher roots are complete, separated, and free of forbidden build/source capabilities.'
  Add-AutomatedCheck 'v1-default' {
    $toml = Get-Content -Raw -LiteralPath (Join-Path $repo 'mir.toml')
    if ($toml -notmatch 'reference-extension-v1/extension\.json' -or $toml -match '--extension sdk/preview/mir4/reference-extension/extension\.json') { throw '[mir4-doctor-v1-default]' }
  } 'The default compile example is V1-native.'
  Add-AutomatedCheck 'package-source' {
    $plan = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json' -Kind 'MIR4PreFreezeDevelopmentPlanV1'
    $actual = Get-MIRPackageSourceFingerprint -RepoRoot $repo
    if ($actual -cne [string]$plan.source_baseline.package_source_sha256) { throw "[mir4-doctor-package-diff] expected $($plan.source_baseline.package_source_sha256), got $actual" }
    if ([int]$plan.verification_plan.invalid -ne 0 -or [int]$plan.verification_plan.passed -ne 30) { throw '[mir4-doctor-development-plan]' }
  } 'Player-package fingerprint is unchanged and the development plan is 30/30 with zero invalid rows.'
  Add-AutomatedCheck 'target-custody' {
    $plan = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json' -Kind 'MIR4PreFreezeDevelopmentPlanV1'
    foreach ($row in @($plan.targets)) {
      $candidate = Join-Path $repo ("build/mir4/release-readiness/target-candidates/distributions/more-infinite-research_{0}.zip" -f [string]$row.distribution_version)
      $predecessor = Join-Path $repo ([string]$row.predecessor.path)
      foreach ($binding in @(
        @{path=$candidate;sha256=[string]$row.development_package.sha256},
        @{path=$predecessor;sha256=[string]$row.predecessor.sha256},
        @{path=[string]$row.engine.path;sha256=[string]$row.engine.sha256}
      )) {
        if (-not (Test-Path -LiteralPath $binding.path -PathType Leaf) -or
            (Get-MIR4PreFreezeFileSha256 $binding.path) -cne $binding.sha256) {
          throw "[mir4-doctor-target-custody] $($row.target):$($binding.path)"
        }
      }
    }
  } 'F210 and F200 development packages, direct predecessors, and exact engine binaries match the governed plan.'
  Add-AutomatedCheck 'preview-assets' {
    $manifestPath = Join-Path $repo 'build/mir4/platform-preview/preview-assets.json'
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json -Depth 100
    $expected = @('mir4-api-sdk-v1-preview.zip','mir4-mep-v1-preview.zip','mir4-reference-extension-v1-preview.zip','mir4-inspector-v1-preview.zip')
    $outputRoot = Split-Path -Parent $manifestPath
    $actualFiles = @(Get-ChildItem -LiteralPath $outputRoot -File | ForEach-Object Name | Sort-Object)
    $expectedFiles = @($expected + 'preview-assets.json' | Sort-Object)
    if ((@($manifest.assets.name | Sort-Object) -join '|') -cne (@($expected | Sort-Object) -join '|') -or
        ($actualFiles -join '|') -cne ($expectedFiles -join '|') -or
        @(Get-ChildItem -LiteralPath $outputRoot -Directory -Force).Count -ne 0) { throw '[mir4-doctor-preview-assets]' }
    foreach ($asset in @($manifest.assets)) {
      $path = Join-Path (Split-Path -Parent $manifestPath) ([string]$asset.name)
      if ((Get-MIR4PreFreezeFileSha256 $path) -ine [string]$asset.sha256) { throw "[mir4-doctor-preview-hash] $($asset.name)" }
    }
  } 'The four public V1 preview archives and deterministic asset manifest are present.'
  Add-AutomatedCheck 'offline-restore-rehearsal' {
    $path = Join-Path $repo 'build/mir4/m4c02-assurance-scale/MIR4_OFFLINE_DRILL_RESULT.json'
    $json = Get-Content -Raw -LiteralPath $path
    if (-not ($json | Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-offline-drill-result-v1.schema.json'))) {
      throw '[mir4-doctor-offline-drill-schema]'
    }
    $drill = $json | ConvertFrom-Json -Depth 100
    if ([string]$drill.record_sha256 -cne (Get-MIR4W08RecordSha256 $drill) -or
        [string]$drill.status -cne 'passed-non-production-offline-drill' -or
        -not [bool]$drill.package_construction.deterministic_repetition -or
        -not [bool]$drill.publisher.verified_before_transfer -or
        [string]$drill.publisher.uncertain_transfer_disposition -cne 'reconciled-idempotent' -or
        [bool]$drill.publication_authorized) { throw '[mir4-doctor-offline-drill]' }
  } 'The non-production offline restore, deterministic package, seal-verifier, and idempotent publisher rehearsal passes.'
  $workflowMaturity = @(Get-MIR4ReleaseWorkflowMaturity -RepoRoot $repo)
  Add-AutomatedCheck 'workflow-registration' {
    $contract = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Release-Workflow-ContractV1.json' -Kind 'MIR4ReleaseWorkflowContractV1'
    if (@($contract.phases).Count -ne 10 -or -not [bool]$contract.current_gate.fail_closed -or
        @($workflowMaturity | Where-Object { -not $_.workflow_registered -or -not $_.workflow_fail_closed }).Count -ne 0) {
      throw '[mir4-doctor-workflow-contract]'
    }
  } 'All ten MIR4 workflow phases are registered and fail closed.'
  Add-AutomatedCheck 'workflow-executor-maturity' {
    $pending = @($workflowMaturity | Where-Object {
      -not $_.workflow_executor_implemented -or
      -not $_.workflow_dry_run_passed -or
      -not $_.workflow_production_rehearsal_passed
    })
    if ($pending.Count -ne 0) {
      throw ("[mir4-doctor-workflow-executor-maturity] {0}" -f (@($pending.phase) -join ','))
    }
  } 'All ten phase executors are implemented, dry-run passed, and production rehearsed.'

  $governance = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/governance/mir4/release-governance.json' -Kind 'MIR4ReleaseGovernanceV1'
  $checks.Add((New-MIR4DoctorCheck 'protected-signing-secret' 'human' 'blocked' ([string]$governance.state)))
  $plan = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json' -Kind 'MIR4PreFreezeDevelopmentPlanV1'
  $acceptedTargets = @{}
  foreach ($decisionFile in @(Get-ChildItem -LiteralPath (Join-Path $repo 'build/mir4/playtests') -Recurse -Filter 'manual-decision.json' -File -ErrorAction SilentlyContinue)) {
    try {
      $root = Split-Path -Parent $decisionFile.FullName
      $decision = Get-Content -Raw -LiteralPath $decisionFile.FullName | ConvertFrom-Json -Depth 100
      $sessionPath = Join-Path $root 'session.json'
      $capturePath = Join-Path $root 'capture.json'
      $session = Get-Content -Raw -LiteralPath $sessionPath | ConvertFrom-Json -Depth 100
      $capture = Get-Content -Raw -LiteralPath $capturePath | ConvertFrom-Json -Depth 100
      $targetRow = @($plan.targets | Where-Object { [string]$_.target -ceq [string]$session.target })
      if ($targetRow.Count -ne 1 -or [string]$decision.decision -cne 'ACCEPTED' -or [bool]$decision.decision_inferred -or
          [bool]$decision.production_release_authorized -or [string]$decision.target -cne [string]$session.target -or
          [string]$decision.candidate_sha256 -cne [string]$targetRow[0].development_package.sha256 -or
          [string]$decision.engine_sha256 -cne [string]$targetRow[0].engine.sha256 -or
          [string]$capture.candidate_sha256 -cne [string]$decision.candidate_sha256 -or
          [string]$capture.engine_sha256 -cne [string]$decision.engine_sha256 -or
          (Get-MIR4PreFreezeFileSha256 $capturePath) -cne [string]$decision.capture_sha256) { continue }
      $evidenceCurrent = $true
      foreach ($evidence in @($capture.files)) {
        if (-not (Test-Path -LiteralPath ([string]$evidence.path) -PathType Leaf) -or
            (Get-MIR4PreFreezeFileSha256 ([string]$evidence.path)) -cne [string]$evidence.sha256) { $evidenceCurrent = $false; break }
      }
      if ($evidenceCurrent) { $acceptedTargets[[string]$session.target] = $true }
    } catch {}
  }
  $playtestComplete = @('F210','F200' | Where-Object { -not $acceptedTargets.ContainsKey($_) }).Count -eq 0
  $playtestStatus = if ($playtestComplete) { 'passed' } else { 'blocked' }
  $playtestDetail = if ($playtestComplete) { 'Explicit, current maintainer ACCEPTED receipts exist for F210 and F200.' } else { 'Current explicit maintainer ACCEPTED receipts are required for both F210 and F200; the command never infers either decision.' }
  $checks.Add((New-MIR4DoctorCheck 'maintainer-manual-playtest' 'human' $playtestStatus $playtestDetail))
  $automatedFailed = @($checks | Where-Object { $_.stage -eq 'automated' -and $_.status -ne 'passed' }).Count
  $humanBlocked = @($checks | Where-Object { $_.stage -eq 'human' -and $_.status -ne 'passed' }).Count
  return [pscustomobject][ordered]@{
    schema=1
    kind='MIR4ReleaseDoctorResultV1'
    source_version='4.0.0'
    candidate_state='pre-freeze-unallocated'
    prefreeze_status=$(if($automatedFailed -eq 0){'ready'}else{'not-ready'})
    release_status=$(if($automatedFailed -eq 0 -and $humanBlocked -eq 0){'ready-for-source-freeze-authorization'}else{'blocked'})
    checks=@($checks)
    workflow_maturity=$workflowMaturity
    counts=[ordered]@{automated_total=$automatedIds.Count;automated_failed=$automatedFailed;human_blocked=$humanBlocked}
    explanation=$(if($Explain){'Automated pre-freeze controls can become ready while protected signing input and maintainer playtest remain separate human gates.'}else{$null})
    source_freeze_authorized=$false
    candidate_allocation_authorized=$false
    publication_authorized=$false
  }
}

function Test-MIR4ReleaseWorkflowInvocation {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('source-freeze','target-build','target-qualification','preview-assets','independent-verification','release-seal','promotion','target-publication','public-readback','restore-drill')][string]$Phase,
    [Parameter(Mandatory)][string]$SourceReleaseRecord,
    [Parameter(Mandatory)][string]$CandidateId,
    [Parameter(Mandatory)][string]$SourceCommit,
    [Parameter(Mandatory)][string]$SourceTree,
    [Parameter(Mandatory)][string]$TargetDistributionRecordSet,
    [Parameter(Mandatory)][string]$ReleasePlanDigest,
    [Parameter(Mandatory)][string]$ProofRoot,
    [Parameter(Mandatory)][string]$SealRoot,
    [switch]$NonProductionRehearsal
  )
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$' -or $SourceTree -cnotmatch '^[0-9a-f]{40}$' -or $ReleasePlanDigest -cnotmatch '^[A-F0-9]{64}$') {
    throw '[mir4-release-workflow-identity]'
  }
  $actualCommit = (& git -C $repo rev-parse HEAD).Trim()
  $actualTree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  if ($actualCommit -cne $SourceCommit -or $actualTree -cne $SourceTree) {
    throw "[mir4-release-workflow-checkout] expected $SourceCommit/$SourceTree, got $actualCommit/$actualTree"
  }
  foreach ($relative in @($SourceReleaseRecord,$TargetDistributionRecordSet)) {
    $full = if ([IO.Path]::IsPathRooted($relative)) { $relative } else { Join-Path $repo $relative }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-release-workflow-record] $relative" }
    Get-Content -Raw -LiteralPath $full | ConvertFrom-Json -Depth 100 | Out-Null
  }
  $contract = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Release-Workflow-ContractV1.json' -Kind 'MIR4ReleaseWorkflowContractV1'
  $phaseRecord = @($contract.phases | Where-Object { [string]$_.id -ceq $Phase })
  if ($phaseRecord.Count -ne 1) { throw '[mir4-release-workflow-phase]' }
  $governance = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/governance/mir4/release-governance.json' -Kind 'MIR4ReleaseGovernanceV1'
  $requiresFreeze = $Phase -in @('source-freeze','target-build','target-qualification','release-seal','promotion','target-publication','public-readback')
  if ($requiresFreeze -and (-not $NonProductionRehearsal -or [string]$CandidateId -ceq 'M4RC1')) {
    throw "[mir4-release-transition-blocked] $Phase"
  }
  return [pscustomobject][ordered]@{
    schema=1;kind='MIR4ReleaseWorkflowInvocationV1';phase=$Phase;candidate_id=$CandidateId
    source_commit=$SourceCommit;source_tree=$SourceTree;release_plan_digest=$ReleasePlanDigest
    proof_root=$ProofRoot;seal_root=$SealRoot
    status=$(if($NonProductionRehearsal){'validated-non-production-rehearsal'}else{'validated'})
    mutation_performed=$false;production_authorized=$false
  }
}

function Get-MIR4PlaytestFileDescriptor {
  param([Parameter(Mandatory)][string]$Path)
  $item = Get-Item -LiteralPath $Path
  return [ordered]@{path=$item.FullName;bytes=$item.Length;sha256=(Get-MIR4PreFreezeFileSha256 $item.FullName)}
}

function New-MIR4PlaytestSession {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidateSet('F210','F200')][string]$Target,
    [string]$CandidatePath = '',
    [string]$PredecessorPath = '',
    [string]$FactorioBin = '',
    [string]$SettingsPath = '',
    [string]$SavePath = '',
    [string]$OutputRoot = '',
    [switch]$DryRun
  )
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $plan = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json' -Kind 'MIR4PreFreezeDevelopmentPlanV1'
  $targetRow = @($plan.targets | Where-Object { [string]$_.target -ceq $Target })
  if ($targetRow.Count -ne 1) { throw "[mir4-playtest-target] $Target" }
  $row = $targetRow[0]
  if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
    $CandidatePath = Join-Path $repo ("build/mir4/release-readiness/target-candidates/distributions/more-infinite-research_{0}.zip" -f [string]$row.distribution_version)
  }
  if ([string]::IsNullOrWhiteSpace($PredecessorPath)) { $PredecessorPath = Join-Path $repo ([string]$row.predecessor.path) }
  if ([string]::IsNullOrWhiteSpace($FactorioBin)) {
    $FactorioBin = if ($Target -ceq 'F210') {
      'C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe'
    } else {
      'D:\Programs\Factorio\2.0\bin\x64\factorio.exe'
    }
  }
  foreach ($required in @($CandidatePath,$PredecessorPath,$FactorioBin)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "[mir4-playtest-input] $required" }
  }
  $candidate = Get-MIR4PlaytestFileDescriptor $CandidatePath
  $predecessor = Get-MIR4PlaytestFileDescriptor $PredecessorPath
  $engine = Get-MIR4PlaytestFileDescriptor $FactorioBin
  if ([string]$candidate.sha256 -cne [string]$row.development_package.sha256) { throw '[mir4-playtest-candidate-hash]' }
  if ([string]$predecessor.sha256 -cne [string]$row.predecessor.sha256) { throw '[mir4-playtest-predecessor-hash]' }
  if ([string]$engine.sha256 -cne [string]$row.engine.sha256) { throw '[mir4-playtest-engine-hash]' }
  foreach ($optional in @($SettingsPath,$SavePath)) {
    if (-not [string]::IsNullOrWhiteSpace($optional) -and -not (Test-Path -LiteralPath $optional -PathType Leaf)) {
      throw "[mir4-playtest-optional-input] $optional"
    }
  }
  if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repo ("build/mir4/playtests/{0}/session-{1}" -f $Target.ToLowerInvariant(),[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
  }
  $output = [IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($OutputRoot)){$OutputRoot}else{Join-Path $repo $OutputRoot}))
  $allowed = [IO.Path]::GetFullPath((Join-Path $repo 'build/mir4/playtests')).TrimEnd('\') + '\'
  if (-not ($output + '\').StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw "[mir4-playtest-output-boundary] $output" }
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4PlaytestSessionV1';status=$(if($DryRun){'planned'}else{'prepared'})
    target=$Target;distribution_version=[string]$row.distribution_version;candidate_state='development-pre-freeze-not-release-identity'
    created_at=[DateTime]::UtcNow.ToString('o');session_root=$output
    engine=$engine;candidate=$candidate;predecessor=$predecessor
    settings=$(if([string]::IsNullOrWhiteSpace($SettingsPath)){$null}else{Get-MIR4PlaytestFileDescriptor $SettingsPath})
    save_fixture=$(if([string]::IsNullOrWhiteSpace($SavePath)){$null}else{Get-MIR4PlaytestFileDescriptor $SavePath})
    checklist=@('fresh-load','upgrade-from-predecessor','second-reload','research-queue-and-fractional-progress','state-and-settings-preservation','technology-and-research-state','performance-observations','maintainer-notes')
    decision=$null;decision_inferred=$false;package_visible=$false;production_release_authorized=$false
  }
  if ($DryRun) { return $record }
  if (Test-Path -LiteralPath $output) { throw "[mir4-playtest-session-exists] $output" }
  $mods = Join-Path $output 'profile/mods'
  New-Item -ItemType Directory -Path $mods -Force | Out-Null
  Copy-Item -LiteralPath $CandidatePath -Destination (Join-Path $mods ([IO.Path]::GetFileName($CandidatePath)))
  Copy-Item -LiteralPath $PredecessorPath -Destination (Join-Path $mods ([IO.Path]::GetFileName($PredecessorPath)))
  if (-not [string]::IsNullOrWhiteSpace($SettingsPath)) {
    Copy-Item -LiteralPath $SettingsPath -Destination (Join-Path $output ('profile/' + [IO.Path]::GetFileName($SettingsPath)))
  }
  if (-not [string]::IsNullOrWhiteSpace($SavePath)) {
    New-Item -ItemType Directory -Path (Join-Path $output 'profile/saves') -Force | Out-Null
    Copy-Item -LiteralPath $SavePath -Destination (Join-Path $output ('profile/saves/' + [IO.Path]::GetFileName($SavePath)))
  }
  $record.candidate.path = Join-Path $mods ([IO.Path]::GetFileName($CandidatePath))
  $record.predecessor.path = Join-Path $mods ([IO.Path]::GetFileName($PredecessorPath))
  $newline = [Environment]::NewLine
  [IO.File]::WriteAllText((Join-Path $output 'session.json'),($record|ConvertTo-Json -Depth 30)+$newline,[Text.UTF8Encoding]::new($false))
  $checklist = "# MIR 4 $Target manual playtest" + $newline + $newline +
    "Candidate and predecessor identities are locked in session.json. Record observations; do not infer acceptance." + $newline + $newline +
    ((@($record.checklist) | ForEach-Object { "- [ ] $_" }) -join $newline) + $newline
  [IO.File]::WriteAllText((Join-Path $output 'review-checklist.md'),$checklist,[Text.UTF8Encoding]::new($false))
  return $record
}

function Capture-MIR4PlaytestSession {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SessionRoot,
    [string[]]$CapturePath = @(),
    [string]$ObservationsPath = '',
    [switch]$DryRun
  )
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $sessionRootFull = [IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($SessionRoot)){$SessionRoot}else{Join-Path $repo $SessionRoot}))
  $sessionPath = Join-Path $sessionRootFull 'session.json'
  $session = Get-Content -Raw -LiteralPath $sessionPath | ConvertFrom-Json -Depth 100
  if ([string]$session.kind -cne 'MIR4PlaytestSessionV1') { throw '[mir4-playtest-session-kind]' }
  foreach ($locked in @($session.candidate,$session.predecessor)) {
    if (-not (Test-Path -LiteralPath ([string]$locked.path) -PathType Leaf) -or
        (Get-MIR4PreFreezeFileSha256 ([string]$locked.path)) -cne [string]$locked.sha256) {
      throw "[mir4-playtest-locked-input] $($locked.path)"
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($ObservationsPath)) { $CapturePath += $ObservationsPath }
  $paths = @($CapturePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
  if ($paths.Count -eq 0) {
    $defaultLog = Join-Path $sessionRootFull 'profile/factorio-current.log'
    if (Test-Path -LiteralPath $defaultLog -PathType Leaf) { $paths = @($defaultLog) }
  }
  if ($paths.Count -eq 0) { throw '[mir4-playtest-capture-empty] Supply --capture paths or place factorio-current.log in the isolated profile.' }
  foreach ($path in $paths) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-playtest-capture-input] $path" } }
  $receipt = [pscustomobject][ordered]@{
    schema=1;kind='MIR4PlaytestCaptureV1';status=$(if($DryRun){'planned'}else{'captured'})
    target=[string]$session.target;captured_at=[DateTime]::UtcNow.ToString('o')
    candidate_sha256=[string]$session.candidate.sha256;engine_sha256=[string]$session.engine.sha256
    files=@($paths | ForEach-Object { Get-MIR4PlaytestFileDescriptor $_ })
    observations_supplied=(-not [string]::IsNullOrWhiteSpace($ObservationsPath))
    decision=$null;decision_inferred=$false;package_visible=$false
  }
  if ($DryRun) { return $receipt }
  $captureRoot = Join-Path $sessionRootFull 'capture'
  if (Test-Path -LiteralPath (Join-Path $sessionRootFull 'capture.json')) { throw '[mir4-playtest-capture-exists]' }
  New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null
  $usedNames = @{}
  foreach ($path in $paths) {
    $name = [IO.Path]::GetFileName($path)
    if ($usedNames.ContainsKey($name)) { throw "[mir4-playtest-capture-name-collision] $name" }
    $usedNames[$name] = $true
    Copy-Item -LiteralPath $path -Destination (Join-Path $captureRoot $name)
  }
  $receipt.files = @($paths | ForEach-Object { Get-MIR4PlaytestFileDescriptor (Join-Path $captureRoot ([IO.Path]::GetFileName($_))) })
  [IO.File]::WriteAllText((Join-Path $sessionRootFull 'capture.json'),($receipt|ConvertTo-Json -Depth 30)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
  return $receipt
}

function Complete-MIR4PlaytestSession {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SessionRoot,
    [Parameter(Mandatory)][ValidateSet('ACCEPTED','CHANGES-REQUESTED','REJECTED')][string]$Decision,
    [Parameter(Mandatory)][string]$Reviewer,
    [string]$Notes = '',
    [switch]$DryRun
  )
  if ([string]::IsNullOrWhiteSpace($Reviewer)) { throw '[mir4-playtest-reviewer-required]' }
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $root = [IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($SessionRoot)){$SessionRoot}else{Join-Path $repo $SessionRoot}))
  $session = Get-Content -Raw -LiteralPath (Join-Path $root 'session.json') | ConvertFrom-Json -Depth 100
  $capturePath = Join-Path $root 'capture.json'
  if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) { throw '[mir4-playtest-finalize-without-capture]' }
  $capture = Get-Content -Raw -LiteralPath $capturePath | ConvertFrom-Json -Depth 100
  if ([string]$capture.candidate_sha256 -cne [string]$session.candidate.sha256) { throw '[mir4-playtest-finalize-candidate]' }
  if ([string]$capture.engine_sha256 -cne [string]$session.engine.sha256) { throw '[mir4-playtest-finalize-engine]' }
  foreach ($evidence in @($capture.files)) {
    if (-not (Test-Path -LiteralPath ([string]$evidence.path) -PathType Leaf) -or
        (Get-MIR4PreFreezeFileSha256 ([string]$evidence.path)) -cne [string]$evidence.sha256) {
      throw "[mir4-playtest-finalize-evidence] $($evidence.path)"
    }
  }
  $receipt = [pscustomobject][ordered]@{
    schema=1;kind='MIR4ManualPlaytestDecisionV1';status=$(if($DryRun){'planned'}else{'final'})
    target=[string]$session.target;candidate_sha256=[string]$session.candidate.sha256
    engine_sha256=[string]$session.engine.sha256;capture_sha256=(Get-MIR4PreFreezeFileSha256 $capturePath)
    reviewer=$Reviewer;decision=$Decision;notes=$Notes;decided_at=[DateTime]::UtcNow.ToString('o')
    decision_inferred=$false;source_freeze_authorized=$false;production_release_authorized=$false
  }
  if ($DryRun) { return $receipt }
  $output = Join-Path $root 'manual-decision.json'
  if (Test-Path -LiteralPath $output) { throw '[mir4-playtest-decision-exists]' }
  [IO.File]::WriteAllText($output,($receipt|ConvertTo-Json -Depth 30)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
  return $receipt
}
