param(
  [string]$FactorioBin = $env:FACTORIO_BIN,
  [string]$FactorioLog = $env:FACTORIO_LOG,
  [string]$UserDataDir = $env:FACTORIO_USERDATA,
  [switch]$StaticOnly
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..")
$repoInfo = Get-Content -Raw (Join-Path $repo "info.json") | ConvertFrom-Json
$isLegacyFactorio20 = $repoInfo.factorio_version -eq "2.0"
$isFactorio21Line = $repoInfo.factorio_version -eq "2.1"

function Invoke-RepoCheck {
  param([string]$Description, [scriptblock]$Script)
  Write-Host "[check] $Description"
  & $Script
}

function Find-RepositoryText {
  param(
    [string]$Path,
    [string]$Pattern
  )

  $files = Get-ChildItem -LiteralPath $Path -Recurse -File
  if (-not $files) { return @() }
  return @($files | Select-String -Pattern $Pattern)
}

Invoke-RepoCheck "info.json parses" {
  $null = $repoInfo
}

Invoke-RepoCheck "release metadata matches Factorio line" {
  $deps = @($repoInfo.dependencies)

  if ($isLegacyFactorio20) {
    if ($deps -notcontains "base >= 2.0") {
      throw "Factorio 2.0 legacy metadata must declare base >= 2.0."
    }

    $factorio21Deps = @($deps | Where-Object { $_ -match ">=\s*2\.1" })
    if ($factorio21Deps.Count -gt 0) {
      throw "Factorio 2.0 legacy metadata must not carry Factorio 2.1 dependency floors: $($factorio21Deps -join ', ')"
    }
  } elseif ($isFactorio21Line) {
    if ($deps -notcontains "base >= 2.1.8") {
      throw "Factorio 2.1 metadata must declare base >= 2.1.8."
    }
    if ($deps -notcontains "(?) quality >= 2.1.8") {
      throw "Factorio 2.1 metadata must declare hidden optional Quality load ordering with (?) quality >= 2.1.8."
    }
    if ($deps -contains "? quality >= 2.1.8") {
      throw "Quality must be a hidden optional dependency so module productivity can see quality module recipes without advertising a visible dependency."
    }
  } else {
    throw "Unsupported factorio_version in info.json: $($repoInfo.factorio_version)"
  }
}

Invoke-RepoCheck "release metadata avoids compatibility mod dependencies" {
  $deps = @($repoInfo.dependencies)
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
  $matches = Find-RepositoryText -Path (Join-Path $repo "prototypes") -Pattern "data.raw.tool|tool_exists|has_tool|PACKS_ALL"
  if ($matches.Count -gt 0) {
    $matches | Write-Host
    throw "Old science-pack authority references remain."
  }
}

Invoke-RepoCheck "generated icons do not use icon_mipmaps" {
  $matches = Find-RepositoryText -Path (Join-Path $repo "prototypes") -Pattern "icon_mipmaps"
  if ($matches.Count -gt 0) {
    $matches | Write-Host
    throw "icon_mipmaps references remain in prototypes."
  }
}

Invoke-RepoCheck "control runtime avoids tick handlers" {
  $luaFiles = @()
  $controlLua = Join-Path $repo "control.lua"
  $controlDir = Join-Path $repo "control"

  if (Test-Path -LiteralPath $controlLua) {
    $luaFiles += Get-Item -LiteralPath $controlLua
  }
  if (Test-Path -LiteralPath $controlDir) {
    $luaFiles += @(Get-ChildItem -LiteralPath $controlDir -Recurse -File -Filter "*.lua")
  }

  $matches = @(
    foreach ($file in $luaFiles) {
      Select-String -LiteralPath $file.FullName -Pattern "defines\.events\.on_tick|script\.on_nth_tick"
    }
  )

  if ($matches.Count -gt 0) {
    $matches | Write-Host
    throw "Runtime tick handlers are not allowed without an explicit documented allowlist and disabled-by-default feature gate."
  }
}

Invoke-RepoCheck "locale files match English fallback" {
  & (Join-Path $repo "scripts\Test-MIRLocales.ps1") -AllowMissingSupportedLanguages
}

Invoke-RepoCheck "science-pack progression settings are wired" {
  $settingsText = Get-Content -Raw -LiteralPath (Join-Path $repo "settings.lua")
  $utilText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\util.lua")
  $baseExtensionsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\base-tech-extensions.lua")
  $scienceText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\lib\science-packs.lua")
  $directEffectsText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\streams\direct-effects.lua")
  $productivityText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\streams\productivity.lua")
  $weaponSpeedText = Get-Content -Raw -LiteralPath (Join-Path $repo "prototypes\weapon-speed-adjustments.lua")
  $defaultsText = Get-Content -Raw -LiteralPath (Join-Path $repo "defaults.lua")
  $localeText = Get-Content -Raw -LiteralPath (Join-Path $repo "locale\en\more-infinite-research.cfg")

  $requiredSnippets = @(
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'name = "ips-require-space-gate"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'default_value = false' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'name = "mir-science-pack-ingredient-policy"' },
    @{ File = "settings.lua"; Text = $settingsText; Snippet = 'allowed_values = {"configured", "space", "space-and-promethium", "all-official", "all"}' },
    @{ File = "prototypes\util.lua"; Text = $utilText; Snippet = 'apply_science_pack_ingredient_policy' },
    @{ File = "prototypes\util.lua"; Text = $utilText; Snippet = 'append_end_game_gate_prerequisite' },
    @{ File = "prototypes\lib\science-packs.lua"; Text = $scienceText; Snippet = 'pack_list_official' },
    @{ File = "prototypes\lib\science-packs.lua"; Text = $scienceText; Snippet = 'is_official_science_pack' },
    @{ File = "prototypes\lib\science-packs.lua"; Text = $scienceText; Snippet = 'desired == "all-official"' },
    @{ File = "prototypes\base-tech-extensions.lua"; Text = $baseExtensionsText; Snippet = 'if data.raw.technology[new_name] then' },
    @{ File = "prototypes\base-tech-extensions.lua"; Text = $baseExtensionsText; Snippet = '"target_exists"' },
    @{ File = "prototypes\base-tech-extensions.lua"; Text = $baseExtensionsText; Snippet = 'apply_science_pack_ingredient_policy' },
    @{ File = "prototypes\base-tech-extensions.lua"; Text = $baseExtensionsText; Snippet = 'append_end_game_gate_prerequisite' },
    @{ File = "prototypes\lib\science-packs.lua"; Text = $scienceText; Snippet = 'end_game_science_pack' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = 'icon_tech = "research-productivity"' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '^omega%-drill$' },
    @{ File = "prototypes\streams\productivity.lua"; Text = $productivityText; Snippet = '^omega%-tau$' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'icon_tech = "discharge-defense-equipment"' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'technology-description.more-infinite-research.electric_shooting_speed' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'technology-description.more-infinite-research.flamethrower_shooting_speed' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'ammo_category = "tesla", modifier = 0.1' },
    @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'ammo_category = "electric", modifier = 0.1' },
    @{ File = "prototypes\weapon-speed-adjustments.lua"; Text = $weaponSpeedText; Snippet = 'tech.unit and tech.unit.count_formula' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = '[modifier-description]' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'cargo-landing-pad-count=Cargo landing pads per surface: +__1__' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.electric_shooting_speed=' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'more-infinite-research.flamethrower_shooting_speed=' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'flamethrower-shooting-speed-bonus=Flamethrower shooting speed: +__1__' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'electric-shooting-speed-bonus=Electric shooting speed: +__1__' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'tesla-shooting-speed-bonus=Tesla shooting speed: +__1__' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-configured=Configured per technology' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-space=Add space science' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-space-and-promethium=Add space and promethium science' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-all-official=Use all official science packs' },
    @{ File = "locale\en\more-infinite-research.cfg"; Text = $localeText; Snippet = 'mir-science-pack-ingredient-policy-all=Use all lab science packs' }
  )

  if ($isLegacyFactorio20) {
    $legacyForbiddenCargoSnippets = @(
      'type = "max-cargo-bay-unloading-distance"',
      'type = "cargo-landing-pad-count"'
    )
    foreach ($snippet in $legacyForbiddenCargoSnippets) {
      if ($directEffectsText.Contains($snippet)) {
        throw "Factorio 2.0 legacy must not include Factorio 2.1-only cargo technology modifier in prototypes\streams\direct-effects.lua: $snippet"
      }
    }
  } else {
    $requiredSnippets += @(
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'research_cargo_landing_pad_count = {' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'required_mods = {"space-age"}' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'required_technologies = {"rocket-silo"}' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'science_packs = "all-official"' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'type = "max-cargo-bay-unloading-distance", modifier = 10' },
      @{ File = "prototypes\streams\direct-effects.lua"; Text = $directEffectsText; Snippet = 'type = "cargo-landing-pad-count", modifier = 1' }
    )
  }

  foreach ($check in $requiredSnippets) {
    if (-not $check.Text.Contains($check.Snippet)) {
      throw "Missing science-pack progression setting wiring in $($check.File): $($check.Snippet)"
    }
  }

  if (-not $isLegacyFactorio20) {
    if ($defaultsText -notmatch '(?s)research_cargo_bay_unloading_distance\s*=\s*\{.*?research_time\s*=\s*120') {
      throw "Cargo bay unloading distance default research time must be 120 seconds."
    }
    if ($defaultsText -notmatch '(?s)research_cargo_landing_pad_count\s*=\s*\{.*?research_time\s*=\s*240') {
      throw "Cargo landing pad count default research time must be 240 seconds."
    }
  }
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
  if ($lines -notcontains "Version: $($repoInfo.version)") {
    throw "changelog.txt must contain an entry for the current info.json version $($repoInfo.version)."
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

  function Normalize-TextForPackageComparison {
    param([string]$Text)
    return ($Text -replace "`r`n", "`n").TrimEnd()
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
      "${root}CONTRIBUTING.md",
      "${root}README.md",
      "${root}LICENSE",
      "${root}thumbnail.png",
      "${root}data.lua",
      "${root}control.lua",
      "${root}data-updates.lua",
      "${root}data-final-fixes.lua",
      "${root}settings.lua",
      "${root}defaults.lua",
      "${root}locale/en/more-infinite-research.cfg",
      "${root}docs/architecture.md",
      "${root}docs/api-proof-points.md",
      "${root}docs/compatibility.md",
      "${root}docs/manual-test-plan.md",
      "${root}docs/todo.md",
      "${root}prototypes/tech-gen.lua",
      "${root}prototypes/base-tech-extensions.lua",
      "${root}prototypes/compat/competing-base-extensions.lua",
      "${root}prototypes/streams/productivity.lua",
      "${root}prototypes/streams/direct-effects.lua",
      "${root}control/scripted-techs.lua",
      "${root}control/effects/spoilage-preservation.lua",
      "${root}control/effects/agricultural-growth-speed.lua",
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

    $repoPath = $repo.Path
    $mustMatchRepo = @(
      "README.md",
      "changelog.txt",
      "CONTRIBUTING.md",
      "control.lua",
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
    $mustMatchRepo += @(
      Get-ChildItem -LiteralPath (Join-Path $repo "control") -Recurse -File -Filter "*.lua" |
        ForEach-Object { [System.IO.Path]::GetRelativePath($repoPath, $_.FullName).Replace("\", "/") }
    )
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
      if ((Normalize-TextForPackageComparison $repoText) -ne (Normalize-TextForPackageComparison $zipText)) {
        throw "Package source file differs from repository source: $relative"
      }
    }
  } finally {
    $zip.Dispose()
  }
}

Invoke-RepoCheck "git whitespace check" {
  git -C $repo diff --check
  if ($LASTEXITCODE -ne 0) {
    throw "git diff --check failed."
  }
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
  "mir-fixture-assert-lab-skip-policy",
  "mir-fixture-assert-base-extension-boundary",
  "mir-fixture-assert-cargo-logistics",
  "mir-fixture-assert-omega-drill-productivity",
  "mir-fixture-assert-weapon-speed-safety"
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

function Set-CopiedStartupSettingDefault {
  param(
    [string]$ModsDir,
    [string]$Name,
    [string]$ValueLiteral
  )

  $copiedSettingsPath = Join-Path $ModsDir "more-infinite-research\settings.lua"
  $copiedSettings = Get-Content -Raw -LiteralPath $copiedSettingsPath
  $escapedName = [regex]::Escape($Name)
  $pattern = "(?s)(name\s*=\s*`"$escapedName`".*?default_value\s*=\s*)([^,\r\n]+)"
  $match = [regex]::Match($copiedSettings, $pattern)
  if (-not $match.Success) {
    throw "Unable to find startup setting default for $Name in copied settings.lua."
  }

  $valueGroup = $match.Groups[2]
  $copiedSettings = $copiedSettings.Substring(0, $valueGroup.Index) +
    $ValueLiteral +
    $copiedSettings.Substring($valueGroup.Index + $valueGroup.Length)
  Set-Content -LiteralPath $copiedSettingsPath -Value $copiedSettings -Encoding UTF8
}

function Set-CopiedLabPolicySkip {
  param([string]$ModsDir)
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "mir-lab-incompatibility-policy" -ValueLiteral '"skip"'
}

function Set-CopiedSciencePackIngredientPolicy {
  param(
    [string]$ModsDir,
    [ValidateSet("configured", "space", "space-and-promethium", "all-official", "all")]
    [string]$Policy
  )
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "mir-science-pack-ingredient-policy" -ValueLiteral "`"$Policy`""
}

function Set-CopiedRequireSpaceGate {
  param([string]$ModsDir)
  Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "ips-require-space-gate" -ValueLiteral "true"
}

function Set-CopiedStreamEnabled {
  param(
    [string]$ModsDir,
    [string]$StreamKey
  )
  try {
    Set-CopiedStartupSettingDefault -ModsDir $ModsDir -Name "ips-enable-$StreamKey" -ValueLiteral "true"
    return
  } catch {
    $copiedDefaultsPath = Join-Path $ModsDir "more-infinite-research\defaults.lua"
    $copiedDefaults = Get-Content -Raw -LiteralPath $copiedDefaultsPath
    $escapedStreamKey = [regex]::Escape($StreamKey)
    $pattern = "(?s)($escapedStreamKey\s*=\s*\{[^{}]*?enabled\s*=\s*)false"
    $match = [regex]::Match($copiedDefaults, $pattern)
    if (-not $match.Success) {
      throw "Unable to enable stream $StreamKey in copied settings.lua or defaults.lua."
    }

    $valueGroup = $match.Groups[1]
    $copiedDefaults = $copiedDefaults.Substring(0, $valueGroup.Index) +
      $valueGroup.Value +
      "true" +
      $copiedDefaults.Substring($valueGroup.Index + $valueGroup.Length + "false".Length)
    Set-Content -LiteralPath $copiedDefaultsPath -Value $copiedDefaults -Encoding UTF8
  }
}

function Initialize-RuntimeScenario {
  param(
    [string]$ScenarioName,
    [string[]]$EnabledFixtureNames,
    [string[]]$EnabledStreamKeys = @(),
    [switch]$LabPolicySkip,
    [ValidateSet("configured", "space", "space-and-promethium", "all-official", "all")]
    [string]$SciencePackIngredientPolicy = "configured",
    [ValidateSet("", "off", "only-when-dedicated-tech-enabled", "always")]
    [string]$WeaponSpeedAdjustmentMode = "",
    [switch]$RequireSpaceGate,
    [switch]$EnableSpaceAge
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
  if ($SciencePackIngredientPolicy -ne "configured") {
    Set-CopiedSciencePackIngredientPolicy -ModsDir $modsDir -Policy $SciencePackIngredientPolicy
  }
  if (-not [string]::IsNullOrWhiteSpace($WeaponSpeedAdjustmentMode)) {
    Set-CopiedStartupSettingDefault -ModsDir $modsDir -Name "mir-adjust-vanilla-weapon-speed-techs" -ValueLiteral "`"$WeaponSpeedAdjustmentMode`""
  }
  if ($RequireSpaceGate) {
    Set-CopiedRequireSpaceGate -ModsDir $modsDir
  }
  foreach ($streamKey in $EnabledStreamKeys) {
    Set-CopiedStreamEnabled -ModsDir $modsDir -StreamKey $streamKey
  }

  $mods = @(
    @{ name = "base"; enabled = $true },
    @{ name = "elevated-rails"; enabled = [bool]$EnableSpaceAge },
    @{ name = "recycler"; enabled = [bool]$EnableSpaceAge },
    @{ name = "quality"; enabled = [bool]$EnableSpaceAge },
    @{ name = "space-age"; enabled = [bool]$EnableSpaceAge },
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
    [string[]]$EnabledStreamKeys = @(),
    [switch]$LabPolicySkip,
    [ValidateSet("configured", "space", "space-and-promethium", "all-official", "all")]
    [string]$SciencePackIngredientPolicy = "configured",
    [ValidateSet("", "off", "only-when-dedicated-tech-enabled", "always")]
    [string]$WeaponSpeedAdjustmentMode = "",
    [switch]$RequireSpaceGate,
    [switch]$EnableSpaceAge
  )

  $scenario = Initialize-RuntimeScenario `
    -ScenarioName $ScenarioName `
    -EnabledFixtureNames $EnabledFixtureNames `
    -EnabledStreamKeys $EnabledStreamKeys `
    -LabPolicySkip:$LabPolicySkip `
    -SciencePackIngredientPolicy $SciencePackIngredientPolicy `
    -WeaponSpeedAdjustmentMode $WeaponSpeedAdjustmentMode `
    -RequireSpaceGate:$RequireSpaceGate `
    -EnableSpaceAge:$EnableSpaceAge
  if (Test-Path -LiteralPath $scenario.SavePath) {
    Remove-Item -LiteralPath $scenario.SavePath -Force
  }

  Write-Host "[run] Factorio load check with fixture mods ($ScenarioName)"
  $factorioArgs = @(
    "--disable-audio",
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

function Get-LastStreamReportLine {
  param([string]$Key)
  $line = Select-String -LiteralPath $FactorioLog -Pattern "kind=stream key=$Key" -SimpleMatch | Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain diagnostics for $Key."
  }
  return $line.Line
}

function Get-LastExtensionReportLine {
  param([string]$Key)
  $line = Select-String -LiteralPath $FactorioLog -Pattern "kind=extension key=$Key" -SimpleMatch | Select-Object -Last 1
  if (-not $line) {
    throw "Runtime validation log did not contain extension diagnostics for $Key."
  }
  return $line.Line
}

function Assert-ReportLineGenerated {
  param([string]$Line, [string]$Context)
  if ($Line -notmatch "status=generated") {
    throw "$Context did not generate as expected: $Line"
  }
}

function Assert-ReportLineContains {
  param([string]$Line, [string]$Expected, [string]$Context)
  if (-not $Line.Contains($Expected)) {
    throw "$Context did not include expected text '$Expected': $Line"
  }
}

function Assert-ReportLineDoesNotContain {
  param([string]$Line, [string]$Unexpected, [string]$Context)
  if ($Line.Contains($Unexpected)) {
    throw "$Context unexpectedly included '$Unexpected': $Line"
  }
}

Invoke-RuntimeScenario -ScenarioName "reduce-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack",
  "mir-fixture-custom-lab",
  "mir-fixture-late-recipe",
  "mir-fixture-assert-science-pack-productivity"
)

$sciencePackProductivityLine = Get-LastStreamReportLine -Key "research_science_pack_productivity"
Assert-ReportLineGenerated -Line $sciencePackProductivityLine -Context "Science pack productivity reduce-policy scenario"
Assert-ReportLineContains -Line $sciencePackProductivityLine -Expected "mir-fixture-science-pack" -Context "Science pack productivity reduce-policy scenario"
Assert-ReportLineContains -Line $sciencePackProductivityLine -Expected "tech:research-productivity" -Context "Science pack productivity vanilla icon scenario"
$effectCountMatch = [regex]::Match($sciencePackProductivityLine, "effects=(\d+)")
if (-not $effectCountMatch.Success) {
  throw "Science pack productivity diagnostics did not include an effect count: $sciencePackProductivityLine"
}
$sciencePackEffectCount = [int]$effectCountMatch.Groups[1].Value
if ($sciencePackEffectCount -lt 1) {
  throw "Science pack productivity stream did not include any recipe productivity effects: $sciencePackProductivityLine"
}

Invoke-RuntimeScenario -ScenarioName "skip-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack",
  "mir-fixture-custom-lab",
  "mir-fixture-late-recipe",
  "mir-fixture-assert-lab-skip-policy"
) -LabPolicySkip

$skipPolicyLine = Get-LastStreamReportLine -Key "research_science_pack_productivity"
if ($skipPolicyLine -notmatch "status=skipped" -or $skipPolicyLine -notmatch "lab_status=invalid") {
  throw "Skip-policy runtime validation did not skip incompatible science-pack productivity as expected: $skipPolicyLine"
}

Invoke-RuntimeScenario -ScenarioName "space-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "space"
$spacePackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $spacePackLine -Context "Space science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $spacePackLine -Expected "space-science-pack" -Context "Space science-pack ingredient policy scenario"
$baseElectricShootingLine = Get-LastStreamReportLine -Key "research_electric_shooting_speed"
Assert-ReportLineGenerated -Line $baseElectricShootingLine -Context "Base electric shooting speed scenario"
Assert-ReportLineContains -Line $baseElectricShootingLine -Expected "effects=1" -Context "Base electric shooting speed scenario"
Assert-ReportLineContains -Line $baseElectricShootingLine -Expected "icon=tech:discharge-defense-equipment" -Context "Base electric shooting speed scenario"
$baseFlamethrowerShootingLine = Get-LastStreamReportLine -Key "research_flamethrower_shooting_speed"
Assert-ReportLineGenerated -Line $baseFlamethrowerShootingLine -Context "Base flamethrower shooting speed scenario"

Invoke-RuntimeScenario -ScenarioName "base-space-promethium-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "space-and-promethium"
$baseSpacePromethiumPackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $baseSpacePromethiumPackLine -Context "Base space and promethium science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $baseSpacePromethiumPackLine -Expected "space-science-pack" -Context "Base space and promethium science-pack ingredient policy scenario"
Assert-ReportLineDoesNotContain -Line $baseSpacePromethiumPackLine -Unexpected "promethium-science-pack" -Context "Base space and promethium science-pack ingredient policy scenario"

Invoke-RuntimeScenario -ScenarioName "space-age-space-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "space" -EnableSpaceAge
$spaceAgeSpacePackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $spaceAgeSpacePackLine -Context "Space Age space-only science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $spaceAgeSpacePackLine -Expected "space-science-pack" -Context "Space Age space-only science-pack ingredient policy scenario"
Assert-ReportLineDoesNotContain -Line $spaceAgeSpacePackLine -Unexpected "promethium-science-pack" -Context "Space Age space-only science-pack ingredient policy scenario"
$spaceAgeElectricShootingLine = Get-LastStreamReportLine -Key "research_electric_shooting_speed"
Assert-ReportLineGenerated -Line $spaceAgeElectricShootingLine -Context "Space Age electric and Tesla shooting speed scenario"
Assert-ReportLineContains -Line $spaceAgeElectricShootingLine -Expected "effects=2" -Context "Space Age electric and Tesla shooting speed scenario"

foreach ($vanillaOwnedStream in @(
  "research_low_density_structure",
  "research_plastic",
  "research_processing_unit",
  "research_rocket_fuel"
)) {
  $vanillaOwnedLine = Get-LastStreamReportLine -Key $vanillaOwnedStream
  if ($vanillaOwnedLine -notmatch "status=skipped" -or $vanillaOwnedLine -notmatch "covered_by_existing_infinite_recipe_productivity") {
    throw "Space Age vanilla-owned productivity stream should skip instead of generating a parallel MIR technology: $vanillaOwnedLine"
  }
}

Invoke-RuntimeScenario -ScenarioName "space-age-space-promethium-pack-policy" -EnabledFixtureNames @() -SciencePackIngredientPolicy "space-and-promethium" -EnableSpaceAge
$spaceAgeSpacePromethiumPackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $spaceAgeSpacePromethiumPackLine -Context "Space Age space and promethium science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $spaceAgeSpacePromethiumPackLine -Expected "space-science-pack" -Context "Space Age space and promethium science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $spaceAgeSpacePromethiumPackLine -Expected "promethium-science-pack" -Context "Space Age space and promethium science-pack ingredient policy scenario"

Invoke-RuntimeScenario -ScenarioName "all-official-pack-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack"
) -SciencePackIngredientPolicy "all-official"
$allOfficialPackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $allOfficialPackLine -Context "All official science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $allOfficialPackLine -Expected "space-science-pack" -Context "All official science-pack ingredient policy scenario"
Assert-ReportLineDoesNotContain -Line $allOfficialPackLine -Unexpected "mir-fixture-science-pack" -Context "All official science-pack ingredient policy scenario"
$allOfficialExtensionLine = Get-LastExtensionReportLine -Key "research-speed"
Assert-ReportLineGenerated -Line $allOfficialExtensionLine -Context "All official base-extension science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $allOfficialExtensionLine -Expected "space-science-pack" -Context "All official base-extension science-pack ingredient policy scenario"
Assert-ReportLineDoesNotContain -Line $allOfficialExtensionLine -Unexpected "mir-fixture-science-pack" -Context "All official base-extension science-pack ingredient policy scenario"

Invoke-RuntimeScenario -ScenarioName "all-pack-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack"
) -SciencePackIngredientPolicy "all"
$allPackLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $allPackLine -Context "All lab science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $allPackLine -Expected "mir-fixture-science-pack" -Context "All lab science-pack ingredient policy scenario"
$allPackExtensionLine = Get-LastExtensionReportLine -Key "braking-force"
Assert-ReportLineGenerated -Line $allPackExtensionLine -Context "All lab base-extension science-pack ingredient policy scenario"
Assert-ReportLineContains -Line $allPackExtensionLine -Expected "mir-fixture-science-pack" -Context "All lab base-extension science-pack ingredient policy scenario"

Invoke-RuntimeScenario -ScenarioName "base-extension-boundary-policy" -EnabledFixtureNames @(
  "mir-fixture-item-science-pack",
  "mir-fixture-finite-base-extension-level",
  "mir-fixture-assert-base-extension-boundary"
) -SciencePackIngredientPolicy "all"
$baseExtensionBoundaryLine = Get-LastExtensionReportLine -Key "research-speed"
Assert-ReportLineGenerated -Line $baseExtensionBoundaryLine -Context "Base extension boundary scenario"
Assert-ReportLineContains -Line $baseExtensionBoundaryLine -Expected "mir-fixture-science-pack" -Context "Base extension boundary scenario"

Invoke-RuntimeScenario -ScenarioName "weapon-speed-overlap-safety" -EnabledFixtureNames @(
  "mir-fixture-assert-weapon-speed-safety"
) -WeaponSpeedAdjustmentMode "only-when-dedicated-tech-enabled"
$weaponSpeedLine = Get-LastExtensionReportLine -Key "weapon-shooting-speed"
Assert-ReportLineGenerated -Line $weaponSpeedLine -Context "Weapon shooting speed overlap safety scenario"

Invoke-RuntimeScenario -ScenarioName "omega-drill-productivity" -EnabledFixtureNames @(
  "mir-fixture-omega-drill",
  "mir-fixture-assert-omega-drill-productivity"
)
$omegaDrillLine = Get-LastStreamReportLine -Key "research_mining_drill"
Assert-ReportLineGenerated -Line $omegaDrillLine -Context "Omega-style drill productivity scenario"
$omegaEffectCountMatch = [regex]::Match($omegaDrillLine, "effects=(\d+)")
if (-not $omegaEffectCountMatch.Success -or [int]$omegaEffectCountMatch.Groups[1].Value -lt 4) {
  throw "Omega-style drill productivity scenario did not include the expected mining drill effect count: $omegaDrillLine"
}

Invoke-RuntimeScenario -ScenarioName "end-game-prerequisite-gate" -EnabledFixtureNames @() -RequireSpaceGate
$gateLine = Get-LastStreamReportLine -Key "research_gears"
Assert-ReportLineGenerated -Line $gateLine -Context "End-game prerequisite gate scenario"
Assert-ReportLineContains -Line $gateLine -Expected "prerequisites=automation-science-pack,logistic-science-pack,chemical-science-pack,production-science-pack,space-science-pack" -Context "End-game prerequisite gate scenario"
Assert-ReportLineDoesNotContain -Line $gateLine -Unexpected "science=automation-science-pack,logistic-science-pack,chemical-science-pack,production-science-pack,space-science-pack" -Context "End-game prerequisite gate scenario"

if ($isLegacyFactorio20) {
  Write-Host "[skip] Factorio 2.1 cargo runtime fixture scenarios skipped for Factorio 2.0 legacy metadata."
} else {
  Invoke-RuntimeScenario -ScenarioName "base-cargo-space-age-gate" -EnabledFixtureNames @() -EnabledStreamKeys @(
    "research_cargo_landing_pad_count"
  )
  $cargoPadLine = Get-LastStreamReportLine -Key "research_cargo_landing_pad_count"
  if ($cargoPadLine -notmatch "status=skipped" -or $cargoPadLine -notmatch "missing required mod space-age") {
    throw "Cargo landing pad count generated or skipped for the wrong reason without Space Age: $cargoPadLine"
  }

  Invoke-RuntimeScenario -ScenarioName "space-age-cargo-pad-enabled" -EnabledFixtureNames @() -EnabledStreamKeys @(
    "research_cargo_landing_pad_count"
  ) -EnableSpaceAge
  $spaceAgeCargoPadLine = Get-LastStreamReportLine -Key "research_cargo_landing_pad_count"
  Assert-ReportLineGenerated -Line $spaceAgeCargoPadLine -Context "Space Age cargo landing pad count scenario"
  $spaceAgeCargoDistanceLine = Get-LastStreamReportLine -Key "research_cargo_bay_unloading_distance"
  Assert-ReportLineGenerated -Line $spaceAgeCargoDistanceLine -Context "Space Age cargo bay unloading distance scenario"

  Invoke-RuntimeScenario -ScenarioName "space-age-cargo-logistics-shape" -EnabledFixtureNames @(
    "mir-fixture-assert-cargo-logistics"
  ) -EnabledStreamKeys @(
    "research_cargo_landing_pad_count"
  ) -EnableSpaceAge
  $spaceAgeCargoShapePadLine = Get-LastStreamReportLine -Key "research_cargo_landing_pad_count"
  Assert-ReportLineGenerated -Line $spaceAgeCargoShapePadLine -Context "Space Age cargo logistics shape scenario"
  $spaceAgeCargoShapeDistanceLine = Get-LastStreamReportLine -Key "research_cargo_bay_unloading_distance"
  Assert-ReportLineGenerated -Line $spaceAgeCargoShapeDistanceLine -Context "Space Age cargo logistics shape scenario"
}

Write-Host "[ok] Validation completed."
$global:LASTEXITCODE = 0
