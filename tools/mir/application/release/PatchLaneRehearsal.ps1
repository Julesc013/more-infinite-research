. (Join-Path $PSScriptRoot '..\..\domain\canonicalization\CanonicalJsonV1.ps1')

$script:MIR4PatchRehearsalDefectPath = 'fixtures/release/m40-01/synthetic-f210-defect.json'
$script:MIR4PatchRehearsalStableRealizationPath = 'fixtures/release/m40-01/stable-realization.json'
$script:MIR4PatchRehearsalMainRealizationPath = 'fixtures/release/m40-01/main-forward-port-realization.json'
$script:MIR4PatchRehearsalDevRealizationPath = 'fixtures/release/m40-01/dev-forward-integration-realization.json'
$script:MIR4PatchRehearsalDefectSchemaPath = 'contracts/release/mir4-defect-record-v1.schema.json'
$script:MIR4PatchRehearsalRealizationSchemaPath = 'contracts/release/mir4-change-realization-v1.schema.json'
$script:MIR4PatchRehearsalResultSchemaPath = 'contracts/release/mir4-patch-lane-rehearsal-result-v1.schema.json'
$script:MIR4PatchRehearsalBranch = 'rehearsal/m40-01-synthetic-f210'

function Get-MIR4PatchRehearsalJsonV1 {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$SchemaPath
  )

  $fullPath = Join-Path $RepoRoot $Path
  $fullSchemaPath = Join-Path $RepoRoot $SchemaPath
  $text = [IO.File]::ReadAllText($fullPath)
  if (-not ($text | Test-Json -SchemaFile $fullSchemaPath -ErrorAction Stop)) {
    throw "[mir4-patch-rehearsal-schema] $Path"
  }
  return $text | ConvertFrom-Json -Depth 100
}

function Get-MIR4PatchRehearsalGitIdentityV1 {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$GitRef,
    [Parameter(Mandatory)][string]$DisplayRef
  )

  $commit = [string](& git -C $RepoRoot rev-parse "$GitRef^{commit}")
  if ($LASTEXITCODE -ne 0 -or $commit -cnotmatch '^[0-9a-f]{40}$') {
    throw "[mir4-patch-rehearsal-ref] $GitRef"
  }
  $tree = [string](& git -C $RepoRoot rev-parse "$GitRef^{tree}")
  if ($LASTEXITCODE -ne 0 -or $tree -cnotmatch '^[0-9a-f]{40}$') {
    throw "[mir4-patch-rehearsal-tree] $GitRef"
  }
  return [pscustomobject][ordered]@{ ref = $DisplayRef; commit = $commit; tree = $tree }
}

function Assert-MIR4PatchRehearsalBranchContainsV1 {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RemoteRef,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$RecordedCommit
  )

  & git -C $RepoRoot merge-base --is-ancestor $RecordedCommit $RemoteRef
  if ($LASTEXITCODE -ne 0) {
    throw "[mir4-patch-rehearsal-branch-continuity] $RemoteRef does not contain $RecordedCommit"
  }
}

function Get-MIR4PatchRehearsalInputIdentityV1 {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Path
  )

  $text = [IO.File]::ReadAllText((Join-Path $RepoRoot $Path))
  $canonical = ConvertFrom-MIR4CanonicalJsonTextV1 -Json $text
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $digest = [BitConverter]::ToString($sha.ComputeHash([Text.UTF8Encoding]::new($false, $true).GetBytes($canonical))).Replace('-', '')
  } finally {
    $sha.Dispose()
  }
  return [pscustomobject][ordered]@{
    path = $Path.Replace('\', '/')
    sha256 = $digest
  }
}

function Get-MIR4PatchRehearsalRecordDigestV1 {
  [CmdletBinding()]
  param([Parameter(Mandatory)]$Record)

  $material = [ordered]@{}
  if ($Record -is [Collections.IDictionary]) {
    foreach ($key in $Record.Keys) {
      if ([string]$key -cne 'record_digest') { $material[[string]$key] = $Record[$key] }
    }
  } else {
    foreach ($property in $Record.PSObject.Properties) {
      if ($property.Name -cne 'record_digest') { $material[$property.Name] = $property.Value }
    }
  }
  return Get-MIR4CanonicalDigestV1 -Value $material -Domain 'mir4:patch-lane-rehearsal-result:1'
}

