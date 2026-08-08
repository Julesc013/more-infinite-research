param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path }
. (Join-Path $RepoRoot "tools\lib\terminal\TerminalEngineObservation.ps1")
. (Join-Path $RepoRoot "tools\lib\assurance\Core.ps1")
. (Join-Path $RepoRoot "tools\lib\assurance\Hashing.ps1")

$testRoot = Join-Path $RepoRoot "build\results\terminal-engine-observation-test"
$resolvedBuildRoot = (Resolve-Path -LiteralPath (Join-Path $RepoRoot "build")).Path.TrimEnd('\') + '\'
if (Test-Path -LiteralPath $testRoot) {
  $resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot).Path
  if (-not $resolvedTestRoot.StartsWith($resolvedBuildRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to replace terminal engine-observation test output outside build/."
  }
  Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$probeSources = @(
  (Join-Path $RepoRoot "scripts\Export-MIRTerminalEngineObservation.ps1"),
  (Join-Path $RepoRoot "tools\lib\terminal\TerminalEngineObservation.ps1")
)
try {
  foreach ($probeSource in $probeSources) {
    $probePath = Join-Path $testRoot ([IO.Path]::GetFileName($probeSource))
    $probeText = [IO.File]::ReadAllText($probeSource).Replace("`r`n", "`n").Replace("`r", "`n")
    [IO.File]::WriteAllText($probePath, $probeText.Replace("`n", "`r`n"), [Text.UTF8Encoding]::new($false))
    if ((Get-MIRAssuranceCanonicalTextFileHash -Path $probePath) -ne (Get-MIRAssuranceCanonicalTextFileHash -Path $probeSource)) {
      throw "Terminal engine-observation tool identity is not invariant across LF and CRLF checkouts: $([IO.Path]::GetFileName($probeSource))"
    }
    if ((Get-FileHash -LiteralPath $probePath -Algorithm SHA256).Hash -eq (Get-MIRAssuranceCanonicalTextFileHash -Path $probePath)) {
      throw "Terminal engine-observation line-ending probe did not exercise distinct CRLF physical bytes: $([IO.Path]::GetFileName($probeSource))"
    }
  }
} finally {
  if (Test-Path -LiteralPath $testRoot) {
    $resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot).Path
    if ($resolvedTestRoot.StartsWith($resolvedBuildRoot, [StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
  }
}

$dataRaw = [pscustomobject][ordered]@{
  technology = [pscustomobject][ordered]@{
    "mir-tech-b" = [pscustomobject][ordered]@{name="mir-tech-b";enabled=$true;max_level="infinite";prerequisites=@("a");unit=[pscustomobject][ordered]@{count_formula="100*L";time=30;ingredients=@(@("automation-science-pack",1))};effects=@([pscustomobject][ordered]@{type="laboratory-speed";modifier=0.1})}
    "mir-tech-a" = [pscustomobject][ordered]@{name="mir-tech-a";enabled=$false;hidden=$true;effects=@()}
  }
  "bool-setting" = [pscustomobject][ordered]@{
    "not-mir" = [pscustomobject][ordered]@{setting_type="startup";default_value=$false}
    "mir-enabled" = [pscustomobject][ordered]@{setting_type="startup";default_value=$true}
  }
  "int-setting" = [pscustomobject][ordered]@{
    "mir-count" = [pscustomobject][ordered]@{setting_type="startup";default_value=7;minimum_value=1;maximum_value=9}
  }
}
$first = Get-MIRTerminalEngineInventory -DataRaw $dataRaw -Release "3.2.5" -Target "2.1" -DeclaredTechnologyNames @("missing", "mir-tech-b", "mir-tech-a") -EvidencePath ".mir/evidence/example.json"
$second = Get-MIRTerminalEngineInventory -DataRaw $dataRaw -Release "3.2.5" -Target "2.1" -DeclaredTechnologyNames @("mir-tech-a", "mir-tech-b", "missing") -EvidencePath ".mir/evidence/example.json"
$firstJson = $first | ConvertTo-Json -Depth 100
$secondJson = $second | ConvertTo-Json -Depth 100
if ($firstJson -ne $secondJson -or @($first.technologies).Count -ne 2 -or @($first.effects_and_owners).Count -ne 1 -or @($first.settings).Count -ne 2) {
  throw "Terminal engine inventory normalization is not deterministic or complete."
}
if ((@($first.technologies.stable_id) -join "|") -ne "mir-tech-a|mir-tech-b" -or
    (@($first.settings.stable_id) -join "|") -ne "mir-count|mir-enabled" -or
    [string]$first.effects_and_owners[0].stable_id -ne "mir-tech-b#effect-001") {
  throw "Terminal engine inventory ordering or MIR filtering failed."
}
$logInventory = Get-MIRTerminalEngineInventoryFromLog -Lines @(
  "  1.0 MIR_TERMINAL_SETTING`tbool-setting`tmir-enabled`tstartup`ttrue`t<nil>`t<nil>`t`tfalse`ta",
  "  1.1 MIR_TERMINAL_TECH`tmir-tech-b`ttrue`tfalse`tfalse`tinfinite`ta`t{count_formula=`"100*L`"}`t1",
  "  1.2 MIR_TERMINAL_EFFECT`tmir-tech-b`t1`tlaboratory-speed`t0.1`t{modifier=0.1,type=`"laboratory-speed`"}",
  "  1.3 MIR_TERMINAL_SETTINGS_COMPLETE`t1",
  "  1.4 MIR_TERMINAL_DATA_COMPLETE`t1`t1"
) -Release "3.2.5" -Target "2.1" -EvidencePath ".mir/evidence/example.json"
if (-not $logInventory.data_complete -or -not $logInventory.settings_complete -or
    @($logInventory.technologies).Count -ne 1 -or @($logInventory.effects_and_owners).Count -ne 1 -or @($logInventory.settings).Count -ne 1) {
  throw "Terminal observer line protocol did not parse its completed inventories."
}

$evidenceRoot = Join-Path $RepoRoot ".mir\evidence\terminal\baselines"
if (Test-Path -LiteralPath $evidenceRoot -PathType Container) {
  $wave = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\releases\archive\MIR-3.5-WAVE-INDEX.json") | ConvertFrom-Json -Depth 100
  $verification = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs\releases\archive\MIR-3.5-PUBLIC-ASSET-VERIFICATION.json") | ConvertFrom-Json -Depth 100
  $toolSha = Get-MIRAssuranceCanonicalTextFileHash -Path (Join-Path $RepoRoot "scripts\Export-MIRTerminalEngineObservation.ps1")
  $normalizerSha = Get-MIRAssuranceCanonicalTextFileHash -Path (Join-Path $RepoRoot "tools\lib\terminal\TerminalEngineObservation.ps1")
  foreach ($file in @(Get-ChildItem -LiteralPath $evidenceRoot -Filter "*-engine-observation.json" -File | Sort-Object Name)) {
    $observation = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json -Depth 100
    $waveRows = @($wave.releases | Where-Object version -eq $observation.release)
    $verificationRows = @($verification.releases | Where-Object version -eq $observation.release)
    if ($waveRows.Count -ne 1 -or $verificationRows.Count -ne 1 -or
        [string]$observation.archive_sha256 -ne [string]$waveRows[0].archive_sha256 -or
        [string]$observation.executable_sha256 -ne [string]$verificationRows[0].factorio_executable_sha256 -or
        [int]$observation.observer_protocol -ne 1 -or
        [string]$observation.observer_tool_sha256 -ne $toolSha -or [string]$observation.normalizer_sha256 -ne $normalizerSha) {
      throw "Tracked terminal engine observation identity or tool binding failed: $($file.Name)"
    }
    $material = [ordered]@{
      technologies=@($observation.technologies)
      effects_and_owners=@($observation.effects_and_owners)
      settings=@($observation.settings)
      data_complete=$true
      settings_complete=(@($observation.capability_omissions.field) -notcontains "setting-prototype-stage")
    }
    $materialSha = Get-MIRAssuranceTextHash -Text ($material | ConvertTo-Json -Depth 100 -Compress)
    if ([string]$observation.semantic_observation_sha256 -ne $materialSha -or @($observation.technologies).Count -eq 0) {
      throw "Tracked terminal engine observation semantic digest or technology inventory failed: $($file.Name)"
    }
    $text = Get-Content -Raw -LiteralPath $file.FullName
    if ($text -match '(?i)[A-Z]:\\|generated_at|duration_seconds') {
      throw "Tracked terminal engine observation contains machine-local or volatile fields: $($file.Name)"
    }
  }
}
Write-Host "[ok] terminal exact-engine observation normalization is deterministic"
