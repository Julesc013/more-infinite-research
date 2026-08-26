if (-not (Get-Command Get-MIR4BootstrapRecordSha256 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot 'BootstrapMaterialization.ps1')
}

function Assert-MIR4RunnerPublisherCondition {
  param(
    [Parameter(Mandatory)][bool]$Condition,
    [Parameter(Mandatory)][string]$Code,
    [string]$Detail = ''
  )
  if (-not $Condition) { throw "[$Code] $Detail".TrimEnd() }
}

function Assert-MIR4CanonicalLfByteSequenceV1 {
  param(
    [Parameter(Mandatory)][byte[]]$Bytes,
    [Parameter(Mandatory)][string]$Path
  )

  Assert-MIR4RunnerPublisherCondition (-not ($Bytes -contains [byte]13)) 'mir4-runner-workflow-checkout-eol' $Path
}

function Assert-MIR4WorkflowCheckoutContractV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$FullPath
  )

  $attributeRows = @(& git -C $RepoRoot check-attr text eol -- $RelativePath)
  Assert-MIR4RunnerPublisherCondition ($LASTEXITCODE -eq 0) 'mir4-runner-workflow-git-attributes-command' $RelativePath
  $expectedRows = @(
    "$RelativePath`: text: set"
    "$RelativePath`: eol: lf"
  )
  Assert-MIR4RunnerPublisherCondition (($attributeRows -join "`n") -ceq ($expectedRows -join "`n")) 'mir4-runner-workflow-git-attributes' $RelativePath
  Assert-MIR4CanonicalLfByteSequenceV1 -Bytes ([IO.File]::ReadAllBytes($FullPath)) -Path $RelativePath
}

function Get-MIR4WorkflowUsesFromText {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

  $rows = [Collections.Generic.List[string]]::new()
  foreach ($match in [regex]::Matches($Text, '(?m)^\s*(?:-\s*)?uses:\s*["'']?(?<value>[^"''\s#]+)')) {
    $rows.Add([string]$match.Groups['value'].Value)
  }
  return $rows.ToArray()
}

function Assert-MIR4ExternalActionReferenceV1 {
  param(
    [Parameter(Mandatory)][string]$Reference,
    [Parameter(Mandatory)]$Lock
  )

  Assert-MIR4RunnerPublisherCondition (
    $Reference -cmatch '^(?<action>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*)@(?<sha>[0-9a-f]{40})$'
  ) 'mir4-runner-action-not-full-sha' $Reference
  $action = [string]$Matches.action
  $sha = [string]$Matches.sha
  $locked = @($Lock.actions | Where-Object { [string]$_.action -ceq $action })
  Assert-MIR4RunnerPublisherCondition ($locked.Count -eq 1) 'mir4-runner-action-lock-row' $action
  Assert-MIR4RunnerPublisherCondition ([string]$locked[0].commit_sha -ceq $sha) 'mir4-runner-action-lock-digest' $Reference
}

function Get-MIR4WorkflowRunInputExpressions {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

  $lines = @($Text.Replace("`r`n", "`n").Replace("`r", "`n").Split("`n"))
  $hits = [Collections.Generic.List[object]]::new()
  for ($index = 0; $index -lt $lines.Count; $index++) {
    if ($lines[$index] -match '^(?<indent>\s*)run:\s*\|?\s*$') {
      $base = $Matches.indent.Length
      for ($cursor = $index + 1; $cursor -lt $lines.Count; $cursor++) {
        if ([string]::IsNullOrWhiteSpace($lines[$cursor])) { continue }
        $indent = $lines[$cursor].Length - $lines[$cursor].TrimStart().Length
        if ($indent -le $base) { break }
        if ($lines[$cursor] -match '\$\{\{\s*inputs\.') {
          $hits.Add([pscustomobject][ordered]@{ line=$cursor + 1; text=$lines[$cursor].Trim() })
        }
      }
    } elseif ($lines[$index] -match '^\s*run:\s*.+\$\{\{\s*inputs\.') {
      $hits.Add([pscustomobject][ordered]@{ line=$index + 1; text=$lines[$index].Trim() })
    }
  }
  return $hits.ToArray()
}

