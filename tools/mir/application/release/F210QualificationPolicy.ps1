Set-StrictMode -Version Latest

$script:MIR4F210HistoricalPolicyRelativePath = '.mir/releases/waves/mir4-r0/MIR4-F210-Release-Qualification-PolicyV1.json'
$script:MIR4F210HistoricalPolicySha256 = '386DA641FF9661CECADB4E23619ACCB0AD5F52EF97886B27E217956DC5569E4E'
$script:MIR4F210HistoricalPolicyRecordSha256 = '7DC4D7CBD8B1F5AB8FB0B0CDF819489C9BAA18008607EDA1A27AD3EE297F504F'
$script:MIR4F210HistoricalPolicyEvolutionReceiptRelativePath = '.mir/releases/waves/mir4-r0/MIR4-F210-Qualification-Policy-Authority-Evolution-ReceiptV1.json'
$script:MIR4F210HistoricalPolicyEvolutionReceiptSha256 = 'CAB840352F129A028D2BD061DAD44A29C43BEB5C39F8639C1D8B64CC1E210831'
$script:MIR4F210CurrentPolicyRelativePath = '.mir/control/MIR4-F210-Current-Qualification-PolicyV2.json'
$script:MIR4F210CurrentPolicySchemaRelativePath = 'spec/schemas/mir4-f210-current-qualification-policy-v2.schema.json'
$script:MIR4F210CurrentPolicySuccessionRelativePath = '.mir/control/MIR4-F210-Current-Qualification-Policy-SuccessionV1.json'
$script:MIR4F210CurrentPolicySuccessionSchemaRelativePath = 'spec/schemas/mir4-f210-current-qualification-policy-succession-v1.schema.json'

if (-not (Get-Command Get-MIR4BootstrapRecordSha256 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../../../lib/mir4/BootstrapMaterialization.ps1')
}

function Get-MIR4F210QualificationPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo $script:MIR4F210HistoricalPolicyRelativePath
  $schema = Join-Path $repo 'spec/schemas/mir4-f210-release-qualification-policy-v1.schema.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not (Test-Path -LiteralPath $schema -PathType Leaf)) {
    throw '[mir4-f210-policy-missing]'
  }
  $json = Get-Content -Raw -LiteralPath $path
  if (-not ($json | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)) {
    throw '[mir4-f210-policy-schema]'
  }
  $policy = $json | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $policy)) { throw '[mir4-f210-policy-hash]' }
  return $policy
}

function Test-MIR4F210HistoricalPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo $script:MIR4F210HistoricalPolicyRelativePath
  if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant() -cne $script:MIR4F210HistoricalPolicySha256) {
    throw '[mir4-f210-historical-policy-bytes]'
  }
  $policy = Get-MIR4F210QualificationPolicyV1 -RepoRoot $repo
  if ([string]$policy.record_sha256 -cne $script:MIR4F210HistoricalPolicyRecordSha256 -or
      [string]$policy.support_floor -cne '2.1.8') {
    throw '[mir4-f210-historical-policy-contract]'
  }
  $receiptPath = Join-Path $repo $script:MIR4F210HistoricalPolicyEvolutionReceiptRelativePath
  if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne $script:MIR4F210HistoricalPolicyEvolutionReceiptSha256) {
    throw '[mir4-f210-historical-policy-evolution-receipt-bytes]'
  }
  $receipt = Get-Content -Raw -LiteralPath $receiptPath | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$receipt.qualification_policy.path -cne $script:MIR4F210HistoricalPolicyRelativePath -or
      [string]$receipt.qualification_policy.sha256 -cne $script:MIR4F210HistoricalPolicySha256 -or
      [string]$receipt.qualification_policy.record_sha256 -cne $script:MIR4F210HistoricalPolicyRecordSha256) {
    throw '[mir4-f210-historical-policy-evolution-receipt-contract]'
  }
  return $policy
}

