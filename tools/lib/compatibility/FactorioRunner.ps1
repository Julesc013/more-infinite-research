$ErrorActionPreference = "Stop"
$mirCompatIdentityModule=New-Module -Name MIRCompatInputIdentity -ArgumentList (Join-Path $PSScriptRoot '../validation/ImmutableInputStaging.ps1') -ScriptBlock {
  param($Path)
  . $Path
  Export-ModuleMember -Function Get-MIRImmutableInputSha256,Get-MIRImmutableInputFileIdentity
}
Import-Module $mirCompatIdentityModule -Force
. (Join-Path $PSScriptRoot 'LibraryActivation.ps1')

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

  if ([string]::IsNullOrWhiteSpace($ZipPath)) { throw '[mir-compat-package-required] Supply the existing materialized MIR ZIP.' }
  $resolvedZip=(Resolve-Path -LiteralPath $ZipPath).Path
  $fileName=[IO.Path]::GetFileName($resolvedZip)
  Copy-MIRCachedModZips -CacheDir (Split-Path -Parent $resolvedZip) -ModsDir $ModsDir -LockEntries @(
    [pscustomobject]@{file_name=$fileName;source_path=$resolvedZip;sha256=Get-MIRImmutableInputSha256 -Path $resolvedZip}
  ) -LinkMode Hardlink
  return Join-Path $ModsDir $fileName
}

