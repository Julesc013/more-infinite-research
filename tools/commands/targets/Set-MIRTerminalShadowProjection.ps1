param(
  [Parameter(Mandatory)][string]$Release,
  [Parameter(Mandatory)][string]$TargetRoot,
  [string]$SourceRepoRoot = "",
  [string]$ProfilesPath = ".mir/releases/terminal/MIR3-Terminal-Shadow-ProjectionProfilesV1.json",
  [switch]$Check
)

$ErrorActionPreference = "Stop"
if (-not $SourceRepoRoot) {
  $SourceRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
}
$SourceRepoRoot = (Resolve-Path -LiteralPath $SourceRepoRoot).Path
$TargetRoot = (Resolve-Path -LiteralPath $TargetRoot).Path
if (-not [IO.Path]::IsPathRooted($ProfilesPath)) { $ProfilesPath = Join-Path $SourceRepoRoot $ProfilesPath }

function Write-MIRUtf8NoBom {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Text)
  [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path))
  [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function ConvertTo-MIRStableJson {
  param([Parameter(Mandatory)]$Value)
  return (($Value | ConvertTo-Json -Depth 100) + "`n")
}

function Assert-OrWriteMIRJson {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value, [switch]$Exact)
  $expected = ConvertTo-MIRStableJson -Value $Value
  if ($Check) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Generated terminal shadow authority is missing: $Path" }
    $actualObject = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100
    $actual = ConvertTo-MIRStableJson -Value $actualObject
    if ($actual -cne $expected) { throw "Generated terminal shadow authority is stale: $Path" }
    return
  }
  Write-MIRUtf8NoBom -Path $Path -Text $expected
}

function Get-MIRGitCommit {
  param([Parameter(Mandatory)][string]$Ref)
  $value = (& git -C $SourceRepoRoot rev-parse "$Ref^{commit}" 2>$null)
  if ($LASTEXITCODE -ne 0 -or @($value).Count -ne 1) { throw "Terminal shadow input ref is unavailable: $Ref" }
  return ([string]$value).Trim()
}

function Get-MIRGitTree {
  param([Parameter(Mandatory)][string]$Ref)
  $value = (& git -C $SourceRepoRoot rev-parse "$Ref^{tree}" 2>$null)
  if ($LASTEXITCODE -ne 0 -or @($value).Count -ne 1) { throw "Terminal shadow input tree is unavailable: $Ref" }
  return ([string]$value).Trim()
}

function Get-MIRGitBlob {
  param([Parameter(Mandatory)][string]$Commit, [Parameter(Mandatory)][string]$Path)
  $value = (& git -C $SourceRepoRoot rev-parse "${Commit}:$Path" 2>$null)
  if ($LASTEXITCODE -ne 0 -or @($value).Count -ne 1) { throw "Terminal assurance overlay path is unavailable: ${Commit}:$Path" }
  return ([string]$value).Trim()
}

function Write-MIRGitBlob {
  param([Parameter(Mandatory)][string]$Commit, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Destination)
  [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination))
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = "git"
  $start.UseShellExecute = $false
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  foreach ($argument in @("-C", $SourceRepoRoot, "cat-file", "blob", "${Commit}:$Path")) { [void]$start.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $start
  [void]$process.Start()
  $memory = [IO.MemoryStream]::new()
  try {
    $process.StandardOutput.BaseStream.CopyTo($memory)
    $errorText = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Unable to materialize terminal assurance overlay ${Commit}:$Path. $errorText" }
    [IO.File]::WriteAllBytes($Destination, $memory.ToArray())
  } finally {
    $memory.Dispose()
    $process.Dispose()
  }
}

