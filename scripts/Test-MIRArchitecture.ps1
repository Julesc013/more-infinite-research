param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

function Get-MIRPath {
  param([Parameter(Mandatory)][string]$RelativePath)
  return Join-Path $repo $RelativePath
}

function Read-MIRFile {
  param([Parameter(Mandatory)][string]$RelativePath)
  $path = Get-MIRPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing required architecture file: $RelativePath"
  }
  return Get-Content -Raw -LiteralPath $path
}

function Get-MIRCodeLines {
  param([Parameter(Mandatory)][string]$Text)
  return @(
    $Text -split "\r?\n" |
      ForEach-Object { $_.Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith("--") }
  )
}

function Assert-MIRContains {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )

  if (-not $Text.Contains($Needle)) {
    throw "$RelativePath is missing required architecture snippet: $Needle"
  }
}

function Assert-MIRNoPatternInLuaTree {
  param(
    [Parameter(Mandatory)][string]$RelativeRoot,
    [Parameter(Mandatory)][string]$Pattern,
    [Parameter(Mandatory)][string]$Message
  )

  $root = Get-MIRPath -RelativePath $RelativeRoot
  if (-not (Test-Path -LiteralPath $root)) { return }

  $matches = @(
    Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.lua" |
      Select-String -Pattern $Pattern
  )
  if ($matches.Count -gt 0) {
    $matches | Write-Host
    throw $Message
  }
}

function Assert-MIRNoPatternInLuaFile {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Pattern,
    [Parameter(Mandatory)][string]$Message
  )

  $path = Get-MIRPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path)) { return }

  $matches = @(Select-String -LiteralPath $path -Pattern $Pattern)
  if ($matches.Count -gt 0) {
    $matches | Write-Host
    throw $Message
  }
}

$entrypoints = @(
  @{
    Root = "settings.lua"
    StageModule = "prototypes.mir.stage.settings"
    StagePath = "prototypes/mir/stage/settings.lua"
    LegacyModule = "prototypes.mir.legacy.settings"
  },
  @{
    Root = "data.lua"
    StageModule = "prototypes.mir.stage.data"
    StagePath = "prototypes/mir/stage/data.lua"
    LegacyModule = "prototypes.mir.legacy.data"
  },
  @{
    Root = "data-updates.lua"
    StageModule = "prototypes.mir.stage.data_updates"
    StagePath = "prototypes/mir/stage/data_updates.lua"
    LegacyModule = "prototypes.mir.legacy.data_updates"
  },
  @{
    Root = "data-final-fixes.lua"
    StageModule = "prototypes.mir.stage.data_final_fixes"
    StagePath = "prototypes/mir/stage/data_final_fixes.lua"
    LegacyModule = "prototypes.mir.legacy.data_final_fixes"
  },
  @{
    Root = "control.lua"
    StageModule = "prototypes.mir.stage.control"
    StagePath = "prototypes/mir/stage/control.lua"
    LegacyModule = "prototypes.mir.legacy.control"
  }
)

foreach ($entry in $entrypoints) {
  $rootText = Read-MIRFile -RelativePath $entry.Root
  $rootCodeLines = @(Get-MIRCodeLines -Text $rootText)
  if ($rootCodeLines.Count -ne 1) {
    throw "$($entry.Root) must be a thin one-line stage wrapper."
  }

  $expectedRoot = 'require("' + $entry.StageModule + '").run()'
  if ($rootCodeLines[0] -ne $expectedRoot) {
    throw "$($entry.Root) must call $expectedRoot."
  }

  $stageText = Read-MIRFile -RelativePath $entry.StagePath
  Assert-MIRContains -RelativePath $entry.StagePath -Text $stageText -Needle "function M.run()"
  Assert-MIRContains -RelativePath $entry.StagePath -Text $stageText -Needle ('require("' + $entry.LegacyModule + '")')
}

$requiredShims = @(
  "prototypes/mir/core/schema.lua",
  "prototypes/mir/domain/facts/registry.lua",
  "prototypes/mir/capabilities/contract.lua",
  "prototypes/mir/capabilities/registry.lua",
  "prototypes/mir/planner/compiler.lua",
  "prototypes/mir/compatibility/registry.lua",
  "prototypes/mir/compatibility/overlay_loader.lua",
  "prototypes/mir/compatibility/claim_registry.lua",
  "prototypes/mir/compatibility/overlays/air_scrubbing.lua",
  "prototypes/mir/legacy/tech_gen.lua",
  "prototypes/mir/legacy/recipe_matching.lua",
  "prototypes/mir/legacy/compat_profiles.lua",
  "prototypes/mir/legacy/diagnostics.lua",
  "prototypes/mir/legacy/stream_specs.lua"
)

foreach ($relative in $requiredShims) {
  $null = Read-MIRFile -RelativePath $relative
}

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/domain" `
  -Pattern "\b(data\.raw|data:extend|mods|settings)\b" `
  -Message "MIR domain modules must not read Factorio globals or mutate prototypes."

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/capabilities" `
  -Pattern "data:extend" `
  -Message "MIR capability modules must not emit prototypes directly."

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/compatibility/overlays" `
  -Pattern "\bdata\.raw\b|data:extend" `
  -Message "MIR compatibility overlays must stay declarative."

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "prototypes/mir/report" `
  -Pattern "\bdata\.raw\b|data:extend" `
  -Message "MIR report modules must not mutate prototypes."

$runtimePrototypePattern = "\bdata\.raw\b|data:extend"
foreach ($relative in @(
  "control.lua",
  "prototypes/mir/stage/control.lua",
  "prototypes/mir/legacy/control.lua"
)) {
  Assert-MIRNoPatternInLuaFile `
    -RelativePath $relative `
    -Pattern $runtimePrototypePattern `
    -Message "MIR runtime control entrypoints must not perform prototype-stage work."
}

Assert-MIRNoPatternInLuaTree `
  -RelativeRoot "control" `
  -Pattern $runtimePrototypePattern `
  -Message "MIR runtime control modules must not perform prototype-stage work."

Write-Host "[ok] MIR architecture boundary lint passed."
