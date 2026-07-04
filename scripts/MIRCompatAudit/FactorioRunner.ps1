$ErrorActionPreference = "Stop"

function New-MIRCompatUserDataDir {
  param([Parameter(Mandatory)][string]$Root)

  $dir = Join-Path $Root ("user-data-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $dir | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $dir "mods") | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $dir "saves") | Out-Null
  return (Resolve-Path -LiteralPath $dir).Path
}

function Write-MIRModList {
  param(
    [Parameter(Mandatory)][string]$ModsDir,
    [Parameter(Mandatory)][string[]]$EnabledMods,
    [string[]]$OfficialBuiltinMods = @("elevated-rails", "recycler", "quality", "space-age")
  )

  $enabledLookup = @{ base = $true }
  foreach ($name in @($EnabledMods)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
      $enabledLookup[[string]$name] = $true
    }
  }

  $additionalModNames = @(
    $EnabledMods |
      Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_) -and
        $_ -ne "base" -and
        $OfficialBuiltinMods -notcontains [string]$_
      } |
      Sort-Object -Unique
  )

  $mods = @()
  foreach ($name in @("base") + $OfficialBuiltinMods + $additionalModNames) {
    $mods += [ordered]@{
      name = $name
      enabled = $enabledLookup.ContainsKey([string]$name)
    }
  }

  [ordered]@{
    mods = $mods
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ModsDir "mod-list.json") -Encoding UTF8
}

function Get-MIRSafeScenarioFileName {
  param([Parameter(Mandatory)][string]$Name)

  $safe = $Name
  foreach ($ch in [System.IO.Path]::GetInvalidFileNameChars()) {
    $safe = $safe.Replace([string]$ch, "-")
  }
  if ([string]::IsNullOrWhiteSpace($safe)) { return "scenario" }
  return $safe
}

function Copy-MIRModUnderTest {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ModsDir
  )

  $target = Join-Path $ModsDir "more-infinite-research"
  if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
  }

  $exclude = @(".git", "artifacts", "build", "dist")
  New-Item -ItemType Directory -Path $target | Out-Null
  Get-ChildItem -LiteralPath $RepoRoot -Force | Where-Object {
    $exclude -notcontains $_.Name
  } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force
  }

  return $target
}

function Enable-MIRCopiedGenerationReport {
  param([Parameter(Mandatory)][string]$ModsDir)

  $diagnosticsPath = Join-Path $ModsDir "more-infinite-research\prototypes\diagnostics.lua"
  if (-not (Test-Path -LiteralPath $diagnosticsPath)) { return }

  $diagnostics = Get-Content -Raw -LiteralPath $diagnosticsPath
  $diagnostics = $diagnostics -replace 'return startup_setting\("mir-debug-generation-report"\) == true', 'return true'
  Set-Content -LiteralPath $diagnosticsPath -Value $diagnostics -Encoding UTF8
}

function Copy-MIRCachedModZips {
  param(
    [Parameter(Mandatory)][string]$CacheDir,
    [Parameter(Mandatory)][string]$ModsDir,
    [Parameter(Mandatory)][object[]]$LockEntries,
    [ValidateSet("Copy", "Hardlink", "Symlink")]
    [string]$LinkMode = "Copy"
  )

  function Copy-MIRZipIntoScenario {
    param(
      [Parameter(Mandatory)][string]$Source,
      [Parameter(Mandatory)][string]$Target,
      [ValidateSet("Copy", "Hardlink", "Symlink")]
      [string]$Mode
    )

    if (Test-Path -LiteralPath $Target) { return }

    if ($Mode -eq "Hardlink") {
      $sourceRoot = [System.IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Source).Path)
      $targetRoot = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Target))
      if ($sourceRoot -eq $targetRoot) {
        try {
          New-Item -ItemType HardLink -Path $Target -Target $Source -ErrorAction Stop | Out-Null
          return
        } catch {
          # Fall back to copy when the filesystem refuses a hardlink.
        }
      }
    } elseif ($Mode -eq "Symlink") {
      try {
        New-Item -ItemType SymbolicLink -Path $Target -Target $Source -ErrorAction Stop | Out-Null
        return
      } catch {
        # Fall back to copy when symlink creation is unavailable.
      }
    }

    Copy-Item -LiteralPath $Source -Destination $Target -Force
  }

  foreach ($entry in $LockEntries) {
    if (-not $entry.file_name) { continue }
    $sourcePath = ""
    $sourcePathProperty = $entry.PSObject.Properties["source_path"]
    if ($null -ne $sourcePathProperty) {
      $sourcePath = [string]$sourcePathProperty.Value
    }
    $source = if (-not [string]::IsNullOrWhiteSpace($sourcePath)) {
      $sourcePath
    } else {
      Join-Path $CacheDir ([string]$entry.file_name)
    }
    if (Test-Path -LiteralPath $source) {
      Copy-MIRZipIntoScenario -Source $source -Target (Join-Path $ModsDir ([string]$entry.file_name)) -Mode $LinkMode
    }
  }
}

function Invoke-MIRFactorioLoadCheck {
  param(
    [Parameter(Mandatory)][string]$FactorioBin,
    [Parameter(Mandatory)][string]$UserDataDir,
    [Parameter(Mandatory)][string]$ScenarioName,
    [int]$ScenarioTimeoutSeconds = 900
  )

  $safeScenarioName = Get-MIRSafeScenarioFileName -Name $ScenarioName
  $savePath = Join-Path $UserDataDir "saves\$safeScenarioName.zip"
  $logPath = Join-Path $UserDataDir "$safeScenarioName.log"
  $args = @(
    "--create", $savePath,
    "--mod-directory", (Join-Path $UserDataDir "mods"),
    "--disable-audio"
  )

  $process = Start-Process -FilePath $FactorioBin -ArgumentList $args -PassThru -NoNewWindow -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err"
  $timedOut = $false
  $waitMilliseconds = [Math]::Max(1, $ScenarioTimeoutSeconds) * 1000
  if (-not $process.WaitForExit($waitMilliseconds)) {
    $timedOut = $true
    try {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      $null = $process.WaitForExit(5000)
    } catch {
      # Best effort cleanup; the timed_out result is the important artifact.
    }
  }

  $auditRows = @()
  if ((Test-Path -LiteralPath $logPath) -and (Get-Command Read-MIRAuditLog -ErrorAction SilentlyContinue)) {
    $auditRows = @(Read-MIRAuditLog -Path $logPath)
  }

  $exitCode = if ($timedOut) { -1 } else { $process.ExitCode }
  [pscustomobject]@{
    scenario = $ScenarioName
    exit_code = $exitCode
    timed_out = $timedOut
    timeout_seconds = $ScenarioTimeoutSeconds
    save = $savePath
    stdout = $logPath
    stderr = "$logPath.err"
    audit_rows = $auditRows
    passed = (-not $timedOut) -and $exitCode -eq 0
  }
}