function Set-MIRAssuranceOverlays {
  param([Parameter(Mandatory)]$Target)
  $targetPrefix = $TargetRoot.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) + [IO.Path]::DirectorySeparatorChar
  foreach ($overlay in @($Target.assurance_overlays)) {
    $commit = Get-MIRGitCommit -Ref ([string]$overlay.commit)
    if ($commit -ne [string]$overlay.commit) { throw "Terminal assurance overlay commit changed: $($overlay.id)" }
    foreach ($file in @($overlay.files)) {
      $path = ([string]$file.path).Replace("\", "/")
      $observedBlob = Get-MIRGitBlob -Commit $commit -Path $path
      if ($observedBlob -ne [string]$file.blob) { throw "Terminal assurance overlay blob changed: $($overlay.id) $path" }
      $destination = [IO.Path]::GetFullPath((Join-Path $TargetRoot $path))
      if (-not $destination.StartsWith($targetPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Terminal assurance overlay escapes the target root: $path" }
      if ($Check) {
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw "Terminal assurance overlay file is missing: $path" }
        $targetBlob = (& git hash-object --no-filters -- $destination 2>$null)
        if ($LASTEXITCODE -ne 0 -or ([string]$targetBlob).Trim() -ne [string]$file.blob) { throw "Terminal assurance overlay file is stale: $path" }
      } else {
        Write-MIRGitBlob -Commit $commit -Path $path -Destination $destination
      }
    }
  }
}

function Get-MIRConvergenceReleaseBlock {
  param([Parameter(Mandatory)]$Target, [Parameter(Mandatory)]$PortableSource)
  $assuranceOverlaySummary = if (@($Target.assurance_overlays).Count -eq 0) { "none" } else { @($Target.assurance_overlays | ForEach-Object { "$([string]$_.id)@$([string]$_.commit)" }) -join "," }
  return @"
release:
  version: "$([string]$Target.release)"
  branch: $([string]$Target.shadow_branch)
  factorio_version: "$([string]$Target.factorio_line)"
  baseline_commit: $([string]$Target.baseline.commit)
  baseline_tag: "$([string]$Target.baseline.tag)"
  pre_dot5_public_predecessor: "$([string]$Target.pre_dot5.tag)"
  portable_source_release: "$([string]$PortableSource.release)"
  portable_source_commit: $([string]$PortableSource.authority_commit)
  target_profile: "$([string]$Target.target_profile)"
  target_adapter: "$([string]$Target.target_adapter)"
  target_assurance_overlays: "$assuranceOverlaySummary"
  objective: $([string]$Target.objective)
  public_contract_change: $([string]$Target.public_contract_change)
  terminal_shadow_status: source-unfrozen-candidate-unassigned
"@
}

function Set-MIRConvergenceAuthority {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Target, [Parameter(Mandatory)]$PortableSource)
  $expected = Get-MIRConvergenceReleaseBlock -Target $Target -PortableSource $PortableSource
  $assuranceOverlaySummary = if (@($Target.assurance_overlays).Count -eq 0) { "none" } else { @($Target.assurance_overlays | ForEach-Object { "$([string]$_.id)@$([string]$_.commit)" }) -join "," }
  if ($Check) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Terminal convergence authority is missing: $Path" }
    $text = Get-Content -Raw -LiteralPath $Path
    foreach ($line in @(
      "  version: `"$([string]$Target.release)`"",
      "  branch: $([string]$Target.shadow_branch)",
      "  factorio_version: `"$([string]$Target.factorio_line)`"",
      "  baseline_commit: $([string]$Target.baseline.commit)",
      "  baseline_tag: `"$([string]$Target.baseline.tag)`"",
      "  pre_dot5_public_predecessor: `"$([string]$Target.pre_dot5.tag)`"",
      "  portable_source_release: `"$([string]$PortableSource.release)`"",
      "  portable_source_commit: $([string]$PortableSource.authority_commit)",
      "  target_profile: `"$([string]$Target.target_profile)`"",
      "  target_adapter: `"$([string]$Target.target_adapter)`"",
      "  target_assurance_overlays: `"$assuranceOverlaySummary`"",
      "  terminal_shadow_status: source-unfrozen-candidate-unassigned"
    )) {
      if (-not $text.Contains($line)) { throw "Terminal convergence authority is stale for ${Release}: $line" }
    }
    return
  }

  $prefix = "schema: 1`n`n"
  $suffix = ""
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    $current = (Get-Content -Raw -LiteralPath $Path).Replace("`r`n", "`n").Replace("`r", "`n")
    $match = [regex]::Match($current, '(?ms)^release:\n(?:^  [^\n]*\n?)*')
    if ($match.Success) {
      $prefix = $current.Substring(0, $match.Index)
      $suffix = $current.Substring($match.Index + $match.Length).TrimStart("`n")
    }
  }
  if ([string]::IsNullOrWhiteSpace($suffix)) {
    $suffix = @"

terminal_projection:
  product_disposition: $([string]$Target.product_disposition)
  candidate_id: null
  source_frozen: false

release_gates:
  - exact-target-engine-load
  - direct-dot5-upgrade
  - direct-pre-dot5-upgrade
  - deterministic-package
  - complete-structured-validation-summary
"@.TrimStart("`n")
  }
  Write-MIRUtf8NoBom -Path $Path -Text ($prefix.TrimEnd() + "`n`n" + $expected.TrimEnd() + "`n`n" + $suffix.TrimStart() + "`n")
}

