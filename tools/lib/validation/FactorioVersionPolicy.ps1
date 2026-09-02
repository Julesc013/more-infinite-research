function Get-MIR4Factorio21ChannelAuthority {
  param([string]$RepoRoot = "")
  Set-StrictMode -Version Latest
  $repo = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
  } else {
    (Resolve-Path -LiteralPath $RepoRoot).Path
  }
  $path = Join-Path $repo "spec/engines/mir4-factorio-2.1-experimental-channel-v1.json"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Factorio 2.1 channel authority is missing: $path" }
  return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function Test-MIR4Factorio21SelectedVersion {
  param(
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)]$Authority
  )
  Set-StrictMode -Version Latest
  if ($Version -notmatch '^2\.1\.[0-9]+$') { return $false }
  return [version]$Version -ge [version]([string]$Authority.selection.minimum_version)
}

function Get-MIR4Factorio21ChangelogDelta {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$ReviewedVersion
  )
  Set-StrictMode -Version Latest
  $rows = [Collections.Generic.List[object]]::new()
  $version = ""
  $category = ""
  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match '^Version:\s+([0-9]+\.[0-9]+\.[0-9]+)$') {
      $version = [string]$Matches[1]
      $category = ""
      if ([version]$version -le [version]$ReviewedVersion) { break }
      continue
    }
    if ([string]::IsNullOrWhiteSpace($version)) { continue }
    if ($line -match '^\s{2}([^:]+):\s*$') {
      $category = ([string]$Matches[1]).Trim().ToLowerInvariant()
      continue
    }
    if ($line -match '^\s{4}-\s+(.+)$') {
      $rows.Add([pscustomobject][ordered]@{
        version = $version
        category = $category
        text = ([string]$Matches[1]).Trim()
        opportunity_review = $category -in @('changes', 'modding', 'scripting')
      })
    }
  }
  return @($rows)
}

function Get-MIR4Factorio21ChannelReview {
  param(
    [Parameter(Mandatory)][string]$FactorioBin,
    [string]$RepoRoot = ""
  )
  Set-StrictMode -Version Latest
  $authority = Get-MIR4Factorio21ChannelAuthority -RepoRoot $RepoRoot
  $binary = (Resolve-Path -LiteralPath $FactorioBin).Path
  $binaryItem = Get-Item -LiteralPath $binary
  $version = [string]$binaryItem.VersionInfo.ProductVersion
  if ($version -match '^([0-9]+\.[0-9]+\.[0-9]+)') { $version = [string]$Matches[1] }
  $fileVersion = [string]$binaryItem.VersionInfo.FileVersion
  $installRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $binary))
  $runtimeApiPath = Join-Path $installRoot 'doc-html/runtime-api.json'
  $prototypeApiPath = Join-Path $installRoot 'doc-html/prototype-api.json'
  $changelogPath = Join-Path $installRoot 'data/changelog.txt'
  foreach ($requiredPath in @($runtimeApiPath, $prototypeApiPath, $changelogPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Factorio 2.1 channel input is missing: $requiredPath" }
  }
  $runtimeApi = Get-Content -Raw -LiteralPath $runtimeApiPath | ConvertFrom-Json
  $prototypeApi = Get-Content -Raw -LiteralPath $prototypeApiPath | ConvertFrom-Json
  $observed = [pscustomobject][ordered]@{
    version = $version
    file_version = $fileVersion
    binary_sha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash
    runtime_api = [pscustomobject][ordered]@{
      application_version = [string]$runtimeApi.application_version
      sha256 = (Get-FileHash -LiteralPath $runtimeApiPath -Algorithm SHA256).Hash
      surface_count = @($runtimeApi.classes).Count + @($runtimeApi.events).Count
    }
    prototype_api = [pscustomobject][ordered]@{
      application_version = [string]$prototypeApi.application_version
      sha256 = (Get-FileHash -LiteralPath $prototypeApiPath -Algorithm SHA256).Hash
      surface_count = @($prototypeApi.prototypes).Count + @($prototypeApi.types).Count
    }
    changelog_sha256 = (Get-FileHash -LiteralPath $changelogPath -Algorithm SHA256).Hash
  }
  $validLine = Test-MIR4Factorio21SelectedVersion -Version $version -Authority $authority
  $apiVersionsMatch = [string]$observed.runtime_api.application_version -eq $version -and
    [string]$observed.prototype_api.application_version -eq $version
  $review = $authority.current_review
  $identityMatches = $validLine -and $apiVersionsMatch -and
    [string]$observed.version -eq [string]$review.version -and
    [string]$observed.file_version -eq [string]$review.file_version -and
    [string]$observed.binary_sha256 -eq [string]$review.binary_sha256 -and
    [string]$observed.runtime_api.sha256 -eq [string]$review.runtime_api.sha256 -and
    [string]$observed.prototype_api.sha256 -eq [string]$review.prototype_api.sha256 -and
    [string]$observed.changelog_sha256 -eq [string]$review.changelog_sha256
  $status = if (-not $validLine -or -not $apiVersionsMatch) { 'invalid-engine-channel-input' } elseif ($identityMatches) { 'current-reviewed' } else { 'review-required' }
  $taskState = if ($identityMatches) { 'satisfied' } else { 'planned' }
  $tasks = @($authority.change_review.required_tasks | ForEach-Object {
    [pscustomobject][ordered]@{id=[string]$_;state=$taskState;observed_version=$version}
  })
  $delta = if ($validLine -and [version]$version -gt [version]([string]$review.version)) {
    @(Get-MIR4Factorio21ChangelogDelta -Path $changelogPath -ReviewedVersion ([string]$review.version))
  } else { @() }
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4Factorio21ChannelReviewPacketV1'
    status = $status
    target = 'f210'
    selector = 'latest-installed-official-2.1-experimental'
    patch_pinned = $false
    reviewed_identity = [pscustomobject][ordered]@{
      version = [string]$review.version
      file_version = [string]$review.file_version
      binary_sha256 = [string]$review.binary_sha256
      runtime_api_sha256 = [string]$review.runtime_api.sha256
      prototype_api_sha256 = [string]$review.prototype_api.sha256
      changelog_sha256 = [string]$review.changelog_sha256
    }
    observed_identity = $observed
    exact_execution_identity_required = $true
    cross_version_evidence_reuse = $false
    tasks = $tasks
    changelog_delta = @($delta)
    opportunity_candidates = @(@($delta) | Where-Object opportunity_review)
    stable_transition_action = [string]$authority.selection.stable_transition
  }
}

