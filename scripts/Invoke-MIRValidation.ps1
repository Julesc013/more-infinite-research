param(
  [string]$FactorioBin = $env:FACTORIO_BIN,
  [string]$FactorioLog = $env:FACTORIO_LOG,
  [string]$UserDataDir = $env:FACTORIO_USERDATA,
  [switch]$StaticOnly
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..")

function Invoke-RepoCheck {
  param([string]$Description, [scriptblock]$Script)
  Write-Host "[check] $Description"
  & $Script
}

Invoke-RepoCheck "info.json parses" {
  $null = Get-Content -Raw (Join-Path $repo "info.json") | ConvertFrom-Json
}

Invoke-RepoCheck "release metadata avoids compatibility mod dependencies" {
  $info = Get-Content -Raw (Join-Path $repo "info.json") | ConvertFrom-Json
  $deps = @($info.dependencies)
  $compatDependencyModIds = @(
    "Advanced-Electric-Revamped-v16",
    "Better_Robots_Extended",
    "OCs_ammo_casting",
    "OCs_stone_casting",
    "fluid-quality-imprinting",
    "plates-n-circuit-productivity"
  )
  $present = @(
    foreach ($dep in $deps) {
      foreach ($modId in $compatDependencyModIds) {
        if ($dep -match "^\?\s+$([regex]::Escape($modId))(\s|$)") {
          $dep
        }
      }
    }
  )
  if ($present.Count -gt 0) {
    throw "Unexpected compatibility mod dependencies in info.json: $($present -join ', ')"
  }
}

Invoke-RepoCheck "docs match opportunistic compatibility policy" {
  $forbiddenPhrases = @(
    "declared as optional dependencies so More Infinite Research",
    "optional load-order dependencies",
    "optional dependencies for Space Age and known compatibility targets",
    "add optional or hidden optional dependencies"
  )
  $files = @(
    (Join-Path $repo "changelog.txt"),
    (Join-Path $repo "docs\compatibility.md"),
    (Join-Path $repo "docs\roadmap.md")
  )
  foreach ($file in $files) {
    $text = Get-Content -Raw -LiteralPath $file
    foreach ($phrase in $forbiddenPhrases) {
      if ($text.Contains($phrase)) {
        throw "Forbidden optional dependency policy phrase found in $file`: $phrase"
      }
    }
  }
}

Invoke-RepoCheck "no old tool-based science pack authority remains" {
  $matches = & rg --line-number "data.raw.tool|tool_exists|has_tool|PACKS_ALL" (Join-Path $repo "prototypes")
  if ($LASTEXITCODE -eq 0) {
    $matches | Write-Host
    throw "Old science-pack authority references remain."
  }
  if ($LASTEXITCODE -ne 1) { throw "rg failed while scanning science-pack authority." }
}

Invoke-RepoCheck "generated icons do not use icon_mipmaps" {
  $matches = & rg --line-number "icon_mipmaps" (Join-Path $repo "prototypes")
  if ($LASTEXITCODE -eq 0) {
    $matches | Write-Host
    throw "icon_mipmaps references remain in prototypes."
  }
  if ($LASTEXITCODE -ne 1) { throw "rg failed while scanning icon_mipmaps." }
}

Invoke-RepoCheck "locale files match English fallback" {
  & (Join-Path $repo "scripts\Test-MIRLocales.ps1") -AllowMissingSupportedLanguages
}

Invoke-RepoCheck "changelog uses Factorio changelog format" {
  $separator = "-" * 99
  $path = Join-Path $repo "changelog.txt"
  $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
  if ($lines.Count -eq 0) {
    throw "changelog.txt is empty."
  }
  if ($lines[0] -ne $separator) {
    throw "changelog.txt must start with exactly 99 dashes."
  }

  $sectionStart = $true
  $expectVersion = $false
  $seenCategory = $false
  $lineNo = 0
  foreach ($line in $lines) {
    $lineNo++
    if ($line -eq $separator) {
      $sectionStart = $false
      $expectVersion = $true
      $seenCategory = $false
      continue
    }
    if ($line -match '^\s*$') {
      continue
    }
    if ($expectVersion) {
      if ($line -notmatch '^Version: .+$') {
        throw "changelog.txt:$lineNo expected a Version line after the separator."
      }
      $expectVersion = $false
      $sectionStart = $true
      continue
    }
    if ($sectionStart -and $line -match '^Date: \d{4}-\d{2}-\d{2}$') {
      continue
    }
    if ($line -match '^  [^ ].+:$') {
      $seenCategory = $true
      $sectionStart = $false
      continue
    }
    if ($line -match '^    - .+$') {
      if (-not $seenCategory) {
        throw "changelog.txt:$lineNo has an entry before any category."
      }
      continue
    }
    throw "changelog.txt:$lineNo is not valid Factorio changelog syntax: $line"
  }

  if ($expectVersion) {
    throw "changelog.txt ended immediately after a separator."
  }
}

Invoke-RepoCheck "release package archive matches metadata" {
  Add-Type -AssemblyName System.IO.Compression.FileSystem

  function Read-ZipEntryText {
    param($Entry)
    $stream = $Entry.Open()
    try {
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
      try {
        return $reader.ReadToEnd()
      } finally {
        $reader.Dispose()
      }
    } finally {
      $stream.Dispose()
    }
  }

  $info = Get-Content -Raw (Join-Path $repo "info.json") | ConvertFrom-Json
  $packageName = "$($info.name)_$($info.version)"
  $zipPath = Join-Path $repo "dist\$packageName.zip"
  if (-not (Test-Path -LiteralPath $zipPath)) {
    throw "Release package not found: $zipPath"
  }

  $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    $entries = @($zip.Entries)
    $entryNames = @($entries | ForEach-Object { $_.FullName })
    $root = "$packageName/"

    $outsideRoot = @($entryNames | Where-Object { -not $_.StartsWith($root) })
    if ($outsideRoot.Count -gt 0) {
      throw "Package entries outside expected root ${root}: $($outsideRoot -join ', ')"
    }

    $requiredEntries = @(
      "${root}info.json",
      "${root}changelog.txt",
      "${root}README.md",
      "${root}LICENSE",
      "${root}thumbnail.png",
      "${root}data.lua",
      "${root}data-updates.lua",
      "${root}data-final-fixes.lua",
      "${root}settings.lua",
      "${root}defaults.lua",
      "${root}locale/en/more-infinite-research.cfg",
      "${root}docs/architecture.md",
      "${root}docs/compatibility.md",
      "${root}prototypes/tech-gen.lua",
      "${root}prototypes/base-tech-extensions.lua",
      "${root}prototypes/compat/competing-base-extensions.lua",
      "${root}prototypes/streams/productivity.lua",
      "${root}prototypes/streams/direct-effects.lua",
      "${root}prototypes/lib/science-packs.lua",
      "${root}prototypes/lib/recipe-matching.lua"
    )
    $missingEntries = @($requiredEntries | Where-Object { $_ -notin $entryNames })
    if ($missingEntries.Count -gt 0) {
      throw "Package is missing expected entries: $($missingEntries -join ', ')"
    }

    $forbiddenPatterns = @(
      "^$([regex]::Escape($root))(\.git|build|dist|fixtures|scripts)(/|$)",
      "(^|/)(\.DS_Store|Thumbs\.db)$",
      "(^|/)__MACOSX(/|$)",
      "~$",
      "\.(tmp|bak|swp)$"
    )
    $forbiddenEntries = @(
      foreach ($entryName in $entryNames) {
        foreach ($pattern in $forbiddenPatterns) {
          if ($entryName -match $pattern) {
            $entryName
            break
          }
        }
      }
    )
    if ($forbiddenEntries.Count -gt 0) {
      throw "Package contains forbidden entries: $($forbiddenEntries -join ', ')"
    }

    $innerInfoEntry = $entries | Where-Object { $_.FullName -eq "${root}info.json" } | Select-Object -First 1
    $innerInfo = Read-ZipEntryText $innerInfoEntry | ConvertFrom-Json
    if ($innerInfo.name -ne $info.name -or $innerInfo.version -ne $info.version -or $innerInfo.factorio_version -ne $info.factorio_version) {
      throw "Package info.json metadata does not match repository info.json."
    }
    $repoDeps = @($info.dependencies)
    $packageDeps = @($innerInfo.dependencies)
    $depDiff = @(Compare-Object -ReferenceObject $repoDeps -DifferenceObject $packageDeps)
    if ($depDiff.Count -gt 0) {
      throw "Package info.json dependencies do not match repository info.json."
    }

    $mustMatchRepo = @(
      "README.md",
      "changelog.txt",
      "data.lua",
      "data-updates.lua",
      "data-final-fixes.lua",
      "settings.lua",
      "defaults.lua",
      "prototypes/config.lua",
      "prototypes/util.lua",
      "prototypes/tech-gen.lua",
      "prototypes/base-tech-extensions.lua",
      "prototypes/compat/competing-base-extensions.lua",
      "prototypes/compat/competing-productivity.lua",
      "prototypes/compat/profiles.lua",
      "prototypes/streams/init.lua",
      "prototypes/streams/productivity.lua",
      "prototypes/streams/direct-effects.lua",
      "prototypes/lib/deepcopy.lua",
      "prototypes/lib/prototype-lookup.lua",
      "prototypes/lib/science-packs.lua",
      "prototypes/lib/recipe-matching.lua",
      "prototypes/lib/table-utils.lua",
      "prototypes/lib/technology-cleanup.lua",
      "prototypes/lib/technology-icons.lua"
    )
    $repoPath = $repo.Path
    $mustMatchRepo += @(
      Get-ChildItem -LiteralPath (Join-Path $repo "docs") -File |
        ForEach-Object { [System.IO.Path]::GetRelativePath($repoPath, $_.FullName).Replace("\", "/") }
    )
    $mustMatchRepo += @(
      Get-ChildItem -LiteralPath (Join-Path $repo "locale") -Recurse -File -Filter "more-infinite-research.cfg" |
        ForEach-Object { [System.IO.Path]::GetRelativePath($repoPath, $_.FullName).Replace("\", "/") }
    )
    $mustMatchRepo = @($mustMatchRepo | Sort-Object -Unique)

    foreach ($relative in $mustMatchRepo) {
      $entryName = "${root}$relative"
      $entry = $entries | Where-Object { $_.FullName -eq $entryName } | Select-Object -First 1
      if (-not $entry) {
        throw "Package is missing expected source file: $entryName"
      }

      $repoText = Get-Content -Raw -LiteralPath (Join-Path $repo $relative)
      $zipText = Read-ZipEntryText $entry
      if ($repoText.TrimEnd() -ne $zipText.TrimEnd()) {
        throw "Package source file differs from repository source: $relative"
      }
    }
  } finally {
    $zip.Dispose()
  }
}

Invoke-RepoCheck "git whitespace check" {
  git -C $repo diff --check
}

if ($StaticOnly -or [string]::IsNullOrWhiteSpace($FactorioBin)) {
  Write-Host "[skip] Factorio runtime validation skipped. Set FACTORIO_BIN or pass -FactorioBin to run load tests."
  exit 0
}

if (-not (Test-Path -LiteralPath $FactorioBin)) {
  throw "Factorio binary not found: $FactorioBin"
}

if ([string]::IsNullOrWhiteSpace($UserDataDir)) {
  $UserDataDir = Join-Path ([System.IO.Path]::GetTempPath()) ("mir-factorio-userdata-" + [guid]::NewGuid().ToString("N"))
}
$validationRoot = (New-Item -ItemType Directory -Force -Path $UserDataDir).FullName
$validationRootWithSeparator = $validationRoot.TrimEnd("\") + "\"

function Invoke-FactorioProcess {
  param(
    [string]$FilePath,
    [string[]]$Arguments,
    [int]$TimeoutMs = 300000
  )

  $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $processInfo.FileName = $FilePath
  $processInfo.UseShellExecute = $false
  $processInfo.CreateNoWindow = $true
  $processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
  foreach ($arg in $Arguments) {
    [void]$processInfo.ArgumentList.Add($arg)
  }

  $process = [System.Diagnostics.Process]::Start($processInfo)
  if (-not $process.WaitForExit($TimeoutMs)) {
    try {
      $process.Kill($true)
    } catch {
      $process.Kill()
    }
    throw "Factorio runtime validation timed out after $TimeoutMs ms."
  }
  return $process.ExitCode
}

function Copy-ModDirectory {
  param([string]$Source, [string]$Name, [string]$ModsDir)
  $modsRootWithSeparator = (Resolve-Path -LiteralPath $ModsDir).Path.TrimEnd("\") + "\"
  $target = Join-Path $modsDir $Name
  if (Test-Path -LiteralPath $target) {
    $resolvedTarget = (Resolve-Path -LiteralPath $target).Path
    if (-not $resolvedTarget.StartsWith($modsRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove mod directory outside scenario mods root: $resolvedTarget"
    }
    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
  }
  Copy-Item -LiteralPath $Source -Destination $target -Recurse
}

$fixtureRoot = Join-Path $repo "fixtures"
if (-not (Test-Path -LiteralPath $fixtureRoot)) {
  throw "Fixture directory not found: $fixtureRoot"
}

$postMirAssertionFixtures = @(
  "mir-fixture-assert-science-pack-productivity",
  "mir-fixture-assert-lab-skip-policy"
)

function Get-FixtureInfos {
  $infos = @()
  foreach ($fixture in Get-ChildItem -LiteralPath $fixtureRoot -Directory) {
    $info = Get-Content -Raw (Join-Path $fixture.FullName "info.json") | ConvertFrom-Json
    $infos += [pscustomobject]@{
      Name = $info.name
      Path = $fixture.FullName
    }
  }
  return $infos
}

function Enable-CopiedDiagnostics {
  param([string]$ModsDir)
  $copiedDiagnosticsPath = Join-Path $ModsDir "more-infinite-research\prototypes\diagnostics.lua"
  $copiedDiagnostics = Get-Content -Raw -LiteralPath $copiedDiagnosticsPath
  $copiedDiagnostics = $copiedDiagnostics -replace 'return startup_setting\("mir-debug-generation-report"\) == true', 'return true'
  Set-Content -LiteralPath $copiedDiagnosticsPath -Value $copiedDiagnostics -Encoding UTF8
}

function Set-CopiedLabPolicySkip {
  param([string]$ModsDir)
  $copiedSettingsPath = Join-Path $ModsDir "more-infinite-research\settings.lua"
  $copiedSettings = Get-Content -Raw -LiteralPath $copiedSettingsPath
  if (-not $copiedSettings.Contains('default_value = "reduce",')) {
    throw "Unable to force lab incompatibility policy to skip in copied settings.lua."
  }
  $copiedSettings = $copiedSettings.Replace('default_value = "reduce",', 'default_value = "skip",')
  Set-Content -LiteralPath $copiedSettingsPath -Value $copiedSettings -Encoding UTF8
}

function Initialize-RuntimeScenario {
  param(
    [string]$ScenarioName,
    [string[]]$EnabledFixtureNames,
    [switch]$LabPolicySkip
  )

  $scenarioRoot = Join-Path $validationRoot $ScenarioName
  if (Test-Path -LiteralPath $scenarioRoot) {
    $resolvedScenarioRoot = (Resolve-Path -LiteralPath $scenarioRoot).Path
    if (-not $resolvedScenarioRoot.StartsWith($validationRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove scenario directory outside validation root: $resolvedScenarioRoot"
    }
    Remove-Item -LiteralPath $resolvedScenarioRoot -Recurse -Force
  }

  $modsDir = Join-Path $scenarioRoot "mods"
  New-Item -ItemType Directory -Force -Path $modsDir | Out-Null

  Copy-ModDirectory -Source $repo -Name "more-infinite-research" -ModsDir $modsDir

  $fixtureInfos = Get-FixtureInfos
  foreach ($fixtureInfo in $fixtureInfos) {
    Copy-ModDirectory -Source $fixtureInfo.Path -Name $fixtureInfo.Name -ModsDir $modsDir
  }

  $fixtureNames = @($fixtureInfos | Select-Object -ExpandProperty Name)
  $copiedInfoPath = Join-Path $modsDir "more-infinite-research\info.json"
  $copiedInfo = Get-Content -Raw -LiteralPath $copiedInfoPath | ConvertFrom-Json
  $dependencies = @($copiedInfo.dependencies)
  foreach ($fixtureName in @($fixtureNames | Where-Object { $_ -notin $postMirAssertionFixtures })) {
    $dependency = "? $fixtureName"
    if ($dependencies -notcontains $dependency) {
      $dependencies += $dependency
    }
  }
  $copiedInfo.dependencies = $dependencies
  $copiedInfo | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $copiedInfoPath -Encoding UTF8

  Enable-CopiedDiagnostics -ModsDir $modsDir
  if ($LabPolicySkip) {
    Set-CopiedLabPolicySkip -ModsDir $modsDir
  }

  $mods = @(
    @{ name = "base"; enabled = $true },
    @{ name = "more-infinite-research"; enabled = $true }
  )
  $enabledFixtures = @{}
  foreach ($fixtureName in $EnabledFixtureNames) {
    $enabledFixtures[$fixtureName] = $true
  }
  foreach ($fixtureName in @($fixtureNames | Sort-Object)) {
    $mods += @{
      name = $fixtureName
      enabled = $enabledFixtures.ContainsKey($fixtureName)
    }
  }

  $modList = @{ mods = $mods } | ConvertTo-Json -Depth 5
  Set-Content -LiteralPath (Join-Path $modsDir "mod-list.json") -Value $modList -Encoding UTF8

  return [pscustomobject]@{
    Name = $ScenarioName
    ModsDir = $modsDir
    SavePath = Join-Path $scenarioRoot "mir-validation.zip"
  }
}

if ([string]::IsNullOrWhiteSpace($FactorioLog)) {
  $FactorioLog = Join-Path $env:APPDATA "Factorio\factorio-current.log"
}

function Assert-RuntimeLogHealthy {
  param([string]$ScenarioName)
  Write-Host "[info] Factorio log path: $FactorioLog"
  if (-not (Test-Path -LiteralPath $FactorioLog)) {
    throw "Factorio log not found after $ScenarioName runtime validation: $FactorioLog"
  }

  $fatalMarkers = Select-String -LiteralPath $FactorioLog -Pattern "------------- Error -------------", "Error Util.cpp" -SimpleMatch
  if ($fatalMarkers) {
    $fatalMarkers | Select-Object -First 10 | ForEach-Object { Write-Host $_.Line }
    throw "Factorio runtime validation log contains fatal error markers after $ScenarioName."
  }
}

function Invoke-RuntimeScenario {
  param(
    [string]$ScenarioName,
    [string[]]$EnabledFixtureNames,
    [switch]$LabPolicySkip
  )

  $scenario = Initialize-RuntimeScenario -ScenarioName $ScenarioName -EnabledFixtureNames $EnabledFixtureNames -LabPolicySkip:$LabPolicySkip
  if (Test-Path -LiteralPath $scenario.SavePath) {
    Remove-Item -LiteralPath $scenario.SavePath -Force
  }

  Write-Host "[run] Factorio load check with fixture mods ($ScenarioName)"
  $factorioArgs = @(
    "--mod-directory",
    $scenario.ModsDir,
    "--create",
    $scenario.SavePath
  )
  $factorioExitCode = Invoke-FactorioProcess -FilePath $FactorioBin -Arguments $factorioArgs
  if ($factorioExitCode -ne 0) {
    throw "Factorio runtime validation scenario $ScenarioName exited with code $factorioExitCode"
  }
  if (-not (Test-Path -LiteralPath $scenario.SavePath)) {
    throw "Factorio runtime validation scenario $ScenarioName did not create the expected save: $($scenario.SavePath). Factorio exit code: $factorioExitCode"
  }

  Assert-RuntimeLogHealthy -ScenarioName $ScenarioName
}

Invoke-RuntimeScenario -ScenarioName "reduce-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack",
  "mir-fixture-custom-lab",
  "mir-fixture-late-recipe",
  "mir-fixture-assert-science-pack-productivity"
)

$sciencePackProductivityLine = Select-String -LiteralPath $FactorioLog -Pattern "key=research_science_pack_productivity" -SimpleMatch | Select-Object -Last 1
if (-not $sciencePackProductivityLine) {
  throw "Factorio runtime validation log did not contain diagnostics for research_science_pack_productivity."
}
if ($sciencePackProductivityLine.Line -notmatch "status=generated") {
  throw "Science pack productivity stream was not generated during runtime validation: $($sciencePackProductivityLine.Line)"
}
$effectCountMatch = [regex]::Match($sciencePackProductivityLine.Line, "effects=(\d+)")
if (-not $effectCountMatch.Success) {
  throw "Science pack productivity diagnostics did not include an effect count: $($sciencePackProductivityLine.Line)"
}
$sciencePackEffectCount = [int]$effectCountMatch.Groups[1].Value
$spaceAgeLoaded = Select-String -LiteralPath $FactorioLog -Pattern "Loading mod space-age" -SimpleMatch
$minimumSciencePackEffects = if ($spaceAgeLoaded) { 13 } else { 8 }
if ($sciencePackEffectCount -lt $minimumSciencePackEffects) {
  throw "Science pack productivity stream did not include the fixture science-pack effect. Expected at least $minimumSciencePackEffects effects, got $sciencePackEffectCount`: $($sciencePackProductivityLine.Line)"
}

Invoke-RuntimeScenario -ScenarioName "skip-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack",
  "mir-fixture-custom-lab",
  "mir-fixture-late-recipe",
  "mir-fixture-assert-lab-skip-policy"
) -LabPolicySkip

$skipPolicyLine = Select-String -LiteralPath $FactorioLog -Pattern "key=research_science_pack_productivity" -SimpleMatch | Select-Object -Last 1
if (-not $skipPolicyLine) {
  throw "Skip-policy runtime validation log did not contain diagnostics for research_science_pack_productivity."
}
if ($skipPolicyLine.Line -notmatch "status=skipped" -or $skipPolicyLine.Line -notmatch "lab_status=invalid") {
  throw "Skip-policy runtime validation did not skip incompatible science-pack productivity as expected: $($skipPolicyLine.Line)"
}

Write-Host "[ok] Validation completed."
$global:LASTEXITCODE = 0