function Get-MIR4WorkflowJobSections {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

  $lines = @($Text.Replace("`r`n", "`n").Replace("`r", "`n").Split("`n"))
  $jobs = [Collections.Generic.List[object]]::new()
  $inJobs = $false
  $name = $null
  $body = [Collections.Generic.List[string]]::new()
  foreach ($line in $lines) {
    if (-not $inJobs) {
      if ($line -ceq 'jobs:') { $inJobs = $true }
      continue
    }
    if ($line -cmatch '^  (?<name>[A-Za-z0-9_-]+):\s*$') {
      if ($null -ne $name) {
        $jobs.Add([pscustomobject][ordered]@{ name=$name; text=($body -join "`n") })
      }
      $name = [string]$Matches.name
      $body = [Collections.Generic.List[string]]::new()
      $body.Add($line)
    } elseif ($null -ne $name) {
      $body.Add($line)
    }
  }
  if ($null -ne $name) { $jobs.Add([pscustomobject][ordered]@{ name=$name; text=($body -join "`n") }) }
  return $jobs.ToArray()
}

function Assert-MIR4WorkflowTextBoundaryV1 {
  param(
    [Parameter(Mandatory)][ValidateSet('public-pr','protected-runtime','external-mod-closure','builder','qualifier','publisher')][string]$Purpose,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
    [string]$Path = '<fixture>'
  )

  Assert-MIR4RunnerPublisherCondition (@(Get-MIR4WorkflowRunInputExpressions -Text $Text).Count -eq 0) 'mir4-runner-shell-input-interpolation' $Path
  if ($Purpose -ceq 'public-pr') {
    Assert-MIR4RunnerPublisherCondition ($Text -match '(?m)^  pull_request:\s*$') 'mir4-runner-public-pr-trigger' $Path
    Assert-MIR4RunnerPublisherCondition ($Text -notmatch '(?i)secrets\.') 'mir4-runner-public-pr-secret' $Path
    Assert-MIR4RunnerPublisherCondition ($Text -notmatch '(?i)runs-on:\s*\[?self-hosted') 'mir4-runner-public-pr-self-hosted' $Path
    Assert-MIR4RunnerPublisherCondition ($Text -notmatch '(?m)^\s*pull_request_target:') 'mir4-runner-public-pr-target' $Path
    return
  }
  if ($Purpose -ceq 'protected-runtime') {
    foreach ($job in @(Get-MIR4WorkflowJobSections -Text $Text)) {
      if ([string]$job.text -match '(?i)secrets\.') {
        Assert-MIR4RunnerPublisherCondition ([string]$job.text -match '(?m)^    runs-on:\s*\[self-hosted,\s*Windows\]\s*$') 'mir4-runner-secret-job-host' "$Path::$($job.name)"
        Assert-MIR4RunnerPublisherCondition ([string]$job.text -match '(?m)^    environment:\s*release-candidate\s*$') 'mir4-runner-secret-job-environment' "$Path::$($job.name)"
      }
    }
    Assert-MIR4RunnerPublisherCondition ($Text -notmatch '(?m)^  pull_request(?:_target)?:') 'mir4-runner-protected-public-trigger' $Path
    return
  }
  if ($Purpose -ceq 'external-mod-closure') {
    $secretNames = @([regex]::Matches($Text, '(?i)secrets\.(?<name>[A-Z0-9_]+)') | ForEach-Object { $_.Groups['name'].Value.ToUpperInvariant() } | Sort-Object -Unique)
    $allowed = @('FACTORIO_BIN','FACTORIO_TOKEN','FACTORIO_USERNAME')
    Assert-MIR4RunnerPublisherCondition (@($secretNames | Where-Object { $_ -notin $allowed }).Count -eq 0) 'mir4-runner-external-release-credential' ($secretNames -join ',')
    Assert-MIR4RunnerPublisherCondition ($Text -match '(?m)^    runs-on:\s*self-hosted\s*$') 'mir4-runner-external-host' $Path
    Assert-MIR4RunnerPublisherCondition ($Text -notmatch '(?i)(MOD_PORTAL_TOKEN|GITHUB_TOKEN|SIGNING|PRIVATE_KEY|PASSPHRASE|PUBLISHER_TOKEN)') 'mir4-runner-external-release-capability' $Path
    return
  }
  if ($Purpose -ceq 'builder') {
    Assert-MIR4RunnerPublisherCondition ($Text -match 'ref:\s*["'']?\$\{\{\s*inputs\.source_commit\s*\}\}') 'mir4-runner-builder-immutable-ref' $Path
    Assert-MIR4RunnerPublisherCondition ($Text -notmatch '(?i)secrets\.|ssh-keygen|targetpublication|publication-clients|MIR_PUBLISHER_HOME') 'mir4-runner-builder-release-capability' $Path
    Assert-MIR4RunnerPublisherCondition ($Text -match "Operation='DryRun'") 'mir4-runner-builder-dry-run' $Path
    return
  }
  if ($Purpose -ceq 'qualifier') {
    Assert-MIR4RunnerPublisherCondition ($Text -match 'ref:\s*["'']?\$\{\{\s*inputs\.source_commit\s*\}\}') 'mir4-runner-qualifier-immutable-ref' $Path
    Assert-MIR4RunnerPublisherCondition ($Text -notmatch '(?i)secrets\.|Build-MIRPackage|assurance\s+build|Copy-Item|Move-Item|Set-Content|WriteAllBytes') 'mir4-runner-qualifier-mutation' $Path
    return
  }
  Assert-MIR4RunnerPublisherCondition (@(Get-MIR4WorkflowUsesFromText -Text $Text).Count -eq 0) 'mir4-runner-publisher-action' $Path
  Assert-MIR4RunnerPublisherCondition ($Text -match '(?m)^    runs-on:\s*\[self-hosted,\s*Windows,\s*mir4-publisher\]\s*$') 'mir4-runner-publisher-host' $Path
  Assert-MIR4RunnerPublisherCondition ($Text -match '(?m)^    environment:\s*mir4-production-publication\s*$') 'mir4-runner-publisher-environment' $Path
  Assert-MIR4RunnerPublisherCondition ($Text -match 'MIR_PUBLISHER_HOME' -and $Text -match 'Test-MIR4PublicationAdmission\.ps1') 'mir4-runner-publisher-admission' $Path
  Assert-MIR4RunnerPublisherCondition ($Text -notmatch '(?i)actions/checkout|Build-MIRPackage|package-materializer|tools/lib/mir4|private[_-]?key|ssh-keygen') 'mir4-runner-publisher-forbidden-capability' $Path
}

