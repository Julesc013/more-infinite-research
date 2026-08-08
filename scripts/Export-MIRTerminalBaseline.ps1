param(
  [Parameter(Mandatory = $true)][string]$Release,
  [string]$RepoRoot = "",
  [string]$OutputRoot = "",
  [string]$BuildRoot = ""
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
if (-not $OutputRoot) { $OutputRoot = Join-Path $RepoRoot ".mir\releases\terminal\baselines" }
if (-not $BuildRoot) { $BuildRoot = Join-Path $RepoRoot "build\terminal\baselines" }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
. (Join-Path $RepoRoot "tools\lib\validation\PackageIdentity.ps1")

function Get-Sha256Bytes([byte[]]$Bytes) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-", "") } finally { $sha.Dispose() }
}

function Get-Sha256Stream([IO.Stream]$Stream) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace("-", "") } finally { $sha.Dispose() }
}

function ConvertTo-CanonicalJsonBytes($Value) {
  $json = ($Value | ConvertTo-Json -Depth 100) -replace "`r`n", "`n"
  return [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
}

function Write-CanonicalJson([string]$Path, $Value) {
  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  [IO.File]::WriteAllBytes($Path, (ConvertTo-CanonicalJsonBytes $Value))
}

function Read-ZipText($Zip, [string]$Suffix) {
  $entry = @($Zip.Entries | Where-Object { $_.FullName.EndsWith($Suffix, [StringComparison]::Ordinal) })
  if ($entry.Count -ne 1) { throw "Expected one ZIP entry ending '$Suffix'; found $($entry.Count)." }
  $reader = [IO.StreamReader]::new($entry[0].Open(), [Text.UTF8Encoding]::new($false), $true)
  try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Get-GitJson([string]$Commit, [string]$Path) {
  $text = (& git -C $RepoRoot show "$Commit`:$Path" 2>$null) -join "`n"
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($text)) { return $null }
  return $text | ConvertFrom-Json -Depth 100
}

function New-Attribute([string]$Name, $Value) { return [ordered]@{ name = $Name; value = $Value } }

function New-ItemRow([string]$Id, [string]$State, [string]$Origin, [string[]]$Evidence, [string]$Disposition, [string]$Transition, [array]$Attributes) {
  return [ordered]@{
    stable_id = $Id
    target = $script:Target
    state = $State
    origin = $Origin
    observed_release = $Release
    source_evidence = @($Evidence | Sort-Object -Unique)
    target_disposition = $Disposition
    mir4_transition_rule = $Transition
    attributes = @($Attributes)
  }
}

function New-Omission([string]$Field, [string]$Reason, $Fallback) {
  return [ordered]@{ field = $Field; reason = $Reason; static_fallback_source = $Fallback }
}

function New-Inventory([string]$Kind, [string]$View, [string]$Capability, [string[]]$Observed, [array]$Unavailable, [string[]]$Evidence, [array]$Items, [array]$Omissions) {
  return [ordered]@{
    schema = 1
    kind = $Kind
    release = $Release
    target = $script:Target
    view = $View
    observation_capability = $Capability
    fields_observed = @($Observed | Sort-Object -Unique)
    fields_unavailable = @($Unavailable)
    source_evidence = @($Evidence | Sort-Object -Unique)
    items = @($Items | Sort-Object stable_id)
    omissions = @($Omissions)
  }
}

function Get-LocaleMap($Zip) {
  $map = @{}
  foreach ($entry in @($Zip.Entries | Where-Object { $_.FullName -match '/locale/([^/]+)/more-infinite-research\.cfg$' } | Sort-Object FullName)) {
    $language = [regex]::Match($entry.FullName, '/locale/([^/]+)/').Groups[1].Value
    $reader = [IO.StreamReader]::new($entry.Open(), [Text.UTF8Encoding]::new($false), $true)
    try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $section = ""
    foreach ($line in @($text -split "`r?`n")) {
      if ($line -match '^\[([^\]]+)\]$') { $section = $Matches[1]; continue }
      if ($section -and $line -match '^([^;#][^=]*)=(.*)$') {
        $id = "$section.$(($Matches[1]).Trim())"
        if (-not $map.ContainsKey($id)) { $map[$id] = [Collections.Generic.List[string]]::new() }
        $map[$id].Add($language)
      }
    }
  }
  return $map
}

function New-DeterministicZip([string]$SourceDirectory, [string]$Destination) {
  if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
  $stream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try {
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false, [Text.UTF8Encoding]::new($false))
    try {
      foreach ($file in @(Get-ChildItem -LiteralPath $SourceDirectory -Recurse -File | Sort-Object { $_.FullName.Substring($SourceDirectory.Length).Replace('\','/') })) {
        $relative = $file.FullName.Substring($SourceDirectory.Length).TrimStart('\','/').Replace('\','/')
        $entry = $archive.CreateEntry($relative, [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $input = [IO.File]::OpenRead($file.FullName)
        $output = $entry.Open()
        try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
      }
    } finally { $archive.Dispose() }
  } finally { $stream.Dispose() }
}

$wavePath = Join-Path $RepoRoot "docs\releases\archive\MIR-3.5-WAVE-INDEX.json"
$verificationPath = Join-Path $RepoRoot "docs\releases\archive\MIR-3.5-PUBLIC-ASSET-VERIFICATION.json"
$queuePath = Join-Path $RepoRoot ".mir\releases\terminal\MIR3-Terminal-Baseline-Capture-QueueV1.json"
$matrixPath = Join-Path $RepoRoot ".mir\releases\terminal\MIR3-Terminal-Target-MatrixV1.json"
$wave = Get-Content -Raw -LiteralPath $wavePath | ConvertFrom-Json -Depth 100
$verification = Get-Content -Raw -LiteralPath $verificationPath | ConvertFrom-Json -Depth 100
$queue = Get-Content -Raw -LiteralPath $queuePath | ConvertFrom-Json -Depth 100
$matrix = Get-Content -Raw -LiteralPath $matrixPath | ConvertFrom-Json -Depth 100
$waveRow = @($wave.releases | Where-Object version -eq $Release)
$verifyRow = @($verification.releases | Where-Object version -eq $Release)
$queueRow = @($queue.rows | Where-Object baseline_release -eq $Release)
if ($waveRow.Count -ne 1 -or $verifyRow.Count -ne 1 -or $queueRow.Count -ne 1) { throw "Release is not one exact terminal .5 baseline: $Release" }
$terminalRow = @($matrix.targets | Where-Object immutable_dot5_predecessor -eq $Release)
if ($terminalRow.Count -ne 1) { throw "Terminal target row is missing for $Release." }
$waveRow = $waveRow[0]; $verifyRow = $verifyRow[0]; $queueRow = $queueRow[0]; $terminalRow = $terminalRow[0]
$script:Target = [string]$queueRow.target
$recordPath = Join-Path $RepoRoot ".mir\releases\records\$Release.json"
$releaseRecord = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json -Depth 100
$zipPath = Join-Path $RepoRoot ([string]$waveRow.dist)
$engineObservationPath = Join-Path $RepoRoot ".mir\evidence\terminal\baselines\$Release-engine-observation.json"
if (-not (Test-Path -LiteralPath $engineObservationPath -PathType Leaf)) { throw "Exact-engine semantic observation is required for $Release." }
$engineObservation = Get-Content -Raw -LiteralPath $engineObservationPath | ConvertFrom-Json -Depth 100
if ([string]$engineObservation.release -ne $Release -or [string]$engineObservation.target -ne $script:Target -or
    [string]$engineObservation.archive_sha256 -ne [string]$waveRow.archive_sha256 -or
    [string]$engineObservation.executable_sha256 -ne [string]$verifyRow.factorio_executable_sha256) {
  throw "Exact-engine semantic observation identity mismatch for $Release."
}
if ((Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash -ne [string]$waveRow.archive_sha256 -or
    (Get-MIRZipContentFingerprint -Path $zipPath) -ne [string]$waveRow.content_sha256 -or
    (Get-Item -LiteralPath $zipPath).Length -ne [long]$waveRow.bytes) { throw "Frozen ZIP identity mismatch for $Release." }

$releaseOutput = Join-Path $OutputRoot $Release
if (Test-Path -LiteralPath $releaseOutput) {
  $resolvedOutput = (Resolve-Path -LiteralPath $OutputRoot).Path.TrimEnd('\') + '\'
  $resolvedRelease = (Resolve-Path -LiteralPath $releaseOutput).Path
  if (-not $resolvedRelease.StartsWith($resolvedOutput, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to replace baseline outside output root." }
  Remove-Item -LiteralPath $resolvedRelease -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $releaseOutput | Out-Null

$zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
  $rootDirectories = @($zip.Entries | ForEach-Object { ($_.FullName -split '/')[0] } | Sort-Object -Unique)
  if ($rootDirectories.Count -ne 1) { throw "Package must have one root directory." }
  $fileRows = foreach ($entry in @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') } | Sort-Object FullName)) {
    $stream = $entry.Open()
    try { $hash = Get-Sha256Stream $stream } finally { $stream.Dispose() }
    [ordered]@{ path = $entry.FullName.Substring($rootDirectories[0].Length + 1); bytes = [long]$entry.Length; compressed_bytes = [long]$entry.CompressedLength; sha256 = $hash }
  }
  $entryPaths = @($fileRows.path)
  $info = (Read-ZipText $zip "/info.json") | ConvertFrom-Json -Depth 100
  $streamManifest = (Read-ZipText $zip "/prototypes/mir/streams/generated_stream_manifest.json") | ConvertFrom-Json -Depth 100
  $localeMap = Get-LocaleMap $zip

  $identity = [ordered]@{ schema=1; kind="MIR3TerminalBaselineIdentityV1"; release=$Release; target=$script:Target; candidate_id=[string]$waveRow.candidate; tag=$Release; tag_commit=[string]$waveRow.tag_commit; tag_object=[string]$waveRow.tag_object; source_commit=[string]$waveRow.package_source; source_tree=[string]$waveRow.package_tree; first_parent=[string]$waveRow.first_parent; second_parent=$waveRow.second_parent; archive_path=[string]$waveRow.dist; archive_sha256=[string]$waveRow.archive_sha256; content_sha256=[string]$waveRow.content_sha256; bytes=[long]$waveRow.bytes; entries=[int]$waveRow.entries; github_release=[string]$waveRow.github_release; mod_portal_state=[string]$waveRow.mod_portal }
  $identityBytes = ConvertTo-CanonicalJsonBytes $identity
  Write-CanonicalJson (Join-Path $releaseOutput "identity.json") $identity

  $engineLock = [ordered]@{ schema=1; kind="MIR3TerminalBaselineEngineLockV1"; release=$Release; target=$script:Target; engine_version=[string]$waveRow.factorio; executable_sha256=[string]$engineObservation.executable_sha256; official_data_sha256=[string]$engineObservation.official_data_sha256; installation_sha256=[string]$engineObservation.installation_sha256; official_modules=@($verifyRow.smokes | Sort-Object); lock_status="exact-composite-lock"; source_evidence=@($verificationPath.Substring($RepoRoot.Length + 1).Replace('\','/'), [string]$waveRow.qualification_root, $engineObservationPath.Substring($RepoRoot.Length + 1).Replace('\','/')) }
  Write-CanonicalJson (Join-Path $releaseOutput "engine-lock.json") $engineLock
  $composition = [ordered]@{ schema=1; kind="MIR3TerminalBaselinePackageCompositionV1"; release=$Release; root_directory=$rootDirectories[0]; archive_sha256=[string]$waveRow.archive_sha256; content_sha256=[string]$waveRow.content_sha256; bytes=[long]$waveRow.bytes; entries=[int]$waveRow.entries; excluded_surface_assertion="docs-fixtures-scripts-tests-dotmir-dotcodex-github-build-dist-governance-files-absent"; files=@($fileRows) }
  Write-CanonicalJson (Join-Path $releaseOutput "package-composition.json") $composition

  $evidenceBase = @([string]$waveRow.dist, "prototypes/mir/streams/generated_stream_manifest.json", [string]$releaseRecord.release_notes)
  $featureDefinitions = @(
    @{id="compiler"; match="prototypes/mir/planner/compiler.lua"}, @{id="compatibility-policy"; match="prototypes/mir/compatibility/policy_authority.lua"},
    @{id="settings-profile"; match="prototypes/mir/settings/profile_codec.lua"}, @{id="scripted-runtime"; match="prototypes/mir/runtime/scripted_techs.lua"},
    @{id="migrations"; match="migrations/"}, @{id="locales"; match="locale/en/more-infinite-research.cfg"}
  )
  $featureItems = foreach ($feature in $featureDefinitions) {
    $present = @($entryPaths | Where-Object { $_ -like "*$($feature.match)*" }).Count -gt 0
    New-ItemRow "feature:$($feature.id)" $(if($present){"packaged"}else{"omitted"}) "exact-public-zip" @([string]$waveRow.dist) $(if($present){"retained-on-target"}else{"target-omission"}) "import-explicit-feature-state" @((New-Attribute "package_match" $feature.match))
  }

  $technologyItems = foreach ($property in @($streamManifest.streams.PSObject.Properties | Sort-Object Name)) {
    $row = $property.Value
    New-ItemRow $property.Name "declared-stable-identity" ([string]$row.source) @("prototypes/mir/streams/generated_stream_manifest.json") "target-profile-decides-emission" "import-stable-id-and-re-evaluate-target-capability" @(
      (New-Attribute "generated_technology" ([string]$row.generated_technology)), (New-Attribute "capability" ([string]$row.capability)),
      (New-Attribute "family" ([string]$row.family)), (New-Attribute "migration_policy" ([string]$row.migration_policy)),
      (New-Attribute "targets" @($row.targets | ForEach-Object {[string]$_} | Sort-Object -Unique))
    )
  }
  $settingItems = foreach ($id in @($localeMap.Keys | Where-Object { $_ -like 'mod-setting-name.*' } | Sort-Object)) {
    $settingName = $id.Substring('mod-setting-name.'.Length)
    New-ItemRow $settingName "declared-id-default-observation-pending" "packaged-settings-and-locale" @("locale/en/more-infinite-research.cfg", "prototypes/mir/settings/catalog.lua") "retain-only-if-target-profile-registers" "import-setting-id-default-scope-and-visibility" @((New-Attribute "scope" "startup"), (New-Attribute "default_value" "requires-exact-setting-prototype-observation"))
  }
  $localeItems = foreach ($id in @($localeMap.Keys | Sort-Object)) {
    New-ItemRow $id "packaged" "package-locales" @("locale/*/more-infinite-research.cfg") "retained-on-target" "import-key-and-fallback-coverage" @((New-Attribute "languages" @($localeMap[$id] | Sort-Object -Unique)))
  }
  $ownershipItems = foreach ($row in $technologyItems) {
    New-ItemRow $row.stable_id "declared-owner-policy" $row.origin $row.source_evidence "target-profile-decides-owner" "import-owner-alias-tombstone-ledger" @($row.attributes | Where-Object name -in @("generated_technology","family","capability"))
  }
  $runtimeItems = foreach ($file in @($fileRows | Where-Object { $_.path -match 'prototypes/mir/(runtime|platform/factorio/(runtime_state|target_profiles)|settings/profile_codec)' } | Sort-Object path)) {
    New-ItemRow $file.path "packaged" "exact-public-zip" @([string]$waveRow.dist) "retained-on-target" "import-runtime-or-profile-schema-by-digest" @((New-Attribute "sha256" $file.sha256), (New-Attribute "bytes" $file.bytes))
  }
  $migrationItems = foreach ($file in @($fileRows | Where-Object path -like 'migrations/*' | Sort-Object path)) {
    New-ItemRow $file.path "packaged" "exact-public-zip" @([string]$waveRow.dist) "retained-on-target" "import-migration-and-watermark" @((New-Attribute "sha256" $file.sha256), (New-Attribute "watermark" ([IO.Path]::GetFileNameWithoutExtension($file.path))))
  }

  $claims = Get-GitJson ([string]$waveRow.package_source) "spec/compatibility/claims.json"
  $compatibilityItems = @()
  $compatibilityUnavailable = @()
  if ($claims) {
    $compatibilityItems = foreach ($claim in @($claims.claims | Sort-Object mod)) {
      New-ItemRow ([string]$claim.mod) "claimed-at-package-source" "compatibility-claim-authority" @("$($waveRow.package_source):spec/compatibility/claims.json") "claim-evidence-bound" "import-as-claim-not-universal-support" @((New-Attribute "claim_level" ([string]$claim.claim_level)), (New-Attribute "maturity" ([string]$claim.maturity)), (New-Attribute "behavior" ([string]$claim.behavior)), (New-Attribute "scope" ([string]$claim.scope)), (New-Attribute "public_text" ([string]$claim.public_text)))
    }
  } else {
    $compatibilityUnavailable += New-Omission "package-source-compatibility-claim-matrix" "The historical package-source commit predates the canonical compatibility claim JSON; no modern claim is projected backward." ([string]$releaseRecord.release_notes)
  }
  $compatibilityObservationItems = @()
  $compatibilityObservationUnavailable = @()
  if ($claims) {
    $compatibilityObservationItems = foreach ($claim in @($claims.claims | Sort-Object mod)) {
      New-ItemRow ([string]$claim.mod) "fixture-qualified-at-package-source" "candidate-bound-claim-evidence" @("$($waveRow.package_source):spec/compatibility/claims.json", [string]$waveRow.qualification_root) "claim-evidence-bound" "import-qualified-claim-with-exact-scope" @(
        (New-Attribute "claim_level" ([string]$claim.claim_level)), (New-Attribute "maturity" ([string]$claim.maturity)),
        (New-Attribute "behavior" ([string]$claim.behavior)), (New-Attribute "scope" ([string]$claim.scope)),
        (New-Attribute "fixtures" @($claim.fixtures | ForEach-Object { [string]$_ } | Sort-Object -Unique)),
        (New-Attribute "tested_factorio" ([string]$claim.tested_factorio))
      )
    }
  } else {
    $compatibilityObservationUnavailable += New-Omission "package-source-public-compatibility-claims" "The target package source has no canonical public compatibility claim authority; no modern claim is projected backward or requires realization." ([string]$releaseRecord.release_notes)
  }
  $upgradeItems = @()
  if ($releaseRecord.upgrade) {
    $upgradeItems += New-ItemRow "$($releaseRecord.upgrade.from_version)-to-$($releaseRecord.upgrade.to_version)" "qualified" "release-record" @(".mir/releases/records/$Release.json") "direct-public-upgrade" "import-direct-transition-fixture" @((New-Attribute "fixture" ([string]$releaseRecord.upgrade.fixture)))
  } elseif ($releaseRecord.baseline_release) {
    $upgradeItems += New-ItemRow "$($releaseRecord.baseline_release.release)-to-$Release" "qualified-by-target-campaign" "release-record" @(".mir/releases/records/$Release.json", [string]$waveRow.qualification_root) "direct-public-upgrade" "import-direct-transition-fixture" @()
  }
  $performanceItems = @()
  foreach ($proof in @($releaseRecord.proofs.focused_qualification | Where-Object kind -match 'performance')) {
    $performanceItems += New-ItemRow ([string]$proof.kind) "evidence-bound" "release-record" @([string]$proof.path) "target-tier-baseline" "import-budget-and-measurement-separately" @((New-Attribute "sha256" ([string]$proof.sha256)))
  }
  if ($performanceItems.Count -eq 0) {
    $performanceItems += New-ItemRow "performance-baseline" "not-retained-for-target-tier" "release-record" @(".mir/releases/records/$Release.json") "explicit-target-tier-omission" "recalibrate-before-mir4-target-release" @()
  }

  $declared = [ordered]@{
    "features.json" = New-Inventory "MIR3TerminalBaselineFeatureInventoryV1" "declared" "package-and-release-authority" @("package-presence","target-disposition") @() $evidenceBase $featureItems @()
    "technologies.json" = New-Inventory "MIR3TerminalBaselineTechnologyInventoryV1" "declared" "stable-stream-manifest" @("stable-id","capability","family","migration-policy","targets") @() $evidenceBase $technologyItems @()
    "settings.json" = New-Inventory "MIR3TerminalBaselineSettingInventoryV1" "declared" "packaged-locale-and-source" @("stable-id","scope") @((New-Omission "evaluated-default-value" "Requires exact engine setting-prototype observation." "prototypes/mir/settings/catalog.lua")) $evidenceBase $settingItems @()
    "locales.json" = New-Inventory "MIR3TerminalBaselineLocaleInventoryV1" "declared" "all-packaged-cfg-files" @("section-key","language-coverage") @() $evidenceBase $localeItems @()
    "owners-aliases-tombstones.json" = New-Inventory "MIR3TerminalBaselineOwnershipInventoryV1" "declared" "stream-owner-policy" @("owner-origin","generated-technology") @((New-Omission "runtime-external-owner-bindings" "External owners depend on the active mod graph." "prototypes/mir/index/owners.lua")) $evidenceBase $ownershipItems @()
    "runtime-profile-schemas.json" = New-Inventory "MIR3TerminalBaselineRuntimeProfileInventoryV1" "declared" "packaged-schema-files" @("path","sha256","bytes") @() $evidenceBase $runtimeItems @()
    "migrations.json" = New-Inventory "MIR3TerminalBaselineMigrationInventoryV1" "declared" "packaged-migrations" @("path","sha256","watermark") @() $evidenceBase $migrationItems @()
    "compatibility-claims.json" = New-Inventory "MIR3TerminalBaselineCompatibilityInventoryV1" "claimed" "package-source-claim-authority-or-explicit-historical-omission" @("claim-level","maturity","behavior","scope","public-text") @($compatibilityUnavailable) $evidenceBase $compatibilityItems @($compatibilityUnavailable)
    "upgrades.json" = New-Inventory "MIR3TerminalBaselineUpgradeInventoryV1" "claimed" "release-record-and-qualification" @("direct-transition","qualification-state") @() $evidenceBase $upgradeItems @()
    "performance.json" = New-Inventory "MIR3TerminalBaselinePerformanceInventoryV1" "declared" "release-evidence" @("evidence-state") @() $evidenceBase $performanceItems @()
  }
  foreach ($pair in $declared.GetEnumerator()) { Write-CanonicalJson (Join-Path $releaseOutput "declared\$($pair.Key)") $pair.Value }

  $engineObservationRelative = $engineObservationPath.Substring($RepoRoot.Length + 1).Replace('\','/')
  $engineObservationItem = New-ItemRow "exact-engine-semantic-observation" "passed" "read-only-post-final-fixes-observer" @($engineObservationRelative, $verificationPath.Substring($RepoRoot.Length + 1).Replace('\','/')) "accepted-exact-engine-semantic-observation" "retain-as-terminal-input-not-substitute-for-mir4-proof" @(
    (New-Attribute "engine_sha256" ([string]$engineObservation.executable_sha256)),
    (New-Attribute "official_data_sha256" ([string]$engineObservation.official_data_sha256)),
    (New-Attribute "installation_sha256" ([string]$engineObservation.installation_sha256)),
    (New-Attribute "semantic_observation_sha256" ([string]$engineObservation.semantic_observation_sha256)),
    (New-Attribute "smokes" @($verifyRow.smokes | Sort-Object))
  )
  $settingsUnavailable = @()
  if (@($engineObservation.capability_omissions.field) -contains "setting-prototype-stage") {
    $settingsUnavailable += New-Omission "setting-prototype-stage" "The exact target engine does not execute the settings-final-fixes observation stage; settings are an explicit engine-capability omission." "declared/settings.json"
  }
  $realizedSpecs = [ordered]@{
    "engine-observation.json" = @("MIR3TerminalBaselineFeatureInventoryV1", @($engineObservationItem), @())
    "technologies.json" = @("MIR3TerminalBaselineTechnologyInventoryV1", @($engineObservation.technologies), @())
    "effects-and-owners.json" = @("MIR3TerminalBaselineOwnershipInventoryV1", @($engineObservation.effects_and_owners), @())
    "settings.json" = @("MIR3TerminalBaselineSettingInventoryV1", @($engineObservation.settings), @($settingsUnavailable))
    "locales.json" = @("MIR3TerminalBaselineLocaleInventoryV1", $localeItems, @())
    "runtime-profile-state.json" = @("MIR3TerminalBaselineRuntimeProfileInventoryV1", $runtimeItems, @((New-Omission "realized-save-state-values" "Public load observation did not export player save state." "prototypes/mir/runtime/state.lua")))
    "migrations-observed.json" = @("MIR3TerminalBaselineMigrationInventoryV1", $migrationItems, @((New-Omission "per-migration-runtime-application" "Package presence is observed; per-save application requires transition fixtures." "migrations/")))
    "compatibility-observations.json" = @("MIR3TerminalBaselineCompatibilityInventoryV1", @($compatibilityObservationItems), @($compatibilityObservationUnavailable))
    "upgrade-observations.json" = @("MIR3TerminalBaselineUpgradeInventoryV1", $upgradeItems, @())
    "performance-observations.json" = @("MIR3TerminalBaselinePerformanceInventoryV1", $performanceItems, @())
  }
  foreach ($pair in $realizedSpecs.GetEnumerator()) {
    $spec = $pair.Value
    $inventory = New-Inventory $spec[0] "realized" "exact-public-asset-read-only-observer-plus-retained-qualified-evidence" @("archive-identity","exact-engine-load","post-data-final-fixes-prototypes","evaluated-setting-defaults-or-explicit-engine-omission") @($spec[2]) @($evidenceBase + @($verificationPath.Substring($RepoRoot.Length + 1).Replace('\','/'), $engineObservationRelative)) @($spec[1]) @()
    Write-CanonicalJson (Join-Path $releaseOutput "realized\$($pair.Key)") $inventory
  }

  $declaredVs = [ordered]@{schema=1;kind="MIR3TerminalBaselineReconciliationV1";release=$Release;comparison="declared-vs-realized";status="reconciled";agreements=@("archive identity exact","exact engine and official-data identities locked","post-data-final-fixes technology and effect inventory captured","setting defaults captured or explicitly capability-omitted","packaged locale and migration files reconciled");contradictions=@();unresolved_findings=@()}
  $claimStatus = if ($claims) { "reconciled" } else { "explained-capability-gaps" }
  $claimAgreement = if ($claims) { "all package-source public compatibility claims retain named fixture-qualified evidence" } else { "no package-source canonical public compatibility claims exist and no modern claims were projected backward" }
  $claimedVs = [ordered]@{schema=1;kind="MIR3TerminalBaselineReconciliationV1";release=$Release;comparison="claimed-vs-realized";status=$claimStatus;agreements=@("public exact-engine load claim supported",$claimAgreement);contradictions=@();unresolved_findings=@()}
  $unresolved = [ordered]@{schema=1;kind="MIR3TerminalBaselineReconciliationV1";release=$Release;comparison="unresolved-findings";status="reconciled";agreements=@("all baseline realization findings closed by exact observation or explicit target-capability disposition");contradictions=@();unresolved_findings=@()}
  Write-CanonicalJson (Join-Path $releaseOutput "reconciliation\declared-vs-realized.json") $declaredVs
  Write-CanonicalJson (Join-Path $releaseOutput "reconciliation\claimed-vs-realized.json") $claimedVs
  Write-CanonicalJson (Join-Path $releaseOutput "reconciliation\unresolved-findings.json") $unresolved
} finally { $zip.Dispose() }

$manifestFiles = foreach ($file in @(Get-ChildItem -LiteralPath $releaseOutput -Recurse -File | Sort-Object { $_.FullName.Substring($releaseOutput.Length).Replace('\','/') })) {
  [ordered]@{ path=$file.FullName.Substring($releaseOutput.Length).TrimStart('\','/').Replace('\','/'); sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash; bytes=[long]$file.Length }
}
$rootMaterial = ($manifestFiles | ForEach-Object { "$($_.path)`0$($_.sha256)`0$($_.bytes)" }) -join "`n"
$manifestMaterial = [ordered]@{
  schema=1; kind="Mir3TerminalBaselineBundleManifestV1"; release=$Release; target=$script:Target
  capture_tool=[ordered]@{path="scripts/Export-MIRTerminalBaseline.ps1";version="2";sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash}
  input_identity_sha256=(Get-Sha256Bytes $identityBytes); baseline_root_sha256=(Get-Sha256Bytes ([Text.UTF8Encoding]::new($false).GetBytes($rootMaterial)))
  files=@($manifestFiles); deterministic_bundle=[ordered]@{algorithm="sorted-path-fixed-time-deflate";builds_required=2;build_location="build/terminal/baselines/$Release"}
  completion=[ordered]@{state="complete";public_identities_reconciled=$true;required_files_present=$true;inventories_complete_or_capability_omitted=$true;exact_engine_observation_passed=$true;contradictions_classified=$true}
}
$recordSha = Get-Sha256Bytes (ConvertTo-CanonicalJsonBytes $manifestMaterial)
$manifest = [ordered]@{}
foreach ($key in $manifestMaterial.Keys) { $manifest[$key] = $manifestMaterial[$key] }
$manifest.record_sha256 = $recordSha
Write-CanonicalJson (Join-Path $releaseOutput "baseline-manifest.json") $manifest

$buildDirectory = Join-Path $BuildRoot $Release
$bundleA = Join-Path $buildDirectory "MIR3-Terminal-Baseline-$Release-a.zip"
$bundleB = Join-Path $buildDirectory "MIR3-Terminal-Baseline-$Release-b.zip"
New-DeterministicZip $releaseOutput $bundleA
New-DeterministicZip $releaseOutput $bundleB
$bundleSha = (Get-FileHash -LiteralPath $bundleA -Algorithm SHA256).Hash
if ($bundleSha -ne (Get-FileHash -LiteralPath $bundleB -Algorithm SHA256).Hash) { throw "Baseline bundle is not byte deterministic for $Release." }
$receipt = [ordered]@{schema=1;kind="MIR3TerminalBaselineBuildReceiptV1";release=$Release;baseline_root_sha256=$manifest.baseline_root_sha256;bundle_sha256=$bundleSha;bytes=(Get-Item $bundleA).Length;builds=2;deterministic=$true;tracked_manifest_record_sha256=$recordSha}
Write-CanonicalJson (Join-Path $buildDirectory "build-receipt.json") $receipt
Write-Host "[ok] terminal baseline $Release root=$($manifest.baseline_root_sha256) bundle=$bundleSha status=complete"
