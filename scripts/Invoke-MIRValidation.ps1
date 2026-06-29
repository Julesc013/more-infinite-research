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
      "${root}locale/en/more-infinite-research.cfg",
      "${root}docs/architecture.md",
      "${root}docs/compatibility.md",
      "${root}prototypes/tech-gen.lua"
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

$modsDir = Join-Path $UserDataDir "mods"
New-Item -ItemType Directory -Force -Path $modsDir | Out-Null

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
  param([string]$Source, [string]$Name)
  $target = Join-Path $modsDir $Name
  if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
  }
  Copy-Item -LiteralPath $Source -Destination $target -Recurse
}

Copy-ModDirectory -Source $repo -Name "more-infinite-research"
$fixtureRoot = Join-Path $repo "fixtures"
if (-not (Test-Path -LiteralPath $fixtureRoot)) {
  throw "Fixture directory not found: $fixtureRoot"
}

$fixtureNames = @()
foreach ($fixture in Get-ChildItem -LiteralPath $fixtureRoot -Directory) {
  $info = Get-Content -Raw (Join-Path $fixture.FullName "info.json") | ConvertFrom-Json
  $fixtureNames += $info.name
  Copy-ModDirectory -Source $fixture.FullName -Name $info.name
}

$copiedInfoPath = Join-Path $modsDir "more-infinite-research\info.json"
$copiedInfo = Get-Content -Raw -LiteralPath $copiedInfoPath | ConvertFrom-Json
$dependencies = @($copiedInfo.dependencies)
foreach ($fixtureName in $fixtureNames) {
  $dependency = "? $fixtureName"
  if ($dependencies -notcontains $dependency) {
    $dependencies += $dependency
  }
}
$copiedInfo.dependencies = $dependencies
$copiedInfo | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $copiedInfoPath -Encoding UTF8

$modList = @{
  mods = @(
    @{ name = "base"; enabled = $true },
    @{ name = "more-infinite-research"; enabled = $true },
    @{ name = "mir-fixture-item-science-pack"; enabled = $true },
    @{ name = "mir-fixture-custom-lab"; enabled = $true },
    @{ name = "mir-fixture-late-recipe"; enabled = $true }
  )
} | ConvertTo-Json -Depth 5

Set-Content -LiteralPath (Join-Path $modsDir "mod-list.json") -Value $modList -Encoding UTF8

$savePath = Join-Path $UserDataDir "mir-validation.zip"
if (Test-Path -LiteralPath $savePath) {
  Remove-Item -LiteralPath $savePath -Force
}

Write-Host "[run] Factorio load check with fixture mods"
$factorioArgs = @(
  "--mod-directory",
  $modsDir,
  "--create",
  $savePath
)
$factorioExitCode = Invoke-FactorioProcess -FilePath $FactorioBin -Arguments $factorioArgs
if ($factorioExitCode -ne 0) {
  throw "Factorio runtime validation exited with code $factorioExitCode"
}
if (-not (Test-Path -LiteralPath $savePath)) {
  throw "Factorio runtime validation did not create the expected save: $savePath. Factorio exit code: $factorioExitCode"
}

if ([string]::IsNullOrWhiteSpace($FactorioLog)) {
  $FactorioLog = Join-Path $env:APPDATA "Factorio\factorio-current.log"
}
Write-Host "[info] Factorio log path: $FactorioLog"
if (Test-Path -LiteralPath $FactorioLog) {
  $fatalMarkers = Select-String -LiteralPath $FactorioLog -Pattern "------------- Error -------------", "Error Util.cpp" -SimpleMatch
  if ($fatalMarkers) {
    $fatalMarkers | Select-Object -First 10 | ForEach-Object { Write-Host $_.Line }
    throw "Factorio runtime validation log contains fatal error markers."
  }
}

Write-Host "[ok] Validation completed."
$global:LASTEXITCODE = 0
