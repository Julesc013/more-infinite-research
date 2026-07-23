param(
  [string]$RepoRoot = "",
  [switch]$SkipPSScriptAnalyzer
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$failures = @()

function Add-MIRPowerShellQualityFailure {
  param(
    [Parameter(Mandatory)][string]$File,
    [Parameter(Mandatory)][string]$Message
  )
  $script:failures += [pscustomobject]@{
    file = $File
    message = $Message
  }
}

function Get-MIRRelativePath {
  param([Parameter(Mandatory)][string]$Path)
  return [System.IO.Path]::GetRelativePath($RepoRoot, $Path).Replace("\", "/")
}

$scriptRoot = Join-Path $RepoRoot "scripts"
$scriptFiles = @(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.ps1" | Sort-Object FullName)

foreach ($file in $scriptFiles) {
  $relative = Get-MIRRelativePath -Path $file.FullName
  $tokens = $null
  $parseErrors = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)

  foreach ($parseError in @($parseErrors)) {
    Add-MIRPowerShellQualityFailure -File $relative -Message ("parse error line {0}: {1}" -f $parseError.Extent.StartLineNumber, $parseError.Message)
  }

  foreach ($paramBlock in @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.ParamBlockAst] }, $true))) {
    $seen = @{}
    foreach ($parameter in @($paramBlock.Parameters)) {
      $name = [string]$parameter.Name.VariablePath.UserPath
      if ([string]::IsNullOrWhiteSpace($name)) { continue }
      $key = $name.ToLowerInvariant()
      if ($seen.ContainsKey($key)) {
        Add-MIRPowerShellQualityFailure -File $relative -Message ("duplicate parameter '{0}' near line {1}" -f $name, $parameter.Extent.StartLineNumber)
      } else {
        $seen[$key] = $true
      }
    }
  }

  $lineNumber = 0
  foreach ($line in Get-Content -LiteralPath $file.FullName) {
    $lineNumber++
    if ($line -match '\bWrite-(Host|Information|Output|Verbose|Warning|Error)\b' -and
        $line -match '(FACTORIO_TOKEN|service-token|ModPortalToken|ModPortalPassword)') {
      Add-MIRPowerShellQualityFailure -File $relative -Message ("possible secret output near line {0}" -f $lineNumber)
    }
  }
}

$retentionHarnessPath = Join-Path $scriptRoot "Test-MIRCandidateRetention.ps1"
if (-not (Test-Path -LiteralPath $retentionHarnessPath)) {
  Add-MIRPowerShellQualityFailure -File "scripts/Test-MIRCandidateRetention.ps1" -Message "missing portable retention harness"
} else {
  $retentionHarnessText = Get-Content -Raw -LiteralPath $retentionHarnessPath
  foreach ($requiredToken in @("Diagnostics.ProcessStartInfo", "WaitForExit", "Kill(`$true)")) {
    if (-not $retentionHarnessText.Contains($requiredToken)) {
      Add-MIRPowerShellQualityFailure -File "scripts/Test-MIRCandidateRetention.ps1" -Message "retention process lifecycle is missing $requiredToken"
    }
  }
  if ($retentionHarnessText -match '(?m)^\s*&\s+\$FactorioBin\s+@') {
    Add-MIRPowerShellQualityFailure -File "scripts/Test-MIRCandidateRetention.ps1" -Message "retention harness must wait on an owned process instead of invoking Factorio as a detached GUI application"
  }
  if ($retentionHarnessText -notmatch '\$profile\.factorio\.line\s+-eq\s+"0\.17"') {
    Add-MIRPowerShellQualityFailure -File "scripts/Test-MIRCandidateRetention.ps1" -Message "benchmark-runs must be capability-gated to Factorio 0.17"
  }
  if ($retentionHarnessText.Contains("(?im)^.*Error ")) {
    Add-MIRPowerShellQualityFailure -File "scripts/Test-MIRCandidateRetention.ps1" -Message "retention verdict must distinguish recoverable engine fallbacks from fatal mod-load errors"
  }
  if (-not $retentionHarnessText.Contains('factorio-current.log')) {
    Add-MIRPowerShellQualityFailure -File "scripts/Test-MIRCandidateRetention.ps1" -Message "retention proof must consume the authoritative Factorio log when console output is absent"
  }
  if ($retentionHarnessText -notmatch '\$profile\.factorio\.line\s+-notin\s+@\("0\.13",\s*"0\.14"\)') {
    Add-MIRPowerShellQualityFailure -File "scripts/Test-MIRCandidateRetention.ps1" -Message "disable-audio must be omitted for Factorio 0.13 and 0.14"
  }
  if (-not $retentionHarnessText.Contains('$requiresGoodbye')) {
    Add-MIRPowerShellQualityFailure -File "scripts/Test-MIRCandidateRetention.ps1" -Message "loaded-map proof must account for finite archive lines that predate the Goodbye marker"
  }
  if (-not $retentionHarnessText.Contains('$benchmarkMap') -or $retentionHarnessText -notmatch '\$profile\.factorio\.line\s+-eq\s+"0\.13"') {
    Add-MIRPowerShellQualityFailure -File "scripts/Test-MIRCandidateRetention.ps1" -Message "Factorio 0.13 benchmark reload must stage and address the save by basename"
  }
}

$gitignorePath = Join-Path $RepoRoot ".gitignore"
if (-not (Test-Path -LiteralPath $gitignorePath)) {
  Add-MIRPowerShellQualityFailure -File ".gitignore" -Message "missing .gitignore"
} else {
  $gitignoreText = Get-Content -Raw -LiteralPath $gitignorePath
  foreach ($requiredPattern in @("/build/", "/tmp/", "/artifacts/")) {
    if (-not $gitignoreText.Contains($requiredPattern)) {
      Add-MIRPowerShellQualityFailure -File ".gitignore" -Message "missing ignored generated-output path: $requiredPattern"
    }
  }
}

if (-not $SkipPSScriptAnalyzer -and (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
  $analyzerResults = @(Invoke-ScriptAnalyzer -Path $scriptRoot -Recurse)
  if ($analyzerResults.Count -gt 0) {
    Write-Warning ("PSScriptAnalyzer reported {0} finding(s); inspect locally if desired." -f $analyzerResults.Count)
  }
}

& (Join-Path $scriptRoot "Test-MIRArtifactCleanup.ps1") -RepoRoot $RepoRoot

if ($failures.Count -gt 0) {
  $failures | Format-Table -AutoSize | Out-String | Write-Host
  throw "PowerShell quality checks failed with $($failures.Count) issue(s)."
}

Write-Host "[ok] validated $($scriptFiles.Count) PowerShell scripts for parse errors, duplicate parameters, and obvious secret output."
