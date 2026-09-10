$ErrorActionPreference = "Stop"

function New-MIRCompatUserDataDir {
  param([Parameter(Mandatory)][string]$Root)

  $dir = Join-Path $Root ("u-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
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
    [Parameter(Mandatory)][string]$ModsDir,
    [string]$ZipPath = ""
  )

  if (-not [string]::IsNullOrWhiteSpace($ZipPath)) {
    $resolvedZip = (Resolve-Path -LiteralPath $ZipPath).Path
    if ([System.IO.Path]::GetExtension($resolvedZip) -ne ".zip") {
      throw "MIR mod-under-test archive must be a zip: $resolvedZip"
    }
    $zipTarget = Join-Path $ModsDir ([System.IO.Path]::GetFileName($resolvedZip))
    Copy-Item -LiteralPath $resolvedZip -Destination $zipTarget -Force
    return $zipTarget
  }

  $target = Join-Path $ModsDir "more-infinite-research"
  if (Test-Path -LiteralPath $target) {
    Remove-Item -LiteralPath $target -Recurse -Force
  }

  $exclude = @(
    ".codex",
    ".git",
    ".github",
    ".mir",
    "AGENTS.md",
    "CONTRIBUTING.md",
    "artifacts",
    "build",
    "dist",
    "docs",
    "fixtures",
    "scripts",
    "tests",
    "tmp",
    "todo.md",
    "tools"
  )
  New-Item -ItemType Directory -Path $target | Out-Null
  Get-ChildItem -LiteralPath $RepoRoot -Force | Where-Object {
    $exclude -notcontains $_.Name
  } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force
  }

  return $target
}

