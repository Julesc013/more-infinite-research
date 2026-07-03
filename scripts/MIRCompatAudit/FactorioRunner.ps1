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
    [Parameter(Mandatory)][string[]]$EnabledMods
  )

  $mods = @()
  foreach ($name in @("base") + ($EnabledMods | Sort-Object -Unique)) {
    $mods += [ordered]@{
      name = $name
      enabled = $true
    }
  }

  [ordered]@{
    mods = $mods
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ModsDir "mod-list.json") -Encoding UTF8
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

  $exclude = @(".git", "build", "dist")
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
    [Parameter(Mandatory)][object[]]$LockEntries
  )

  foreach ($entry in $LockEntries) {
    if (-not $entry.file_name) { continue }
    $source = Join-Path $CacheDir ([string]$entry.file_name)
    if (Test-Path -LiteralPath $source) {
      Copy-Item -LiteralPath $source -Destination (Join-Path $ModsDir ([string]$entry.file_name)) -Force
    }
  }
}

function Invoke-MIRFactorioLoadCheck {
  param(
    [Parameter(Mandatory)][string]$FactorioBin,
    [Parameter(Mandatory)][string]$UserDataDir,
    [Parameter(Mandatory)][string]$ScenarioName
  )

  $savePath = Join-Path $UserDataDir "saves\$ScenarioName.zip"
  $logPath = Join-Path $UserDataDir "$ScenarioName.log"
  $args = @(
    "--create", $savePath,
    "--mod-directory", (Join-Path $UserDataDir "mods"),
    "--disable-audio"
  )

  $process = Start-Process -FilePath $FactorioBin -ArgumentList $args -Wait -PassThru -NoNewWindow -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err"
  $auditRows = @()
  if ((Test-Path -LiteralPath $logPath) -and (Get-Command Read-MIRAuditLog -ErrorAction SilentlyContinue)) {
    $auditRows = @(Read-MIRAuditLog -Path $logPath)
  }

  [pscustomobject]@{
    scenario = $ScenarioName
    exit_code = $process.ExitCode
    save = $savePath
    stdout = $logPath
    stderr = "$logPath.err"
    audit_rows = $auditRows
    passed = $process.ExitCode -eq 0
  }
}
