param(
  [Parameter(Mandatory)][string[]]$AuditLogPaths,
  [Parameter(Mandatory)][string]$TargetProfile,
  [string]$SourceCommit = "",
  [string]$ArchiveSha256 = "",
  [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "MIRCompatAudit\DiagnosticsParser.ps1")

function Get-MIRPlannerRowKey {
  param($Row)
  return (@("kind", "key", "subject", "recipe", "capability", "rule", "target_stream", "decision") | ForEach-Object {
    [string]$Row.PSObject.Properties[$_].Value
  }) -join "|"
}

function Get-MIRSha256 {
  param([string]$Text)
  $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
  $hash = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return ([BitConverter]::ToString($hash)).Replace("-", "")
}

$rows = @()
foreach ($path in $AuditLogPaths) {
  $resolved = (Resolve-Path -LiteralPath $path).Path
  $rows += @(Read-MIRAuditLog -Path $resolved)
}
$rows = @($rows | Sort-Object @{Expression = { Get-MIRPlannerRowKey $_ }})
$planRows = @($rows | Where-Object { $_.kind -in @("stream", "decision") })
$coverageRows = @($rows | Where-Object {
  $_.kind -in @("coverage", "recipe_coverage", "decision", "loop_risk", "recipe_owner") -or
  -not [string]::IsNullOrWhiteSpace([string]$_.category)
})

$identity = [ordered]@{
  schema = 1
  kind = "mir-planner-snapshot"
  target_profile = $TargetProfile
  source_commit = $SourceCommit
  archive_sha256 = $ArchiveSha256.ToUpperInvariant()
  plan_rows = $planRows
  coverage_rows = $coverageRows
}
$canonical = $identity | ConvertTo-Json -Depth 30 -Compress
$artifact = [ordered]@{}
foreach ($property in $identity.GetEnumerator()) { $artifact[$property.Key] = $property.Value }
$artifact["fingerprint_sha256"] = Get-MIRSha256 -Text $canonical
$artifact["all_rows"] = $rows

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
$artifact | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "[ok] wrote MIR planner snapshot $OutputPath rows=$($rows.Count) fingerprint=$($artifact.fingerprint_sha256)"
