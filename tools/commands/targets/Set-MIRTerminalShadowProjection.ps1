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

function Get-MIRGitText {
  param([Parameter(Mandatory)][string]$Commit, [Parameter(Mandatory)][string]$Path)
  $value = @(& git -C $SourceRepoRoot show "${Commit}:$Path" 2>$null)
  if ($LASTEXITCODE -ne 0) { throw "Terminal projection text is unavailable: ${Commit}:$Path" }
  return (($value -join "`n").TrimEnd() + "`n")
}

function Test-MIRGitBlob {
  param([Parameter(Mandatory)][string]$Commit, [Parameter(Mandatory)][string]$Path)
  & git -C $SourceRepoRoot cat-file -e "${Commit}:$Path" 2>$null
  $exists = $LASTEXITCODE -eq 0
  $global:LASTEXITCODE = 0
  return $exists
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
        $orderedOverlayOutputs = @(
          foreach ($orderedOverlay in @($Target.assurance_overlays)) {
            foreach ($orderedFile in @($orderedOverlay.files)) {
              if (([string]$orderedFile.path).Replace("\", "/") -eq $path) { $orderedFile }
            }
          }
        )
        $transitionOutput = @($Target.performance_transition.output_blobs | Where-Object { [string]$_.path -eq $path })
        $expectedBlob = if ($transitionOutput.Count -eq 1) {
          [string]$transitionOutput[0].blob
        } elseif ($orderedOverlayOutputs.Count -gt 0) {
          [string]$orderedOverlayOutputs[-1].blob
        } else {
          [string]$file.blob
        }
        # Worktree checkouts may apply the repository's text normalization (for
        # example, CRLF on Windows).  Compare the clean-filtered worktree value
        # with the immutable Git blob rather than hashing platform bytes.
        $targetBlob = (& git -C $SourceRepoRoot hash-object --path=$path -- $destination 2>$null)
        if ($LASTEXITCODE -ne 0 -or ([string]$targetBlob).Trim() -ne $expectedBlob) { throw "Terminal assurance overlay file is stale: $path" }
      } else {
        Write-MIRGitBlob -Commit $commit -Path $path -Destination $destination
      }
    }
  }
}