function Invoke-MIR4DisposablePatchBranchProbeV1 {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$BaseCommit
  )

  $branchName = $script:MIR4PatchRehearsalBranch
  $branchRef = "refs/heads/$branchName"
  if (@(& git -C $RepoRoot branch --list $branchName).Count -ne 0) {
    throw "[mir4-patch-rehearsal-branch-exists] $branchName"
  }

  $scratch = Join-Path ([IO.Path]::GetTempPath()) ("mir4-m40-01-" + [guid]::NewGuid().ToString('N'))
  $worktreeAdded = $false
  $branchCreated = $false
  try {
    & git -C $RepoRoot worktree add --detach $scratch $BaseCommit | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '[mir4-patch-rehearsal-worktree-add]' }
    $worktreeAdded = $true

    & git -C $scratch switch -c $branchName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '[mir4-patch-rehearsal-branch-create]' }
    $branchCreated = $true

    $head = [string](& git -C $scratch rev-parse HEAD)
    $branch = [string](& git -C $scratch branch --show-current)
    if ($head -cne $BaseCommit -or $branch -cne $branchName) {
      throw '[mir4-patch-rehearsal-branch-base]'
    }
  } finally {
    if ($worktreeAdded -and (Test-Path -LiteralPath $scratch)) {
      & git -C $RepoRoot worktree remove $scratch | Out-Null
      if ($LASTEXITCODE -ne 0) { throw '[mir4-patch-rehearsal-worktree-remove]' }
    }
    if ($branchCreated) {
      & git -C $RepoRoot update-ref -d $branchRef $BaseCommit
      if ($LASTEXITCODE -ne 0) { throw '[mir4-patch-rehearsal-branch-remove]' }
    }
  }

  if ((Test-Path -LiteralPath $scratch) -or @(& git -C $RepoRoot branch --list $branchName).Count -ne 0) {
    throw '[mir4-patch-rehearsal-cleanup]'
  }

  return [pscustomobject][ordered]@{
    name = $branchName
    base_commit = $BaseCommit
    created = $true
    checked_out_at_base = $true
    removed = $true
    remote_write = $false
  }
}

function Assert-MIR4PatchRehearsalTargetMatrixV1 {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Defect,
    [Parameter(Mandatory)]$StableRealization,
    [Parameter(Mandatory)]$MainRealization,
    [Parameter(Mandatory)]$DevRealization
  )

  $targetOrder = @('F210', 'F200', 'F110', 'F100')
  foreach ($rows in @(@($Defect.target_dispositions), @($StableRealization.target_effects), @($MainRealization.target_effects), @($DevRealization.target_effects))) {
    if ($rows.Count -ne 4 -or @($rows.target | Sort-Object -Unique).Count -ne 4) {
      throw '[mir4-patch-rehearsal-target-closure]'
    }
    for ($index = 0; $index -lt $targetOrder.Count; $index++) {
      if ([string]$rows[$index].target -cne $targetOrder[$index]) {
        throw '[mir4-patch-rehearsal-target-order]'
      }
    }
  }
  if (@($Defect.target_dispositions | Where-Object disposition -eq 'unknown').Count -ne 0) {
    throw '[mir4-patch-rehearsal-target-unknown]'
  }
  if ((@($Defect.target_dispositions | Where-Object disposition -eq 'affected').target -join '|') -cne 'F210') {
    throw '[mir4-patch-rehearsal-affected-target]'
  }

  foreach ($realization in @($StableRealization, $MainRealization, $DevRealization)) {
    if ((@($realization.target_effects | Where-Object disposition -eq 'affected').target -join '|') -cne 'F210' -or
        (@($realization.target_effects | Where-Object disposition -eq 'unchanged').target -join '|') -cne 'F200|F110|F100') {
      throw '[mir4-patch-rehearsal-realization-targets]'
    }
  }
}