$profiles = Get-Content -Raw -LiteralPath $ProfilesPath | ConvertFrom-Json -Depth 100
if ([int]$profiles.schema -ne 1 -or [string]$profiles.kind -ne "MIR3TerminalShadowProjectionProfilesV1") {
  throw "Terminal shadow projection profile authority is invalid."
}
$rows = @($profiles.targets | Where-Object { [string]$_.release -eq $Release })
if ($rows.Count -ne 1) { throw "Expected one terminal shadow projection profile for $Release." }
$target = $rows[0]

foreach ($input in @($target.baseline, $target.pre_dot5)) {
  if ([string]$input.release -ne [string]$input.tag) { throw "Terminal shadow input release/tag mismatch for $Release." }
  $observed = Get-MIRGitCommit -Ref ([string]$input.tag)
  if ($observed -ne [string]$input.commit) { throw "Terminal shadow input tag moved: $($input.tag)" }
}
if ((Get-MIRGitCommit -Ref ([string]$profiles.portable_source.authority_commit)) -ne [string]$profiles.portable_source.authority_commit -or
    (Get-MIRGitTree -Ref ([string]$profiles.portable_source.authority_commit)) -ne [string]$profiles.portable_source.authority_tree) {
  throw "Portable terminal source authority changed."
}

Set-MIRAssuranceOverlays -Target $target

$infoPath = Join-Path $TargetRoot "info.json"
if (-not (Test-Path -LiteralPath $infoPath -PathType Leaf)) { throw "Target shadow has no info.json: $TargetRoot" }
$info = Get-Content -Raw -LiteralPath $infoPath | ConvertFrom-Json -Depth 100
if ($Check) {
  if ([string]$info.version -ne [string]$target.release -or [string]$info.factorio_version -ne [string]$target.factorio_line) {
    throw "Target package metadata does not match terminal projection $Release."
  }
} else {
  $info.version = [string]$target.release
  $info.factorio_version = [string]$target.factorio_line
  Write-MIRUtf8NoBom -Path $infoPath -Text (ConvertTo-MIRStableJson -Value $info)
}

Set-MIRConvergenceAuthority -Path (Join-Path $TargetRoot ".mir/convergence.yml") -Target $target -PortableSource $profiles.portable_source

$releaseRecordPath = Join-Path $SourceRepoRoot ".mir/releases/records/$Release.json"
if (-not (Test-Path -LiteralPath $releaseRecordPath -PathType Leaf)) { throw "Canonical planned ReleaseRecord is missing for $Release." }
$releaseRecord = Get-Content -Raw -LiteralPath $releaseRecordPath | ConvertFrom-Json -Depth 100
if ([string]$releaseRecord.release -ne $Release -or [string]$releaseRecord.target -ne [string]$target.factorio_line -or
    [string]$releaseRecord.state -ne "planned" -or [string]$releaseRecord.candidate_id -ne "not-assigned") {
  throw "Canonical planned ReleaseRecord disagrees with terminal projection $Release."
}
$projectionRoot = Join-Path $TargetRoot ".mir/releases/terminal/shadows/$Release"
Assert-OrWriteMIRJson -Path (Join-Path $TargetRoot ".mir/releases/records/$Release.json") -Value $releaseRecord

