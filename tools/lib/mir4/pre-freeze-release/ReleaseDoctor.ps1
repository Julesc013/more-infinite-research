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
  if (-not (Get-Command Get-MIRPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
    . (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
  }
  . (Join-Path $repo 'tools/lib/mir4/ReleaseGovernance.ps1')
  . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
  . (Join-Path $repo 'tools/mir/application/assurance/AssuranceScale.ps1')
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
  Add-AutomatedCheck 'f210-qualification-policy' {
    $policy = Get-MIR4F210QualificationPolicyV1 -RepoRoot $repo
    if ([string]$policy.support_floor -cne '2.1.8' -or
        [string]$policy.pre_freeze.selection -cne 'highest-official-experimental-installed-on-single-authorized-steam-path-at-execution-time' -or
        [string]$policy.post_stable.minimum_lane.version -cne '2.1.8' -or
        [string]$policy.post_stable.latest_lane.selection -cne 'latest-official-stable-2.1.x' -or
        @($policy.boundaries.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
      throw '[mir4-doctor-f210-qualification-policy]'
    }
  } 'F210 uses the installed official Steam experimental before freeze, exact freeze locks, and stable minimum/latest lanes after the 2.1 stable transition.'
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
    $t13 = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-T13-Authority-Evolution-ReceiptV1.json' -Kind 'MIR4T13AuthorityEvolutionReceiptV1'
    $t15 = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json' -Kind 'MIR4T15AuthorityEvolutionReceiptV1'
    $actual = Get-MIRPackageSourceFingerprint -RepoRoot $repo
    if ([string]$plan.source_baseline.package_source_sha256 -cne [string]$t13.player_package_source_sha256 -or
        $actual -cne [string]$t15.player_package_source_sha256) {
      throw "[mir4-doctor-package-diff] expected current $($t15.player_package_source_sha256), got $actual"
    }
    if ([int]$plan.verification_plan.invalid -ne 0 -or [int]$plan.verification_plan.passed -ne 30) { throw '[mir4-doctor-development-plan]' }
  } 'Player-package fingerprint is unchanged and the development plan is 30/30 with zero invalid rows.'
  Add-AutomatedCheck 'target-custody' {
    $plan = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json' -Kind 'MIR4PreFreezeDevelopmentPlanV1'
    foreach ($row in @($plan.targets)) {
      $candidate = Join-Path $repo ("build/mir4/release-readiness/target-candidates/distributions/more-infinite-research_{0}.zip" -f [string]$row.distribution_version)
      $predecessor = Join-Path $repo ([string]$row.predecessor.path)
      $bindings = @(
        @{path=$candidate;sha256=[string]$row.development_package.sha256},
        @{path=$predecessor;sha256=[string]$row.predecessor.sha256}
      )
      if ([string]$row.target -ceq 'F210') {
        $resolution = Get-MIR4F210EngineResolutionV1 -RepoRoot $repo
        $bindings += @{path=[string]$resolution.engine.path;sha256=[string]$resolution.engine.sha256}
      } else {
        $bindings += @{path=[string]$row.engine.path;sha256=[string]$row.engine.sha256}
      }
      foreach ($binding in $bindings) {
        if (-not (Test-Path -LiteralPath $binding.path -PathType Leaf) -or
            (Get-MIR4PreFreezeFileSha256 $binding.path) -cne $binding.sha256) {
          throw "[mir4-doctor-target-custody] $($row.target):$($binding.path)"
        }
      }
    }
  } 'F210 and F200 development packages and predecessors are exact; F210 resolves the current authorized Steam experimental and F200 remains bound to its governed exact engine.'
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
  $plan = Get-MIR4FinalMilePlaytestCandidateAuthorityV1 -RepoRoot $repo
  $currentF210Resolution = try { Get-MIR4F210EngineResolutionV1 -RepoRoot $repo } catch { $null }
  $acceptedTargets = @{}
  foreach ($decisionFile in @(Get-ChildItem -LiteralPath (Join-Path $repo 'build/mir4/playtests') -Recurse -Filter 'manual-decision.json' -File -ErrorAction SilentlyContinue)) {
    try {
      $root = Split-Path -Parent $decisionFile.FullName
      $decision = Get-Content -Raw -LiteralPath $decisionFile.FullName | ConvertFrom-Json -Depth 100
      $sessionPath = Join-Path $root 'session.json'
      $capturePath = Join-Path $root 'capture.json'
      $summaryPath = Join-Path $root 'result-summary.json'
      $session = Get-Content -Raw -LiteralPath $sessionPath | ConvertFrom-Json -Depth 100
      $capture = Get-Content -Raw -LiteralPath $capturePath | ConvertFrom-Json -Depth 100
      $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json -Depth 100
      $targetRow = @($plan.targets | Where-Object { [string]$_.target -ceq [string]$session.target })
      $expectedEngineSha256 = if ([string]$session.target -ceq 'F210') {
        if ($null -eq $currentF210Resolution) { '' } else { [string]$currentF210Resolution.engine.sha256 }
      } else { [string]$targetRow[0].engine.sha256 }
      if ($targetRow.Count -ne 1 -or [string]$session.kind -cne 'MIR4PlaytestSessionV1' -or
          [string]$capture.kind -cne 'MIR4PlaytestCaptureV1' -or [string]$summary.kind -cne 'MIR4PlaytestResultSummaryV1' -or
          [string]$decision.kind -cne 'MIR4ManualPlaytestDecisionV1' -or [string]$decision.decision -cne 'ACCEPTED' -or [bool]$decision.decision_inferred -or
          [bool]$decision.production_release_authorized -or [string]$decision.target -cne [string]$session.target -or
          [string]$decision.candidate_sha256 -cne [string]$targetRow[0].development_package.sha256 -or
          [string]$decision.engine_sha256 -cne $expectedEngineSha256 -or
          [string]$session.predecessor.sha256 -cne [string]$targetRow[0].predecessor.sha256 -or
          [string]$capture.candidate_sha256 -cne [string]$decision.candidate_sha256 -or
          [string]$capture.engine_sha256 -cne [string]$decision.engine_sha256 -or
          [string]$capture.status -cne 'ready-for-maintainer-decision' -or [string]$capture.comparison.status -cne 'MATCHED' -or
          @($capture.missing_capture_requirements).Count -ne 0 -or [string]$summary.status -cne 'ready-for-maintainer-decision' -or
          (Get-MIR4PreFreezeFileSha256 $sessionPath) -cne [string]$decision.session_sha256 -or
          (Get-MIR4PreFreezeFileSha256 $capturePath) -cne [string]$decision.capture_sha256 -or
          (Get-MIR4PreFreezeFileSha256 $summaryPath) -cne [string]$decision.result_summary_sha256 -or
          (Get-MIR4PreFreezeFileSha256 ([string]$session.authority.development_plan.path)) -cne [string]$session.authority.development_plan.sha256) { continue }
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
