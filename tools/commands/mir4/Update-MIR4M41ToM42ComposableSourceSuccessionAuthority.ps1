[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$RecordedAt = '2026-09-15T12:00:00+10:00',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/ComposableSourceSuccession.ps1')

$policy = Get-MIR4M41ToM42SourceSuccessionPolicy
$relative = $policy.output_path
$path = Join-Path $RepoRoot $relative
$schema = Join-Path $RepoRoot $policy.output_schema
$record = New-MIR4M41ToM42ComposableSourceSuccession -RepoRoot $RepoRoot -RecordedAt $RecordedAt
$json = (ConvertTo-MIR4BootstrapCanonicalJson -Value $record) + "`n"
if (-not ($json | Test-Json -SchemaFile $schema)) { throw '[mir4-m41-m42-succession-writer-schema]' }
if ($Check) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
      [IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n") -cne $json) {
    throw '[mir4-m41-m42-succession-writer-stale]'
  }
} else {
  [IO.File]::WriteAllText($path, $json, [Text.UTF8Encoding]::new($false))
}
return [pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$relative;record_sha256=[string]$record.record_sha256;release_authority=$false}
