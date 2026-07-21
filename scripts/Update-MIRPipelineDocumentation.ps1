param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")),
  [switch]$Check
)

$ErrorActionPreference = "Stop"

$commandsPath = Join-Path $RepoRoot "prototypes\mir\pipeline\commands.lua"
$readmePath = Join-Path $RepoRoot "README.md"
$commandsText = Get-Content -Raw -LiteralPath $commandsPath
$readmeText = Get-Content -Raw -LiteralPath $readmePath

$commandPattern = '(?ms)^  \["(?<id>[^"]+)"\] = \{\r?\n    kind = "(?<kind>[^"]+)".*?\r?\n    implementation = "(?<implementation>[^"]+)"'
$orderingPattern = '(?m)^  \["(?<id>[^"]+)"\] = \{phase = (?<phase>\d+), dependencies = \{(?<dependencies>[^}]*)\}\}'
$commands = @{}
foreach ($match in [regex]::Matches($commandsText, $commandPattern)) {
  $commands[$match.Groups["id"].Value] = [ordered]@{
    id = $match.Groups["id"].Value
    kind = $match.Groups["kind"].Value
    implementation = $match.Groups["implementation"].Value
    phase = 0
    dependencies = @()
  }
}
foreach ($match in [regex]::Matches($commandsText, $orderingPattern)) {
  $id = $match.Groups["id"].Value
  if (-not $commands.ContainsKey($id)) { throw "Pipeline ordering references undeclared command: $id" }
  $dependencies = @([regex]::Matches($match.Groups["dependencies"].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
  $commands[$id].phase = [int]$match.Groups["phase"].Value
  $commands[$id].dependencies = $dependencies
}
if ($commands.Count -eq 0) { throw "No MIR pipeline commands were parsed from $commandsPath" }
foreach ($command in $commands.Values) {
  if ($command.phase -le 0) { throw "Pipeline command lacks ordering metadata: $($command.id)" }
  foreach ($dependency in $command.dependencies) {
    if (-not $commands.ContainsKey($dependency)) { throw "Pipeline command $($command.id) has unknown dependency $dependency" }
  }
}

$ordered = [System.Collections.Generic.List[object]]::new()
$visiting = @{}
$visited = @{}
function Add-MIRPipelineCommand {
  param([Parameter(Mandatory)][string]$Id)
  if ($visiting[$Id]) { throw "Pipeline dependency cycle at $Id" }
  if ($visited[$Id]) { return }
  $visiting[$Id] = $true
  foreach ($dependency in $commands[$Id].dependencies) { Add-MIRPipelineCommand -Id $dependency }
  $visiting.Remove($Id)
  $visited[$Id] = $true
  $ordered.Add($commands[$Id])
}
foreach ($command in @($commands.Values | Sort-Object phase, id)) { Add-MIRPipelineCommand -Id $command.id }

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('<!-- BEGIN GENERATED MIR PIPELINE -->')
$lines.Add('This table is generated from `prototypes/mir/pipeline/commands.lua`; run `./scripts/Update-MIRPipelineDocumentation.ps1` after changing the command DAG.')
$lines.Add('')
$lines.Add('| Phase | Command | Kind | Implementation | Depends on |')
$lines.Add('| ---: | --- | --- | --- | --- |')
foreach ($command in $ordered) {
  $dependencies = if ($command.dependencies.Count -gt 0) {
    (($command.dependencies | ForEach-Object { '`' + $_ + '`' }) -join ', ')
  } else {
    'none'
  }
  $lines.Add("| $($command.phase) | ``$($command.id)`` | $($command.kind) | ``$($command.implementation)`` | $dependencies |")
}
$lines.Add('<!-- END GENERATED MIR PIPELINE -->')
$generated = $lines -join [Environment]::NewLine
$markerPattern = '(?s)<!-- BEGIN GENERATED MIR PIPELINE -->.*?<!-- END GENERATED MIR PIPELINE -->'
if (-not [regex]::IsMatch($readmeText, $markerPattern)) { throw "README pipeline markers are missing." }
$updated = [regex]::Replace($readmeText, $markerPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $generated }, 1)

if ($Check) {
  if ($updated -cne $readmeText) { throw "README pipeline table is stale; run scripts/Update-MIRPipelineDocumentation.ps1." }
  Write-Host "[ok] README pipeline table matches commands.lua."
  return
}

[System.IO.File]::WriteAllText($readmePath, $updated, [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated $readmePath"
