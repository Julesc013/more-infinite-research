Set-StrictMode -Version Latest

$script:MIR4F210PolicyRelativePath = '.mir/releases/waves/mir4-r0/MIR4-F210-Release-Qualification-PolicyV1.json'

if (-not (Get-Command Get-MIR4BootstrapRecordSha256 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../../../lib/mir4/BootstrapMaterialization.ps1')
}

function Get-MIR4F210QualificationPolicyV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $path = Join-Path $repo $script:MIR4F210PolicyRelativePath
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

function Test-MIR4F210PathEqualV1 {
  param([Parameter(Mandatory)][string]$Left,[Parameter(Mandatory)][string]$Right)
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  return [IO.Path]::GetFullPath($Left).TrimEnd('\','/').Equals(
    [IO.Path]::GetFullPath($Right).TrimEnd('\','/'),
    $comparison
  )
}

function Assert-MIR4F210EngineFactsV1 {
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

function Get-MIR4F210EngineResolutionV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$FactorioBin = '',
    [string]$SteamManifest = ''
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $policy = Get-MIR4F210QualificationPolicyV1 -RepoRoot $repo
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
  Assert-MIR4F210EngineFactsV1 -Policy $policy -Version $version -Build $build -FileVersion $fileVersion `
    -Distribution $distribution -Platform $platform -SteamAppId $appId -SteamBranch $branch `
    -SteamBuildId $steamBuildId -ResolvedBinaryPath $binary -ManifestBinaryPath $manifestBinary | Out-Null

  $policyPath = Join-Path $repo $script:MIR4F210PolicyRelativePath
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4F210EngineResolutionV1'
    status = 'selected-pre-freeze-experimental-exact-execution-lock'
    phase = 'pre-freeze-experimental'
    observed_at = [DateTimeOffset]::UtcNow.ToString('o')
    target = 'F210'
    support_floor = [string]$policy.support_floor
    policy = [ordered]@{
      path = $script:MIR4F210PolicyRelativePath
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

function New-MIR4F210FreezeLockV1 {
  param([Parameter(Mandatory)]$Observation,[switch]$FreezeAuthorized)
  if (-not $FreezeAuthorized) { throw '[mir4-f210-freeze-authorization-required]' }
  if ([string]$Observation.kind -cne 'MIR4F210EngineResolutionV1' -or -not [bool]$Observation.selection.exact_execution_lock) {
    throw '[mir4-f210-freeze-observation]'
  }
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4F210FreezeEngineLockV1'
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

function Test-MIR4F210FreezeLockV1 {
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

function Test-MIR4F210StableLaneSetV1 {
  param([Parameter(Mandatory)]$Policy,[Parameter(Mandatory)]$MinimumLane,[Parameter(Mandatory)]$LatestLane)
  if ([string]$MinimumLane.id -cne 'stable-minimum' -or [string]$LatestLane.id -cne 'stable-latest' -or
      [string]$MinimumLane.channel -cne 'stable' -or [string]$LatestLane.channel -cne 'stable' -or
      [string]$MinimumLane.version -cne [string]$Policy.post_stable.minimum_lane.version -or
      [version][string]$LatestLane.version -lt [version][string]$MinimumLane.version -or
      [string]$MinimumLane.sha256 -notmatch '^[A-F0-9]{64}$' -or [string]$LatestLane.sha256 -notmatch '^[A-F0-9]{64}$' -or
      -not [bool]$MinimumLane.exact_candidate_lock -or -not [bool]$LatestLane.exact_candidate_lock) {
    throw '[mir4-f210-stable-dual-lane]'
  }
  return $true
}