function Resolve-MIR4FactorioQualificationProfile {
  param(
    [Parameter(Mandatory)]$Profile,
    [string]$FactorioBin = "",
    [string]$RepoRoot = ""
  )
  Set-StrictMode -Version Latest
  $copy = $Profile | ConvertTo-Json -Depth 40 | ConvertFrom-Json
  $mode = if ($null -ne $copy.PSObject.Properties['qualification_factorio_version_mode']) {
    [string]$copy.qualification_factorio_version_mode
  } else { 'exact' }
  if ($mode -ne 'latest-installed-experimental') { return $copy }
  $authority = Get-MIR4Factorio21ChannelAuthority -RepoRoot $RepoRoot
  $selected = [string]$authority.current_review.version
  if (-not [string]::IsNullOrWhiteSpace($FactorioBin)) {
    $item = Get-Item -LiteralPath (Resolve-Path -LiteralPath $FactorioBin).Path
    $selected = [string]$item.VersionInfo.ProductVersion
    if ($selected -match '^([0-9]+\.[0-9]+\.[0-9]+)') { $selected = [string]$Matches[1] }
  }
  if (-not (Test-MIR4Factorio21SelectedVersion -Version $selected -Authority $authority)) {
    throw "Factorio $selected is outside the governed latest 2.1 experimental channel."
  }
  $copy.qualification_factorio_version = $selected
  $copy | Add-Member -NotePropertyName qualification_factorio_selection -NotePropertyValue 'latest-installed-official-2.1-experimental' -Force
  return $copy
}