function Set-MIRPerformanceTransition {
  param([Parameter(Mandatory)]$Target)
  $transition = $Target.performance_transition
  if ($null -eq $transition) { return }
  if ([string]$transition.phase -ne "shadow-convergence" -or [string]$transition.development_package.version -ne [string]$Target.release) {
    throw "Terminal performance transition identity is invalid for $Release."
  }
  foreach ($file in @($transition.source_files)) {
    $commit = Get-MIRGitCommit -Ref ([string]$file.commit)
    if ($commit -ne [string]$file.commit -or (Get-MIRGitBlob -Commit $commit -Path ([string]$file.path)) -ne [string]$file.blob) {
      throw "Terminal performance transition source changed: $($file.path)"
    }
    if (-not $Check) {
      Write-MIRGitBlob -Commit $commit -Path ([string]$file.path) -Destination (Join-Path $TargetRoot ([string]$file.path))
    }
  }
  if (-not $Check) {

    $policyPath = Join-Path $TargetRoot ".mir/performance.yml"
    $policy = (Get-Content -Raw -LiteralPath $policyPath).Replace("`r`n", "`n").Replace("`r", "`n")
    $policy = $policy.Replace("release: $([string]$Target.baseline.release)", "release: $Release")
    $policy = $policy.Replace("accepted_evidence: build/reports/release/$([string]$Target.baseline.release)/performance-regression.json", "accepted_evidence: pending-source-freeze-candidate-performance")
    $policy = $policy.Replace("  - Release regression evidence uses the published 2.5.0 archive and the exact 2.5.5 P12 candidate on one Factorio 2.0.77 installation.", "  - Shadow convergence uses the immutable published 2.5.5 archive and the exact current 2.5.9 development archive on one Factorio 2.0.77 installation; final acceptance requires the later assigned candidate.")
    $policy = $policy.Replace('  qualified_baseline: "2.5.0"', '  qualified_baseline: "2.5.5"')
    Write-MIRUtf8NoBom -Path $policyPath -Text ($policy.TrimEnd() + "`n")

    $budgetsPath = Join-Path $TargetRoot ".mir/performance-budgets.json"
    $budgetsText = (Get-Content -Raw -LiteralPath $budgetsPath).Replace("`r`n", "`n").Replace("`r", "`n")
    $budgetsText = $budgetsText.Replace('  "release": "2.5.5",', '  "release": "2.5.9",')
    Write-MIRUtf8NoBom -Path $budgetsPath -Text ($budgetsText.TrimEnd() + "`n")

    $campaignPath = Join-Path $TargetRoot ".mir/performance-campaign.json"
    $campaignText = (Get-Content -Raw -LiteralPath $campaignPath).Replace("`r`n", "`n").Replace("`r", "`n")
    $campaignText = $campaignText.Replace('  "schema": 2,' + "`n" + '  "release": "2.5.5",', '  "schema": 2,' + "`n" + '  "phase": "shadow-convergence",' + "`n" + '  "release": "2.5.9",')
    $campaignText = $campaignText.Replace('    "version": "2.5.0",' + "`n" + '    "archive_sha256": "65C1610BAE120F135E328583899672E3636EAAD6D946DF104FD045B2D9AB10F1",' + "`n" + '    "package_content_sha256": "5BBE4D09FD4F65D8A91D2F4AF1664D1C68B846288B9BEF7858162F3F156158F1"', '    "version": "2.5.5",' + "`n" + '    "archive_sha256": "03DFC05F94435FAACB86F19D1BF0BCD160C515C46B8372C483EEBAEB5208A41C",' + "`n" + '    "package_content_sha256": "047B3442067FEA6D43EEE8DE4C79BE6FD265B92A059B546F6EC4D5C986CCF154"')
    $oldCandidate = '    "candidate_id": "2.5-P12",' + "`n" + '    "version": "2.5.5",' + "`n" + '    "package_source_commit": "689940f436b004cf4e5981f1944ddb04eaa17367",' + "`n" + '    "package_source_sha256": "047B3442067FEA6D43EEE8DE4C79BE6FD265B92A059B546F6EC4D5C986CCF154",' + "`n" + '    "archive_sha256": "03DFC05F94435FAACB86F19D1BF0BCD160C515C46B8372C483EEBAEB5208A41C",' + "`n" + '    "package_content_sha256": "047B3442067FEA6D43EEE8DE4C79BE6FD265B92A059B546F6EC4D5C986CCF154"'
    $development = $transition.development_package
    $newCandidate = '    "state": "development-shadow-unfrozen",' + "`n" + '    "candidate_id": null,' + "`n" + "    `"version`": `"$([string]$development.version)`"," + "`n" + "    `"package_source_commit`": `"$([string]$development.package_source_commit)`"," + "`n" + "    `"package_source_sha256`": `"$([string]$development.package_source_sha256)`"," + "`n" + "    `"archive_sha256`": `"$([string]$development.archive_sha256)`"," + "`n" + "    `"package_content_sha256`": `"$([string]$development.package_content_sha256)`""
    $campaignText = $campaignText.Replace($oldCandidate, $newCandidate)
    Write-MIRUtf8NoBom -Path $campaignPath -Text ($campaignText.TrimEnd() + "`n")

    $probePath = Join-Path $TargetRoot "fixtures/performance-regression-probe/data.lua"
    $probe = (Get-Content -Raw -LiteralPath $probePath).Replace("`r`n", "`n").Replace("`r", "`n")
    $probe = $probe.Replace('mir_version ~= "2.5.5" then', 'mir_version ~= "2.5.5" and mir_version ~= "2.5.9" then')
    Write-MIRUtf8NoBom -Path $probePath -Text ($probe.TrimEnd() + "`n")

    $testPath = Join-Path $TargetRoot "scripts/Test-MIRPerformanceBudgets.ps1"
    $test = (Get-Content -Raw -LiteralPath $testPath).Replace("`r`n", "`n").Replace("`r", "`n")
    $candidateGate = @'
if ($null -eq $activeCandidate -or
    [string]$campaign.candidate.candidate_id -ne [string]$activeCandidate.candidate_id -or
    [string]$campaign.candidate.version -ne [string]$activeCandidate.mir_version -or
    [string]$campaign.candidate.package_source_commit -ne [string]$activeCandidate.package_source_commit -or
    [string]$campaign.candidate.package_source_sha256 -ne [string]$activeCandidate.package_source_sha256 -or
    [string]$campaign.candidate.archive_sha256 -ne [string]$activeCandidate.archive_sha256 -or
    [string]$campaign.candidate.package_content_sha256 -ne [string]$activeCandidate.package_content_sha256) {
  throw "Performance campaign candidate authority differs from the active $targetKey release candidate."
}
'@
    $shadowGate = @'
$shadowManifestPath = Join-Path $RepoRoot ".mir\releases\terminal\shadows\$([string]$campaign.release)\package-manifest.json"
$isShadowConvergence = [string]$campaign.phase -eq "shadow-convergence"
if ($isShadowConvergence) {
  if (-not (Test-Path -LiteralPath $shadowManifestPath -PathType Leaf)) { throw "Shadow performance campaign lacks a terminal package manifest." }
  $shadowManifest = Get-Content -Raw -LiteralPath $shadowManifestPath | ConvertFrom-Json -Depth 100
  $candidateArchive = Join-Path $RepoRoot "dist\more-infinite-research_$([string]$campaign.release).zip"
  . (Join-Path $RepoRoot "scripts\validation\PackageIdentity.ps1")
  if ($null -ne $campaign.candidate.candidate_id -or [string]$campaign.candidate.state -ne "development-shadow-unfrozen" -or
      [bool]$shadowManifest.source_frozen -or $null -ne $shadowManifest.candidate_id -or
      [string]$campaign.candidate.version -ne [string]$shadowManifest.release -or
      -not (Test-Path -LiteralPath $candidateArchive -PathType Leaf) -or
      [string]$campaign.candidate.archive_sha256 -ne (Get-MIRFileSha256 -Path $candidateArchive) -or
      [string]$campaign.candidate.package_content_sha256 -ne (Get-MIRZipContentFingerprint -Path $candidateArchive)) {
    throw "Shadow performance campaign must bind exact development bytes without allocating a candidate."
  }
} elseif ($null -eq $activeCandidate -or
          [string]$campaign.candidate.candidate_id -ne [string]$activeCandidate.candidate_id -or
          [string]$campaign.candidate.version -ne [string]$activeCandidate.mir_version -or
          [string]$campaign.candidate.package_source_commit -ne [string]$activeCandidate.package_source_commit -or
          [string]$campaign.candidate.package_source_sha256 -ne [string]$activeCandidate.package_source_sha256 -or
          [string]$campaign.candidate.archive_sha256 -ne [string]$activeCandidate.archive_sha256 -or
          [string]$campaign.candidate.package_content_sha256 -ne [string]$activeCandidate.package_content_sha256) {
  throw "Performance campaign candidate authority differs from the active $targetKey release candidate."
}
'@
    if (-not $test.Contains($candidateGate.Trim())) { throw "Terminal performance validator source boundary changed." }
    $test = $test.Replace($candidateGate.Trim(), $shadowGate.Trim())
    Write-MIRUtf8NoBom -Path $testPath -Text ($test.TrimEnd() + "`n")
  }

  foreach ($output in @($transition.output_blobs)) {
    $path = Join-Path $TargetRoot ([string]$output.path)
    $blob = (& git hash-object --no-filters -- $path 2>$null)
    if ($LASTEXITCODE -ne 0 -or ([string]$blob).Trim() -ne [string]$output.blob) { throw "Terminal performance transition output is stale: $($output.path)" }
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
  $normalizedSuffix = $suffix.Trim([char[]]@("`r", "`n"))
  Write-MIRUtf8NoBom -Path $Path -Text ($prefix.TrimEnd() + "`n`n" + $expected.TrimEnd() + "`n`n" + $normalizedSuffix + "`n")
}

function Set-MIRTerminalShadowAssuranceProfile {
  $path = Join-Path $TargetRoot ".mir/assurance.json"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Target shadow has no assurance profile authority: $path"
  }

  $config = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ([int]$config.schema -ne 1) { throw "Target shadow assurance profile schema must be 1." }

  $profileName = "terminal-shadow-convergence"
  $requiredTests = @(
    "tooling.self-test",
    "static.balance",
    "static.museum",
    "runtime.full",
    "runtime.exact-zip"
  )
  $profileProperty = $config.profiles.PSObject.Properties[$profileName]
  if ($null -eq $profileProperty) {
    $config.profiles | Add-Member -NotePropertyName $profileName -NotePropertyValue $requiredTests
  } else {
    $profileProperty.Value = $requiredTests
  }

  $releaseGovernance = @($config.classes | Where-Object { [string]$_.id -eq "release-governance" })
  if ($releaseGovernance.Count -ne 1) { throw "Target assurance policy must contain one release-governance class." }
  $shadowAuthorityPattern = '^\.mir/releases/(records/|terminal/shadows/)'
  if (@($releaseGovernance[0].patterns | Where-Object { [string]$_ -eq $shadowAuthorityPattern }).Count -eq 0) {
    $releaseGovernance[0].patterns = @($releaseGovernance[0].patterns) + $shadowAuthorityPattern
  }

  $expected = ConvertTo-MIRStableJson -Value $config
  if ($Check) {
    $actual = ConvertTo-MIRStableJson -Value (Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100)
    if ($actual -cne $expected) { throw "Terminal shadow assurance profile authority is stale: $path" }
    return
  }
  Write-MIRUtf8NoBom -Path $path -Text $expected
}