function Invoke-MIR4PatchLaneRehearsalV1 {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $defect = Get-MIR4PatchRehearsalJsonV1 -RepoRoot $repo -Path $script:MIR4PatchRehearsalDefectPath -SchemaPath $script:MIR4PatchRehearsalDefectSchemaPath
  $stable = Get-MIR4PatchRehearsalJsonV1 -RepoRoot $repo -Path $script:MIR4PatchRehearsalStableRealizationPath -SchemaPath $script:MIR4PatchRehearsalRealizationSchemaPath
  $mainRealization = Get-MIR4PatchRehearsalJsonV1 -RepoRoot $repo -Path $script:MIR4PatchRehearsalMainRealizationPath -SchemaPath $script:MIR4PatchRehearsalRealizationSchemaPath
  $devRealization = Get-MIR4PatchRehearsalJsonV1 -RepoRoot $repo -Path $script:MIR4PatchRehearsalDevRealizationPath -SchemaPath $script:MIR4PatchRehearsalRealizationSchemaPath

  if ([string]$defect.finding_id -cne [string]$stable.finding_id -or
      [string]$defect.finding_id -cne [string]$mainRealization.finding_id -or
      [string]$defect.finding_id -cne [string]$devRealization.finding_id) {
    throw '[mir4-patch-rehearsal-finding-identity]'
  }
  if ([string]$stable.lane -cne 'release/4.0' -or [string]$mainRealization.lane -cne 'main' -or
      [string]$devRealization.lane -cne 'dev') {
    throw '[mir4-patch-rehearsal-lane]'
  }
  if ([string]$stable.semantic_equivalence.other_realization_id -cne [string]$mainRealization.realization_id -or
      [string]$mainRealization.semantic_equivalence.other_realization_id -cne [string]$stable.realization_id) {
    throw '[mir4-patch-rehearsal-equivalence-link]'
  }
  if ([string]$devRealization.semantic_equivalence.other_realization_id -cne [string]$mainRealization.realization_id) {
    throw '[mir4-patch-rehearsal-dev-equivalence-link]'
  }
  Assert-MIR4PatchRehearsalTargetMatrixV1 -Defect $defect -StableRealization $stable -MainRealization $mainRealization -DevRealization $devRealization

  $releaseIdentity = Get-MIR4PatchRehearsalGitIdentityV1 -RepoRoot $repo -GitRef ([string]$stable.base.commit) -DisplayRef 'release/4.0'
  $mainIdentity = Get-MIR4PatchRehearsalGitIdentityV1 -RepoRoot $repo -GitRef ([string]$mainRealization.base.commit) -DisplayRef 'main'
  $devIdentity = Get-MIR4PatchRehearsalGitIdentityV1 -RepoRoot $repo -GitRef ([string]$devRealization.base.commit) -DisplayRef 'dev'

  foreach ($pair in @(
    @{ expected = $stable.base; actual = $releaseIdentity; name = 'release/4.0' },
    @{ expected = $mainRealization.base; actual = $mainIdentity; name = 'main' },
    @{ expected = $devRealization.base; actual = $devIdentity; name = 'dev' }
  )) {
    if ([string]$pair.expected.commit -cne [string]$pair.actual.commit -or
        [string]$pair.expected.tree -cne [string]$pair.actual.tree) {
      throw "[mir4-patch-rehearsal-base-drift] $($pair.name)"
    }
  }
  if ([string]$defect.reproducer.base_commit -cne [string]$releaseIdentity.commit) {
    throw '[mir4-patch-rehearsal-reproducer-base]'
  }
  Assert-MIR4PatchRehearsalBranchContainsV1 -RepoRoot $repo -RemoteRef 'refs/remotes/origin/release/4.0' -RecordedCommit $releaseIdentity.commit
  Assert-MIR4PatchRehearsalBranchContainsV1 -RepoRoot $repo -RemoteRef 'refs/remotes/origin/main' -RecordedCommit $mainIdentity.commit
  Assert-MIR4PatchRehearsalBranchContainsV1 -RepoRoot $repo -RemoteRef 'refs/remotes/origin/dev' -RecordedCommit $devIdentity.commit

  $branchProbe = Invoke-MIR4DisposablePatchBranchProbeV1 -RepoRoot $repo -BaseCommit $releaseIdentity.commit
  $packageAuthority = Get-MIR4PatchRehearsalJsonV1 -RepoRoot $repo `
    -Path 'spec/distribution/mir4-package-presentation-baseline-v1.json' `
    -SchemaPath 'spec/schemas/mir4-package-presentation-baseline-v1.schema.json'

  $record = [ordered]@{
    schema = 1
    kind = 'MIR4PatchLaneRehearsalResultV1'
    rehearsal_id = 'M40-01-SYNTHETIC-F210-2026-08-31'
    status = 'passed-unpublished'
    finding_id = [string]$defect.finding_id
    inputs = [ordered]@{
      defect_record = Get-MIR4PatchRehearsalInputIdentityV1 -RepoRoot $repo -Path $script:MIR4PatchRehearsalDefectPath
      stable_realization = Get-MIR4PatchRehearsalInputIdentityV1 -RepoRoot $repo -Path $script:MIR4PatchRehearsalStableRealizationPath
      main_realization = Get-MIR4PatchRehearsalInputIdentityV1 -RepoRoot $repo -Path $script:MIR4PatchRehearsalMainRealizationPath
      dev_realization = Get-MIR4PatchRehearsalInputIdentityV1 -RepoRoot $repo -Path $script:MIR4PatchRehearsalDevRealizationPath
    }
    source_identity = [ordered]@{
      release_4_0 = $releaseIdentity
      main = $mainIdentity
      dev = $devIdentity
    }
    disposable_branch = $branchProbe
    target_matrix = @(
      [ordered]@{ target = 'F210'; disposition = 'affected'; package_action = 'plan-and-qualify' },
      [ordered]@{ target = 'F200'; disposition = 'unchanged'; package_action = 'record-unchanged-no-package' },
      [ordered]@{ target = 'F110'; disposition = 'unchanged'; package_action = 'record-unchanged-no-package' },
      [ordered]@{ target = 'F100'; disposition = 'unchanged'; package_action = 'record-unchanged-no-package' }
    )
    package_plan = [ordered]@{
      affected_targets = @('F210')
      unchanged_targets = @('F200', 'F110', 'F100')
      materializer = 'independent-target-plan'
      determinism = 'same-base-plus-realization-plus-target-produces-byte-identical-plan'
      manufacture_unchanged_targets = $false
    }
    qualification_plan = [ordered]@{
      F210 = @('schema', 'package', 'exact-engine-load', 'direct-upgrade', 'regression-proposition')
      F200 = @('unchanged-package-identity')
      F110 = @('unchanged-package-identity')
      F100 = @('unchanged-package-identity')
    }
    forward_port_plan = [ordered]@{
      from = 'release/4.0'
      to = 'main'
      strategy = 'reimplement-intent-and-regression-proof'
      shared_finding_id = [string]$defect.finding_id
      semantic_equivalence_required = $true
      dev_disposition = 'receive-semantic-forward-port-from-main'
    }
    firewall = [ordered]@{
      merge = $false
      tag = $false
      version_allocation = $false
      sign = $false
      seal = $false
      publish = $false
      remote_branch_write = $false
    }
    package_source_sha256 = [string]$packageAuthority.current.package_source_sha256
    record_digest = ''
  }
  $digestMaterial = ($record | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
  $record.record_digest = Get-MIR4PatchRehearsalRecordDigestV1 -Record $digestMaterial

  $json = $record | ConvertTo-Json -Depth 100
  if (-not ($json | Test-Json -SchemaFile (Join-Path $repo $script:MIR4PatchRehearsalResultSchemaPath))) {
    throw '[mir4-patch-rehearsal-result-schema]'
  }
  return [pscustomobject]$record
}