function Get-MIR4F210CurrentQualificationPolicyV2 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo $script:MIR4F210CurrentPolicyRelativePath
  $schema = Join-Path $repo $script:MIR4F210CurrentPolicySchemaRelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not (Test-Path -LiteralPath $schema -PathType Leaf)) {
    throw '[mir4-f210-current-policy-missing]'
  }
  $json = Get-Content -Raw -LiteralPath $path
  if (-not ($json | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)) {
    throw '[mir4-f210-current-policy-schema]'
  }
  $policy = $json | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $policy)) { throw '[mir4-f210-current-policy-hash]' }
  if ([string]$policy.predecessor.policy.path -cne $script:MIR4F210HistoricalPolicyRelativePath -or
      [string]$policy.predecessor.policy.sha256 -cne $script:MIR4F210HistoricalPolicySha256 -or
      [string]$policy.predecessor.policy.record_sha256 -cne $script:MIR4F210HistoricalPolicyRecordSha256 -or
      [string]$policy.predecessor.authority_evolution_receipt.path -cne $script:MIR4F210HistoricalPolicyEvolutionReceiptRelativePath -or
      [string]$policy.predecessor.authority_evolution_receipt.sha256 -cne $script:MIR4F210HistoricalPolicyEvolutionReceiptSha256) {
    throw '[mir4-f210-current-policy-predecessor]'
  }
  return $policy
}

function Get-MIR4F210CurrentQualificationPolicySuccessionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo $script:MIR4F210CurrentPolicySuccessionRelativePath
  $schema = Join-Path $repo $script:MIR4F210CurrentPolicySuccessionSchemaRelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not (Test-Path -LiteralPath $schema -PathType Leaf)) {
    throw '[mir4-f210-current-policy-succession-missing]'
  }
  $json = Get-Content -Raw -LiteralPath $path
  if (-not ($json | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)) {
    throw '[mir4-f210-current-policy-succession-schema]'
  }
  $receipt = $json | ConvertFrom-Json -Depth 100 -DateKind String
  if (-not (Test-MIR4BootstrapRecordHash -Record $receipt)) { throw '[mir4-f210-current-policy-succession-hash]' }
  $policy = Get-MIR4F210CurrentQualificationPolicyV2 -RepoRoot $repo
  $policyPath = Join-Path $repo $script:MIR4F210CurrentPolicyRelativePath
  if ([string]$receipt.current_policy.path -cne $script:MIR4F210CurrentPolicyRelativePath -or
      [string]$receipt.current_policy.sha256 -cne (Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash.ToUpperInvariant() -or
      [string]$receipt.current_policy.record_sha256 -cne [string]$policy.record_sha256 -or
      [string]$receipt.historical_policy.sha256 -cne $script:MIR4F210HistoricalPolicySha256 -or
      [string]$receipt.historical_policy.record_sha256 -cne $script:MIR4F210HistoricalPolicyRecordSha256) {
    throw '[mir4-f210-current-policy-succession-binding]'
  }
  return $receipt
}