$packageManifest = [ordered]@{
  schema = 1
  kind = "Mir3TerminalPackageManifestV1"
  release = [string]$target.release
  target = [string]$target.factorio_line
  source = [ordered]@{
    portable_release = [string]$profiles.portable_source.release
    portable_authority_commit = [string]$profiles.portable_source.authority_commit
    portable_authority_tree = [string]$profiles.portable_source.authority_tree
    target_assurance_overlays = @($target.assurance_overlays)
    immutable_dot5_predecessor = $target.baseline
    pre_dot5_public_predecessor = $target.pre_dot5
  }
  semantic_roots = @(
    [string]$profiles.portable_source.product_admission,
    [string]$profiles.portable_source.product_implementation,
    ".mir/releases/terminal/baselines/$([string]$target.baseline.release)"
  )
  inventories = [ordered]@{
    baseline = ".mir/releases/terminal/baselines/$([string]$target.baseline.release)"
    product_findings = @($target.product_findings)
    product_disposition = [string]$target.product_disposition
  }
  schemas = @(
    "spec/schemas/mir3-terminal-package-manifest.schema.json",
    "spec/schemas/mir3-terminal-release-manifest.schema.json"
  )
  migration_watermark = [ordered]@{
    predecessor = [string]$target.baseline.release
    stable_identifiers = "preserve"
    new_identity_allocation = "forbidden-without-admitted-target-delta"
  }
  toolchain = [ordered]@{
    projection_profiles = ".mir/releases/terminal/MIR3-Terminal-Shadow-ProjectionProfilesV1.json"
    projection_command = "tools/commands/targets/Set-MIRTerminalShadowProjection.ps1"
    target_adapter = [string]$target.target_adapter
  }
  mir4_successor_target = [string]$target.mir4_successor_target
  upgrade_obligation = @($target.upgrade_rows)
  source_frozen = $false
  candidate_id = $null
}
Assert-OrWriteMIRJson -Path (Join-Path $projectionRoot "package-manifest.json") -Value $packageManifest

$qualificationContext = [ordered]@{
  schema = 1
  kind = "MIR3TerminalShadowQualificationContextV1"
  release = [string]$target.release
  target = [string]$target.factorio_line
  exact_engine = [string]$target.exact_engine
  support_tier = [string]$target.support_tier
  target_profile = [string]$target.target_profile
  target_adapter = [string]$target.target_adapter
  assurance_overlays = @($target.assurance_overlays)
  baseline = $target.baseline
  pre_dot5 = $target.pre_dot5
  upgrade_rows = @($target.upgrade_rows)
  package_manifest = ".mir/releases/terminal/shadows/$Release/package-manifest.json"
  release_record = ".mir/releases/records/$Release.json"
  release_notes = "docs/releases/notes/release-notes-$Release.md"
  phase = "shadow-convergence"
  candidate_id = $null
}
Assert-OrWriteMIRJson -Path (Join-Path $projectionRoot "qualification-context.json") -Value $qualificationContext

$transitionPlan = [ordered]@{
  schema = 1
  kind = "MIR3TerminalShadowTransitionPlanV1"
  release = [string]$target.release
  target = [string]$target.factorio_line
  state = "materialized-source-unfrozen-candidate-unassigned"
  shadow_branch = [string]$target.shadow_branch
  promotion_branch = [string]$target.promotion_branch
  immutable_inputs = [ordered]@{baseline=$target.baseline;pre_dot5=$target.pre_dot5;portable_source=$profiles.portable_source;assurance_overlays=@($target.assurance_overlays)}
  generated_authorities = @(
    "info.json",
    ".mir/convergence.yml",
    ".mir/releases/records/$Release.json",
    ".mir/releases/terminal/shadows/$Release/package-manifest.json",
    ".mir/releases/terminal/shadows/$Release/qualification-context.json",
    "docs/releases/notes/release-notes-$Release.md",
    "changelog.txt"
  )
  product_findings = @($target.product_findings)
  product_disposition = [string]$target.product_disposition
  receipt_after_proof = ".mir/releases/terminal/shadows/$Release/transition-receipt.json"
  source_frozen = $false
  candidate_id = $null
}
Assert-OrWriteMIRJson -Path (Join-Path $projectionRoot "transition-plan.json") -Value $transitionPlan