function Assert-MIR4WorkflowTopPermissionsV1 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Text
  )

  Assert-MIR4RunnerPublisherCondition ($Text -match '(?m)^permissions:\s*(?:\{[^\r\n]+\})?\s*$') 'mir4-runner-permissions-absent' $Path
  $writes = @([regex]::Matches($Text, '(?m)^  (?<permission>[a-z-]+):\s*write\s*$') | ForEach-Object { $_.Groups['permission'].Value })
  if ($Path -ceq '.github/workflows/branch-policy.yml') {
    Assert-MIR4RunnerPublisherCondition ((@($writes | Sort-Object) -join '|') -ceq 'checks|statuses') 'mir4-runner-branch-policy-permissions' ($writes -join ',')
  } else {
    Assert-MIR4RunnerPublisherCondition ($writes.Count -eq 0) 'mir4-runner-write-permission' $Path
  }
  Assert-MIR4RunnerPublisherCondition ($Text -match '(?m)(?:^permissions:\s*\{\s*contents:\s*read\s*\}\s*$|^  contents:\s*read\s*$)') 'mir4-runner-contents-read' $Path
}

function New-MIR4RunnerPublisherConfinementReceiptV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [switch]$RequireClean
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $lockPath = Join-Path $repo '.mir/releases/governance/mir4/github-actions-lock-v2.json'
  $schemaPath = Join-Path $repo 'spec/schemas/mir4-github-actions-lock-v2.schema.json'
  $lockText = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $lockPath).Path)
  $lock = $lockText | ConvertFrom-Json -Depth 40 -DateKind String
  Assert-MIR4RunnerPublisherCondition ($lockText | Test-Json -SchemaFile $schemaPath) 'mir4-runner-action-lock-schema'

  $workflowRoot = Join-Path $repo '.github/workflows'
  $workflowPaths = @(Get-ChildItem -LiteralPath $workflowRoot -File -Filter '*.yml' | ForEach-Object {
    [IO.Path]::GetRelativePath($repo, $_.FullName).Replace('\','/')
  } | Sort-Object)
  $lockedPaths = @($lock.repository_workflows | ForEach-Object { [string]$_ } | Sort-Object)
  Assert-MIR4RunnerPublisherCondition (($workflowPaths -join '|') -ceq ($lockedPaths -join '|')) 'mir4-runner-workflow-closure'

  $workflowRows = [Collections.Generic.List[object]]::new()
  $allExternalUses = [Collections.Generic.List[string]]::new()
  foreach ($relative in $workflowPaths) {
    $path = Join-Path $repo $relative
    Assert-MIR4WorkflowCheckoutContractV1 -RepoRoot $repo -RelativePath $relative -FullPath $path
    $text = [IO.File]::ReadAllText($path)
    Assert-MIR4WorkflowTopPermissionsV1 -Path $relative -Text $text
    Assert-MIR4RunnerPublisherCondition ($text -notmatch '(?m)^\s*pull_request_target:') 'mir4-runner-pull-request-target' $relative
    $uses = @(Get-MIR4WorkflowUsesFromText -Text $text)
    foreach ($reference in @($uses | Where-Object { -not $_.StartsWith('./', [StringComparison]::Ordinal) })) {
      Assert-MIR4ExternalActionReferenceV1 -Reference $reference -Lock $lock
      $allExternalUses.Add($reference)
    }
    Assert-MIR4RunnerPublisherCondition (@(Get-MIR4WorkflowRunInputExpressions -Text $text).Count -eq 0) 'mir4-runner-shell-input-interpolation' $relative
    $workflowRows.Add([pscustomobject][ordered]@{
      path = $relative
      sha256 = Get-MIR4Sha256File -Path $path
      external_actions = @($uses | Where-Object { -not $_.StartsWith('./', [StringComparison]::Ordinal) } | Sort-Object -Unique)
      public_pull_request = [bool]($text -match '(?m)^  pull_request:\s*$')
      secret_references = [int]([regex]::Matches($text, '(?i)secrets\.').Count)
    })
  }
  foreach ($relative in @($lock.generated_workflow_sources)) {
    $path = Join-Path $repo ([string]$relative)
    Assert-MIR4RunnerPublisherCondition (Test-Path -LiteralPath $path -PathType Leaf) 'mir4-runner-generated-source-missing' ([string]$relative)
    foreach ($reference in @(Get-MIR4WorkflowUsesFromText -Text ([IO.File]::ReadAllText($path)))) {
      if (-not $reference.StartsWith('./', [StringComparison]::Ordinal)) {
        Assert-MIR4ExternalActionReferenceV1 -Reference $reference -Lock $lock
        $allExternalUses.Add($reference)
      }
    }
  }
  $usedActions = @($allExternalUses | ForEach-Object { $_.Substring(0, $_.LastIndexOf('@')) } | Sort-Object -Unique)
  $lockedActions = @($lock.actions | ForEach-Object { [string]$_.action } | Sort-Object -Unique)
  Assert-MIR4RunnerPublisherCondition (($usedActions -join '|') -ceq ($lockedActions -join '|')) 'mir4-runner-action-closure'

  $validateText = [IO.File]::ReadAllText((Join-Path $repo '.github/workflows/validate.yml'))
  Assert-MIR4WorkflowTextBoundaryV1 -Purpose public-pr -Text $validateText -Path '.github/workflows/validate.yml'
  foreach ($relative in @('.github/workflows/assurance-targeted.yml','.github/workflows/assurance-scheduled.yml','.github/workflows/control-plane-v5.yml','.github/workflows/release-candidate.yml')) {
    Assert-MIR4WorkflowTextBoundaryV1 -Purpose protected-runtime -Text ([IO.File]::ReadAllText((Join-Path $repo $relative))) -Path $relative
  }
  Assert-MIR4WorkflowTextBoundaryV1 -Purpose external-mod-closure -Text ([IO.File]::ReadAllText((Join-Path $repo '.github/workflows/extended-compat-audit.yml'))) -Path '.github/workflows/extended-compat-audit.yml'
  Assert-MIR4WorkflowTextBoundaryV1 -Purpose builder -Text ([IO.File]::ReadAllText((Join-Path $repo '.github/workflows/mir4-target-build.yml'))) -Path '.github/workflows/mir4-target-build.yml'
  Assert-MIR4WorkflowTextBoundaryV1 -Purpose qualifier -Text ([IO.File]::ReadAllText((Join-Path $repo '.github/workflows/mir4-target-qualification.yml'))) -Path '.github/workflows/mir4-target-qualification.yml'
  Assert-MIR4WorkflowTextBoundaryV1 -Purpose publisher -Text ([IO.File]::ReadAllText((Join-Path $repo '.github/workflows/mir4-target-publication.yml'))) -Path '.github/workflows/mir4-target-publication.yml'

  $resourcePolicies = [ordered]@{
    assurance_backport = '.github/workflows/assurance-backport.yml'
    assurance_scheduled = '.github/workflows/assurance-scheduled.yml'
    assurance_targeted = '.github/workflows/assurance-targeted.yml'
    control_plane = '.github/workflows/control-plane-v5.yml'
  }
  foreach ($entry in $resourcePolicies.GetEnumerator()) {
    $text = [IO.File]::ReadAllText((Join-Path $repo $entry.Value))
    Assert-MIR4RunnerPublisherCondition ($text -match '(?m)^\s+max-parallel:\s*1\s*$') 'mir4-runner-heavy-parallelism' $entry.Value
  }
  Assert-MIR4RunnerPublisherCondition ($validateText -match '(?m)^\s+max-parallel:\s*2\s*$') 'mir4-runner-lightweight-parallelism' '.github/workflows/validate.yml'
  $controlText = [IO.File]::ReadAllText((Join-Path $repo '.github/workflows/control-plane-v5.yml'))
  Assert-MIR4RunnerPublisherCondition ($controlText -match '(?m)^\s+needs:\s*\[context,\s*package,\s*environments\]\s*$') 'mir4-runner-transition-serialization'
  Assert-MIR4RunnerPublisherCondition ($controlText -match '(?m)^\s+needs:\s*\[context,\s*package,\s*transitions\]\s*$') 'mir4-runner-ecosystem-serialization'

  $head = (& git -C $repo rev-parse HEAD).Trim()
  $tree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  $clean = @(& git -C $repo status --porcelain --untracked-files=no).Count -eq 0
  if ($RequireClean) { Assert-MIR4RunnerPublisherCondition $clean 'mir4-runner-clean-tree' }
  $rows = @($workflowRows | Sort-Object path)
  $receipt = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4RunnerPublisherConfinementReceiptV1'
    canonicalization = 'MIR4BootstrapCanonicalJsonV1'
    programme_id = 'M4C02-09-24H'
    turn = 'T15'
    source = [pscustomobject][ordered]@{ repository='Julesc013/more-infinite-research';commit=$head;tree=$tree;working_tree_clean=$clean }
    workflow_closure = [pscustomobject][ordered]@{
      count = $rows.Count
      root_sha256 = Get-MIR4Sha256String -Value (ConvertTo-MIR4BootstrapCanonicalJson -Value $rows)
      rows = $rows
    }
    action_lock = [pscustomobject][ordered]@{
      path = '.mir/releases/governance/mir4/github-actions-lock-v2.json'
      file_sha256 = Get-MIR4Sha256File -Path $lockPath
      actions = $lockedActions.Count
      generated_sources = @($lock.generated_workflow_sources).Count
    }
    checks = @(
      [pscustomobject][ordered]@{id='public-pr-secret-free-hosted';status='passed'},
      [pscustomobject][ordered]@{id='protected-jobs-trusted-environment';status='passed'},
      [pscustomobject][ordered]@{id='third-party-actions-full-sha';status='passed'},
      [pscustomobject][ordered]@{id='least-privilege-permissions';status='passed'},
      [pscustomobject][ordered]@{id='workflow-input-shell-isolation';status='passed'},
      [pscustomobject][ordered]@{id='builder-no-signing-upload';status='passed'},
      [pscustomobject][ordered]@{id='qualifier-no-package-mutation';status='passed'},
      [pscustomobject][ordered]@{id='external-mod-closure-no-release-credentials';status='passed'},
      [pscustomobject][ordered]@{id='publisher-no-checkout-builder-signing';status='passed'},
      [pscustomobject][ordered]@{id='single-heavy-job-resource-policy';status='passed'}
    )
    confinement = [pscustomobject][ordered]@{
      public_pr_secrets = $false
      builder_signing_credentials = $false
      builder_upload_credentials = $false
      qualifier_package_mutation = $false
      external_mod_release_credentials = $false
      publisher_source_checkout = $false
      publisher_package_builder = $false
      publisher_private_signing_key = $false
      publisher_admission_required = $true
    }
    package_source_sha256 = Get-MIRPackageSourceFingerprint -RepoRoot $repo
    transition_authority = [pscustomobject][ordered]@{
      source_freeze=$false;candidate_allocation=$false;production_signing=$false;sealing=$false;promotion=$false;tagging=$false;publication=$false
    }
    record_sha256 = $null
  }
  $receipt.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $receipt
  return $receipt
}

function Test-MIR4RunnerPublisherConfinementReceiptV1 {
  param(
    [Parameter(Mandatory)]$Receipt,
    [Parameter(Mandatory)][string]$RepoRoot
  )

  try {
    $schema = Join-Path $RepoRoot 'spec/schemas/mir4-runner-publisher-confinement-receipt-v1.schema.json'
    $json = ConvertTo-MIR4BootstrapCanonicalJson -Value $Receipt
    if (-not ($json | Test-Json -SchemaFile $schema -ErrorAction Stop)) { return $false }
    if ([string]$Receipt.record_sha256 -cne (Get-MIR4BootstrapRecordSha256 -Record $Receipt)) { return $false }
    if (@($Receipt.checks | Where-Object { [string]$_.status -cne 'passed' }).Count -ne 0) { return $false }
    if (@($Receipt.transition_authority.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) { return $false }
    return $true
  } catch { return $false }
}