function Get-MIR4FixedFactorioEngineLock {
  param(
    [Parameter(Mandatory)][ValidateSet('f200','f110','f100')][string]$Target,
    [string]$RepoRoot = ""
  )
  Set-StrictMode -Version Latest
  $repo = if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
  } else {
    (Resolve-Path -LiteralPath $RepoRoot).Path
  }
  $baselinePath = Join-Path $repo 'spec/distribution/mir4-golden-four-target-baseline-v1.json'
  $golden = Get-Content -Raw -LiteralPath $baselinePath | ConvertFrom-Json -Depth 100
  $baseline = @($golden.targets | Where-Object target -eq $Target)
  if ($baseline.Count -ne 1) { throw "Fixed Factorio target baseline is not unique: $Target" }
  $targetRow = $baseline[0]
  $profilePath = Join-Path $repo "validation/profiles/factorio-$([string]$targetRow.factorio_line).json"
  $profile = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json -Depth 40
  $expectedVersion = [string]$profile.qualification_factorio_version
  $baselineVersion = [string]$targetRow.exact_engine.version
  if ($baselineVersion -cne $expectedVersion -and $baselineVersion -cne "$expectedVersion-only") {
    throw "Fixed Factorio version authorities disagree for $Target."
  }
  $expectedSha256 = [string]$targetRow.exact_engine.executable_sha256
  if ($expectedSha256 -notmatch '^[A-F0-9]{64}$') { throw "Fixed Factorio executable lock is invalid for $Target." }
  $fileVersion = ''
  $authorityPaths = [Collections.Generic.List[string]]::new()
  $authorityPaths.Add('spec/distribution/mir4-golden-four-target-baseline-v1.json')
  $authorityPaths.Add("validation/profiles/factorio-$([string]$targetRow.factorio_line).json")
  $releaseRelative = ".mir/releases/records/$([string]$targetRow.predecessor).json"
  $releasePath = Join-Path $repo $releaseRelative
  if (Test-Path -LiteralPath $releasePath -PathType Leaf) {
    $release = Get-Content -Raw -LiteralPath $releasePath | ConvertFrom-Json -Depth 100
    $packageProperties = $release.package.PSObject.Properties
    $releaseEngine = if ($null -ne $packageProperties['factorio_engine']) { [string]$packageProperties['factorio_engine'].Value } else { '' }
    $releaseBuild = if ($null -ne $packageProperties['factorio_engine_build']) { [string]$packageProperties['factorio_engine_build'].Value } else { '' }
    $releaseSha256 = if ($null -ne $packageProperties['factorio_engine_sha256']) { [string]$packageProperties['factorio_engine_sha256'].Value } else { '' }
    $releaseEngineFields = @($releaseEngine,$releaseBuild,$releaseSha256 | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($releaseEngineFields.Count -gt 0) {
      if ($releaseEngineFields.Count -ne 3) { throw "Fixed Factorio release engine identity is incomplete for $Target." }
      if ($releaseEngine -cne $expectedVersion -or $releaseSha256 -cne $expectedSha256 -or [string]::IsNullOrWhiteSpace($releaseBuild)) {
        throw "Fixed Factorio release and target authorities disagree for $Target."
      }
      $fileVersion = $releaseBuild
      $authorityPaths.Add($releaseRelative.Replace('\\','/'))
    }
  }
  if ([string]::IsNullOrWhiteSpace($fileVersion)) {
    $observationRelative = '.mir/evidence/mir4-r0/2026-08-16/MIR4-Bootstrap-Engine-Availability-ObservationV1.json'
    $observationSchemaRelative = 'spec/schemas/mir4-bootstrap-engine-availability-observation.schema.json'
    $observationPath = Join-Path $repo $observationRelative
    $observationSchemaPath = Join-Path $repo $observationSchemaRelative
    if (-not (Test-Path -LiteralPath $observationPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $observationSchemaPath -PathType Leaf) -or
        -not ((Get-Content -Raw -LiteralPath $observationPath) | Test-Json -SchemaFile $observationSchemaPath)) {
      throw "Fixed Factorio engine availability observation is invalid for $Target."
    }
    $observation = Get-Content -Raw -LiteralPath $observationPath | ConvertFrom-Json -Depth 100
    $observationTarget = @($observation.targets | Where-Object target_key -eq $Target)
    if ($observationTarget.Count -ne 1) { throw "Fixed Factorio engine availability observation is not unique for $Target." }
    $observationTarget = $observationTarget[0]
    $build = [int]$observationTarget.required_engine.build
    if ([string]$observationTarget.lock_label -cne $baselineVersion -or
        [string]$observationTarget.required_engine.version -cne $expectedVersion -or
        [string]$observationTarget.required_engine.executable_sha256 -cne $expectedSha256 -or
        -not [bool]$observationTarget.comparison.exact_lock_match -or
        [string]$observationTarget.lock_state -cne 'exact-lock-match' -or
        $build -le 0) {
      throw "Fixed Factorio availability observation and target authorities disagree for $Target."
    }
    $fileVersion = "$expectedVersion.$build"
    $authorityPaths.Add($observationRelative)
    $authorityPaths.Add($observationSchemaRelative)
  }
  return [pscustomobject][ordered]@{
    target = $Target
    selection = 'exact-profile'
    version = $expectedVersion
    file_version = $fileVersion
    binary_sha256 = $expectedSha256
    authority_paths = @($authorityPaths)
  }
}

function Test-MIR4FixedFactorioEngineIdentity {
  param(
    [Parameter(Mandatory)][ValidateSet('f200','f110','f100')][string]$Target,
    [Parameter(Mandatory)]$ObservedIdentity,
    [string]$RepoRoot = ""
  )
  Set-StrictMode -Version Latest
  $lock = Get-MIR4FixedFactorioEngineLock -Target $Target -RepoRoot $RepoRoot
  if ([string]$ObservedIdentity.version -cne [string]$lock.version -or
      [string]$ObservedIdentity.binary_sha256 -cne [string]$lock.binary_sha256) { return $false }
  if (-not [string]::IsNullOrWhiteSpace([string]$lock.file_version) -and
      [string]$ObservedIdentity.file_version -cne [string]$lock.file_version) { return $false }
  return $true
}

function Write-MIR4Factorio21ChannelReview {
  param(
    [Parameter(Mandatory)]$Review,
    [Parameter(Mandatory)][string]$OutputPath
  )
  Set-StrictMode -Version Latest
  $resolved = [IO.Path]::GetFullPath($OutputPath)
  $parent = Split-Path -Parent $resolved
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  [IO.File]::WriteAllText($resolved, (($Review | ConvertTo-Json -Depth 40) + "`n"), [Text.UTF8Encoding]::new($false))
  return $resolved
}