function Set-MIRTerminalLegacyFactorioVersionProbe {
  param([Parameter(Mandatory)]$Target)
  if ([string]$Target.support_tier -notin @("lts", "historical", "finite")) { return @() }
  if ([string]::IsNullOrWhiteSpace([string]$Target.exact_engine_sha256) -or
      [string]$Target.exact_engine_sha256 -notmatch '^[0-9A-F]{64}$') {
    throw "Lower terminal target lacks an exact engine SHA-256: $Release"
  }

  $relativePath = "scripts/Invoke-MIRAssurance.ps1"
  $path = Join-Path $TargetRoot $relativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Target shadow has no assurance entry point: $path" }
  $text = (Get-Content -Raw -LiteralPath $path).Replace("`r`n", "`n").Replace("`r", "`n")
  $oldLine = '    $factorioVersion = if ($factorioExists) { [string](Get-Item -LiteralPath $context.factorio).VersionInfo.FileVersion } else { "not-provided" }'
  $newLine = '    $factorioVersion = if ($factorioExists) { Get-MIRAssuranceFactorioVersion -Path $context.factorio } else { "not-provided" }'
  $functionText = @'
function Get-MIRAssuranceFactorioVersion {
  param([Parameter(Mandatory)][string]$Path)
  $item = Get-Item -LiteralPath $Path
  $version = [string]$item.VersionInfo.FileVersion
  if ([string]::IsNullOrWhiteSpace($version)) { $version = [string]$item.VersionInfo.ProductVersion }
  if ([string]::IsNullOrWhiteSpace($version)) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Path
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    [void]$start.ArgumentList.Add("--version")
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
      [void]$process.Start()
      $versionText = $process.StandardOutput.ReadToEnd() + "`n" + $process.StandardError.ReadToEnd()
      $process.WaitForExit()
      if ($process.ExitCode -eq 0 -and $versionText -match '(?m)^Version:\s+([0-9]+(?:\.[0-9]+)+)') { $version = $Matches[1] }
    } finally { $process.Dispose() }
  }
  if ([string]::IsNullOrWhiteSpace($version)) {
    $observedSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
    if ($observedSha256 -eq "__MIR_EXACT_ENGINE_SHA256__") { $version = "__MIR_EXACT_ENGINE_VERSION__" }
  }
  if ([string]::IsNullOrWhiteSpace($version)) { $version = "unknown" }
  return $version.Trim()
}
'@.Trim()
  $functionText = $functionText.Replace("__MIR_EXACT_ENGINE_SHA256__", [string]$Target.exact_engine_sha256)
  $functionText = $functionText.Replace("__MIR_EXACT_ENGINE_VERSION__", ([string]$Target.exact_engine).Replace("-only", ""))
  $functionMarker = "function Get-MIRAssuranceFactorioVersion {"
  if ($text.Contains($functionMarker)) {
    $functionPattern = '(?ms)^function Get-MIRAssuranceFactorioVersion \{.*?^\}\n\n(?=function Show-MIRAssuranceHelp \{)'
    if (-not [regex]::IsMatch($text, $functionPattern)) { throw "Existing generated Factorio version probe layout changed." }
    $text = [regex]::Replace($text, $functionPattern, $functionText + "`n`n", 1)
  } else {
    $insertMarker = "function Show-MIRAssuranceHelp {"
    if (-not $text.Contains($insertMarker)) { throw "Target assurance entry-point layout changed before the Factorio version probe." }
    $text = $text.Replace($insertMarker, $functionText + "`n`n" + $insertMarker)
  }
  if ($text.Contains($oldLine)) { $text = $text.Replace($oldLine, $newLine) }
  if (-not $text.Contains($newLine) -or -not $text.Contains('[void]$start.ArgumentList.Add("--version")')) {
    throw "Target assurance entry point lacks the bounded legacy Factorio version probe."
  }
  Assert-OrWriteMIRText -Path $path -Text ($text.TrimEnd() + "`n")
  return @($relativePath)
}