function New-MIR4F210CurrentQualificationPolicyV2 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RecordedAt)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $historical = Test-MIR4F210HistoricalPolicyV1 -RepoRoot $repo
  $historicalPath = Join-Path $repo $script:MIR4F210HistoricalPolicyRelativePath
  $historicalReceiptRelative = $script:MIR4F210HistoricalPolicyEvolutionReceiptRelativePath
  $historicalReceiptPath = Join-Path $repo $historicalReceiptRelative
  if (-not (Test-Path -LiteralPath $historicalReceiptPath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $historicalReceiptPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne $script:MIR4F210HistoricalPolicyEvolutionReceiptSha256) {
    throw '[mir4-f210-current-policy-historical-receipt-missing-or-mutated]'
  }
  $record = [pscustomobject][ordered]@{
    schema = 2
    kind = 'MIR4F210CurrentQualificationPolicyV2'
    recorded_at = $RecordedAt
    predecessor = [ordered]@{
      policy = [ordered]@{
        path = $script:MIR4F210HistoricalPolicyRelativePath
        sha256 = (Get-FileHash -LiteralPath $historicalPath -Algorithm SHA256).Hash.ToUpperInvariant()
        record_sha256 = [string]$historical.record_sha256
      }
      authority_evolution_receipt = [ordered]@{
        path = $historicalReceiptRelative
        sha256 = $script:MIR4F210HistoricalPolicyEvolutionReceiptSha256
      }
    }
    target = 'F210'
    factorio_line = '2.1'
    support_floor = '2.1.18'
    pre_freeze = [ordered]@{
      phase = 'experimental'
      selection = 'highest-official-experimental-installed-on-single-authorized-steam-path-at-execution-time'
      steam = [ordered]@{
        app_id = '427520'
        branch = 'experimental'
        app_manifest = [string]$historical.pre_freeze.steam.app_manifest
        factorio_binary = [string]$historical.pre_freeze.steam.factorio_binary
      }
      execution_binding = 'exact-version-build-file-version-binary-sha256-steam-build-id-manifest-sha256-api-prototype-data-and-mod-closure'
      drift = 'invalidate-prior-execution-and-rerun-affected-build-and-qualification'
      engine_admission = 'pending-exact-engine-api-prototype-data-and-official-mod-capsule'
    }
    freeze = [ordered]@{
      trigger = 'explicit-T19-source-freeze-authorization'
      lock = 'exact-selected-version-build-file-version-binary-sha256-steam-build-id-manifest-sha256-api-prototype-data-and-mod-closure'
      drift = 'candidate-invalid-rebuild-and-full-f210-requalification-required'
    }
    post_stable = [ordered]@{
      activation = 'official-2.1-stable-availability-plus-append-only-transition-authority'
      minimum_lane = [ordered]@{
        id = 'stable-minimum'
        channel = 'stable'
        floor_rule = 'numeric-version-max(requested-2.1.18,first-official-stable-2.1-patch,later-accepted-mandatory-floor)'
        operands = @('requested-2.1.18','first-official-stable-2.1-patch','later-accepted-mandatory-floor')
      }
      latest_lane = [ordered]@{
        id = 'stable-latest'
        selection = 'latest-official-stable-2.1.x'
        channel = 'stable'
      }
      candidate_lock = 'each-lane-exact-version-build-binary-and-official-data-identities'
    }
    qualification = [ordered]@{
      current_engine_api_prototype_data_mod_capsule_admitted = $false
      current_engine_qualification_passed = $false
      stable_transition_recorded = $false
      stable_qualification_passed = $false
    }
    boundaries = [ordered]@{
      compatibility_floor_changed = $true
      prototype_mutation_authorized = $false
      source_freeze_authorized = $false
      candidate_allocation_authorized = $false
      signing_authorized = $false
      promotion_to_main_authorized = $false
      publication_authorized = $false
    }
    status = 'active-current-experimental-policy-engine-admission-and-qualification-pending'
    record_sha256 = ''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

function New-MIR4F210CurrentQualificationPolicySuccessionV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$RecordedAt)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $historical = Test-MIR4F210HistoricalPolicyV1 -RepoRoot $repo
  $policy = Get-MIR4F210CurrentQualificationPolicyV2 -RepoRoot $repo
  $policyPath = Join-Path $repo $script:MIR4F210CurrentPolicyRelativePath
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4F210CurrentQualificationPolicySuccessionV1'
    recorded_at = $RecordedAt
    historical_policy = [ordered]@{
      path = $script:MIR4F210HistoricalPolicyRelativePath
      sha256 = $script:MIR4F210HistoricalPolicySha256
      record_sha256 = [string]$historical.record_sha256
      disposition = 'immutable-historical-predecessor-not-current-selection-authority'
    }
    current_policy = [ordered]@{
      path = $script:MIR4F210CurrentPolicyRelativePath
      sha256 = (Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash.ToUpperInvariant()
      record_sha256 = [string]$policy.record_sha256
      support_floor = [string]$policy.support_floor
    }
    current_generation_inputs = @(
      [ordered]@{
        path = 'source/presentation/f210/info.json.template'
        required_dependencies = @('base >= 2.1.18','? recycler >= 2.1.18','? space-age >= 2.1.18')
      }
    )
    exact_engine_qualification = [ordered]@{
      required_floor = '2.1.18'
      admitted = $false
      qualified = $false
      blocker = 'No authorized local Factorio 2.1.18-or-newer engine/API/prototype/data/mod capsule is bound by this receipt.'
    }
    transition_gate = [ordered]@{
      source_freeze = $false
      candidate_allocation = $false
      production_signing = $false
      production_seal = $false
      promotion_to_main = $false
      tagging = $false
      publication = $false
    }
    status = 'CURRENT-F210-FLOOR-2.1.18-ADOPTED-ENGINE-ADMISSION-AND-QUALIFICATION-PENDING'
    record_sha256 = ''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

function Test-MIR4F210PathEqualV1 {
  param([Parameter(Mandatory)][string]$Left,[Parameter(Mandatory)][string]$Right)
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  return [IO.Path]::GetFullPath($Left).TrimEnd('\','/').Equals(
    [IO.Path]::GetFullPath($Right).TrimEnd('\','/'),
    $comparison
  )
}

function Assert-MIR4F210HistoricalEngineFactsV1 {
  param(
    [Parameter(Mandatory)]$Policy,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][int]$Build,
    [Parameter(Mandatory)][string]$FileVersion,
    [Parameter(Mandatory)][string]$Distribution,
    [Parameter(Mandatory)][string]$Platform,
    [Parameter(Mandatory)][string]$SteamAppId,
    [Parameter(Mandatory)][string]$SteamBranch,
    [Parameter(Mandatory)][string]$SteamBuildId,
    [Parameter(Mandatory)][string]$ResolvedBinaryPath,
    [Parameter(Mandatory)][string]$ManifestBinaryPath
  )
  try { $engineVersion = [version]$Version; $floor = [version][string]$Policy.support_floor }
  catch { throw '[mir4-f210-engine-version-format]' }
  if ($engineVersion.Major -ne 2 -or $engineVersion.Minor -ne 1 -or $engineVersion -lt $floor) {
    throw "[mir4-f210-engine-floor] $Version"
  }
  if ($Build -le 0 -or $FileVersion -cne "$Version.$Build") { throw '[mir4-f210-engine-build-binding]' }
  if ($Distribution -cne 'steam' -or $Platform -cne 'win64') { throw '[mir4-f210-engine-distribution]' }
  if ($SteamAppId -cne [string]$Policy.pre_freeze.steam.app_id -or
      $SteamBranch -cne [string]$Policy.pre_freeze.steam.branch -or
      $SteamBuildId -notmatch '^[1-9][0-9]*$') {
    throw '[mir4-f210-steam-channel]'
  }
  if (-not (Test-MIR4F210PathEqualV1 -Left $ResolvedBinaryPath -Right $ManifestBinaryPath) -or
      -not (Test-MIR4F210PathEqualV1 -Left $ResolvedBinaryPath -Right ([string]$Policy.pre_freeze.steam.factorio_binary))) {
    throw '[mir4-f210-authorized-install-path]'
  }
  return $true
}

function Assert-MIR4F210EngineFactsV2 {
  param(
    [Parameter(Mandatory)]$Policy,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][int]$Build,
    [Parameter(Mandatory)][string]$FileVersion,
    [Parameter(Mandatory)][string]$Distribution,
    [Parameter(Mandatory)][string]$Platform,
    [Parameter(Mandatory)][string]$SteamAppId,
    [Parameter(Mandatory)][string]$SteamBranch,
    [Parameter(Mandatory)][string]$SteamBuildId,
    [Parameter(Mandatory)][string]$ResolvedBinaryPath,
    [Parameter(Mandatory)][string]$ManifestBinaryPath
  )
  try { $engineVersion = [version]$Version; $floor = [version][string]$Policy.support_floor }
  catch { throw '[mir4-f210-current-engine-version-format]' }
  if ($engineVersion.Major -ne 2 -or $engineVersion.Minor -ne 1 -or $engineVersion -lt $floor) {
    throw "[mir4-f210-current-engine-floor] $Version"
  }
  if ($Build -le 0 -or $FileVersion -cne "$Version.$Build") { throw '[mir4-f210-current-engine-build-binding]' }
  if ($Distribution -cne 'steam' -or $Platform -cne 'win64') { throw '[mir4-f210-current-engine-distribution]' }
  if ($SteamAppId -cne [string]$Policy.pre_freeze.steam.app_id -or
      $SteamBranch -cne [string]$Policy.pre_freeze.steam.branch -or
      $SteamBuildId -notmatch '^[1-9][0-9]*$') {
    throw '[mir4-f210-current-steam-channel]'
  }
  if (-not (Test-MIR4F210PathEqualV1 -Left $ResolvedBinaryPath -Right $ManifestBinaryPath) -or
      -not (Test-MIR4F210PathEqualV1 -Left $ResolvedBinaryPath -Right ([string]$Policy.pre_freeze.steam.factorio_binary))) {
    throw '[mir4-f210-current-authorized-install-path]'
  }
  return $true
}

function Get-MIR4F210AcfValueV1 {
  param([Parameter(Mandatory)][string]$Text,[Parameter(Mandatory)][string]$Name,[switch]$AllowEmpty)
  $matches = [regex]::Matches($Text, '(?im)^\s*"' + [regex]::Escape($Name) + '"\s+"([^"]*)"\s*$')
  if ($matches.Count -eq 0) { throw "[mir4-f210-steam-manifest-field] $Name" }
  $values = @($matches | ForEach-Object { [string]$_.Groups[1].Value } | Sort-Object -Unique -CaseSensitive)
  if (-not $AllowEmpty -and @($values | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) {
    throw "[mir4-f210-steam-manifest-field] $Name"
  }
  if ($values.Count -ne 1) { throw "[mir4-f210-steam-manifest-ambiguous] $Name" }
  return [string]$values[0]
}

function Get-MIR4F210EngineResolutionV2 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$FactorioBin = '',
    [string]$SteamManifest = ''
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4F210CurrentQualificationPolicyV2 -RepoRoot $repo
  if ([string]::IsNullOrWhiteSpace($FactorioBin)) { $FactorioBin = [string]$policy.pre_freeze.steam.factorio_binary }
  if ([string]::IsNullOrWhiteSpace($SteamManifest)) { $SteamManifest = [string]$policy.pre_freeze.steam.app_manifest }
  if (-not (Test-Path -LiteralPath $FactorioBin -PathType Leaf) -or -not (Test-Path -LiteralPath $SteamManifest -PathType Leaf)) {
    throw '[mir4-f210-engine-custody-missing]'
  }
  $binary = (Resolve-Path -LiteralPath $FactorioBin).Path
  $manifest = (Resolve-Path -LiteralPath $SteamManifest).Path
  $manifestText = Get-Content -Raw -LiteralPath $manifest
  $appId = Get-MIR4F210AcfValueV1 -Text $manifestText -Name 'appid'
  $installDir = Get-MIR4F210AcfValueV1 -Text $manifestText -Name 'installdir'
  $steamBuildId = Get-MIR4F210AcfValueV1 -Text $manifestText -Name 'buildid'
  $stateFlags = Get-MIR4F210AcfValueV1 -Text $manifestText -Name 'StateFlags'
  $branch = Get-MIR4F210AcfValueV1 -Text $manifestText -Name 'BetaKey'
  if ($stateFlags -cne '4') { throw "[mir4-f210-steam-install-not-current] state=$stateFlags" }

  $steamApps = Split-Path -Parent $manifest
  $manifestBinary = Join-Path $steamApps "common/$installDir/bin/x64/factorio.exe"
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = $binary
  $start.UseShellExecute = $false
  $start.CreateNoWindow = $true
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  [void]$start.ArgumentList.Add('--version')
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $start
  try {
    if (-not $process.Start()) { throw '[mir4-f210-engine-version-command]' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $versionText = $stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0) { throw '[mir4-f210-engine-version-command]' }
  } finally { $process.Dispose() }
  $versionLine = @($versionText -split '\r?\n' | Where-Object { [string]$_ -match '^Version:\s+[0-9]+\.[0-9]+\.[0-9]+\s+\(build\s+[0-9]+,\s*[^,]+,\s*[^\)]+\)$' })
  if ($versionLine.Count -ne 1 -or [string]$versionLine[0] -notmatch '^Version:\s+([0-9]+\.[0-9]+\.[0-9]+)\s+\(build\s+([0-9]+),\s*([^,]+),\s*([^\)]+)\)$') {
    throw '[mir4-f210-engine-version-output]'
  }
  $version = [string]$Matches[1]
  $build = [int]$Matches[2]
  $platform = [string]$Matches[3]
  $distribution = [string]$Matches[4]
  $fileVersion = [string](Get-Item -LiteralPath $binary).VersionInfo.FileVersion
  Assert-MIR4F210EngineFactsV2 -Policy $policy -Version $version -Build $build -FileVersion $fileVersion `
    -Distribution $distribution -Platform $platform -SteamAppId $appId -SteamBranch $branch `
    -SteamBuildId $steamBuildId -ResolvedBinaryPath $binary -ManifestBinaryPath $manifestBinary | Out-Null

  $policyPath = Join-Path $repo $script:MIR4F210CurrentPolicyRelativePath
  $record = [pscustomobject][ordered]@{
    schema = 2
    kind = 'MIR4F210EngineResolutionV2'
    status = 'selected-pre-freeze-experimental-exact-execution-lock'
    phase = 'pre-freeze-experimental'
    observed_at = [DateTimeOffset]::UtcNow.ToString('o')
    target = 'F210'
    support_floor = [string]$policy.support_floor
    policy = [ordered]@{
      path = $script:MIR4F210CurrentPolicyRelativePath
      sha256 = (Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash.ToUpperInvariant()
      record_sha256 = [string]$policy.record_sha256
    }
    engine = [ordered]@{
      version = $version
      build = $build
      file_version = $fileVersion
      platform = $platform
      distribution = $distribution
      path = $binary
      sha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToUpperInvariant()
      bytes = (Get-Item -LiteralPath $binary).Length
    }
    steam = [ordered]@{
      app_id = $appId
      branch = $branch
      build_id = $steamBuildId
      app_manifest = $manifest
      app_manifest_sha256 = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToUpperInvariant()
      install_directory = $installDir
      state_flags = $stateFlags
    }
    selection = [ordered]@{
      selected_from_single_authorized_install = $true
      highest_installed_official_experimental_on_authorized_path = $true
      global_latest_claimed = $false
      exact_execution_lock = $true
      drift_requires_rebuild_and_requalification = $true
    }
    boundaries = [ordered]@{
      source_freeze_authorized = $false
      candidate_allocation_authorized = $false
      signing_authorized = $false
      publication_authorized = $false
    }
    record_sha256 = ''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

function New-MIR4F210FreezeLockV2 {
  param([Parameter(Mandatory)]$Observation,[switch]$FreezeAuthorized)
  if (-not $FreezeAuthorized) { throw '[mir4-f210-freeze-authorization-required]' }
  if ([string]$Observation.kind -cne 'MIR4F210EngineResolutionV2' -or -not [bool]$Observation.selection.exact_execution_lock) {
    throw '[mir4-f210-freeze-observation]'
  }
  $record = [pscustomobject][ordered]@{
    schema = 2
    kind = 'MIR4F210FreezeEngineLockV2'
    status = 'exact-engine-frozen-requalification-required-on-any-drift'
    target = 'F210'
    policy = $Observation.policy
    engine = $Observation.engine
    steam = $Observation.steam
    observation_record_sha256 = [string]$Observation.record_sha256
    drift_policy = 'invalidate-candidate-rebuild-and-rerun-all-f210-qualification'
    record_sha256 = ''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

function Test-MIR4F210FreezeLockV2 {
  param([Parameter(Mandatory)]$Lock,[Parameter(Mandatory)]$Observation)
  foreach ($binding in @(
    @([string]$Lock.engine.version,[string]$Observation.engine.version),
    @([string]$Lock.engine.build,[string]$Observation.engine.build),
    @([string]$Lock.engine.file_version,[string]$Observation.engine.file_version),
    @([string]$Lock.engine.sha256,[string]$Observation.engine.sha256),
    @([string]$Lock.steam.build_id,[string]$Observation.steam.build_id),
    @([string]$Lock.steam.app_manifest_sha256,[string]$Observation.steam.app_manifest_sha256)
  )) {
    if ($binding[0] -cne $binding[1]) { throw '[mir4-f210-freeze-engine-drift]' }
  }
  return $true
}

function Resolve-MIR4F210StableFloorV2 {
  param(
    [Parameter(Mandatory)]$Policy,
    [Parameter(Mandatory)][string]$FirstOfficialStableVersion,
    [Parameter(Mandatory)][string]$LaterAcceptedMandatoryFloor
  )
  try {
    $requested = [version][string]$Policy.support_floor
    $firstStable = [version]$FirstOfficialStableVersion
    $laterMandatory = [version]$LaterAcceptedMandatoryFloor
  } catch { throw '[mir4-f210-stable-floor-version-format]' }
  foreach ($candidate in @($requested,$firstStable,$laterMandatory)) {
    if ($candidate.Major -ne 2 -or $candidate.Minor -ne 1) { throw '[mir4-f210-stable-floor-line]' }
  }
  return ((@($requested,$firstStable,$laterMandatory) | Sort-Object -Descending | Select-Object -First 1).ToString())
}

function Test-MIR4F210StableLaneSetV2 {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)]$MinimumLane,[Parameter(Mandatory)]$LatestLane)
  $effectiveFloor = Resolve-MIR4F210StableFloorV2 -Policy $Policy `
    -FirstOfficialStableVersion ([string]$MinimumLane.first_official_stable_version) `
    -LaterAcceptedMandatoryFloor ([string]$MinimumLane.later_accepted_mandatory_floor)
  if ([string]$MinimumLane.id -cne 'stable-minimum' -or [string]$LatestLane.id -cne 'stable-latest' -or
      [string]$MinimumLane.channel -cne 'stable' -or [string]$LatestLane.channel -cne 'stable' -or
      [string]$MinimumLane.floor_rule -cne [string]$Policy.post_stable.minimum_lane.floor_rule -or
      [string]$MinimumLane.version -cne $effectiveFloor -or
      [version][string]$LatestLane.version -lt [version][string]$MinimumLane.version -or
      [string]$MinimumLane.sha256 -notmatch '^[A-F0-9]{64}$' -or [string]$LatestLane.sha256 -notmatch '^[A-F0-9]{64}$' -or
      -not [bool]$MinimumLane.exact_candidate_lock -or -not [bool]$LatestLane.exact_candidate_lock) {
    throw '[mir4-f210-current-stable-dual-lane]'
  }
  return $true
}
