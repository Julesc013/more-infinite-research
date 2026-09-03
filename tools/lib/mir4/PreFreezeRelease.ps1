Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '../../mir/application/release/F210QualificationPolicy.ps1')

$script:MIR4FinalMilePlaytestCandidateAuthorityRelativePath = '.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Playtest-Candidate-AuthorityV1.json'
$script:MIR4FinalMilePlaytestCandidateAuthoritySchemaRelativePath = 'spec/schemas/mir4-final-mile-playtest-candidate-authority-v1.schema.json'
$script:MIR4MaintainerFinalGitHubReleaseAuthorizationRelativePath = '.mir/releases/waves/mir4-r0/MIR4-Maintainer-Final-GitHub-Release-AuthorizationV1.json'
$script:MIR4MaintainerFinalGitHubReleaseAuthorizationSchemaRelativePath = 'spec/schemas/mir4-maintainer-final-github-release-authorization-v1.schema.json'

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

function Test-MIR4T14HistoricalDocumentationSha256 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$ExpectedSha256
  )
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $path = Join-Path $repo $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or $ExpectedSha256 -notmatch '^[A-F0-9]{64}$') { return $false }
  if ((Get-MIR4PreFreezeFileSha256 -Path $path) -ceq $ExpectedSha256) { return $true }

  $authority = Read-MIR4PreFreezeJson -RepoRoot $repo `
    -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Documentation-Continuity-T14V1.json' `
    -Kind 'MIR4DocumentationContinuityT14V1'
  if ([string]$authority.result -cne 'completed' -or
      [string]$authority.metadata_authority -cne 'markdown-frontmatter' -or
      [string]$authority.compatibility_projection -cne '.mir/docs.yml' -or
      -not [bool]$authority.queue_generation_authority_preserved) {
    return $false
  }

  $utf8 = [Text.UTF8Encoding]::new($false, $true)
  $text = $utf8.GetString([IO.File]::ReadAllBytes($path))
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
  $lf = [string][char]10
  $text = $text.Replace(([string][char]13 + $lf), $lf).Replace([string][char]13, $lf)
  $lines = [regex]::Split($text, $lf)
  $historical = [Collections.Generic.List[string]]::new()
  $insideFrontMatter = $false
  $skipSourceIds = $false
  $removedSourceIdLines = 0
  foreach ($line in $lines) {
    if ($line -ceq '---') {
      $insideFrontMatter = -not $insideFrontMatter
      $skipSourceIds = $false
      $historical.Add($line)
      continue
    }
    if ($insideFrontMatter -and $line -match '^source_of_truth_for:\s*$') {
      $skipSourceIds = $true
      $removedSourceIdLines++
      continue
    }
    if ($skipSourceIds -and $line -match '^\s+-\s+\S') {
      $removedSourceIdLines++
      continue
    }
    $skipSourceIds = $false
    $historical.Add($line)
  }
  if ($removedSourceIdLines -lt 2) { return $false }
  $historicalBytes = $utf8.GetBytes(($historical -join $lf).Normalize([Text.NormalizationForm]::FormC))
  $historicalSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($historicalBytes))
  return $historicalSha256 -ceq $ExpectedSha256
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

function Get-MIR4FinalMilePlaytestCandidateAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $externalEvidenceMode = [string]$env:MIR4_EXTERNAL_EVIDENCE_MODE
  $hostedReceiptOnly = $externalEvidenceMode -ceq 'hosted-receipt'
  if (-not [string]::IsNullOrWhiteSpace($externalEvidenceMode) -and -not $hostedReceiptOnly) {
    throw '[mir4-final-mile-playtest-external-evidence-mode]'
  }
  if ($hostedReceiptOnly -and [string]$env:GITHUB_ACTIONS -cne 'true') {
    throw '[mir4-final-mile-playtest-hosted-receipt-context]'
  }
  $path = Join-Path $repo $script:MIR4FinalMilePlaytestCandidateAuthorityRelativePath
  $schema = Join-Path $repo $script:MIR4FinalMilePlaytestCandidateAuthoritySchemaRelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not (Test-Path -LiteralPath $schema -PathType Leaf)) {
    throw '[mir4-final-mile-playtest-authority-missing]'
  }
  $text = Get-Content -Raw -LiteralPath $path
  if (-not ($text | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)) {
    throw '[mir4-final-mile-playtest-authority-schema]'
  }
  $authority = $text | ConvertFrom-Json -Depth 100
  if ((@($authority.targets | ForEach-Object { [string]$_.target } | Sort-Object) -join '|') -cne 'F200|F210') {
    throw '[mir4-final-mile-playtest-authority-targets]'
  }
  if (-not (Get-Command Get-MIRPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
    . (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
  }
  if ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -cne [string]$authority.source_baseline.package_source_sha256) {
    throw '[mir4-final-mile-playtest-authority-package-source]'
  }
  $authorizationDescriptorPath = Join-Path $repo ([string]$authority.authorization.path)
  if (-not (Test-Path -LiteralPath $authorizationDescriptorPath -PathType Leaf) -or
      (Get-MIR4PreFreezeFileSha256 $authorizationDescriptorPath) -cne [string]$authority.authorization.sha256 -or
      [long](Get-Item -LiteralPath $authorizationDescriptorPath).Length -ne [long]$authority.authorization.bytes) {
    throw "[mir4-final-mile-playtest-authority-descriptor] $($authority.authorization.path)"
  }
  foreach ($descriptor in @($authority.targets | ForEach-Object { $_.candidate_manifest; $_.assurance })) {
    $relative = ([string]$descriptor.path).Replace('\', '/')
    $allowedPrivateRoot = $relative.StartsWith('build/mir4/', [StringComparison]::Ordinal) -or
      $relative.StartsWith('build/results/assurance/', [StringComparison]::Ordinal)
    if ([IO.Path]::IsPathRooted([string]$descriptor.path) -or $relative -match '(^|/)\.\.(/|$)' -or
        -not $allowedPrivateRoot -or [string]$descriptor.sha256 -cnotmatch '^[A-F0-9]{64}$' -or
        [long]$descriptor.bytes -le 0) {
      throw "[mir4-final-mile-playtest-authority-external-descriptor] $($descriptor.path)"
    }
    if (-not $hostedReceiptOnly) {
      $descriptorPath = Join-Path $repo ([string]$descriptor.path)
      if (-not (Test-Path -LiteralPath $descriptorPath -PathType Leaf) -or
          (Get-MIR4PreFreezeFileSha256 $descriptorPath) -cne [string]$descriptor.sha256 -or
          [long](Get-Item -LiteralPath $descriptorPath).Length -ne [long]$descriptor.bytes) {
        throw "[mir4-final-mile-playtest-authority-descriptor] $($descriptor.path)"
      }
    }
  }
  if ([string]$authority.authorization.path -cne $script:MIR4MaintainerFinalGitHubReleaseAuthorizationRelativePath) {
    throw '[mir4-final-mile-playtest-authorization-path]'
  }
  $authorizationPath = Join-Path $repo $script:MIR4MaintainerFinalGitHubReleaseAuthorizationRelativePath
  $authorizationSchema = Join-Path $repo $script:MIR4MaintainerFinalGitHubReleaseAuthorizationSchemaRelativePath
  if (-not (Test-Path -LiteralPath $authorizationSchema -PathType Leaf)) { throw '[mir4-final-mile-playtest-authorization-schema-missing]' }
  $authorizationText = Get-Content -Raw -LiteralPath $authorizationPath
  if (-not ($authorizationText | Test-Json -SchemaFile $authorizationSchema -ErrorAction SilentlyContinue)) {
    throw '[mir4-final-mile-playtest-authorization-schema]'
  }
  $authorization = $authorizationText | ConvertFrom-Json -Depth 100
  foreach ($property in @('branch','commit','tree','package_source_sha256')) {
    if ([string]$authorization.starting_source.$property -cne [string]$authority.source_baseline.$property) {
      throw "[mir4-final-mile-playtest-authorization-source] $property"
    }
  }
  foreach ($target in @($authority.targets)) {
    $decision = @($authorization.playtest_decisions | Where-Object { [string]$_.target -ceq [string]$target.target })
    $expectedAssuranceTarget = if ([string]$target.target -ceq 'F210') { '2.1' } else { '2.0' }
    if ($hostedReceiptOnly) {
      $externalEvidenceCurrent = [string]$target.assurance.status -ceq 'passed' -and
        [int]$target.assurance.expected -gt 0 -and [int]$target.assurance.failed -eq 0 -and
        [int]$target.assurance.incomplete -eq 0
    } else {
      $manifest = Get-Content -Raw -LiteralPath (Join-Path $repo ([string]$target.candidate_manifest.path)) | ConvertFrom-Json -Depth 100
      $assurance = Get-Content -Raw -LiteralPath (Join-Path $repo ([string]$target.assurance.path)) | ConvertFrom-Json -Depth 100
      $externalEvidenceCurrent = [string]$manifest.local_distribution.archive_sha256 -ceq [string]$target.development_package.sha256 -and
        [string]$manifest.local_distribution.content_sha256 -ceq [string]$target.development_package.content_sha256 -and
        [long]$manifest.local_distribution.bytes -eq [long]$target.development_package.bytes -and
        [int]$manifest.local_distribution.entry_count -eq [int]$target.development_package.entry_count -and
        [string]$assurance.status -ceq 'passed' -and [int]$assurance.counts.expected -eq [int]$target.assurance.expected -and
        [int]$assurance.counts.failed -eq 0 -and [int]$assurance.counts.incomplete -eq 0 -and
        [string]$assurance.plan.target -ceq $expectedAssuranceTarget -and
        [string]$assurance.plan.package_source_sha256 -ceq [string]$authority.source_baseline.package_source_sha256 -and
        [string]$assurance.plan.domain_manifest.artifact.sha256 -ceq [string]$target.development_package.sha256 -and
        [string]$assurance.plan.domain_manifest.artifact.content_sha256 -ceq [string]$target.development_package.content_sha256
    }
    if (-not $externalEvidenceCurrent -or $decision.Count -ne 1 -or
        [string]$decision[0].distribution -cne [string]$target.distribution_version -or
        [string]$decision[0].candidate_zip_sha256 -cne [string]$target.development_package.sha256 -or
        [string]$decision[0].content_root -cne [string]$target.development_package.content_sha256 -or
        [string]$decision[0].engine.version -cne [string]$target.engine.version -or
        [string]$decision[0].engine.build -cne [string]$target.engine.build -or
        [string]$decision[0].engine.executable_sha256 -cne [string]$target.engine.sha256) {
      throw "[mir4-final-mile-playtest-authority-binding] $($target.target)"
    }
  }
  return $authority
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
  $bindings = [ordered]@{
    source_release_record = 'MIR4_SOURCE_RELEASE_RECORD'
    candidate_id = 'MIR4_CANDIDATE_ID'
    source_commit = 'MIR4_SOURCE_COMMIT'
    source_tree = 'MIR4_SOURCE_TREE'
    target_distribution_record_set = 'MIR4_TARGET_RECORD_SET'
    release_plan_digest = 'MIR4_RELEASE_PLAN_DIGEST'
    proof_root = 'MIR4_PROOF_ROOT'
    seal_root = 'MIR4_SEAL_ROOT'
  }
  foreach ($binding in $bindings.GetEnumerator()) {
    $field = [string]$binding.Key
    $environmentVariable = [string]$binding.Value
    $environmentPattern = '(?m)^\s+' + [regex]::Escape($environmentVariable) + ':\s*\$\{\{\s*inputs\.' + [regex]::Escape($field) + '\s*\}\}\s*$'
    $comparisonPattern = '\[string\]\$admission\.' + [regex]::Escape($field) + '\s*-cne\s*\$env:' + [regex]::Escape($environmentVariable)
    if ($WorkflowText -notmatch $environmentPattern -or $WorkflowText -notmatch $comparisonPattern) {
      throw "[mir4-publisher-admission-binding-missing] $field"
    }
  }
  return $true
}

function Test-MIR4ProductionActionLock {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $relative = 'governance/automation/github-actions-lock.json'
  $path = Join-Path $repo $relative
  $schema = Join-Path $repo 'contracts/repository/mir-github-actions-lock-v1.schema.json'
  $json = Get-Content -Raw -LiteralPath $path
  if (-not ($json | Test-Json -SchemaFile $schema)) { throw '[mir4-actions-lock-schema]' }
  $lock = $json | ConvertFrom-Json -Depth 100
  $pins = @{}
  foreach ($action in @($lock.actions)) { $pins[[string]$action.action] = [string]$action.commit_sha }
  $actualWorkflows = @(Get-ChildItem -LiteralPath (Join-Path $repo '.github/workflows') -File |
    Where-Object { $_.Extension -in @('.yml','.yaml') } |
    ForEach-Object { [IO.Path]::GetRelativePath($repo,$_.FullName).Replace('\','/') } |
    Sort-Object -CaseSensitive)
  $governedWorkflows = @($lock.repository_workflows | ForEach-Object { [string]$_ } | Sort-Object -CaseSensitive)
  if (($actualWorkflows -join '|') -cne ($governedWorkflows -join '|')) {
    throw '[mir4-actions-workflow-closure]'
  }
  $scanPaths = @($governedWorkflows + @($lock.generated_workflow_sources | ForEach-Object { [string]$_ }))
  foreach ($relativeWorkflow in $scanPaths) {
    $workflow = Join-Path $repo ([string]$relativeWorkflow)
    if (-not (Test-Path -LiteralPath $workflow -PathType Leaf)) { throw "[mir4-actions-workflow-missing] $relativeWorkflow" }
    $text = Get-Content -Raw -LiteralPath $workflow
    foreach ($match in [regex]::Matches($text, 'uses:\s*(actions/[A-Za-z0-9_/-]+)@([A-Za-z0-9._-]+)')) {
      $actionName = [string]$match.Groups[1].Value
      $reference = [string]$match.Groups[2].Value
      if (-not $pins.ContainsKey($actionName) -or $reference -cne $pins[$actionName]) {
        throw "[mir4-actions-unpinned] $relativeWorkflow -> $actionName@$reference"
      }
    }
    if ($relativeWorkflow -in $governedWorkflows) {
      if ($text -notmatch '(?m)^permissions:\s*(?:\{|$)') { throw "[mir4-actions-permissions-implicit] $relativeWorkflow" }
      if ($text -match '(?m)^\s{2}pull_request:' -and $text -match 'secrets\.[A-Za-z0-9_]+') {
        throw "[mir4-actions-public-pr-secret] $relativeWorkflow"
      }
      foreach ($write in [regex]::Matches($text,'(?m)(?<permission>[a-z-]+):\s*write\b')) {
        $permission = [string]$write.Groups['permission'].Value
        if ($relativeWorkflow -cne '.github/workflows/branch-policy.yml' -or $permission -notin @('checks','statuses')) {
          throw "[mir4-actions-excess-write-permission] $relativeWorkflow -> $permission"
        }
      }
    }
  }
  $builder = Get-Content -Raw -LiteralPath (Join-Path $repo '.github/workflows/mir4-target-build.yml')
  if ($builder -match '(?i)ssh-keygen|private[_-]?key|sign(?:ing)?|upload-artifact|gh\s+release|mod[_ -]?portal' -or
      $builder -notmatch "Operation='DryRun'") { throw '[mir4-builder-capability-confinement]' }
  $qualifier = Get-Content -Raw -LiteralPath (Join-Path $repo '.github/workflows/mir4-target-qualification.yml')
  if ($qualifier -match 'Operation=''Execute''|production_mutation_performed\s*=\s*\$true|upload-artifact|gh\s+release|mod[_ -]?portal') {
    throw '[mir4-qualifier-capability-confinement]'
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

function Get-MIR4PreFreezeAuthorityState {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [switch]$IncludeT17MachinePreparation,
    [switch]$IncludeRepositoryMigration,
    [switch]$IncludeCanonicalizationMigration,
    [switch]$IncludeDiagnosticsMigration,
    [switch]$IncludeTargetKeyMigration,
    [switch]$IncludeWholePlatformMigration,
    [switch]$IncludeTechnologyAcceptanceMigration,
    [switch]$IncludeTargetCompilerMigration,
    [switch]$IncludeSemanticCompilerPolicyMigration,
    [switch]$IncludeRuntimeContinuityMigration,
    [switch]$IncludeModuleSdkMepMigration,
    [switch]$IncludeProcessIRExactMigration,
    [switch]$IncludeInspectorCompatibilityMigration,
    [switch]$IncludeAssuranceOfflineCustodyMigration,
    [switch]$IncludeHistoricalToolingMigration,
    [switch]$IncludeReleaseToolingMigration,
    [switch]$IncludeF210QualificationPolicyEvolution,
    [switch]$IncludeFinalMileToolingEvolution,
    [switch]$IncludeFinalReleaseClosureEvolution,
    [switch]$IncludePostReleasePackageBaselineEvolution,
    [switch]$IncludePostReleaseAutomationCutover,
    [switch]$IncludePostReleaseBranchOperatingModel,
    [switch]$IncludePostReleasePatchLaneRehearsal,
    [switch]$IncludeM4103ChangeReleaseAuthority,
    [switch]$IncludeM4105AM4200ACharacterizationAuthority,
    [switch]$IncludeM41F0TruthReconciliationAuthority,
    [switch]$IncludeM41F1GoldenBaselineAuthority,
    [switch]$IncludeM41F2AShadowMaterializerAuthority,
    [switch]$IncludeM41F2BShadowSourceModelAuthority,
    [switch]$IncludeM41F2CEditableSourceMaterializerAuthority,
    [switch]$IncludeM41F2DHarnessAuthority,
    [switch]$IncludeM41F2DF210RuntimeReplayAuthority,
    [string[]]$M41F2DTargetRuntimeReplayTargets = @(),
    [switch]$IncludeM41F2DAggregateAuthority
  )
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $receipt = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json' -Kind 'MIR4PostReadinessMergeReceiptSOL15V1'
  $authorityHashes = @{}
  $authorityHashModes = @{}
  foreach ($binding in @($receipt.authority_bindings)) {
    $authorityHashes[[string]$binding.path] = [string]$binding.sha256
    $authorityHashModes[[string]$binding.path] = $(if($binding.PSObject.Properties.Name-contains'hash_mode'){[string]$binding.hash_mode}else{'raw-bytes'})
  }
  $priorReceiptPath = '.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json'
  $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  $links = @(
    @{path='.mir/releases/waves/mir4-r0/MIR4-T02-Authority-Evolution-ReceiptV1.json';kind='MIR4T02AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T03-Authority-Evolution-ReceiptV1.json';kind='MIR4T03AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T04-Authority-Evolution-ReceiptV1.json';kind='MIR4T04AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T05-Authority-Evolution-ReceiptV1.json';kind='MIR4T05AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T06-Authority-Evolution-ReceiptV1.json';kind='MIR4T06AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T07-Authority-Evolution-ReceiptV1.json';kind='MIR4T07AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T08-Authority-Evolution-ReceiptV1.json';kind='MIR4T08AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T09-Authority-Evolution-ReceiptV1.json';kind='MIR4T09AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T10-Authority-Evolution-ReceiptV1.json';kind='MIR4T10AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T11-Authority-Evolution-ReceiptV1.json';kind='MIR4T11AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T12-Authority-Evolution-ReceiptV1.json';kind='MIR4T12AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T13-Authority-Evolution-ReceiptV1.json';kind='MIR4T13AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T14-Authority-Evolution-ReceiptV1.json';kind='MIR4T14AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json';kind='MIR4T15AuthorityEvolutionReceiptV1'}
  )
  if ($IncludeT17MachinePreparation) {
    $links += @{path='.mir/releases/waves/mir4-r0/MIR4-T17-Machine-Preparation-Authority-Evolution-ReceiptV1.json';kind='MIR4T17MachinePreparationAuthorityEvolutionReceiptV1'}
  }
  if ($IncludeRepositoryMigration) {
    if (-not $IncludeT17MachinePreparation) { throw '[mir4-prefreeze-repository-migration-requires-t17]' }
    $links += @{path='releases/migrations/MIR4-Repository-Fixed-Point-Tooling-MigrationV1.json';kind='MIR4RepositoryMigrationReceiptV1'}
  }
  if ($IncludeCanonicalizationMigration) {
    if (-not $IncludeRepositoryMigration) { throw '[mir4-prefreeze-canonicalization-migration-requires-repository-migration]' }
    $links += @{path='releases/migrations/MIR4-Canonicalization-Tooling-MigrationV1.json';kind='MIR4CanonicalizationMigrationReceiptV1'}
  }
  if ($IncludeDiagnosticsMigration) {
    if (-not $IncludeCanonicalizationMigration) { throw '[mir4-prefreeze-diagnostics-migration-requires-canonicalization-migration]' }
    $links += @{path='releases/migrations/MIR4-Diagnostics-Tooling-MigrationV1.json';kind='MIR4DiagnosticsMigrationReceiptV1'}
  }
  if ($IncludeTargetKeyMigration) {
    if (-not $IncludeDiagnosticsMigration) { throw '[mir4-prefreeze-target-key-migration-requires-diagnostics-migration]' }
    $links += @{path='releases/migrations/MIR4-Target-Key-Tooling-MigrationV1.json';kind='MIR4TargetKeyMigrationReceiptV1'}
  }
  if ($IncludeWholePlatformMigration) {
    if (-not $IncludeTargetKeyMigration) { throw '[mir4-prefreeze-whole-platform-migration-requires-target-key-migration]' }
    $links += @{path='releases/migrations/MIR4-Whole-Platform-Tooling-MigrationV1.json';kind='MIR4WholePlatformMigrationReceiptV1'}
  }
  if ($IncludeTechnologyAcceptanceMigration) {
    if (-not $IncludeWholePlatformMigration) { throw '[mir4-prefreeze-technology-acceptance-migration-requires-whole-platform-migration]' }
    $links += @{path='releases/migrations/MIR4-Technology-Acceptance-Tooling-MigrationV1.json';kind='MIR4TechnologyAcceptanceMigrationReceiptV1'}
  }
  if ($IncludeTargetCompilerMigration) {
    if (-not $IncludeTechnologyAcceptanceMigration) { throw '[mir4-prefreeze-target-compiler-migration-requires-technology-acceptance-migration]' }
    $links += @{path='releases/migrations/MIR4-Target-Compiler-Tooling-MigrationV1.json';kind='MIR4TargetCompilerMigrationReceiptV1'}
  }
  if ($IncludeSemanticCompilerPolicyMigration) {
    if (-not $IncludeTargetCompilerMigration) { throw '[mir4-prefreeze-semantic-compiler-policy-migration-requires-target-compiler-migration]' }
    $links += @{path='releases/migrations/MIR4-Semantic-Compiler-Policy-Tooling-MigrationV1.json';kind='MIR4SemanticCompilerPolicyMigrationReceiptV1'}
  }
  if ($IncludeRuntimeContinuityMigration) {
    if (-not $IncludeSemanticCompilerPolicyMigration) { throw '[mir4-prefreeze-runtime-continuity-migration-requires-semantic-compiler-policy-migration]' }
    $links += @{path='releases/migrations/MIR4-Runtime-Continuity-Tooling-MigrationV1.json';kind='MIR4RuntimeContinuityMigrationReceiptV1'}
  }
  if ($IncludeModuleSdkMepMigration) {
    if (-not $IncludeRuntimeContinuityMigration) { throw '[mir4-prefreeze-module-sdk-mep-migration-requires-runtime-continuity-migration]' }
    $links += @{path='releases/migrations/MIR4-Module-Sdk-Mep-Tooling-MigrationV1.json';kind='MIR4ModuleSdkMepMigrationReceiptV1'}
  }
  if ($IncludeProcessIRExactMigration) {
    if (-not $IncludeModuleSdkMepMigration) { throw '[mir4-prefreeze-processir-exact-migration-requires-module-sdk-mep-migration]' }
    $links += @{path='releases/migrations/MIR4-ProcessIR-Exact-Tooling-MigrationV1.json';kind='MIR4ProcessIRExactMigrationReceiptV1'}
  }
  if ($IncludeInspectorCompatibilityMigration) {
    if (-not $IncludeProcessIRExactMigration) { throw '[mir4-prefreeze-inspector-compatibility-migration-requires-processir-exact-migration]' }
    $links += @{path='releases/migrations/MIR4-Inspector-Compatibility-Tooling-MigrationV1.json';kind='MIR4InspectorCompatibilityMigrationReceiptV1'}
  }
  if ($IncludeAssuranceOfflineCustodyMigration) {
    if (-not $IncludeInspectorCompatibilityMigration) { throw '[mir4-prefreeze-assurance-offline-custody-migration-requires-inspector-compatibility-migration]' }
    $links += @{path='releases/migrations/MIR4-Assurance-Offline-Custody-Tooling-MigrationV1.json';kind='MIR4AssuranceOfflineCustodyMigrationReceiptV1'}
  }
  if ($IncludeHistoricalToolingMigration) {
    if (-not $IncludeAssuranceOfflineCustodyMigration) { throw '[mir4-prefreeze-historical-tooling-migration-requires-assurance-offline-custody-migration]' }
    $links += @{path='releases/migrations/MIR4-Historical-Tooling-MigrationV1.json';kind='MIR4HistoricalToolingMigrationReceiptV1'}
  }
  if ($IncludeReleaseToolingMigration) {
    if (-not $IncludeHistoricalToolingMigration) { throw '[mir4-prefreeze-release-tooling-migration-requires-historical-tooling-migration]' }
    $links += @{path='releases/migrations/MIR4-Release-Tooling-MigrationV1.json';kind='MIR4ReleaseToolingMigrationReceiptV1'}
  }
  if ($IncludeF210QualificationPolicyEvolution) {
    if (-not $IncludeReleaseToolingMigration) { throw '[mir4-prefreeze-f210-policy-evolution-requires-release-tooling-migration]' }
    $links += @{path='.mir/releases/waves/mir4-r0/MIR4-F210-Qualification-Policy-Authority-Evolution-ReceiptV1.json';kind='MIR4F210QualificationPolicyAuthorityEvolutionReceiptV1'}
  }
  if ($IncludeFinalMileToolingEvolution) {
    if (-not $IncludeF210QualificationPolicyEvolution) { throw '[mir4-prefreeze-final-mile-tooling-evolution-requires-f210-policy-evolution]' }
    $links += @{path='.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Tooling-Authority-Evolution-ReceiptV1.json';kind='MIR4FinalMileToolingAuthorityEvolutionReceiptV1'}
  }
  if ($IncludeFinalReleaseClosureEvolution) {
    if (-not $IncludeFinalMileToolingEvolution) { throw '[mir4-prefreeze-final-release-closure-evolution-requires-final-mile-tooling-evolution]' }
    $links += @{path='.mir/releases/waves/mir4-r0/MIR4-Final-Release-Closure-Authority-Evolution-ReceiptV1.json';kind='MIR4FinalReleaseClosureAuthorityEvolutionReceiptV1'}
  }
  if ($IncludePostReleasePackageBaselineEvolution) {
    if (-not $IncludeFinalReleaseClosureEvolution) { throw '[mir4-prefreeze-post-release-package-baseline-evolution-requires-final-release-closure-evolution]' }
    $links += @{path='.mir/releases/waves/mir4-r0/MIR4-Post-Release-Package-Baseline-Authority-Evolution-ReceiptV1.json';kind='MIR4PostReleasePackageBaselineAuthorityEvolutionReceiptV1'}
  }
  if ($IncludePostReleaseAutomationCutover) {
    if (-not $IncludePostReleasePackageBaselineEvolution) { throw '[mir4-prefreeze-post-release-automation-cutover-requires-package-baseline-evolution]' }
    $links += @{path='releases/migrations/MIR4-Post-Release-Automation-Authority-CutoverV1.json';kind='MIR4PostReleaseAutomationAuthorityCutoverV1'}
  }
  if ($IncludePostReleaseBranchOperatingModel) {
    if (-not $IncludePostReleaseAutomationCutover) { throw '[mir4-prefreeze-post-release-branch-operating-model-requires-automation-cutover]' }
    $links += @{path='releases/migrations/MIR4-Branch-Operating-Model-Authority-EvolutionV1.json';kind='MIR4BranchOperatingModelAuthorityEvolutionV1'}
  }
  if ($IncludePostReleasePatchLaneRehearsal) {
    if (-not $IncludePostReleaseBranchOperatingModel) { throw '[mir4-prefreeze-post-release-patch-lane-rehearsal-requires-branch-operating-model]' }
    $links += @{path='releases/migrations/MIR4-Patch-Lane-Rehearsal-Authority-EvolutionV1.json';kind='MIR4PatchLaneRehearsalAuthorityEvolutionV1'}
  }
  if ($IncludeM4103ChangeReleaseAuthority) {
    if (-not $IncludePostReleasePatchLaneRehearsal) { throw '[mir4-prefreeze-m41-03-requires-patch-lane-rehearsal]' }
    $links += @{path='releases/migrations/MIR4-M41-03-Change-And-Release-Authority-EvolutionV1.json';kind='MIR4M4103ChangeAndReleaseAuthorityEvolutionV1'}
  }
  if ($IncludeM4105AM4200ACharacterizationAuthority) {
    if (-not $IncludeM4103ChangeReleaseAuthority) { throw '[mir4-prefreeze-m41-05a-m42-00a-requires-m41-03]' }
    $links += @{path='releases/migrations/MIR4-M41-05A-M42-00A-Repository-Characterization-Authority-EvolutionV1.json';kind='MIR4M4105AM4200ARepositoryCharacterizationAuthorityEvolutionV1'}
  }
  if ($IncludeM41F0TruthReconciliationAuthority) {
    if (-not $IncludeM4105AM4200ACharacterizationAuthority) { throw '[mir4-prefreeze-m41-f0-requires-characterization]' }
    $links += @{path='releases/migrations/MIR4-M41-F0-Truth-Reconciliation-Authority-EvolutionV1.json';kind='MIR4M41F0TruthReconciliationAuthorityEvolutionV1'}
  }
  if ($IncludeM41F1GoldenBaselineAuthority) {
    if (-not $IncludeM41F0TruthReconciliationAuthority) { throw '[mir4-prefreeze-m41-f1-requires-m41-f0]' }
    $links += @{path='releases/migrations/MIR4-M41-F1-Golden-Four-Target-Baseline-Authority-EvolutionV1.json';kind='MIR4M41F1GoldenFourTargetBaselineAuthorityEvolutionV1'}
  }
  if ($IncludeM41F2AShadowMaterializerAuthority) {
    if (-not $IncludeM41F1GoldenBaselineAuthority) { throw '[mir4-prefreeze-m41-f2a-requires-m41-f1]' }
    $links += @{path='releases/migrations/MIR4-M41-F2A-Shadow-Target-Materializer-Authority-EvolutionV1.json';kind='MIR4M41F2AShadowTargetMaterializerAuthorityEvolutionV1'}
  }
  if ($IncludeM41F2BShadowSourceModelAuthority) {
    if (-not $IncludeM41F2AShadowMaterializerAuthority) { throw '[mir4-prefreeze-m41-f2b-requires-m41-f2a]' }
    $links += @{path='releases/migrations/MIR4-M41-F2B-Shadow-Source-Model-Authority-EvolutionV1.json';kind='MIR4M41F2BShadowSourceModelAuthorityEvolutionV1'}
  }
  if ($IncludeM41F2CEditableSourceMaterializerAuthority) {
    if (-not $IncludeM41F2BShadowSourceModelAuthority) { throw '[mir4-prefreeze-m41-f2c-requires-m41-f2b]' }
    $links += @{path='releases/migrations/MIR4-M41-F2C-Editable-Source-Materializer-Authority-EvolutionV1.json';kind='MIR4M41F2CEditableSourceMaterializerAuthorityEvolutionV1'}
  }
  if ($IncludeM41F2DHarnessAuthority) {
    if (-not $IncludeM41F2CEditableSourceMaterializerAuthority) { throw '[mir4-prefreeze-m41-f2d-harness-requires-m41-f2c]' }
    $links += @{path='releases/migrations/MIR4-M41-F2D-Runtime-Replay-Harness-Authority-EvolutionV1.json';kind='MIR4M41F2DRuntimeReplayHarnessAuthorityEvolutionV1'}
  }
  if ($IncludeM41F2DF210RuntimeReplayAuthority) {
    if (-not $IncludeM41F2DHarnessAuthority) { throw '[mir4-prefreeze-m41-f2d-f210-requires-f2d-harness]' }
    $links += @{path='releases/migrations/MIR4-M41-F2D-F210-Runtime-Replay-Authority-EvolutionV1.json';kind='MIR4M41F2DF210RuntimeReplayAuthorityEvolutionV1'}
  }
  $orderedF2DTargets = @('f200','f110','f100')
  $requestedF2DTargets = @($M41F2DTargetRuntimeReplayTargets | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique)
  if (@($requestedF2DTargets | Where-Object { $_ -notin $orderedF2DTargets }).Count -ne 0) { throw '[mir4-prefreeze-m41-f2d-target-unsupported]' }
  $acceptedF2DTargets = [Collections.Generic.List[string]]::new()
  foreach ($target in $orderedF2DTargets) {
    if ($target -notin $requestedF2DTargets) { continue }
    if ($target -eq 'f200' -and -not $IncludeM41F2DF210RuntimeReplayAuthority) { throw '[mir4-prefreeze-m41-f2d-f200-requires-f210]' }
    if ($target -eq 'f110' -and 'f200' -notin $acceptedF2DTargets) { throw '[mir4-prefreeze-m41-f2d-f110-requires-f200]' }
    if ($target -eq 'f100' -and 'f110' -notin $acceptedF2DTargets) { throw '[mir4-prefreeze-m41-f2d-f100-requires-f110]' }
    $code = $target.Substring(1).ToUpperInvariant()
    $links += @{path="releases/migrations/MIR4-M41-F2D-F$code-Runtime-Replay-Authority-EvolutionV1.json";kind='MIR4M41F2DTargetRuntimeReplayAuthorityEvolutionV1'}
    $acceptedF2DTargets.Add($target)
  }
  if ($IncludeM41F2DAggregateAuthority) {
    if ((@($acceptedF2DTargets) -join '|') -cne 'f200|f110|f100') { throw '[mir4-prefreeze-m41-f2d-aggregate-requires-four-targets]' }
    $links += @{path='releases/migrations/MIR4-M41-F2D-Four-Target-Runtime-Replay-AggregateV1.json';kind='MIR4M41F2DFourTargetRuntimeReplayAggregateV1'}
  }
  foreach ($link in $links) {
    $evolution = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $link.path -Kind $link.kind
    if ([string]$evolution.predecessor_receipt.path -cne $priorReceiptPath -or
        [string]$evolution.predecessor_receipt.sha256 -cne $priorReceiptSha256) {
      throw "[mir4-prefreeze-evolution-predecessor] $($link.path)"
    }
    $evolvedPaths = @{}
    foreach ($binding in @($evolution.evolved_bindings)) {
      $path = [string]$binding.path
      $allowedPackageVisibleSuccessor = [string]$evolution.kind -ceq 'MIR4PostReleasePackageBaselineAuthorityEvolutionReceiptV1' -and
        $path -ceq 'README.md' -and [bool]$binding.package_visible
      if (-not $authorityHashes.ContainsKey($path) -or [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          ([bool]$binding.package_visible -and -not $allowedPackageVisibleSuccessor) -or [bool]$binding.release_authority -or $evolvedPaths.ContainsKey($path)) {
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
      $authorityHashModes[$path] = $(if($binding.PSObject.Properties.Name-contains'hash_mode'){[string]$binding.hash_mode}else{'raw-bytes'})
    }
    if ($evolution.PSObject.Properties.Name -contains 'retired_bindings') {
      if ([string]$evolution.kind -cne 'MIR4PostReleaseAutomationAuthorityCutoverV1') { throw "[mir4-prefreeze-retired-binding-kind] $($link.path)" }
      $retiredPaths = @{}
      foreach ($binding in @($evolution.retired_bindings)) {
        $path = [string]$binding.path
        if (-not $authorityHashes.ContainsKey($path) -or
            [string]$authorityHashes[$path] -cne [string]$binding.historical_sha256 -or
            $retiredPaths.ContainsKey($path)) {
          throw "[mir4-prefreeze-retired-binding] $path"
        }
        [void]$authorityHashes.Remove($path)
        [void]$authorityHashModes.Remove($path)
        $retiredPaths[$path] = $true
      }
    }
    foreach ($property in $evolution.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-evolution-transition] $($link.path):$($property.Name)" }
    }
    $priorReceiptPath = [string]$link.path
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  return [pscustomobject][ordered]@{
    authority_hashes = $authorityHashes
    authority_hash_modes = $authorityHashModes
    prior_receipt_path = $priorReceiptPath
    prior_receipt_sha256 = $priorReceiptSha256
  }
}

function Test-MIR4PreFreezeAuthorities {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $schemas = [ordered]@{
    '.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json' = 'spec/schemas/mir4-post-readiness-merge-receipt-sol15-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Pre-Freeze-Development-PlanV1.json' = 'spec/schemas/mir4-pre-freeze-development-plan-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-F210-Release-Qualification-PolicyV1.json' = 'spec/schemas/mir4-f210-release-qualification-policy-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Release-Workflow-ContractV1.json' = 'spec/schemas/mir4-release-workflow-contract-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Release-Phase-Engine-ContractV1.json' = 'spec/schemas/mir4-release-phase-engine-contract-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T02-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t02-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T03-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t03-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T04-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t04-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T05-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t05-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Release-Fault-CorpusV1.json' = 'spec/schemas/mir4-release-fault-corpus-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T06-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t06-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T07-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t07-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T08-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t08-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T09-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t09-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T10-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t10-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T11-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t11-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T12-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t12-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Release-Compatibility-Canaries-T13V1.json' = 'spec/schemas/mir4-release-compatibility-canaries-t13-v1.schema.json'
    'sdk/preview/mir4/reference/t13/MIR4_T13_RECEIPT.json' = 'spec/schemas/preview/mir4-t13-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T13-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t13-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Documentation-Continuity-T14V1.json' = 'spec/schemas/mir4-documentation-continuity-t14-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T14-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t14-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Supply-Chain-Preservation-T15V1.json' = 'spec/schemas/mir4-supply-chain-preservation-t15-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T15-Independent-Machine-AcceptanceV1.json' = 'spec/schemas/mir4-t15-independent-machine-acceptance-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t15-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-T17-Machine-Preparation-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-t17-machine-preparation-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-F210-Qualification-Policy-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-f210-qualification-policy-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Tooling-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-final-mile-tooling-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Final-Release-Closure-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-final-release-closure-authority-evolution-receipt-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Post-Release-Package-Baseline-Authority-Evolution-ReceiptV1.json' = 'spec/schemas/mir4-post-release-package-baseline-authority-evolution-receipt-v1.schema.json'
    'releases/migrations/MIR4-Post-Release-Automation-Authority-CutoverV1.json' = 'contracts/repository/mir4-post-release-automation-authority-cutover-v1.schema.json'
    'releases/migrations/MIR4-Branch-Operating-Model-Authority-EvolutionV1.json' = 'contracts/repository/mir4-branch-operating-model-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-Patch-Lane-Rehearsal-Authority-EvolutionV1.json' = 'contracts/repository/mir4-patch-lane-rehearsal-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-03-Change-And-Release-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-03-change-and-release-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-05A-M42-00A-Repository-Characterization-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-05a-m42-00a-repository-characterization-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F0-Truth-Reconciliation-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f0-truth-reconciliation-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F1-Golden-Four-Target-Baseline-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f1-golden-four-target-baseline-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F2A-Shadow-Target-Materializer-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f2a-shadow-target-materializer-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F2B-Shadow-Source-Model-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f2b-shadow-source-model-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F2C-Editable-Source-Materializer-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f2c-editable-source-materializer-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F2D-Runtime-Replay-Harness-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f2d-runtime-replay-harness-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F2D-F210-Runtime-Replay-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f2d-f210-runtime-replay-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F2D-F200-Runtime-Replay-Authority-EvolutionV1.json' = 'contracts/repository/mir4-m41-f2d-target-runtime-replay-authority-evolution-v1.schema.json'
    'releases/migrations/MIR4-M41-F2E-Package-Authority-CutoverV1.json' = 'contracts/repository/mir4-m41-f2e-package-authority-cutover-v1.schema.json'
    'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json' = 'contracts/repository/mir4-m41-05b-documentation-cutover-v1.schema.json'
    'releases/migrations/MIR4-M42-01A-CLI-Release-ConvergenceV1.json' = 'contracts/repository/mir4-m42-01a-cli-release-convergence-v1.schema.json'
    'releases/migrations/MIR4-M42-01B-Test-Workflow-ConvergenceV1.json' = 'contracts/repository/mir4-m42-01b-test-workflow-convergence-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Compilation-Plan-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-compilation-plan-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Base-Continuations-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-base-continuations-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Stream-Compiler-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-stream-compiler-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Technology-Catalog-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-technology-catalog-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Effect-Ownership-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-effect-ownership-decomposition-v1.schema.json'
    'releases/migrations/MIR4-M42-02-Compiler-Orchestrator-DecompositionV1.json' = 'contracts/repository/mir4-m42-02-compiler-orchestrator-decomposition-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Maintainer-Final-GitHub-Release-AuthorizationV1.json' = 'spec/schemas/mir4-maintainer-final-github-release-authorization-v1.schema.json'
    '.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Playtest-Candidate-AuthorityV1.json' = 'spec/schemas/mir4-final-mile-playtest-candidate-authority-v1.schema.json'
    'releases/migrations/MIR4-Repository-Fixed-Point-Tooling-MigrationV1.json' = 'contracts/repository/mir4-repository-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Canonicalization-Tooling-MigrationV1.json' = 'contracts/repository/mir4-canonicalization-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Diagnostics-Tooling-MigrationV1.json' = 'contracts/repository/mir4-diagnostics-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Target-Key-Tooling-MigrationV1.json' = 'contracts/repository/mir4-target-key-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Whole-Platform-Tooling-MigrationV1.json' = 'contracts/repository/mir4-whole-platform-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Technology-Acceptance-Tooling-MigrationV1.json' = 'contracts/repository/mir4-technology-acceptance-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Target-Compiler-Tooling-MigrationV1.json' = 'contracts/repository/mir4-target-compiler-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Semantic-Compiler-Policy-Tooling-MigrationV1.json' = 'contracts/repository/mir4-semantic-compiler-policy-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Runtime-Continuity-Tooling-MigrationV1.json' = 'contracts/repository/mir4-runtime-continuity-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Module-Sdk-Mep-Tooling-MigrationV1.json' = 'contracts/repository/mir4-module-sdk-mep-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-ProcessIR-Exact-Tooling-MigrationV1.json' = 'contracts/repository/mir4-processir-exact-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Inspector-Compatibility-Tooling-MigrationV1.json' = 'contracts/repository/mir4-inspector-compatibility-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Assurance-Offline-Custody-Tooling-MigrationV1.json' = 'contracts/repository/mir4-assurance-offline-custody-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Historical-Tooling-MigrationV1.json' = 'contracts/repository/mir4-historical-tooling-migration-receipt-v1.schema.json'
    'releases/migrations/MIR4-Release-Tooling-MigrationV1.json' = 'contracts/repository/mir4-release-tooling-migration-receipt-v1.schema.json'
  }
  $lowerTargetReceiptPaths = [ordered]@{
    f110 = 'releases/migrations/MIR4-M41-F2D-F110-Runtime-Replay-Authority-EvolutionV1.json'
    f100 = 'releases/migrations/MIR4-M41-F2D-F100-Runtime-Replay-Authority-EvolutionV1.json'
  }
  $lowerTargetReceiptPresence = @{}
  foreach ($target in $lowerTargetReceiptPaths.Keys) {
    $relativePath = [string]$lowerTargetReceiptPaths[$target]
    $present = Test-Path -LiteralPath (Join-Path $repo $relativePath) -PathType Leaf
    $lowerTargetReceiptPresence[$target] = $present
    if ($present) {
      $schemas[$relativePath] = 'contracts/repository/mir4-m41-f2d-target-runtime-replay-authority-evolution-v1.schema.json'
    }
  }
  if ($lowerTargetReceiptPresence.f100 -and -not $lowerTargetReceiptPresence.f110) {
    throw '[mir4-prefreeze-lower-target-receipt-order] f100 requires f110'
  }
  $aggregateReceiptPath = 'releases/migrations/MIR4-M41-F2D-Four-Target-Runtime-Replay-AggregateV1.json'
  $aggregateReceiptPresent = Test-Path -LiteralPath (Join-Path $repo $aggregateReceiptPath) -PathType Leaf
  if ($aggregateReceiptPresent) {
    if (-not $lowerTargetReceiptPresence.f100) { throw '[mir4-prefreeze-f2d-aggregate-requires-f100]' }
    $schemas[$aggregateReceiptPath] = 'contracts/repository/mir4-m41-f2d-four-target-runtime-replay-aggregate-v1.schema.json'
  }
  foreach ($entry in $schemas.GetEnumerator()) {
    $json = Get-Content -Raw -LiteralPath (Join-Path $repo $entry.Key)
    if (-not ($json | Test-Json -SchemaFile (Join-Path $repo $entry.Value))) { throw "[mir4-prefreeze-schema] $($entry.Key)" }
  }
  $receipt = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json' -Kind 'MIR4PostReadinessMergeReceiptSOL15V1'
  $authorityHashes = @{}
  $authorityHashModes = @{}
  foreach ($binding in @($receipt.authority_bindings)) {
    $authorityHashes[[string]$binding.path] = [string]$binding.sha256
    $authorityHashModes[[string]$binding.path] = $(if($binding.PSObject.Properties.Name-contains'hash_mode'){[string]$binding.hash_mode}else{'raw-bytes'})
  }
  $priorReceiptPath = '.mir/releases/waves/mir4-r0/MIR4-Post-Readiness-Merge-Receipt-SOL15V1.json'
  $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  $evolutionLinks = @(
    @{path='.mir/releases/waves/mir4-r0/MIR4-T02-Authority-Evolution-ReceiptV1.json';kind='MIR4T02AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T03-Authority-Evolution-ReceiptV1.json';kind='MIR4T03AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T04-Authority-Evolution-ReceiptV1.json';kind='MIR4T04AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T05-Authority-Evolution-ReceiptV1.json';kind='MIR4T05AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T06-Authority-Evolution-ReceiptV1.json';kind='MIR4T06AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T07-Authority-Evolution-ReceiptV1.json';kind='MIR4T07AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T08-Authority-Evolution-ReceiptV1.json';kind='MIR4T08AuthorityEvolutionReceiptV1'},
    @{path='.mir/releases/waves/mir4-r0/MIR4-T09-Authority-Evolution-ReceiptV1.json';kind='MIR4T09AuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-T10-Authority-Evolution-ReceiptV1.json';kind='MIR4T10AuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-T11-Authority-Evolution-ReceiptV1.json';kind='MIR4T11AuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-T12-Authority-Evolution-ReceiptV1.json';kind='MIR4T12AuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-T13-Authority-Evolution-ReceiptV1.json';kind='MIR4T13AuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-T14-Authority-Evolution-ReceiptV1.json';kind='MIR4T14AuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json';kind='MIR4T15AuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-T17-Machine-Preparation-Authority-Evolution-ReceiptV1.json';kind='MIR4T17MachinePreparationAuthorityEvolutionReceiptV1'}
    @{path='releases/migrations/MIR4-Repository-Fixed-Point-Tooling-MigrationV1.json';kind='MIR4RepositoryMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Canonicalization-Tooling-MigrationV1.json';kind='MIR4CanonicalizationMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Diagnostics-Tooling-MigrationV1.json';kind='MIR4DiagnosticsMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Target-Key-Tooling-MigrationV1.json';kind='MIR4TargetKeyMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Whole-Platform-Tooling-MigrationV1.json';kind='MIR4WholePlatformMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Technology-Acceptance-Tooling-MigrationV1.json';kind='MIR4TechnologyAcceptanceMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Target-Compiler-Tooling-MigrationV1.json';kind='MIR4TargetCompilerMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Semantic-Compiler-Policy-Tooling-MigrationV1.json';kind='MIR4SemanticCompilerPolicyMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Runtime-Continuity-Tooling-MigrationV1.json';kind='MIR4RuntimeContinuityMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Module-Sdk-Mep-Tooling-MigrationV1.json';kind='MIR4ModuleSdkMepMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-ProcessIR-Exact-Tooling-MigrationV1.json';kind='MIR4ProcessIRExactMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Inspector-Compatibility-Tooling-MigrationV1.json';kind='MIR4InspectorCompatibilityMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Assurance-Offline-Custody-Tooling-MigrationV1.json';kind='MIR4AssuranceOfflineCustodyMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Historical-Tooling-MigrationV1.json';kind='MIR4HistoricalToolingMigrationReceiptV1'}
    @{path='releases/migrations/MIR4-Release-Tooling-MigrationV1.json';kind='MIR4ReleaseToolingMigrationReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-F210-Qualification-Policy-Authority-Evolution-ReceiptV1.json';kind='MIR4F210QualificationPolicyAuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Tooling-Authority-Evolution-ReceiptV1.json';kind='MIR4FinalMileToolingAuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-Final-Release-Closure-Authority-Evolution-ReceiptV1.json';kind='MIR4FinalReleaseClosureAuthorityEvolutionReceiptV1'}
    @{path='.mir/releases/waves/mir4-r0/MIR4-Post-Release-Package-Baseline-Authority-Evolution-ReceiptV1.json';kind='MIR4PostReleasePackageBaselineAuthorityEvolutionReceiptV1'}
    @{path='releases/migrations/MIR4-Post-Release-Automation-Authority-CutoverV1.json';kind='MIR4PostReleaseAutomationAuthorityCutoverV1'}
    @{path='releases/migrations/MIR4-Branch-Operating-Model-Authority-EvolutionV1.json';kind='MIR4BranchOperatingModelAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-Patch-Lane-Rehearsal-Authority-EvolutionV1.json';kind='MIR4PatchLaneRehearsalAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-03-Change-And-Release-Authority-EvolutionV1.json';kind='MIR4M4103ChangeAndReleaseAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-05A-M42-00A-Repository-Characterization-Authority-EvolutionV1.json';kind='MIR4M4105AM4200ARepositoryCharacterizationAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F0-Truth-Reconciliation-Authority-EvolutionV1.json';kind='MIR4M41F0TruthReconciliationAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F1-Golden-Four-Target-Baseline-Authority-EvolutionV1.json';kind='MIR4M41F1GoldenFourTargetBaselineAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F2A-Shadow-Target-Materializer-Authority-EvolutionV1.json';kind='MIR4M41F2AShadowTargetMaterializerAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F2B-Shadow-Source-Model-Authority-EvolutionV1.json';kind='MIR4M41F2BShadowSourceModelAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F2C-Editable-Source-Materializer-Authority-EvolutionV1.json';kind='MIR4M41F2CEditableSourceMaterializerAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F2D-Runtime-Replay-Harness-Authority-EvolutionV1.json';kind='MIR4M41F2DRuntimeReplayHarnessAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F2D-F210-Runtime-Replay-Authority-EvolutionV1.json';kind='MIR4M41F2DF210RuntimeReplayAuthorityEvolutionV1'}
    @{path='releases/migrations/MIR4-M41-F2D-F200-Runtime-Replay-Authority-EvolutionV1.json';kind='MIR4M41F2DTargetRuntimeReplayAuthorityEvolutionV1'}
  )
  foreach ($target in $lowerTargetReceiptPaths.Keys) {
    if ($lowerTargetReceiptPresence[$target]) {
      $evolutionLinks += @{
        path = [string]$lowerTargetReceiptPaths[$target]
        kind = 'MIR4M41F2DTargetRuntimeReplayAuthorityEvolutionV1'
      }
    }
  }
  if ($aggregateReceiptPresent) {
    $evolutionLinks += @{path=$aggregateReceiptPath;kind='MIR4M41F2DFourTargetRuntimeReplayAggregateV1'}
  }
  foreach ($link in $evolutionLinks) {
    $evolution = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $link.path -Kind $link.kind
    if ([string]$evolution.predecessor_receipt.path -cne $priorReceiptPath -or
        [string]$evolution.predecessor_receipt.sha256 -cne $priorReceiptSha256) {
      throw "[mir4-prefreeze-evolution-predecessor] $($link.path)"
    }
    $evolvedPaths = @{}
    foreach ($binding in @($evolution.evolved_bindings)) {
      $path = [string]$binding.path
      $allowedPackageVisibleSuccessor = [string]$evolution.kind -ceq 'MIR4PostReleasePackageBaselineAuthorityEvolutionReceiptV1' -and
        $path -ceq 'README.md' -and [bool]$binding.package_visible
      if (-not $authorityHashes.ContainsKey($path) -or [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          ([bool]$binding.package_visible -and -not $allowedPackageVisibleSuccessor) -or [bool]$binding.release_authority -or $evolvedPaths.ContainsKey($path)) {
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
      $authorityHashModes[$path] = $(if($binding.PSObject.Properties.Name-contains'hash_mode'){[string]$binding.hash_mode}else{'raw-bytes'})
    }
    if ($evolution.PSObject.Properties.Name -contains 'retired_bindings') {
      if ([string]$evolution.kind -cne 'MIR4PostReleaseAutomationAuthorityCutoverV1') { throw "[mir4-prefreeze-retired-binding-kind] $($link.path)" }
      $retiredPaths = @{}
      foreach ($binding in @($evolution.retired_bindings)) {
        $path = [string]$binding.path
        if (-not $authorityHashes.ContainsKey($path) -or
            [string]$authorityHashes[$path] -cne [string]$binding.historical_sha256 -or
            $retiredPaths.ContainsKey($path)) {
          throw "[mir4-prefreeze-retired-binding] $path"
        }
        [void]$authorityHashes.Remove($path)
        [void]$authorityHashModes.Remove($path)
        $retiredPaths[$path] = $true
      }
    }
    foreach ($property in $evolution.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-evolution-transition] $($link.path):$($property.Name)" }
    }
    $priorReceiptPath = [string]$link.path
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $f2eReceiptPath = 'releases/migrations/MIR4-M41-F2E-Package-Authority-CutoverV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $f2eReceiptPath) -PathType Leaf) {
    $f2e = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $f2eReceiptPath -Kind 'MIR4M41F2EPackageAuthorityCutoverV1'
    if ([string]$f2e.predecessor_receipt.path -cne $priorReceiptPath -or
        [string]$f2e.predecessor_receipt.sha256 -cne $priorReceiptSha256) {
      throw '[mir4-prefreeze-f2e-predecessor]'
    }
    $supersededPaths = @{}
    foreach ($binding in @($f2e.superseded_pre_cutover_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path) -or
          [string]$authorityHashes[$path] -cne [string]$binding.historical_sha256 -or
          [string]$binding.hash_mode -cne [string]$authorityHashModes[$path] -or
          $supersededPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-f2e-superseded-binding] $path"
      }
      [void]$authorityHashes.Remove($path)
      [void]$authorityHashModes.Remove($path)
      $supersededPaths[$path] = $true
    }
    if (-not [bool]$f2e.transition_gate.package_cutover -or
        -not [bool]$f2e.transition_gate.old_writer_retirement -or
        @($f2e.transition_gate.PSObject.Properties | Where-Object {
          $_.Name -notin @('package_cutover','old_writer_retirement') -and [bool]$_.Value
        }).Count -ne 0) {
      throw '[mir4-prefreeze-f2e-transition-boundary]'
    }
    $priorReceiptPath = $f2eReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $documentationReceiptPath = 'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $documentationReceiptPath) -PathType Leaf) {
    $documentation = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $documentationReceiptPath -Kind 'MIR4M4105BDocumentationCutoverV1'
    if ([string]$documentation.predecessor_receipt.path -cne $priorReceiptPath -or
        [string]$documentation.predecessor_receipt.sha256 -cne $priorReceiptSha256) {
      throw '[mir4-prefreeze-m41-05b-predecessor]'
    }
    $evolvedPaths = @{}
    foreach ($binding in @($documentation.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path) -or
          [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m41-05b-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $evolvedPaths[$path] = $true
    }
    foreach ($binding in @($documentation.current_authorities)) {
      $path = [string]$binding.path
      if ($authorityHashes.ContainsKey($path) -and
          [string]$authorityHashes[$path] -cne [string]$binding.sha256 -and
          -not $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m41-05b-current-authority-evolution-missing] $path"
      }
      if ([bool]$binding.package_visible -or [bool]$binding.release_authority) {
        throw "[mir4-prefreeze-m41-05b-current-authority-boundary] $path"
      }
      $authorityHashes[$path] = [string]$binding.sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
    }
    foreach ($property in $documentation.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m41-05b-transition] $($property.Name)" }
    }
    $priorReceiptPath = $documentationReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $cliReleaseReceiptPath = 'releases/migrations/MIR4-M42-01A-CLI-Release-ConvergenceV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $cliReleaseReceiptPath) -PathType Leaf) {
    $cliRelease = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $cliReleaseReceiptPath -Kind 'MIR4M4201ACliReleaseConvergenceV1'
    if ([string]$cliRelease.predecessor_receipt.path -cne $priorReceiptPath -or
        [string]$cliRelease.predecessor_receipt.sha256 -cne $priorReceiptSha256) {
      throw '[mir4-prefreeze-m42-01a-predecessor]'
    }
    $evolvedPaths = @{}
    foreach ($binding in @($cliRelease.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path) -or
          [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-01a-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $evolvedPaths[$path] = $true
    }
    foreach ($binding in @($cliRelease.current_authorities)) {
      $path = [string]$binding.path
      if ($authorityHashes.ContainsKey($path) -and
          [string]$authorityHashes[$path] -cne [string]$binding.sha256 -and
          -not $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-01a-current-authority-evolution-missing] $path"
      }
      if ([bool]$binding.package_visible -or [bool]$binding.release_authority) {
        throw "[mir4-prefreeze-m42-01a-current-authority-boundary] $path"
      }
      $authorityHashes[$path] = [string]$binding.sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
    }
    if (-not [bool]$cliRelease.invariants.one_public_cli -or
        -not [bool]$cliRelease.invariants.one_command_route_per_key -or
        -not [bool]$cliRelease.invariants.one_release_application_dag -or
        -not [bool]$cliRelease.invariants.publisher_cannot_build) {
      throw '[mir4-prefreeze-m42-01a-invariants]'
    }
    foreach ($property in $cliRelease.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-01a-transition] $($property.Name)" }
    }
    $priorReceiptPath = $cliReleaseReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $testWorkflowReceiptPath = 'releases/migrations/MIR4-M42-01B-Test-Workflow-ConvergenceV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $testWorkflowReceiptPath) -PathType Leaf) {
    $testWorkflow = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $testWorkflowReceiptPath -Kind 'MIR4M4201BTestWorkflowConvergenceV1'
    if ([string]$testWorkflow.predecessor_receipt.path -cne $priorReceiptPath -or
        [string]$testWorkflow.predecessor_receipt.sha256 -cne $priorReceiptSha256) {
      throw '[mir4-prefreeze-m42-01b-predecessor]'
    }
    foreach ($binding in @($testWorkflow.evolved_bindings)) {
      $path = [string]$binding.path
      if (($authorityHashes.ContainsKey($path) -and [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256) -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority) {
        throw "[mir4-prefreeze-m42-01b-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
    }
    foreach ($binding in @($testWorkflow.projection_bindings)) {
      $path = [string]$binding.path
      if ($authorityHashes.ContainsKey($path) -and [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256) {
        throw "[mir4-prefreeze-m42-01b-projection-binding] $path"
      }
      if ([bool]$binding.package_visible -or [bool]$binding.release_authority) { throw "[mir4-prefreeze-m42-01b-projection-boundary] $path" }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
    }
    foreach ($binding in @($testWorkflow.relocated_bindings)) {
      $fromPath = [string]$binding.from_path
      $toPath = [string]$binding.to_path
      if ($fromPath -notmatch '^validation/tests/.+\.ps1$' -or $toPath -notmatch '^tests/.+\.ps1$' -or
          (Test-Path -LiteralPath (Join-Path $repo $fromPath)) -or
          -not (Test-Path -LiteralPath (Join-Path $repo $toPath) -PathType Leaf) -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority) {
        throw "[mir4-prefreeze-m42-01b-relocation] $fromPath"
      }
      if ($authorityHashes.ContainsKey($fromPath)) {
        [void]$authorityHashes.Remove($fromPath)
        [void]$authorityHashModes.Remove($fromPath)
      }
      $authorityHashes[$toPath] = [string]$binding.current_sha256
      $authorityHashModes[$toPath] = [string]$binding.hash_mode
    }
    foreach ($binding in @($testWorkflow.current_authorities)) {
      $path = [string]$binding.path
      if ($authorityHashes.ContainsKey($path) -and [string]$authorityHashes[$path] -cne [string]$binding.sha256) {
        throw "[mir4-prefreeze-m42-01b-current-authority-evolution-missing] $path"
      }
      if ([bool]$binding.package_visible -or [bool]$binding.release_authority) { throw "[mir4-prefreeze-m42-01b-current-authority-boundary] $path" }
      $authorityHashes[$path] = [string]$binding.sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
    }
    if (@($testWorkflow.invariants.PSObject.Properties | Where-Object { -not [bool]$_.Value }).Count -ne 0) { throw '[mir4-prefreeze-m42-01b-invariants]' }
    foreach ($property in $testWorkflow.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-01b-transition] $($property.Name)" }
    }
    $priorReceiptPath = $testWorkflowReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $compilationPlanReceiptPath = 'releases/migrations/MIR4-M42-02-Compilation-Plan-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $compilationPlanReceiptPath) -PathType Leaf) {
    $compilationPlan = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $compilationPlanReceiptPath -Kind 'MIR4M4202CompilationPlanDecompositionV1'
    if ([string]$compilationPlan.predecessor.receipt -cne $priorReceiptPath -or
        [string]$compilationPlan.predecessor.receipt_sha256 -cne $priorReceiptSha256) {
      throw '[mir4-prefreeze-m42-02-predecessor]'
    }
    $evolvedPaths = @{}
    foreach ($binding in @($compilationPlan.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path) -or
          [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $evolvedPaths[$path] = $true
    }
    if ($evolvedPaths.Count -ne 8 -or
        [string]$compilationPlan.responsibility -cne 'compilation-plan' -or
        [string]$compilationPlan.status -cne 'M42-02-L1-COMPILATION-PLAN-DECOMPOSED') {
      throw '[mir4-prefreeze-m42-02-scope]'
    }
    $currentPaths = @{}
    foreach ($binding in @($compilationPlan.current_authorities)) {
      $path = [string]$binding.path
      if ($authorityHashes.ContainsKey($path) -and
          [string]$authorityHashes[$path] -cne [string]$binding.sha256 -and
          -not $evolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-current-authority-evolution-missing] $path"
      }
      if ([bool]$binding.package_visible -or [bool]$binding.release_authority -or $currentPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-current-authority-boundary] $path"
      }
      $authorityHashes[$path] = [string]$binding.sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $currentPaths[$path] = $true
    }
    if ($currentPaths.Count -ne 2) { throw '[mir4-prefreeze-m42-02-current-authority-count]' }
    foreach ($property in $compilationPlan.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-transition] $($property.Name)" }
    }
    $priorReceiptPath = $compilationPlanReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $baseContinuationsReceiptPath = 'releases/migrations/MIR4-M42-02-Base-Continuations-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $baseContinuationsReceiptPath) -PathType Leaf) {
    $baseContinuations = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $baseContinuationsReceiptPath -Kind 'MIR4M4202BaseContinuationsDecompositionV1'
    if ([string]$baseContinuations.predecessor.receipt -cne $priorReceiptPath -or
        [string]$baseContinuations.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$baseContinuations.predecessor.record_sha256 -cne [string]$compilationPlan.record_sha256 -or
        [string]$baseContinuations.predecessor.package_source_sha256 -cne [string]$compilationPlan.package_authority.package_source_sha256) {
      throw '[mir4-prefreeze-m42-02-l2-predecessor]'
    }
    $baseContinuationEvolvedPaths = @{}
    foreach ($binding in @($baseContinuations.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path) -or
          [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $baseContinuationEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-l2-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $baseContinuationEvolvedPaths[$path] = $true
    }
    if ($baseContinuationEvolvedPaths.Count -ne 6 -or
        [string]$baseContinuations.responsibility -cne 'base-continuations' -or
        [string]$baseContinuations.status -cne 'M42-02-L2-BASE-CONTINUATIONS-DECOMPOSED') {
      throw '[mir4-prefreeze-m42-02-l2-scope]'
    }
    foreach ($property in $baseContinuations.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-l2-transition] $($property.Name)" }
    }
    $priorReceiptPath = $baseContinuationsReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $streamCompilerReceiptPath = 'releases/migrations/MIR4-M42-02-Stream-Compiler-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $streamCompilerReceiptPath) -PathType Leaf) {
    $streamCompiler = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $streamCompilerReceiptPath -Kind 'MIR4M4202StreamCompilerDecompositionV1'
    if ([string]$streamCompiler.predecessor.receipt -cne $priorReceiptPath -or
        [string]$streamCompiler.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$streamCompiler.predecessor.record_sha256 -cne [string]$baseContinuations.record_sha256 -or
        [string]$streamCompiler.predecessor.package_source_sha256 -cne [string]$baseContinuations.package_authority.package_source_sha256) {
      throw '[mir4-prefreeze-m42-02-l3-predecessor]'
    }
    $streamCompilerEvolvedPaths = @{}
    $streamCompilerEnrollmentBaselines = @{
      'spec/schemas/mir4-package-source-manifest-v1.schema.json' = 'A8B04D8ADE76EF2718F88EF7E0B47ABA4B3699377B8FB054C99C43BA1C4358E8'
      'tests/repository/Test-MIR4RepositoryFixedPoint.ps1' = 'B3A535D84A910E776F4F76F5D1DB3E97381EED817A439AF90C7D2AF16BF92254'
    }
    foreach ($binding in @($streamCompiler.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $streamCompilerEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$streamCompilerEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-l3-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if (-not $authorityHashes.ContainsKey($path) -or
          [string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $streamCompilerEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-l3-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $streamCompilerEvolvedPaths[$path] = $true
    }
    if ($streamCompilerEvolvedPaths.Count -ne 12 -or
        [string]$streamCompiler.responsibility -cne 'stream-compiler' -or
        [string]$streamCompiler.status -cne 'M42-02-L3-STREAM-COMPILER-DECOMPOSED') {
      throw '[mir4-prefreeze-m42-02-l3-scope]'
    }
    foreach ($property in $streamCompiler.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-l3-transition] $($property.Name)" }
    }
    $priorReceiptPath = $streamCompilerReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $technologyCatalogReceiptPath = 'releases/migrations/MIR4-M42-02-Technology-Catalog-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $technologyCatalogReceiptPath) -PathType Leaf) {
    $technologyCatalog = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $technologyCatalogReceiptPath -Kind 'MIR4M4202TechnologyCatalogDecompositionV1'
    if ([string]$technologyCatalog.predecessor.receipt -cne $priorReceiptPath -or
        [string]$technologyCatalog.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$technologyCatalog.predecessor.record_sha256 -cne [string]$streamCompiler.record_sha256 -or
        [string]$technologyCatalog.predecessor.package_source_sha256 -cne [string]$streamCompiler.package_authority.package_source_sha256) {
      throw '[mir4-prefreeze-m42-02-l4-predecessor]'
    }
    $technologyCatalogEvolvedPaths = @{}
    $technologyCatalogEnrollmentBaselines = @{
      'tests/compiler/Test-MIR4CompilationPlanDecompositionM4202.ps1' = 'A5326EA3FBE5941AD0FE86934306EC7267F8ABC25079235DBFE8349C845A03B5'
      'tests/compiler/Test-MIR4BaseContinuationsDecompositionM4202.ps1' = 'C933AF6E213C5ABCF482FFF2CFC6375A053A7ADACA8847F98CF4E8AD50E870EF'
      'tests/compiler/Test-MIR4StreamCompilerDecompositionM4202.ps1' = '1D74336F21F11F6CBD1A11660615621993E75A9F1E98B421C271335502B5071D'
    }
    foreach ($binding in @($technologyCatalog.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $technologyCatalogEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$technologyCatalogEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-l4-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $technologyCatalogEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-l4-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $technologyCatalogEvolvedPaths[$path] = $true
    }
    if ($technologyCatalogEvolvedPaths.Count -ne 14 -or
        [string]$technologyCatalog.responsibility -cne 'technology-catalog' -or
        [string]$technologyCatalog.status -cne 'M42-02-L4-TECHNOLOGY-CATALOG-DECOMPOSED') {
      throw '[mir4-prefreeze-m42-02-l4-scope]'
    }
    foreach ($property in $technologyCatalog.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-l4-transition] $($property.Name)" }
    }
    $priorReceiptPath = $technologyCatalogReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $effectOwnershipReceiptPath = 'releases/migrations/MIR4-M42-02-Effect-Ownership-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $effectOwnershipReceiptPath) -PathType Leaf) {
    $effectOwnership = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $effectOwnershipReceiptPath -Kind 'MIR4M4202EffectOwnershipDecompositionV1'
    if ([string]$effectOwnership.predecessor.receipt -cne $priorReceiptPath -or
        [string]$effectOwnership.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$effectOwnership.predecessor.record_sha256 -cne [string]$technologyCatalog.record_sha256 -or
        [string]$effectOwnership.predecessor.package_source_sha256 -cne [string]$technologyCatalog.package_authority.package_source_sha256) {
      throw '[mir4-prefreeze-m42-02-l5-predecessor]'
    }
    $effectOwnershipEvolvedPaths = @{}
    $effectOwnershipEnrollmentBaselines = @{
      'tests/compiler/Test-MIR4TechnologyCatalogDecompositionM4202.ps1' = '5177840DC386C2075D96F7A86EC679874E091001273C1F3211B81A1334428902'
    }
    foreach ($binding in @($effectOwnership.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $effectOwnershipEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$effectOwnershipEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-l5-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $effectOwnershipEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-l5-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $effectOwnershipEvolvedPaths[$path] = $true
    }
    if ($effectOwnershipEvolvedPaths.Count -ne 15 -or
        [string]$effectOwnership.responsibility -cne 'effect-ownership' -or
        [string]$effectOwnership.status -cne 'M42-02-L5-EFFECT-OWNERSHIP-DECOMPOSED') {
      throw '[mir4-prefreeze-m42-02-l5-scope]'
    }
    foreach ($property in $effectOwnership.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-l5-transition] $($property.Name)" }
    }
    $priorReceiptPath = $effectOwnershipReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $compilerOrchestratorReceiptPath = 'releases/migrations/MIR4-M42-02-Compiler-Orchestrator-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $compilerOrchestratorReceiptPath) -PathType Leaf) {
    $compilerOrchestrator = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $compilerOrchestratorReceiptPath -Kind 'MIR4M4202CompilerOrchestratorDecompositionV1'
    if ([string]$compilerOrchestrator.predecessor.receipt -cne $priorReceiptPath -or
        [string]$compilerOrchestrator.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$compilerOrchestrator.predecessor.record_sha256 -cne [string]$effectOwnership.record_sha256 -or
        [string]$compilerOrchestrator.predecessor.package_source_sha256 -cne [string]$effectOwnership.package_authority.package_source_sha256) {
      throw '[mir4-prefreeze-m42-02-l6-predecessor]'
    }
    $compilerOrchestratorEvolvedPaths = @{}
    $compilerOrchestratorEnrollmentBaselines = @{
      'tests/compiler/Test-MIR4EffectOwnershipDecompositionM4202.ps1' = 'E761F5D6F931A3F9FECCEB34DAA979D5630CA1804659F46C210A7371CEFE7808'
    }
    foreach ($binding in @($compilerOrchestrator.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $compilerOrchestratorEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$compilerOrchestratorEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-l6-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $compilerOrchestratorEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-l6-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $compilerOrchestratorEvolvedPaths[$path] = $true
    }
    if ($compilerOrchestratorEvolvedPaths.Count -ne 16 -or
        [string]$compilerOrchestrator.responsibility -cne 'compiler-orchestrator' -or
        [string]$compilerOrchestrator.status -cne 'M42-02-L6-COMPILER-ORCHESTRATOR-DECOMPOSED') {
      throw '[mir4-prefreeze-m42-02-l6-scope]'
    }
    foreach ($property in $compilerOrchestrator.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-l6-transition] $($property.Name)" }
    }
    $priorReceiptPath = $compilerOrchestratorReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $powerShellCharacterizationReceiptPath = 'releases/migrations/MIR4-M42-02-PowerShell-CharacterizationV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $powerShellCharacterizationReceiptPath) -PathType Leaf) {
    $powerShellCharacterization = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $powerShellCharacterizationReceiptPath -Kind 'MIR4M4202PowerShellCharacterizationV1'
    if ([string]$powerShellCharacterization.predecessor.receipt -cne $priorReceiptPath -or
        [string]$powerShellCharacterization.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$powerShellCharacterization.predecessor.record_sha256 -cne [string]$compilerOrchestrator.record_sha256) {
      throw '[mir4-prefreeze-m42-02-powershell-characterization-predecessor]'
    }
    $powerShellCharacterizationPaths = @{}
    foreach ($binding in @($powerShellCharacterization.authority_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path) -or
          [string]$binding.hash_mode -cne 'canonical-text-v1' -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or
          $powerShellCharacterizationPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-powershell-characterization-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.sha256
      $powerShellCharacterizationPaths[$path] = $true
    }
    if ($powerShellCharacterizationPaths.Count -ne 12 -or
        [string]$powerShellCharacterization.status -cne 'M42-02-RESIDUAL-POWERSHELL-CHARACTERIZED' -or
        [string]$powerShellCharacterization.next_fixed_point -cne 'M42-02-PS1-COMMAND-ROUTER') {
      throw '[mir4-prefreeze-m42-02-powershell-characterization-scope]'
    }
    foreach ($property in $powerShellCharacterization.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-powershell-characterization-transition] $($property.Name)" }
    }
    $priorReceiptPath = $powerShellCharacterizationReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $commandRouterReceiptPath = 'releases/migrations/MIR4-M42-02-PowerShell-Command-Router-DecompositionV1.json'
  if (Test-Path -LiteralPath (Join-Path $repo $commandRouterReceiptPath) -PathType Leaf) {
    if (-not (Get-Command Get-MIR4CanonicalPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
      . (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
    }
    $commandRouter = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath $commandRouterReceiptPath -Kind 'MIR4M4202PowerShellCommandRouterDecompositionV1'
    if ([string]$commandRouter.predecessor.receipt -cne $priorReceiptPath -or
        [string]$commandRouter.predecessor.receipt_sha256 -cne $priorReceiptSha256 -or
        [string]$commandRouter.predecessor.record_sha256 -cne [string]$powerShellCharacterization.record_sha256) {
      throw '[mir4-prefreeze-m42-02-command-router-predecessor]'
    }
    $commandRouterEnrollmentBaselines = @{
      'contracts/repository/mir4-command-inventory-v1.schema.json'='790EE7D6CA662D8A4E7A51DEEEBC6BF9A14754D4FF828204DFE8DACA034BF099'
      'docs/architecture/module-boundaries.md'='24D5CB06F955FC6189D5CA02B4B0769547F16069D20692B4D7F909AB07824F6F'
      'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1'='5BE01F0320FDC1074CD7524B951CE5D56C624AF4BAE07C77362B9444483CD2AD'
      'tests/tooling/Test-MIRAssurance.ps1'='7E6C860FB364052EF0ED8852D8DF2AAB9131DFBEB6A23CB45E43BB3A86403603'
      'tests/tooling/Test-MIR4CliReleaseConvergence.ps1'='FECB62355A5E37EA3CA33F9D52F3B36F99BD01011FA7E7C0E341156479BB101A'
      'tools/mir/application/repository/RepositoryFixedPoint.ps1'='E33A3D0761FE92D03CC32000A033FF5C3C70FE7802982E796FBB2933B84F42C9'
      'tools/mir/application/tooling/CommandInventory.ps1'='B29A081BC21EC057B22D3A1E61946D3BA7BBC5DCFA5D14B973E9A94D895DD01E'
      'tools/mir/cli/Invoke-MIRCommandRouter.ps1'='AA50E7DF8CD41C756B3270A47A23E13F4F8B911F9ED89B05813D4B99376E7E25'
    }
    $commandRouterEvolvedPaths = @{}
    foreach ($binding in @($commandRouter.evolved_bindings)) {
      $path = [string]$binding.path
      if (-not $authorityHashes.ContainsKey($path)) {
        if (-not $commandRouterEnrollmentBaselines.ContainsKey($path) -or
            [string]$binding.previous_sha256 -cne [string]$commandRouterEnrollmentBaselines[$path] -or
            [string]$binding.hash_mode -cne 'canonical-text-v1') {
          throw "[mir4-prefreeze-m42-02-command-router-enrollment-binding] $path"
        }
        $authorityHashes[$path] = [string]$binding.previous_sha256
        $authorityHashModes[$path] = [string]$binding.hash_mode
      }
      if ([string]$authorityHashes[$path] -cne [string]$binding.previous_sha256 -or
          [string]$authorityHashModes[$path] -cne [string]$binding.hash_mode -or
          [bool]$binding.package_visible -or [bool]$binding.release_authority -or
          $commandRouterEvolvedPaths.ContainsKey($path)) {
        throw "[mir4-prefreeze-m42-02-command-router-evolved-binding] $path"
      }
      $authorityHashes[$path] = [string]$binding.current_sha256
      $authorityHashModes[$path] = [string]$binding.hash_mode
      $commandRouterEvolvedPaths[$path] = $true
    }
    if ($commandRouterEvolvedPaths.Count -ne 17 -or
        [string]$commandRouter.status -cne 'M42-02-PS1-COMMAND-ROUTER-DECOMPOSED' -or
        [string]$commandRouter.decomposition.responsibility -cne 'command-router' -or
        [string]$commandRouter.next_fixed_point -cne 'M42-02-PS2-VALIDATION-RUNNER' -or
        @($commandRouter.decomposition.modules).Count -ne 12 -or
        -not [bool]$commandRouter.public_contract.unchanged -or
        [int]$commandRouter.public_contract.command_count -ne 85 -or
        [string]$commandRouter.preservation.package_source_sha256 -cne (Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo)) {
      throw '[mir4-prefreeze-m42-02-command-router-scope]'
    }
    foreach ($property in $commandRouter.transition_gate.PSObject.Properties) {
      if ([bool]$property.Value) { throw "[mir4-prefreeze-m42-02-command-router-transition] $($property.Name)" }
    }
    $priorReceiptPath = $commandRouterReceiptPath
    $priorReceiptSha256 = Get-MIR4PreFreezeFileSha256 (Join-Path $repo $priorReceiptPath)
  }
  $staleAuthorityBindings = @()
  foreach ($binding in $authorityHashes.GetEnumerator()) {
    $full = Join-Path $repo ([string]$binding.Key)
    $hashMode = if($authorityHashModes.ContainsKey([string]$binding.Key)){[string]$authorityHashModes[[string]$binding.Key]}else{'raw-bytes'}
    if (-not (Test-Path -LiteralPath $full -PathType Leaf) -or
        (Get-MIR4PreFreezeFileSha256 -Path $full -Mode $hashMode) -cne [string]$binding.Value) {
      $currentBindingSha256 = if (Test-Path -LiteralPath $full -PathType Leaf) {
        Get-MIR4PreFreezeFileSha256 -Path $full -Mode $hashMode
      } else {
        'ABSENT'
      }
      $staleAuthorityBindings += "$([string]$binding.Key)|$([string]$binding.Value)|$currentBindingSha256|$hashMode"
    }
  }
  if ($staleAuthorityBindings.Count -ne 0) {
    throw "[mir4-prefreeze-current-authority-binding] $(@($staleAuthorityBindings | Sort-Object) -join ',')"
  }
  $review = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-PR152-Independent-Readiness-Acceptance-LUNAV1.json' -Kind 'MIR4IndependentReadinessAcceptanceLunaV1'
  if ([string]$review.verdict -cne 'ACCEPTED-RELEASE-READINESS' -or [bool]$review.maintainer_acceptance) {
    throw '[mir4-prefreeze-independent-review]'
  }
  $t15Review = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-T15-Independent-Machine-AcceptanceV1.json' -Kind 'MIR4T15IndependentMachineAcceptanceV1'
  if ([string]$t15Review.verdict -cne 'ACCEPTED-T15-MACHINE-SCOPE' -or
      [bool]$t15Review.reviewer.human_reviewer_claimed -or
      [bool]$t15Review.reviewer.human_acceptance_inferred -or
      [bool]$t15Review.release_authority) {
    throw '[mir4-prefreeze-t15-independent-machine-review]'
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

function Get-MIR4PlaytestFileDescriptor {
  param([Parameter(Mandatory)][string]$Path)
  $item = Get-Item -LiteralPath $Path
  return [ordered]@{path=$item.FullName;bytes=$item.Length;sha256=(Get-MIR4PreFreezeFileSha256 $item.FullName)}
}

function Write-MIR4PlaytestJson {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value)
  [IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 100)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
}

function Assert-MIR4PlaytestEvidenceV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Record)
  $schema = Join-Path (Get-MIR4PreFreezeRepoRoot $RepoRoot) 'spec/schemas/mir4-playtest-evidence-v1.schema.json'
  if (-not (Test-Path -LiteralPath $schema -PathType Leaf)) { throw '[mir4-playtest-evidence-schema-missing]' }
  $json = $Record | ConvertTo-Json -Depth 100
  if (-not ($json | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)) {
    throw "[mir4-playtest-evidence-schema] $($Record.kind)"
  }
  return $true
}

function Get-MIR4PlaytestScenarioContract {
  param([Parameter(Mandatory)][ValidateSet('F210','F200')][string]$Target)
  $rows = if ($Target -ceq 'F210') {
    @(
      @{id='fresh-load';expected='A new default-settings game loads with the exact F210 development package.'},
      @{id='direct-upgrade-3.2.11';expected='A representative 3.2.11 save upgrades directly to the exact F210 development package.'},
      @{id='reload-1';expected='The upgraded F210 save reloads once without identity, state, or graph drift.'},
      @{id='reload-2';expected='The same F210 save reloads a second time without identity, state, or graph drift.'},
      @{id='maximum-level-states';expected='Maximum-level and continuation states match the F210 target contract.'},
      @{id='research-progress-and-queue';expected='Current research, fractional progress, and queued research survive upgrade and reload.'},
      @{id='production-route-policy';expected='Production-route selection matches the admitted F210 policy.'},
      @{id='cubium-canary';expected='The bounded Cubium compatibility canary matches its exact expected state.'},
      @{id='corrundum-canary';expected='The bounded Corrundum compatibility canary matches its exact expected state.'},
      @{id='recycler-canary';expected='The bounded Recycler compatibility canary matches its exact expected state.'},
      @{id='bounded-k2';expected='The exact bounded F210 Krastorio 2 scenario matches its target-bound claim.'},
      @{id='bounded-k2so';expected='The exact bounded F210 K2SO scenario matches its target-bound claim.'},
      @{id='settings-runtime-presentation-diagnostics';expected='Settings, runtime behavior, UI presentation, locales, and diagnostics match the F210 handoff.'}
    )
  } else {
    @(
      @{id='fresh-load';expected='A new default-settings game loads with the exact F200 development package.'},
      @{id='direct-upgrade-2.5.11';expected='A representative 2.5.11 save upgrades directly to the exact F200 development package.'},
      @{id='reload-1';expected='The upgraded F200 save reloads once without identity, state, or graph drift.'},
      @{id='reload-2';expected='The same F200 save reloads a second time without identity, state, or graph drift.'},
      @{id='target-appropriate-maximum-level';expected='Maximum-level behavior matches the F200 target contract and its finite omissions.'},
      @{id='research-progress-and-queue';expected='Current research, fractional progress, and queued research survive upgrade and reload.'},
      @{id='route-policy';expected='Production-route selection matches the admitted F200 policy.'},
      @{id='bounded-f200-k2';expected='The exact bounded F200 Krastorio 2 scenario matches its target-bound claim.'},
      @{id='bounded-f200-k2so';expected='The exact bounded F200 K2SO scenario matches its target-bound claim.'},
      @{id='explicit-target-omissions';expected='F210-only capabilities remain absent exactly where the F200 profile requires omission.'},
      @{id='settings-runtime-presentation-diagnostics';expected='Settings, runtime behavior, UI presentation, locales, and diagnostics match the F200 handoff.'}
    )
  }
  return @($rows | ForEach-Object { [pscustomobject][ordered]@{id=[string]$_.id;expected=[string]$_.expected} })
}

function Get-MIR4PlaytestLauncherText {
  return @'
param(
  [ValidateSet('Candidate','Predecessor')][string]$Package = 'Candidate',
  [string]$SavePath = '',
  [string]$CaptureLabel = ''
)

$ErrorActionPreference = 'Stop'
$sessionPath = Join-Path $PSScriptRoot 'session.json'
$session = Get-Content -Raw -LiteralPath $sessionPath | ConvertFrom-Json -Depth 100
function Get-LauncherSha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
$enginePath = [string]$session.engine.path
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf) -or (Get-LauncherSha256 $enginePath) -cne [string]$session.engine.sha256) {
  throw '[mir4-playtest-launcher-engine-hash]'
}
$selected = if ($Package -ceq 'Candidate') { $session.candidate } else { $session.predecessor }
if (-not (Test-Path -LiteralPath ([string]$selected.path) -PathType Leaf) -or (Get-LauncherSha256 ([string]$selected.path)) -cne [string]$selected.sha256) {
  throw '[mir4-playtest-launcher-package-hash]'
}
$mods = [string]$session.profile.mods
$stagedName = [IO.Path]::GetFileName([string]$selected.path)
foreach ($item in @(Get-ChildItem -LiteralPath $mods -Filter 'more-infinite-research_*.zip' -File -ErrorAction SilentlyContinue)) {
  Remove-Item -LiteralPath $item.FullName -Force
}
Copy-Item -LiteralPath ([string]$selected.path) -Destination (Join-Path $mods $stagedName)
$arguments = @('--config',[string]$session.profile.config,'--no-log-rotation','--mod-directory',$mods)
if (-not [string]::IsNullOrWhiteSpace($SavePath)) {
  $resolvedSave = (Resolve-Path -LiteralPath $SavePath -ErrorAction Stop).Path
  $arguments += @('--load-game',$resolvedSave)
}
& $enginePath @arguments
$exitCode = $LASTEXITCODE
$logPath = Join-Path ([string]$session.profile.userdata) 'factorio-current.log'
if (Test-Path -LiteralPath $logPath -PathType Leaf) {
  if ([string]::IsNullOrWhiteSpace($CaptureLabel)) { $CaptureLabel = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') }
  if ($CaptureLabel -notmatch '^[A-Za-z0-9._-]+$') { throw '[mir4-playtest-launcher-capture-label]' }
  $captureLog = Join-Path ([string]$session.profile.capture_queue) ('logs/' + $CaptureLabel + '-factorio-current.log')
  New-Item -ItemType Directory -Path (Split-Path -Parent $captureLog) -Force | Out-Null
  if (Test-Path -LiteralPath $captureLog) { throw '[mir4-playtest-launcher-capture-exists]' }
  Copy-Item -LiteralPath $logPath -Destination $captureLog
}
if ($exitCode -ne 0) { throw "[mir4-playtest-launcher-exit] $exitCode" }
'@
}

function Get-MIR4PlaytestCaptureKind {
  param([Parameter(Mandatory)][string]$Path,[string]$ObservationsPath='')
  $full = [IO.Path]::GetFullPath($Path)
  if (-not [string]::IsNullOrWhiteSpace($ObservationsPath) -and $full -ceq [IO.Path]::GetFullPath($ObservationsPath)) { return 'observations' }
  $extension = [IO.Path]::GetExtension($full).ToLowerInvariant()
  if ($extension -eq '.log') { return 'factorio-log' }
  if ($extension -eq '.zip') { return 'save' }
  if ($extension -in @('.png','.jpg','.jpeg','.webp')) { return 'screenshot' }
  if ($extension -in @('.md','.txt')) { return 'note' }
  return 'attachment'
}

function Compare-MIR4PlaytestObservations {
  param([Parameter(Mandatory)]$Session,[Parameter(Mandatory)]$Observations)
  if ([string]$Observations.kind -cne 'MIR4PlaytestObservationsV1' -or
      [string]$Observations.target -cne [string]$Session.target -or
      [string]$Observations.candidate_sha256 -cne [string]$Session.candidate.sha256 -or
      [string]$Observations.engine_sha256 -cne [string]$Session.engine.sha256) {
    throw '[mir4-playtest-observations-binding]'
  }
  $expectedIds = @($Session.expected_scenarios | ForEach-Object { [string]$_.id })
  $actualIds = @($Observations.scenarios | ForEach-Object { [string]$_.id })
  if (@($actualIds | Sort-Object -Unique).Count -ne $actualIds.Count -or
      (($expectedIds | Sort-Object) -join '|') -cne (($actualIds | Sort-Object) -join '|')) {
    throw '[mir4-playtest-observations-scenario-set]'
  }
  $allowed = @('PASSED','FAILED','BLOCKED','PENDING')
  foreach ($row in @($Observations.scenarios)) {
    if ([string]$row.status -notin $allowed) { throw "[mir4-playtest-observations-status] $($row.id)" }
  }
  $passed = @($Observations.scenarios | Where-Object { [string]$_.status -ceq 'PASSED' }).Count
  $failed = @($Observations.scenarios | Where-Object { [string]$_.status -ceq 'FAILED' }).Count
  $blocked = @($Observations.scenarios | Where-Object { [string]$_.status -ceq 'BLOCKED' }).Count
  $pending = @($Observations.scenarios | Where-Object { [string]$_.status -ceq 'PENDING' }).Count
  $status = if ($failed -gt 0) { 'MISMATCH' } elseif ($blocked -gt 0 -or $pending -gt 0) { 'INCOMPLETE' } else { 'MATCHED' }
  return [pscustomobject][ordered]@{status=$status;total=$actualIds.Count;passed=$passed;failed=$failed;blocked=$blocked;pending=$pending}
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
  if (-not (Get-Command Get-MIRPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
    . (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
  }
  $plan = Get-MIR4FinalMilePlaytestCandidateAuthorityV1 -RepoRoot $repo
  $t15Path = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json'
  $t15 = Read-MIR4PreFreezeJson -RepoRoot $repo -RelativePath '.mir/releases/waves/mir4-r0/MIR4-T15-Authority-Evolution-ReceiptV1.json' -Kind 'MIR4T15AuthorityEvolutionReceiptV1'
  $f210Resolution = $null
  $f210PolicyPath = Join-Path $repo $script:MIR4F210PolicyRelativePath
  $targetRow = @($plan.targets | Where-Object { [string]$_.target -ceq $Target })
  if ($targetRow.Count -ne 1) { throw "[mir4-playtest-target] $Target" }
  $row = $targetRow[0]
  $packageSourceSha256 = Get-MIRPackageSourceFingerprint -RepoRoot $repo
  if ($packageSourceSha256 -cne [string]$t15.player_package_source_sha256) { throw '[mir4-playtest-package-source-superseded]' }
  if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
    $CandidatePath = Join-Path $repo ("build/results/mir4-sol/sol08/target-candidates/distributions/more-infinite-research_{0}.zip" -f [string]$row.distribution_version)
  }
  if ([string]::IsNullOrWhiteSpace($PredecessorPath)) { $PredecessorPath = Join-Path $repo ([string]$row.predecessor.path) }
  if ($Target -ceq 'F210') {
    $f210Resolution = Get-MIR4F210EngineResolutionV1 -RepoRoot $repo -FactorioBin $FactorioBin
    $FactorioBin = [string]$f210Resolution.engine.path
  } elseif ([string]::IsNullOrWhiteSpace($FactorioBin)) { $FactorioBin = [string]$row.engine.path }
  foreach ($required in @($CandidatePath,$PredecessorPath,$FactorioBin)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "[mir4-playtest-input] $required" }
  }
  $candidate = Get-MIR4PlaytestFileDescriptor $CandidatePath
  $predecessor = Get-MIR4PlaytestFileDescriptor $PredecessorPath
  $engine = Get-MIR4PlaytestFileDescriptor $FactorioBin
  if ([string]$candidate.sha256 -cne [string]$row.development_package.sha256) { throw '[mir4-playtest-candidate-hash]' }
  if ([string]$predecessor.sha256 -cne [string]$row.predecessor.sha256) { throw '[mir4-playtest-predecessor-hash]' }
  $expectedEngineSha256 = if ($Target -ceq 'F210') { [string]$f210Resolution.engine.sha256 } else { [string]$row.engine.sha256 }
  if ([string]$engine.sha256 -cne $expectedEngineSha256) { throw '[mir4-playtest-engine-hash]' }
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
  $profile = Join-Path $output 'profile'
  $mods = Join-Path $profile 'mods'
  $userdata = Join-Path $profile 'userdata'
  $packages = Join-Path $output 'packages'
  $captureQueue = Join-Path $output 'capture-queue'
  $config = Join-Path $profile 'config.ini'
  $launcher = Join-Path $output 'Invoke-MIR4PlaytestEngine.ps1'
  $observationsPath = Join-Path $output 'observations.json'
  $decisionTemplatePath = Join-Path $output 'manual-decision.template.json'
  $planPath = Join-Path $repo $script:MIR4FinalMilePlaytestCandidateAuthorityRelativePath
  $handoffPath = Join-Path $repo 'docs/maintainer/mir4-w09-manual-playtest.md'
  $scenarioContract = @(Get-MIR4PlaytestScenarioContract -Target $Target)
  $record = [pscustomobject][ordered]@{
    schema=1;kind='MIR4PlaytestSessionV1';status=$(if($DryRun){'planned'}else{'prepared'})
    target=$Target;distribution_version=[string]$row.distribution_version;candidate_state='development-pre-freeze-not-release-identity'
    created_at=[DateTime]::UtcNow.ToString('o');session_root=$output
    engine=$engine;candidate=$candidate;predecessor=$predecessor
    authority=[ordered]@{
      development_plan=(Get-MIR4PlaytestFileDescriptor $planPath)
      current_package_authority=(Get-MIR4PlaytestFileDescriptor $t15Path)
      f210_engine_policy=$(if($Target -ceq 'F210'){Get-MIR4PlaytestFileDescriptor $f210PolicyPath}else{$null})
      f210_engine_resolution=$f210Resolution
      manual_handoff=(Get-MIR4PlaytestFileDescriptor $handoffPath)
      source_baseline=$plan.source_baseline
      verification_plan=[ordered]@{profile='mir4-final-mile';assurance=$row.assurance}
      package_source_sha256=$packageSourceSha256
    }
    settings=$(if([string]::IsNullOrWhiteSpace($SettingsPath)){$null}else{Get-MIR4PlaytestFileDescriptor $SettingsPath})
    save_fixture=$(if([string]::IsNullOrWhiteSpace($SavePath)){$null}else{Get-MIR4PlaytestFileDescriptor $SavePath})
    profile=[ordered]@{root=$profile;config=$config;mods=$mods;userdata=$userdata;capture_queue=$captureQueue;default_package='Candidate'}
    engine_command=[ordered]@{launcher=$launcher;base_arguments=@('--config',$config,'--no-log-rotation','--mod-directory',$mods);save_argument='--load-game'}
    expected_scenarios=$scenarioContract
    capture_requirements=@('factorio-log','save','observations','screenshot-or-note')
    observations_template=$observationsPath
    decision_template=$decisionTemplatePath
    decision=$null;decision_inferred=$false;package_visible=$false;production_release_authorized=$false
  }
  if ($DryRun) { Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $record | Out-Null; return $record }
  if (Test-Path -LiteralPath $output) { throw "[mir4-playtest-session-exists] $output" }
  New-Item -ItemType Directory -Path $mods,$userdata,$packages,$captureQueue,(Join-Path $captureQueue 'logs'),(Join-Path $captureQueue 'saves'),(Join-Path $captureQueue 'screenshots'),(Join-Path $captureQueue 'notes') -Force | Out-Null
  $candidateStored = Join-Path $packages ([IO.Path]::GetFileName($CandidatePath))
  $predecessorStored = Join-Path $packages ([IO.Path]::GetFileName($PredecessorPath))
  Copy-Item -LiteralPath $CandidatePath -Destination $candidateStored
  Copy-Item -LiteralPath $PredecessorPath -Destination $predecessorStored
  Copy-Item -LiteralPath $candidateStored -Destination (Join-Path $mods ([IO.Path]::GetFileName($candidateStored)))
  if (-not [string]::IsNullOrWhiteSpace($SettingsPath)) {
    Copy-Item -LiteralPath $SettingsPath -Destination (Join-Path $output ('profile/' + [IO.Path]::GetFileName($SettingsPath)))
  }
  if (-not [string]::IsNullOrWhiteSpace($SavePath)) {
    New-Item -ItemType Directory -Path (Join-Path $output 'profile/saves') -Force | Out-Null
    Copy-Item -LiteralPath $SavePath -Destination (Join-Path $output ('profile/saves/' + [IO.Path]::GetFileName($SavePath)))
  }
  $record.candidate.path = $candidateStored
  $record.predecessor.path = $predecessorStored
  $newline = [Environment]::NewLine
  $configText = @(
    '; Generated by MIR 4 T17 playtest preparation.',$newline,
    '[path]',
    'read-data=__PATH__executable__/../../data',
    ('write-data=' + $userdata.Replace('\','/')),
    '[other]',
    'check-updates=false'
  ) -join $newline
  [IO.File]::WriteAllText($config,$configText+$newline,[Text.UTF8Encoding]::new($false))
  $modList = [ordered]@{mods=@([ordered]@{name='base';enabled=$true},[ordered]@{name='more-infinite-research';enabled=$true})}
  Write-MIR4PlaytestJson -Path (Join-Path $mods 'mod-list.json') -Value $modList
  [IO.File]::WriteAllText($launcher,(Get-MIR4PlaytestLauncherText)+$newline,[Text.UTF8Encoding]::new($false))
  $record.engine_command.launcher_sha256 = Get-MIR4PreFreezeFileSha256 $launcher
  $observations = [ordered]@{
    schema=1;kind='MIR4PlaytestObservationsV1';status='in-progress';target=$Target
    candidate_sha256=[string]$record.candidate.sha256;engine_sha256=[string]$record.engine.sha256
    scenarios=@($scenarioContract | ForEach-Object { [ordered]@{id=[string]$_.id;status='PENDING';notes=''} })
    decision=$null;decision_inferred=$false;production_release_authorized=$false
  }
  Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $observations | Out-Null
  Write-MIR4PlaytestJson -Path $observationsPath -Value $observations
  $decisionTemplate = [ordered]@{
    schema=1;kind='MIR4ManualPlaytestDecisionTemplateV1';valid_evidence=$false;target=$Target
    candidate_sha256=[string]$record.candidate.sha256;engine_sha256=[string]$record.engine.sha256
    allowed_decisions=@('ACCEPTED','CHANGES-REQUESTED','REJECTED')
    instruction='Do not edit this template into evidence. After capture, the maintainer runs tools/mir.ps1 playtest finalize with an explicit decision and reviewer.'
    decision=$null;reviewer=$null;source_freeze_authorized=$false;production_release_authorized=$false
  }
  Write-MIR4PlaytestJson -Path $decisionTemplatePath -Value $decisionTemplate
  Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $record | Out-Null
  Write-MIR4PlaytestJson -Path (Join-Path $output 'session.json') -Value $record
  $checklist = "# MIR 4 $Target manual playtest" + $newline + $newline +
    "Candidate, predecessor, engine, plan, package-source, and handoff identities are locked in session.json. Record observations; do not infer acceptance." + $newline + $newline +
    "Launch the isolated engine with .\Invoke-MIR4PlaytestEngine.ps1 -Package Candidate. Use -Package Predecessor to create or inspect the direct-upgrade source save, then switch back to Candidate and pass -SavePath <save>." + $newline + $newline +
    ((@($scenarioContract) | ForEach-Object { "- [ ] $($_.id): $($_.expected)" }) -join $newline) + $newline + $newline +
    "Place logs, saves, screenshots, and notes below capture-queue, set every observations.json scenario to PASSED, FAILED, or BLOCKED, then run playtest capture. Only the maintainer may run playtest finalize." + $newline
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
  foreach ($locked in @($session.candidate,$session.predecessor,$session.engine,$session.authority.development_plan,$session.authority.current_package_authority,$session.authority.manual_handoff)) {
    if (-not (Test-Path -LiteralPath ([string]$locked.path) -PathType Leaf) -or
        (Get-MIR4PreFreezeFileSha256 ([string]$locked.path)) -cne [string]$locked.sha256) {
      throw "[mir4-playtest-locked-input] $($locked.path)"
    }
  }
  if (-not (Test-Path -LiteralPath ([string]$session.engine_command.launcher) -PathType Leaf) -or
      (Get-MIR4PreFreezeFileSha256 ([string]$session.engine_command.launcher)) -cne [string]$session.engine_command.launcher_sha256) {
    throw '[mir4-playtest-launcher-current]'
  }
  if ([string]::IsNullOrWhiteSpace($ObservationsPath)) { $ObservationsPath = [string]$session.observations_template }
  if (-not (Test-Path -LiteralPath $ObservationsPath -PathType Leaf)) { throw '[mir4-playtest-observations-required]' }
  $observations = Get-Content -Raw -LiteralPath $ObservationsPath | ConvertFrom-Json -Depth 100
  Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $observations | Out-Null
  $comparison = Compare-MIR4PlaytestObservations -Session $session -Observations $observations
  $paths = [Collections.Generic.List[string]]::new()
  foreach ($path in @($CapturePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    $paths.Add([IO.Path]::GetFullPath($path))
  }
  $queueRoot = [string]$session.profile.capture_queue
  if (Test-Path -LiteralPath $queueRoot -PathType Container) {
    foreach ($item in @(Get-ChildItem -LiteralPath $queueRoot -Recurse -File -ErrorAction Stop | Sort-Object FullName)) { $paths.Add($item.FullName) }
  }
  $paths.Add([IO.Path]::GetFullPath($ObservationsPath))
  $paths = @($paths | Sort-Object -Unique)
  foreach ($path in $paths) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-playtest-capture-input] $path" } }
  $sourceRows = @($paths | ForEach-Object {
    $descriptor = Get-MIR4PlaytestFileDescriptor $_
    $descriptor['kind'] = Get-MIR4PlaytestCaptureKind -Path $_ -ObservationsPath $ObservationsPath
    [pscustomobject]$descriptor
  })
  $kinds = @($sourceRows | ForEach-Object { [string]$_.kind })
  $missingRequirements = [Collections.Generic.List[string]]::new()
  foreach ($required in @('factorio-log','save','observations')) { if ($required -notin $kinds) { $missingRequirements.Add($required) } }
  if ('screenshot' -notin $kinds -and 'note' -notin $kinds) { $missingRequirements.Add('screenshot-or-note') }
  $ready = $comparison.status -ceq 'MATCHED' -and $missingRequirements.Count -eq 0
  $receipt = [pscustomobject][ordered]@{
    schema=1;kind='MIR4PlaytestCaptureV1';status=$(if($DryRun){'planned'}elseif($ready){'ready-for-maintainer-decision'}else{'captured-incomplete'})
    target=[string]$session.target;captured_at=[DateTime]::UtcNow.ToString('o')
    candidate_sha256=[string]$session.candidate.sha256;engine_sha256=[string]$session.engine.sha256
    session_sha256=(Get-MIR4PreFreezeFileSha256 $sessionPath)
    files=$sourceRows;observations_supplied=$true;comparison=$comparison
    missing_capture_requirements=@($missingRequirements);result_summary=$null
    decision=$null;decision_inferred=$false;package_visible=$false;production_release_authorized=$false
  }
  Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $receipt | Out-Null
  if ($DryRun) { return $receipt }
  $captureRoot = Join-Path $sessionRootFull 'capture'
  if (Test-Path -LiteralPath (Join-Path $sessionRootFull 'capture.json')) { throw '[mir4-playtest-capture-exists]' }
  New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null
  $usedNames = @{}
  $capturedRows = [Collections.Generic.List[object]]::new()
  foreach ($source in $sourceRows) {
    $name = [IO.Path]::GetFileName([string]$source.path)
    if ($usedNames.ContainsKey($name)) { throw "[mir4-playtest-capture-name-collision] $name" }
    $usedNames[$name] = $true
    $destination = Join-Path $captureRoot $name
    Copy-Item -LiteralPath ([string]$source.path) -Destination $destination
    $descriptor = Get-MIR4PlaytestFileDescriptor $destination
    $descriptor['kind'] = [string]$source.kind
    $capturedRows.Add([pscustomobject]$descriptor)
  }
  $receipt.files = @($capturedRows)
  $summary = [ordered]@{
    schema=1;kind='MIR4PlaytestResultSummaryV1';status=$(if($ready){'ready-for-maintainer-decision'}else{'changes-required-or-incomplete'})
    target=[string]$session.target;candidate_sha256=[string]$session.candidate.sha256;engine_sha256=[string]$session.engine.sha256
    comparison=$comparison;capture_file_count=$capturedRows.Count;capture_kinds=@($capturedRows.kind | Sort-Object -Unique)
    missing_capture_requirements=@($missingRequirements)
    next_action=$(if($ready){'Maintainer reviews the retained evidence and supplies an explicit decision.'}else{'Complete or correct the named scenarios and capture requirements; do not infer acceptance.'})
    decision=$null;decision_inferred=$false;source_freeze_authorized=$false;production_release_authorized=$false
  }
  $summaryPath = Join-Path $sessionRootFull 'result-summary.json'
  Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $summary | Out-Null
  Write-MIR4PlaytestJson -Path $summaryPath -Value $summary
  $receipt.result_summary = Get-MIR4PlaytestFileDescriptor $summaryPath
  Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $receipt | Out-Null
  Write-MIR4PlaytestJson -Path (Join-Path $sessionRootFull 'capture.json') -Value $receipt
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
  if (-not (Get-Command Get-MIRPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
    . (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
  }
  $root = [IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($SessionRoot)){$SessionRoot}else{Join-Path $repo $SessionRoot}))
  $sessionPath = Join-Path $root 'session.json'
  $session = Get-Content -Raw -LiteralPath $sessionPath | ConvertFrom-Json -Depth 100
  if ([string]$session.kind -cne 'MIR4PlaytestSessionV1' -or [bool]$session.decision_inferred -or [bool]$session.production_release_authorized) {
    throw '[mir4-playtest-finalize-session]'
  }
  $planPath = [string]$session.authority.development_plan.path
  if ((Get-MIR4PreFreezeFileSha256 $planPath) -cne [string]$session.authority.development_plan.sha256) { throw '[mir4-playtest-finalize-plan-superseded]' }
  if (-not (Test-Path -LiteralPath ([string]$session.authority.current_package_authority.path) -PathType Leaf) -or
      (Get-MIR4PreFreezeFileSha256 ([string]$session.authority.current_package_authority.path)) -cne [string]$session.authority.current_package_authority.sha256 -or
      (Get-MIRPackageSourceFingerprint -RepoRoot $repo) -cne [string]$session.authority.package_source_sha256) {
    throw '[mir4-playtest-finalize-package-source-superseded]'
  }
  $plan = Get-MIR4FinalMilePlaytestCandidateAuthorityV1 -RepoRoot $repo
  if ([IO.Path]::GetFullPath($planPath) -cne [IO.Path]::GetFullPath((Join-Path $repo $script:MIR4FinalMilePlaytestCandidateAuthorityRelativePath))) {
    throw '[mir4-playtest-finalize-plan-path]'
  }
  $targetRow = @($plan.targets | Where-Object { [string]$_.target -ceq [string]$session.target })
  $expectedEngineSha256 = if ([string]$session.target -ceq 'F210') {
    $resolution = Get-MIR4F210EngineResolutionV1 -RepoRoot $repo -FactorioBin ([string]$session.engine.path)
    if ($null -eq $session.authority.f210_engine_policy -or
        (Get-MIR4PreFreezeFileSha256 ([string]$session.authority.f210_engine_policy.path)) -cne [string]$session.authority.f210_engine_policy.sha256 -or
        [string]$resolution.record_sha256 -cne [string]$session.authority.f210_engine_resolution.record_sha256) {
      throw '[mir4-playtest-finalize-f210-policy-or-engine-drift]'
    }
    [string]$resolution.engine.sha256
  } else { [string]$targetRow[0].engine.sha256 }
  if ($targetRow.Count -ne 1 -or [string]$targetRow[0].development_package.sha256 -cne [string]$session.candidate.sha256 -or
      [string]$targetRow[0].predecessor.sha256 -cne [string]$session.predecessor.sha256 -or
      $expectedEngineSha256 -cne [string]$session.engine.sha256) {
    throw '[mir4-playtest-finalize-current-bindings]'
  }
  $capturePath = Join-Path $root 'capture.json'
  if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) { throw '[mir4-playtest-finalize-without-capture]' }
  $capture = Get-Content -Raw -LiteralPath $capturePath | ConvertFrom-Json -Depth 100
  if ([string]$capture.candidate_sha256 -cne [string]$session.candidate.sha256 -or
      [string]$capture.engine_sha256 -cne [string]$session.engine.sha256 -or
      [string]$capture.session_sha256 -cne (Get-MIR4PreFreezeFileSha256 $sessionPath) -or
      [bool]$capture.decision_inferred -or [bool]$capture.production_release_authorized) {
    throw '[mir4-playtest-finalize-capture-binding]'
  }
  foreach ($evidence in @($capture.files)) {
    if (-not (Test-Path -LiteralPath ([string]$evidence.path) -PathType Leaf) -or
        (Get-MIR4PreFreezeFileSha256 ([string]$evidence.path)) -cne [string]$evidence.sha256) {
      throw "[mir4-playtest-finalize-evidence] $($evidence.path)"
    }
  }
  $summaryPath = Join-Path $root 'result-summary.json'
  if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf) -or
      (Get-MIR4PreFreezeFileSha256 $summaryPath) -cne [string]$capture.result_summary.sha256) {
    throw '[mir4-playtest-finalize-summary-binding]'
  }
  $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json -Depth 100
  if ($Decision -ceq 'ACCEPTED' -and ([string]$capture.status -cne 'ready-for-maintainer-decision' -or
      [string]$capture.comparison.status -cne 'MATCHED' -or @($capture.missing_capture_requirements).Count -ne 0 -or
      [string]$summary.status -cne 'ready-for-maintainer-decision')) {
    throw '[mir4-playtest-acceptance-evidence-incomplete]'
  }
  $receipt = [pscustomobject][ordered]@{
    schema=1;kind='MIR4ManualPlaytestDecisionV1';status=$(if($DryRun){'planned'}else{'final'})
    target=[string]$session.target;candidate_sha256=[string]$session.candidate.sha256
    engine_sha256=[string]$session.engine.sha256;capture_sha256=(Get-MIR4PreFreezeFileSha256 $capturePath)
    session_sha256=(Get-MIR4PreFreezeFileSha256 $sessionPath);result_summary_sha256=(Get-MIR4PreFreezeFileSha256 $summaryPath)
    reviewer=$Reviewer;decision=$Decision;notes=$Notes;decided_at=[DateTime]::UtcNow.ToString('o')
    decision_inferred=$false;source_freeze_authorized=$false;production_release_authorized=$false
  }
  Assert-MIR4PlaytestEvidenceV1 -RepoRoot $repo -Record $receipt | Out-Null
  if ($DryRun) { return $receipt }
  $output = Join-Path $root 'manual-decision.json'
  if (Test-Path -LiteralPath $output) { throw '[mir4-playtest-decision-exists]' }
  Write-MIR4PlaytestJson -Path $output -Value $receipt
  return $receipt
}