$marker = "<!-- MIR3-TERMINAL-SHADOW release=$Release target=$([string]$target.factorio_line) baseline=$([string]$target.baseline.release) pre-dot5=$([string]$target.pre_dot5.release) candidate=unassigned source-frozen=false -->"
$notesPath = Join-Path $TargetRoot "docs/releases/notes/release-notes-$Release.md"
if ($Check) {
  if (-not (Test-Path -LiteralPath $notesPath -PathType Leaf)) { throw "Terminal release notes are missing for $Release." }
  $notes = (Get-Content -Raw -LiteralPath $notesPath).Replace("`r`n", "`n").Replace("`r", "`n")
  if (-not $notes.StartsWith("---`n") -or -not $notes.Contains($marker) -or $notes -notmatch [regex]::Escape($Release)) {
    throw "Terminal release-note identity or front matter is stale for $Release."
  }
  $frontMatterEnd = $notes.IndexOf("`n---`n", 4)
  if ($frontMatterEnd -lt 0 -or $notes.IndexOf($marker) -lt ($frontMatterEnd + 5)) {
    throw "Terminal release-note marker must follow YAML front matter for $Release."
  }
} else {
  if (Test-Path -LiteralPath $notesPath -PathType Leaf) {
    $notes = (Get-Content -Raw -LiteralPath $notesPath).Replace("`r`n", "`n").Replace("`r", "`n")
    $notes = [regex]::Replace($notes, '(?m)^<!-- MIR3-TERMINAL-SHADOW[^\n]*-->\n*', '')
    $notes = $notes.TrimStart()
    if (-not $notes.StartsWith("---`n")) { throw "Existing terminal release notes require YAML front matter for $Release." }
    $frontMatterEnd = $notes.IndexOf("`n---`n", 4)
    if ($frontMatterEnd -lt 0) { throw "Existing terminal release-note front matter is unterminated for $Release." }
    $afterFrontMatter = $frontMatterEnd + 5
    $notes = $notes.Substring(0, $afterFrontMatter).TrimEnd() + "`n`n" + $marker + "`n`n" + $notes.Substring($afterFrontMatter).TrimStart()
  } else {
    $notes = @"
---
title: "MIR $Release Terminal Shadow Notes"
status: draft
applies_to: "$Release"
audience: player
doc_type: release-plan
owner: mir-maintainers
last_reviewed: 2026-08-12
supersedes: []
superseded_by: []
---

$marker

# MIR $Release terminal shadow

This is an unfrozen target-native MIR 3 terminal shadow for Factorio $([string]$target.factorio_line). Its candidate remains unassigned.

- Immutable predecessor: $([string]$target.baseline.release) at $([string]$target.baseline.commit)
- Portable source authority: $([string]$profiles.portable_source.release) at $([string]$profiles.portable_source.authority_commit)
- Product disposition: $([string]$target.product_disposition)
- Required upgrades: $(@($target.upgrade_rows) -join ", ")
"@
  }
  Write-MIRUtf8NoBom -Path $notesPath -Text ($notes.TrimEnd() + "`n")
}

$changelogPath = Join-Path $TargetRoot "changelog.txt"
$versionPattern = '(?m)^Version:\s+' + [regex]::Escape($Release) + '\s*$'
if ($Check) {
  if (-not (Test-Path -LiteralPath $changelogPath -PathType Leaf) -or (Get-Content -Raw -LiteralPath $changelogPath) -notmatch $versionPattern) {
    throw "Terminal package changelog identity is missing for $Release."
  }
} else {
  $changelog = if (Test-Path -LiteralPath $changelogPath -PathType Leaf) { (Get-Content -Raw -LiteralPath $changelogPath).Replace("`r`n", "`n").Replace("`r", "`n") } else { "" }
  if ($changelog -notmatch $versionPattern) {
    $entry = @"
---------------------------------------------------------------------------------------------------
Version: $Release
Date: 2026-08-12

  Changes:

    - Materialized the governed MIR 3 terminal target shadow from immutable $([string]$target.baseline.release) inputs.

  Compatibility:

    - Applied target disposition: $([string]$target.product_disposition).

"@
    $changelog = $entry.TrimStart("`n") + $changelog.TrimStart()
    Write-MIRUtf8NoBom -Path $changelogPath -Text ($changelog.TrimEnd() + "`n")
  }
}

$verb = if ($Check) { "is current" } else { "materialized" }
Write-Host "[ok] MIR $Release terminal shadow projection authority $verb."
