$script:MIRColorMode = "Auto"
$script:MIRQuiet = $false

function Set-MIRConsoleOptions {
  param(
    [ValidateSet("Auto", "Always", "Never")]
    [string]$ColorMode = "Auto",
    [switch]$NoColor,
    [switch]$Quiet,
    [switch]$CI
  )

  if ($NoColor -or $CI) {
    $script:MIRColorMode = "Never"
  } else {
    $script:MIRColorMode = $ColorMode
  }
  $script:MIRQuiet = [bool]$Quiet
}

function Test-MIRConsoleColor {
  if ($script:MIRColorMode -eq "Always") { return $true }
  if ($script:MIRColorMode -eq "Never") { return $false }
  return -not [Console]::IsOutputRedirected
}

function Get-MIRConsoleColor {
  param([Parameter(Mandatory)][string]$Token)

  switch ($Token) {
    "RUN" { return "Cyan" }
    "STEP" { return "Cyan" }
    "SCEN" { return "Blue" }
    "PASS" { return "Green" }
    "SKIP" { return "Yellow" }
    "WARN" { return "Yellow" }
    "FAIL" { return "Red" }
    "TIME" { return "Magenta" }
    default { return "White" }
  }
}

function Write-MIRConsole {
  param(
    [Parameter(Mandatory)][string]$Token,
    [Parameter(Mandatory)][string]$Message
  )

  if ($script:MIRQuiet) { return }

  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
  $line = "[{0}] [{1,-5}] {2}" -f $timestamp, $Token, $Message
  if (Test-MIRConsoleColor) {
    Write-Host $line -ForegroundColor (Get-MIRConsoleColor -Token $Token)
  } else {
    Write-Host $line
  }
}

function Write-MIRSection { param([string]$Message) Write-MIRConsole -Token "RUN" -Message $Message }
function Write-MIRStep { param([string]$Message) Write-MIRConsole -Token "STEP" -Message $Message }
function Write-MIRInfo { param([string]$Message) Write-MIRConsole -Token "INFO" -Message $Message }
function Write-MIRSuccess { param([string]$Message) Write-MIRConsole -Token "PASS" -Message $Message }
function Write-MIRWarning { param([string]$Message) Write-MIRConsole -Token "WARN" -Message $Message }
function Write-MIRError { param([string]$Message) Write-MIRConsole -Token "FAIL" -Message $Message }
function Write-MIRSkip { param([string]$Message) Write-MIRConsole -Token "SKIP" -Message $Message }
function Write-MIRTimeout { param([string]$Message) Write-MIRConsole -Token "TIME" -Message $Message }

function Write-MIRScenarioStart {
  param(
    [int]$Index,
    [int]$Total,
    [string]$Name,
    [string[]]$Roots = @()
  )
  $rootText = if ($Roots.Count -gt 0) { " roots=$($Roots -join ',')" } else { "" }
  Write-MIRConsole -Token "SCEN" -Message ("{0:D3}/{1:D3} {2}{3}" -f $Index, $Total, $Name, $rootText)
}

function Write-MIRScenarioResult {
  param(
    [int]$Index,
    [int]$Total,
    [string]$Name,
    [string]$Status,
    [double]$Seconds = 0,
    [int]$AuditRows = 0
  )

  $token = switch ($Status) {
    "passed" { "PASS" }
    "skipped" { "SKIP" }
    "timed_out" { "TIME" }
    default { "FAIL" }
  }
  Write-MIRConsole -Token $token -Message ("{0:D3}/{1:D3} {2} status={3} audit_rows={4} seconds={5}" -f $Index, $Total, $Name, $Status, $AuditRows, $Seconds)
}

function Write-MIRKeyValue {
  param([string]$Key, [string]$Value)
  Write-MIRConsole -Token "INFO" -Message ("{0}={1}" -f $Key, $Value)
}
