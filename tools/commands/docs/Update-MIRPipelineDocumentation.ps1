param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")),
  [switch]$Check
)

$ErrorActionPreference = "Stop"

$commandsPath = Join-Path $RepoRoot "src\mod\families\modern\prototypes\mir\pipeline\commands.lua"
$documentPath = Join-Path $RepoRoot "docs\reference\generated\runtime-pipeline.md"
$commandsText = Get-Content -Raw -LiteralPath $commandsPath

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
$lines.Add('---')
$lines.Add('title: "Generated Runtime Pipeline"')
$lines.Add('status: current')
$lines.Add('applies_to: "4.0.0+"')
$lines.Add('audience: maintainer')
$lines.Add('doc_type: reference')
$lines.Add('owner: mir-maintainers')
$lines.Add('last_reviewed: 2026-09-02')
$lines.Add('supersedes: []')
$lines.Add('superseded_by: []')
$lines.Add('---')
$lines.Add('')
$lines.Add('# Generated Runtime Pipeline')
$lines.Add('')
$lines.Add('<!-- BEGIN GENERATED MIR PIPELINE -->')
$lines.Add('This package-excluded reference is generated from `src/mod/families/modern/prototypes/mir/pipeline/commands.lua`; run `./scripts/Update-MIRPipelineDocumentation.ps1` after changing the command DAG.')
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
$generated = ($lines -join "`n") + "`n"

$readmePath = Join-Path $RepoRoot 'README.md'
$readmeText = [IO.File]::ReadAllText($readmePath).Replace("`r`n", "`n")
$projectionPattern = '(?s)<!-- BEGIN GENERATED MIR PIPELINE -->.*?<!-- END GENERATED MIR PIPELINE -->'
$projection = [regex]::Match($generated, $projectionPattern).Value
if ([regex]::Matches($readmeText, $projectionPattern).Count -ne 1 -or -not $projection) { throw 'README must retain exactly one generated PIPELINE reference.' }
$projectedReadme = [regex]::Replace($readmeText, $projectionPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $projection })
if ($Check) {
  if ($readmeText -cne $projectedReadme) { throw 'README PIPELINE reference is stale; run its documentation writer.' }
} else {
  [IO.File]::WriteAllText($readmePath, $projectedReadme, [Text.UTF8Encoding]::new($false))
}
if ($Check) {
  if (-not (Test-Path -LiteralPath $documentPath -PathType Leaf)) { throw "Generated runtime pipeline is missing; run tools/commands/docs/Update-MIRPipelineDocumentation.ps1." }
  $current = [IO.File]::ReadAllText($documentPath).Replace("`r`n", "`n")
  if ($current -cne $generated) { throw "Generated runtime pipeline is stale; run tools/commands/docs/Update-MIRPipelineDocumentation.ps1." }
  Write-Host "[ok] generated runtime pipeline matches commands.lua."
  return
}

[System.IO.File]::WriteAllText($documentPath, $generated, [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated $documentPath"