function Copy-MIRCachedModZips {
  param(
    [Parameter(Mandatory)][string]$CacheDir,
    [Parameter(Mandatory)][string]$ModsDir,
    [object[]]$LockEntries = @(),
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

function Assert-MIRManualScenarioRuntimeContract {
  param($Scenario,[string]$ManifestPath,[string]$RepoRoot,[int]$DefaultTimeoutSeconds=900)
  $name=[string](Get-MIRObjectProperty -Object $Scenario -Name "name" -Default "")
  $timeout=[int](Get-MIRObjectProperty -Object $Scenario -Name "timeout_seconds" -Default $DefaultTimeoutSeconds)
  $rawCount=Get-MIRObjectProperty -Object $Scenario -Name "required_reload_count" -Default 0
  $rawMaximum=Get-MIRObjectProperty -Object $Scenario -Name "max_reload_duration_seconds" -Default 0
  if(($rawCount-isnot[int]-and$rawCount-isnot[long])-or($rawMaximum-isnot[int]-and$rawMaximum-isnot[long])){throw "Scenario '$name' reload count and duration must be integers in $ManifestPath."}
  $count=[int]$rawCount;$maximum=[int]$rawMaximum
  if($count-lt 0-or$count-gt 2-or($count-eq 0-and$maximum-ne 0)-or($count-gt 0-and($maximum-lt 1-or$maximum-gt$timeout))){throw "Scenario '$name' reload duration contract is invalid in $ManifestPath."}
  $fixtureProperty=$Scenario.PSObject.Properties['runtime_fixtures']
  if($null-ne$fixtureProperty-and$fixtureProperty.Value-isnot[System.Array]){throw "Scenario '$name' runtime_fixtures must be an array in $ManifestPath."}
  $fixtures=@(if($null-eq$fixtureProperty){@()}else{@($fixtureProperty.Value)})
  if($fixtures.Count-gt 0-and$count-eq 0){throw "Scenario '$name' cannot declare runtime_fixtures without reloads in $ManifestPath."}
  $fixtureRoot=[IO.Path]::GetFullPath((Join-Path $RepoRoot 'fixtures'));$fixturePrefix=$fixtureRoot.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  foreach($fixture in $fixtures){
    $relative=([string]$fixture).Replace('\','/')
    if([string]::IsNullOrWhiteSpace($relative)-or[IO.Path]::IsPathRooted($relative)-or$relative-notmatch'^fixtures/[A-Za-z0-9._/-]+$'-or$relative-match'(^|/)\.\.(/|$)'){throw "Scenario '$name' has an unsafe runtime fixture path '$fixture' in $ManifestPath."}
    $resolved=[IO.Path]::GetFullPath((Join-Path $RepoRoot $relative))
    if(-not$resolved.StartsWith($fixturePrefix,[StringComparison]::OrdinalIgnoreCase)-or-not(Test-Path -LiteralPath $resolved -PathType Container)-or-not(Test-Path -LiteralPath(Join-Path $resolved 'info.json')-PathType Leaf)-or-not(Test-Path -LiteralPath(Join-Path $resolved 'control.lua')-PathType Leaf)){throw "Scenario '$name' runtime fixture '$fixture' is incomplete in $ManifestPath."}
    $info=Get-Content -Raw -LiteralPath(Join-Path $resolved 'info.json')|ConvertFrom-Json
    if([string]::IsNullOrWhiteSpace([string]$info.name)){throw "Scenario '$name' runtime fixture '$fixture' has no mod identity in $ManifestPath."}
  }
  $plan=Get-MIRObjectProperty -Object $Scenario -Name 'expected_plan' -Default([pscustomobject]@{});$logProperty=$plan.PSObject.Properties['required_reload_log_fragments']
  if($null-ne$logProperty-and$logProperty.Value-isnot[System.Array]){throw "Scenario '$name' required_reload_log_fragments must be an array in $ManifestPath."}
  $fragments=@(if($null-eq$logProperty){@()}else{@($logProperty.Value)})
  if($fragments.Count-gt 0-and$count-eq 0){throw "Scenario '$name' cannot require reload log fragments without reloads in $ManifestPath."}
  foreach($fragment in $fragments){if($fragment-isnot[string]-or[string]::IsNullOrWhiteSpace([string]$fragment)){throw "Scenario '$name' has an empty reload log fragment in $ManifestPath."}}
}

function Get-MIRCompatFileSha256 {param([string]$Path);if([string]::IsNullOrWhiteSpace($Path)-or-not(Test-Path -LiteralPath $Path -PathType Leaf)){return ''};(Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()}
function Copy-MIRCompatFactorioCurrentLog {param([string]$UserDataDir,[string]$Destination);$source=Join-Path $UserDataDir 'factorio-current.log';if(-not(Test-Path -LiteralPath $source -PathType Leaf)){return ''};Copy-Item -LiteralPath $source -Destination $Destination -Force;return $Destination}
function Invoke-MIRCompatFactorioProcess {
  param([string]$FactorioBin,[object[]]$ArgumentList,[string]$StdoutPath,[string]$StderrPath,[int]$TimeoutSeconds)
  $timer=[Diagnostics.Stopwatch]::StartNew();$parameters=@{FilePath=$FactorioBin;ArgumentList=$ArgumentList;PassThru=$true;RedirectStandardOutput=$StdoutPath;RedirectStandardError=$StderrPath}
  if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){$parameters.WindowStyle='Hidden'}else{$parameters.NoNewWindow=$true}
  $process=Start-Process @parameters;$timedOut=$false
  try{if(-not$process.WaitForExit([Math]::Max(1,$TimeoutSeconds)*1000)){$timedOut=$true;try{Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue;$null=$process.WaitForExit(5000)}catch{}};$exitCode=if($timedOut){-1}else{$process.ExitCode}}finally{$timer.Stop();$process.Dispose()}
  [pscustomobject]@{exit_code=$exitCode;timed_out=$timedOut;duration_seconds=[Math]::Round($timer.Elapsed.TotalSeconds,6);passed=(-not$timedOut)-and$exitCode-eq 0}
}
function Invoke-MIRFactorioLoadCheck {
  param([string]$FactorioBin,[string]$UserDataDir,[string]$ScenarioName,[int]$ScenarioTimeoutSeconds=900)
  $safe=Get-MIRSafeScenarioFileName -Name $ScenarioName
  $save=Join-Path $UserDataDir "saves\$safe.zip";$stdout=Join-Path $UserDataDir "$safe.stdout.log";$stderr=Join-Path $UserDataDir "$safe.stderr.log";$factorioLog=Join-Path $UserDataDir "$safe.factorio.log"
  $binary=(Resolve-Path -LiteralPath $FactorioBin).Path;$factorioRoot=Split-Path -Parent(Split-Path -Parent(Split-Path -Parent $binary));$readData=Join-Path $factorioRoot 'data'
  if(-not(Test-Path -LiteralPath $readData)){throw "Unable to find Factorio read-data directory for compatibility audit config: $readData"}
  $config=Join-Path $UserDataDir 'mir-compat-config.ini';$configText=@"
; Generated by More Infinite Research compatibility audit.
[path]
read-data=$readData
write-data=$UserDataDir

[general]
locale=auto

[other]
enable-steam-networking=false
disable-blueprint-storage=true
"@
  Set-Content -LiteralPath $config -Value $configText -Encoding UTF8
  $currentLog=Join-Path $UserDataDir 'factorio-current.log';if(Test-Path -LiteralPath $currentLog){Remove-Item -LiteralPath $currentLog -Force}
  $arguments=@('--config',$config,'--no-log-rotation','--create',$save,'--mod-directory',(Join-Path $UserDataDir 'mods'),'--disable-audio')
  $process=Invoke-MIRCompatFactorioProcess -FactorioBin $binary -ArgumentList $arguments -StdoutPath $stdout -StderrPath $stderr -TimeoutSeconds $ScenarioTimeoutSeconds
  $captured=Copy-MIRCompatFactorioCurrentLog -UserDataDir $UserDataDir -Destination $factorioLog
  $audit=if($captured-and(Get-Command Read-MIRAuditLog -ErrorAction SilentlyContinue)){@(Read-MIRAuditLog -Path $captured)}else{@()};$sanitation=if($captured-and(Get-Command Read-MIRSanitationLog -ErrorAction SilentlyContinue)){@(Read-MIRSanitationLog -Path $captured)}else{@()};$saveHash=Get-MIRCompatFileSha256 -Path $save
  [pscustomobject]@{scenario=$ScenarioName;exit_code=$process.exit_code;timed_out=$process.timed_out;timeout_seconds=$ScenarioTimeoutSeconds;duration_seconds=$process.duration_seconds;save=$save;save_sha256=$saveHash;stdout=$stdout;stdout_sha256=Get-MIRCompatFileSha256 $stdout;stderr=$stderr;stderr_sha256=Get-MIRCompatFileSha256 $stderr;factorio_log=$captured;factorio_log_sha256=Get-MIRCompatFileSha256 $captured;audit_rows=$audit;sanitation_rows=$sanitation;passed=$process.passed-and-not[string]::IsNullOrWhiteSpace($saveHash)-and-not[string]::IsNullOrWhiteSpace($captured)}
}

function Invoke-MIRFactorioBenchmarkReload {
  param([string]$FactorioBin,[string]$UserDataDir,[string]$ScenarioName,[string]$SavePath,[ValidateRange(1,2)][int]$Ordinal,[ValidateRange(1,3600)][int]$MaximumDurationSeconds)
  $userData=(Resolve-Path -LiteralPath $UserDataDir).Path;$save=(Resolve-Path -LiteralPath $SavePath).Path;$prefix=$userData.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  if(-not$save.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "Reload save is outside the compatibility user-data root: $save"}
  $inputHash=Get-MIRCompatFileSha256 $save;$safe=Get-MIRSafeScenarioFileName -Name $ScenarioName;$label="$safe.reload-{0:D2}"-f$Ordinal
  $stdout=Join-Path $userData "$label.stdout.log";$stderr=Join-Path $userData "$label.stderr.log";$factorioLog=Join-Path $userData "$label.factorio.log";$currentLog=Join-Path $userData 'factorio-current.log'
  if(Test-Path -LiteralPath $currentLog){Remove-Item -LiteralPath $currentLog -Force}
  $config=Join-Path $userData 'mir-compat-config.ini';$binary=(Resolve-Path -LiteralPath $FactorioBin).Path
  $arguments=@('--config',$config,'--no-log-rotation','--disable-audio','--mod-directory',(Join-Path $userData 'mods'),'--benchmark',$save,'--benchmark-ticks','1','--benchmark-runs','1','--benchmark-sanitize')
  $process=Invoke-MIRCompatFactorioProcess -FactorioBin $binary -ArgumentList $arguments -StdoutPath $stdout -StderrPath $stderr -TimeoutSeconds $MaximumDurationSeconds
  $captured=Copy-MIRCompatFactorioCurrentLog -UserDataDir $userData -Destination $factorioLog;$saveHash=Get-MIRCompatFileSha256 $save;$identical=-not[string]::IsNullOrWhiteSpace($inputHash)-and$saveHash-ceq$inputHash
  $audit=if($captured-and(Get-Command Read-MIRAuditLog -ErrorAction SilentlyContinue)){@(Read-MIRAuditLog -Path $captured)}else{@()};$sanitation=if($captured-and(Get-Command Read-MIRSanitationLog -ErrorAction SilentlyContinue)){@(Read-MIRSanitationLog -Path $captured)}else{@()}
  $passed=$process.passed-and$process.duration_seconds-le$MaximumDurationSeconds-and$identical-and-not[string]::IsNullOrWhiteSpace($captured)
  [pscustomobject]@{ordinal=$Ordinal;status=if($passed){'passed'}else{'failed'};passed=$passed;exit_code=$process.exit_code;timed_out=$process.timed_out;duration_seconds=$process.duration_seconds;maximum_duration_seconds=$MaximumDurationSeconds;input_save_sha256=$inputHash;save_sha256=$saveHash;save_byte_identical=$identical;stdout=$stdout;stdout_sha256=Get-MIRCompatFileSha256 $stdout;stderr=$stderr;stderr_sha256=Get-MIRCompatFileSha256 $stderr;factorio_log=$captured;factorio_log_sha256=Get-MIRCompatFileSha256 $captured;audit_rows=$audit;sanitation_rows=$sanitation}
}
function Invoke-MIRFactorioReloadContract {
  param(
    [Parameter(Mandatory)][string]$FactorioBin,
    [Parameter(Mandatory)][string]$UserDataDir,
    [Parameter(Mandatory)][string]$ScenarioName,
    [Parameter(Mandatory)][string]$SavePath,
    [ValidateRange(1, 2)][int]$RequiredReloadCount,
    [ValidateRange(1, 3600)][int]$MaxReloadDurationSeconds,
    [string[]]$RequiredLogFragments = @()
  )

  $reloads = @()
  foreach ($ordinal in 1..$RequiredReloadCount) {
    $reload = Invoke-MIRFactorioBenchmarkReload `
      -FactorioBin $FactorioBin `
      -UserDataDir $UserDataDir `
      -ScenarioName $ScenarioName `
      -SavePath $SavePath `
      -Ordinal $ordinal `
      -MaximumDurationSeconds $MaxReloadDurationSeconds
    $reloadLogText = if (-not [string]::IsNullOrWhiteSpace([string]$reload.factorio_log) -and
        (Test-Path -LiteralPath ([string]$reload.factorio_log) -PathType Leaf)) {
      [IO.File]::ReadAllText([string]$reload.factorio_log)
    } else { "" }
    $assertions = @(
      foreach ($fragment in $RequiredLogFragments) {
        [pscustomobject]@{
          fragment = $fragment
          passed = $reloadLogText.Contains($fragment, [StringComparison]::Ordinal)
        }
      }
    )
    $logContractPassed = @($assertions | Where-Object { $_.passed -ne $true }).Count -eq 0
    $reload.passed = [bool]($reload.passed -and $logContractPassed)
    $reload.status = if ($reload.passed) { "passed" } else { "failed" }
    $reload | Add-Member -NotePropertyName reload_log_contract_passed -NotePropertyValue $logContractPassed -Force
    $reload | Add-Member -NotePropertyName required_log_assertions -NotePropertyValue $assertions -Force
    $reloads += $reload
  }

  [pscustomobject]@{
    attempted = $true
    required_count = $RequiredReloadCount
    actual_count = $reloads.Count
    required_log_fragments = @($RequiredLogFragments)
    reloads = $reloads
    passed = ($reloads.Count -eq $RequiredReloadCount -and
      @($reloads | Where-Object { $_.passed -ne $true }).Count -eq 0)
  }
}
