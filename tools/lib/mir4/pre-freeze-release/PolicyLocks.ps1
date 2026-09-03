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