function Copy-MIRCachedModZips {
  param(
    [Parameter(Mandatory)][string]$CacheDir,
    [Parameter(Mandatory)][string]$ModsDir,
    [object[]]$LockEntries = @(),
    [ValidateSet("Hardlink")]
    [string]$LinkMode = "Hardlink"
  )
  foreach ($entry in $LockEntries) {
    if ([string]$entry.file_name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*[.]zip$') { throw '[mir-compat-archive-name]' }
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
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "[mir-compat-archive-missing] $($entry.file_name)" }
    $source=(Resolve-Path -LiteralPath $source).Path
    if (((Get-Item -LiteralPath $source -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '[mir-compat-archive-reparse]' }
    $expected=Get-MIRImmutableInputSha256 -Path $source
    $hashProperty=$entry.PSObject.Properties['sha256']
    if ($null -ne $hashProperty -and [string]$hashProperty.Value -cne $expected) { throw '[mir-compat-archive-hash]' }
    $target=Join-Path $ModsDir ([string]$entry.file_name)
    if ((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '[mir-compat-archive-reparse]' }
    if (-not (Test-Path -LiteralPath $target)) {
      # A failed link refuses the scenario. Never copy a dependency archive.
      New-Item -ItemType HardLink -Path $target -Target $source -ErrorAction Stop | Out-Null
    }
    if ((Get-MIRImmutableInputFileIdentity -Path $source) -cne (Get-MIRImmutableInputFileIdentity -Path $target) -or
        (Get-MIRImmutableInputSha256 -Path $target) -cne $expected) { throw '[mir-compat-archive-alias]' }
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
  param([string]$FactorioBin,[object[]]$ArgumentList,[string]$StdoutPath,[string]$StderrPath,[int]$TimeoutSeconds,
    [int64]$EstimatedPeakBytes=0,[int64]$ExpectedPeakMemoryBytes=0,$LibraryActivation=$null)
  . (Join-Path $PSScriptRoot '../../mir/application/release/readiness/Common.ps1')
  . (Join-Path $PSScriptRoot '../../mir/application/release/readiness/ResourceGovernor.ps1')
  $work=Resolve-MIR441RecoveryScratchPath -Path (Split-Path -Parent $StdoutPath)
  if($null -ne $LibraryActivation){Assert-MIRLibraryLaunch -Activation $LibraryActivation -FactorioBin $FactorioBin -Arguments $ArgumentList}
  foreach($flag in @('--config','--mod-directory','--create','--log-file')){
    if(@($ArgumentList|Where-Object {$_-ceq$flag}).Count-gt1){throw '[mir441-resource-factorio-duplicate-output-argument]'}
    $index=[Array]::IndexOf($ArgumentList,$flag)
    if($index-ge0){if($index+1-ge$ArgumentList.Count){throw '[mir441-resource-factorio-output-argument]'};if($flag -cne '--mod-directory' -or $null -eq $LibraryActivation){$null=Resolve-MIR441RecoveryScratchPath -Path ([string]$ArgumentList[$index+1])}}
  }
  $configIndex=[Array]::IndexOf($ArgumentList,'--config')
  if($configIndex-lt0){throw '[mir441-resource-factorio-config-required]'}
  $config=Get-Content -LiteralPath ([string]$ArgumentList[$configIndex+1]) -Raw
  $writeData=[regex]::Matches($config,'(?m)^\s*write-data\s*=\s*(.+?)\s*$')
  if($writeData.Count-ne1){throw '[mir441-resource-factorio-write-data-required]'}
  $null=Resolve-MIR441RecoveryScratchPath -Path $writeData[0].Groups[1].Value
  Invoke-MIR441MonitoredProcess -FilePath $FactorioBin -Arguments ([string[]]$ArgumentList) -WorkRoot $work `
    -LedgerPath ($StdoutPath+'.resources.jsonl') -Policy ([pscustomobject]@{minimum_free_ram_gib=4}) `
    -EstimatedPeakBytes $EstimatedPeakBytes -ExpectedPeakMemoryBytes $ExpectedPeakMemoryBytes `
    -StdoutPath $StdoutPath -StderrPath $StderrPath -TimeoutSeconds $TimeoutSeconds -AllowNonZeroExit
}
function Invoke-MIRFactorioLoadCheck {
  param([string]$FactorioBin,[string]$UserDataDir,[string]$ScenarioName,[int]$ScenarioTimeoutSeconds=900,$LibraryActivation=$null)
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
enable-new-mods=false
"@
  Set-Content -LiteralPath $config -Value $configText -Encoding UTF8
  $currentLog=Join-Path $UserDataDir 'factorio-current.log';if(Test-Path -LiteralPath $currentLog){Remove-Item -LiteralPath $currentLog -Force}
  $mods=if($null -ne $LibraryActivation){$LibraryActivation.library}else{Join-Path $UserDataDir 'mods'}
  $arguments=@('--config',$config,'--no-log-rotation','--create',$save,'--mod-directory',$mods,'--disable-audio')
  $activationArgs=@{};if($null -ne $LibraryActivation){$activationArgs.LibraryActivation=$LibraryActivation}
  $process=Invoke-MIRCompatFactorioProcess -FactorioBin $binary -ArgumentList $arguments -StdoutPath $stdout -StderrPath $stderr -TimeoutSeconds $ScenarioTimeoutSeconds @activationArgs
  $captured=Copy-MIRCompatFactorioCurrentLog -UserDataDir $UserDataDir -Destination $factorioLog
  if($null -ne $LibraryActivation -and $process.passed){$null=Assert-MIRLibraryLoadedSelection -Activation $LibraryActivation -LogPath $captured}
  $audit=if($captured-and(Get-Command Read-MIRAuditLog -ErrorAction SilentlyContinue)){@(Read-MIRAuditLog -Path $captured)}else{@()};$sanitation=if($captured-and(Get-Command Read-MIRSanitationLog -ErrorAction SilentlyContinue)){@(Read-MIRSanitationLog -Path $captured)}else{@()};$saveHash=Get-MIRCompatFileSha256 -Path $save
  [pscustomobject]@{scenario=$ScenarioName;exit_code=$process.exit_code;timed_out=$process.timed_out;timeout_seconds=$ScenarioTimeoutSeconds;duration_seconds=$process.duration_seconds;save=$save;save_sha256=$saveHash;stdout=$stdout;stdout_sha256=Get-MIRCompatFileSha256 $stdout;stderr=$stderr;stderr_sha256=Get-MIRCompatFileSha256 $stderr;factorio_log=$captured;factorio_log_sha256=Get-MIRCompatFileSha256 $captured;audit_rows=$audit;sanitation_rows=$sanitation;passed=$process.passed-and-not[string]::IsNullOrWhiteSpace($saveHash)-and-not[string]::IsNullOrWhiteSpace($captured)}
}

function Invoke-MIRFactorioBenchmarkReload {
  param([string]$FactorioBin,[string]$UserDataDir,[string]$ScenarioName,[string]$SavePath,[ValidateRange(1,2)][int]$Ordinal,[ValidateRange(1,3600)][int]$MaximumDurationSeconds,$LibraryActivation=$null)
  $userData=(Resolve-Path -LiteralPath $UserDataDir).Path;$save=(Resolve-Path -LiteralPath $SavePath).Path;$prefix=$userData.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  if(-not$save.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw "Reload save is outside the compatibility user-data root: $save"}
  $inputHash=Get-MIRCompatFileSha256 $save;$safe=Get-MIRSafeScenarioFileName -Name $ScenarioName;$label="$safe.reload-{0:D2}"-f$Ordinal
  $stdout=Join-Path $userData "$label.stdout.log";$stderr=Join-Path $userData "$label.stderr.log";$factorioLog=Join-Path $userData "$label.factorio.log";$currentLog=Join-Path $userData 'factorio-current.log'
  if(Test-Path -LiteralPath $currentLog){Remove-Item -LiteralPath $currentLog -Force}
  $config=Join-Path $userData 'mir-compat-config.ini';$binary=(Resolve-Path -LiteralPath $FactorioBin).Path
  $mods=if($null -ne $LibraryActivation){$LibraryActivation.library}else{Join-Path $userData 'mods'}
  $arguments=@('--config',$config,'--no-log-rotation','--disable-audio','--mod-directory',$mods,'--benchmark',$save,'--benchmark-ticks','1','--benchmark-runs','1','--benchmark-sanitize')
  $activationArgs=@{};if($null -ne $LibraryActivation){$activationArgs.LibraryActivation=$LibraryActivation}
  $process=Invoke-MIRCompatFactorioProcess -FactorioBin $binary -ArgumentList $arguments -StdoutPath $stdout -StderrPath $stderr -TimeoutSeconds $MaximumDurationSeconds @activationArgs
  $captured=Copy-MIRCompatFactorioCurrentLog -UserDataDir $userData -Destination $factorioLog;$saveHash=Get-MIRCompatFileSha256 $save;$identical=-not[string]::IsNullOrWhiteSpace($inputHash)-and$saveHash-ceq$inputHash
  if($null -ne $LibraryActivation -and $process.passed){$null=Assert-MIRLibraryLoadedSelection -Activation $LibraryActivation -LogPath $captured}
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
    [string[]]$RequiredLogFragments = @(),
    $LibraryActivation=$null
  )

  $reloads = @()
  foreach ($ordinal in 1..$RequiredReloadCount) {
    $reload = Invoke-MIRFactorioBenchmarkReload `
      -FactorioBin $FactorioBin `
      -UserDataDir $UserDataDir `
      -ScenarioName $ScenarioName `
      -SavePath $SavePath `
      -Ordinal $ordinal `
      -MaximumDurationSeconds $MaxReloadDurationSeconds -LibraryActivation $LibraryActivation
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