function Get-MIRVersionSlug {
  param([Parameter(Mandatory)][string]$Version)
  return $Version.Replace(".", "-")
}

function Assert-OrWriteMIRText {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Text)
  $expected = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
  if ($Check) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Generated terminal shadow text is missing: $Path" }
    $actual = (Get-Content -Raw -LiteralPath $Path).Replace("`r`n", "`n").Replace("`r", "`n")
    if ($actual -cne $expected) { throw "Generated terminal shadow text is stale: $Path" }
    return
  }
  Write-MIRUtf8NoBom -Path $Path -Text $expected
}

function Set-MIRTerminalUpgradeFixtures {
  param([Parameter(Mandatory)]$Target)
  if ([string]$Target.support_tier -notin @("lts", "historical", "finite")) { return @() }

  $baselineVersion = [string]$Target.baseline.release
  $preDot5Version = [string]$Target.pre_dot5.release
  $sourceFixtureName = "assert-upgrade-$(Get-MIRVersionSlug -Version $preDot5Version)-to-$(Get-MIRVersionSlug -Version $baselineVersion)"
  $sourceFixtureRoot = "fixtures/$sourceFixtureName"
  $sourceCommit = [string]$Target.baseline.commit
  foreach ($requiredPath in @("info.json", "control.lua", "data.lua")) {
    if (-not (Test-MIRGitBlob -Commit $sourceCommit -Path "$sourceFixtureRoot/$requiredPath")) {
      throw "Immutable predecessor lacks the target-native upgrade fixture input: $sourceFixtureRoot/$requiredPath"
    }
  }

  $sourceInfo = Get-MIRGitText -Commit $sourceCommit -Path "$sourceFixtureRoot/info.json" | ConvertFrom-Json -Depth 100
  $sourceControl = Get-MIRGitText -Commit $sourceCommit -Path "$sourceFixtureRoot/control.lua"
  $sourceData = Get-MIRGitText -Commit $sourceCommit -Path "$sourceFixtureRoot/data.lua"
  $hasSettingsUpdates = Test-MIRGitBlob -Commit $sourceCommit -Path "$sourceFixtureRoot/settings-updates.lua"
  $sourceSettingsUpdates = if ($hasSettingsUpdates) { Get-MIRGitText -Commit $sourceCommit -Path "$sourceFixtureRoot/settings-updates.lua" } else { "" }
  $rows = @()
  $registryBlocks = @()
  $generatedAuthorities = @()

  foreach ($fromVersion in @($baselineVersion, $preDot5Version)) {
    $rowId = "$fromVersion-to-$Release"
    if (@($Target.upgrade_rows | Where-Object { [string]$_ -eq $rowId }).Count -ne 1) {
      throw "Terminal upgrade row $rowId is absent or duplicated for $Release."
    }
    $fixtureName = "assert-upgrade-$(Get-MIRVersionSlug -Version $fromVersion)-to-$(Get-MIRVersionSlug -Version $Release)"
    $fixtureRoot = "fixtures/$fixtureName"
    $info = $sourceInfo | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    $info.name = "mir-fixture-$fixtureName"
    $info.title = "MIR Fixture - Assert $fromVersion to $Release Retention"
    $info.dependencies = @($info.dependencies | ForEach-Object {
      $dependency = [string]$_
      if ($dependency -match '^more-infinite-research\s') { "more-infinite-research >= $fromVersion" } else { $dependency }
    })

    $control = $sourceControl
    $control = $control.Replace("local from_version = `"$preDot5Version`"", "local from_version = `"$fromVersion`"")
    $control = $control.Replace("local to_version = `"$baselineVersion`"", "local to_version = `"$Release`"")
    $control = $control.Replace("$preDot5Version to $baselineVersion", "$fromVersion to $Release")
    $control = $control.Replace("$preDot5Version upgrade source proof", "$fromVersion upgrade source proof")
    $control = $control.Replace("mir-$preDot5Version-save", "mir-$fromVersion-save")
    foreach ($requiredMarker in @(
      "local from_version = `"$fromVersion`"",
      "local to_version = `"$Release`"",
      "[mir-fixture] $fromVersion upgrade source proof complete",
      "[mir-fixture] $fromVersion to $Release upgrade proof complete"
    )) {
      if (-not $control.Contains($requiredMarker)) { throw "Generated terminal upgrade fixture lacks marker: $requiredMarker" }
    }

    Assert-OrWriteMIRJson -Path (Join-Path $TargetRoot "$fixtureRoot/info.json") -Value $info
    Assert-OrWriteMIRText -Path (Join-Path $TargetRoot "$fixtureRoot/control.lua") -Text $control
    Assert-OrWriteMIRText -Path (Join-Path $TargetRoot "$fixtureRoot/data.lua") -Text $sourceData
    if ($hasSettingsUpdates) {
      Assert-OrWriteMIRText -Path (Join-Path $TargetRoot "$fixtureRoot/settings-updates.lua") -Text $sourceSettingsUpdates
    }

    $rows += [ordered]@{
      id = $rowId
      from = if ($fromVersion -eq $baselineVersion) { $Target.baseline } else { $Target.pre_dot5 }
      to_release = $Release
      exact_engine = [string]$Target.exact_engine
      source_fixture = [ordered]@{path=$sourceFixtureRoot;commit=$sourceCommit}
      generated_fixture = $fixtureRoot
      proof_path = "build/reports/release/$Release/$rowId-upgrade-proof.json"
      status = "planned-unfrozen-candidate-unassigned"
    }
    $registryKey = "terminal-upgrade-$(Get-MIRVersionSlug -Version $fromVersion)-to-$(Get-MIRVersionSlug -Version $Release)"
    $registryBlocks += @"
  ${registryKey}:
    requires_features: []
    assertion_path: $fixtureRoot
    validates:
      - exact-$fromVersion-source-archive
      - stable-identifier-retention
      - research-and-runtime-state-retention
      - exact-$Release-development-archive-load
"@.TrimEnd()
    $generatedAuthorities += $fixtureRoot
  }

  $manifest = [ordered]@{
    schema = 1
    kind = "MIR3TerminalShadowUpgradeFixturesV1"
    release = $Release
    target = [string]$Target.factorio_line
    phase = "shadow-convergence"
    rows = $rows
    source_frozen = $false
    candidate_id = $null
  }
  $manifestPath = ".mir/releases/terminal/shadows/$Release/upgrade-fixtures.json"
  Assert-OrWriteMIRJson -Path (Join-Path $TargetRoot $manifestPath) -Value $manifest

  $registryPath = Join-Path $TargetRoot ".mir/fixtures.yml"
  if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) { throw "Target shadow has no fixture registry: $registryPath" }
  $registry = (Get-Content -Raw -LiteralPath $registryPath).Replace("`r`n", "`n").Replace("`r", "`n")
  $startMarker = "# MIR3-TERMINAL-UPGRADE-FIXTURES release=$Release"
  $endMarker = "# MIR3-TERMINAL-UPGRADE-FIXTURES-END release=$Release"
  $blockPattern = '(?ms)^' + [regex]::Escape($startMarker) + '.*?^' + [regex]::Escape($endMarker) + '\n?'
  $registry = [regex]::Replace($registry, $blockPattern, '').TrimEnd()
  $expectedRegistry = $registry + "`n`n$startMarker`n" + ($registryBlocks -join "`n`n") + "`n$endMarker`n"
  Assert-OrWriteMIRText -Path $registryPath -Text $expectedRegistry

  return @($manifestPath, ".mir/fixtures.yml") + @($generatedAuthorities)
}

function Set-MIRTerminalReleaseNoteRegistry {
  param([Parameter(Mandatory)]$Target)
  $path = Join-Path $TargetRoot ".mir/docs.yml"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Target shadow has no documentation registry: $path" }
  $relativeNote = "docs/releases/notes/release-notes-$Release.md"
  $text = (Get-Content -Raw -LiteralPath $path).Replace("`r`n", "`n").Replace("`r", "`n")
  $startMarker = "# MIR3-TERMINAL-RELEASE-NOTE release=$Release"
  $endMarker = "# MIR3-TERMINAL-RELEASE-NOTE-END release=$Release"
  $blockPattern = '(?ms)^' + [regex]::Escape($startMarker) + '.*?^' + [regex]::Escape($endMarker) + '\n?'
  $text = [regex]::Replace($text, $blockPattern, '').TrimEnd()
  $block = @"
$startMarker
  - path: $relativeNote
    title: "MIR $Release Terminal Shadow Notes"
    status: draft
    audience: player
    doc_type: release-plan
    owner: mir-maintainers
    source_of_truth_for:
      - mir-$($Release.Replace('.', '-'))-terminal-shadow-notes
$endMarker
"@.TrimEnd()
  Assert-OrWriteMIRText -Path $path -Text ($text + "`n`n" + $block + "`n")
  return @(".mir/docs.yml")
}

function Set-MIRTerminalBackportSourceLock {
  param([Parameter(Mandatory)]$Target)
  if ([string]$Target.support_tier -notin @("lts", "historical", "finite")) { return @() }
  $lockPath = Join-Path $TargetRoot ".mir/backport-source-lock.json"
  if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { throw "Lower target shadow lacks a backport source lock: $lockPath" }
  $lock = Get-Content -Raw -LiteralPath $lockPath | ConvertFrom-Json -Depth 100
  if ([int]$lock.schema -ne 1 -or [string]$lock.mir_version -notin @([string]$Target.baseline.release, $Release)) {
    throw "Lower target source lock is not an immutable predecessor or current terminal projection."
  }
  $originalFeaturePath = [string]$lock.feature_classification
  $featurePath = ".mir/releases/terminal/shadows/$Release/feature-classification.json"
  $sourceFeaturePath = Join-Path $TargetRoot $originalFeaturePath
  if ([string]$lock.mir_version -eq $Release -and (Test-Path -LiteralPath (Join-Path $TargetRoot $featurePath) -PathType Leaf)) {
    $sourceFeaturePath = Join-Path $TargetRoot $featurePath
  }
  if (-not (Test-Path -LiteralPath $sourceFeaturePath -PathType Leaf)) { throw "Lower target source-lock feature classification is missing: $sourceFeaturePath" }
  $feature = Get-Content -Raw -LiteralPath $sourceFeaturePath | ConvertFrom-Json -Depth 100
  $feature.mir_version = $Release
  Assert-OrWriteMIRJson -Path (Join-Path $TargetRoot $featurePath) -Value $feature

  $lock.mir_version = $Release
  $lock.feature_classification = $featurePath
  $lock.release_notes = "docs/releases/notes/release-notes-$Release.md"
  $lock.validation_summary = "build/reports/release/$Release/shadow-qualification.json"
  $lock.candidate_seal = "build/reports/release/$Release/candidate-unassigned.json"
  Assert-OrWriteMIRJson -Path $lockPath -Value $lock
  return @(".mir/backport-source-lock.json", $featurePath)
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
Set-MIRPerformanceTransition -Target $target
Set-MIRTerminalShadowAssuranceProfile
$terminalLegacyProbeAuthorities = @(Set-MIRTerminalLegacyFactorioVersionProbe -Target $target)
$terminalUpgradeFixtureAuthorities = @(Set-MIRTerminalUpgradeFixtures -Target $target)
$terminalDocumentationAuthorities = @(Set-MIRTerminalReleaseNoteRegistry -Target $target)
$terminalBackportLockAuthorities = @(Set-MIRTerminalBackportSourceLock -Target $target)

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
    performance_transition = $target.performance_transition
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
  exact_engine_sha256 = [string]$target.exact_engine_sha256
  support_tier = [string]$target.support_tier
  target_profile = [string]$target.target_profile
  target_adapter = [string]$target.target_adapter
  assurance_profile = "terminal-shadow-convergence"
  assurance_overlays = @($target.assurance_overlays)
  performance_transition = $target.performance_transition
  baseline = $target.baseline
  pre_dot5 = $target.pre_dot5
  upgrade_rows = @($target.upgrade_rows)
  upgrade_fixture_manifest = if ($terminalUpgradeFixtureAuthorities.Count -gt 0) { ".mir/releases/terminal/shadows/$Release/upgrade-fixtures.json" } else { $null }
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
  immutable_inputs = [ordered]@{baseline=$target.baseline;pre_dot5=$target.pre_dot5;portable_source=$profiles.portable_source;assurance_overlays=@($target.assurance_overlays);performance_transition=$target.performance_transition}
  generated_authorities = @(
    "info.json",
    ".mir/convergence.yml",
    ".mir/assurance.json",
    ".mir/releases/records/$Release.json",
    ".mir/releases/terminal/shadows/$Release/package-manifest.json",
    ".mir/releases/terminal/shadows/$Release/qualification-context.json",
    "docs/releases/notes/release-notes-$Release.md",
    "changelog.txt"
  ) + @($terminalLegacyProbeAuthorities) + @($terminalUpgradeFixtureAuthorities) + @($terminalDocumentationAuthorities) + @($terminalBackportLockAuthorities)
  product_findings = @($target.product_findings)
  product_disposition = [string]$target.product_disposition
  receipt_after_proof = ".mir/releases/terminal/shadows/$Release/transition-receipt.json"
  source_frozen = $false
  candidate_id = $null
}
Assert-OrWriteMIRJson -Path (Join-Path $projectionRoot "transition-plan.json") -Value $transitionPlan

$marker = "<!-- MIR3-TERMINAL-SHADOW release=$Release target=$([string]$target.factorio_line) baseline=$([string]$target.baseline.release) pre-dot5=$([string]$target.pre_dot5.release) candidate=unassigned source-frozen=false -->"
$notesPath = Join-Path $TargetRoot "docs/releases/notes/release-notes-$Release.md"
$sourceLockLine = ""
if ([string]$target.support_tier -in @("lts", "historical", "finite")) {
  $shadowSourceLock = Get-Content -Raw -LiteralPath (Join-Path $TargetRoot ".mir/backport-source-lock.json") | ConvertFrom-Json -Depth 100
  $sourceLockLine = "- Historical canonical development anchor: $([string]$shadowSourceLock.canonical_dev_anchor)"
}
if ($Check) {
  if (-not (Test-Path -LiteralPath $notesPath -PathType Leaf)) { throw "Terminal release notes are missing for $Release." }
  $notes = (Get-Content -Raw -LiteralPath $notesPath).Replace("`r`n", "`n").Replace("`r", "`n")
  if (-not $notes.StartsWith("---`n") -or -not $notes.Contains($marker) -or $notes -notmatch [regex]::Escape($Release) -or
      ($sourceLockLine -and -not $notes.Contains($sourceLockLine))) {
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
- Historical target anchor: $([string]$target.baseline.release) source-lock ancestry remains bound by .mir/backport-source-lock.json
- Product disposition: $([string]$target.product_disposition)
- Required upgrades: $(@($target.upgrade_rows) -join ", ")
"@
  }
  if ($sourceLockLine) {
    $notes = [regex]::Replace($notes, '(?m)^- Historical canonical development anchor: [0-9a-f]{40}\n?', '')
    $notes = $notes.TrimEnd() + "`n`n$sourceLockLine`n"
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
