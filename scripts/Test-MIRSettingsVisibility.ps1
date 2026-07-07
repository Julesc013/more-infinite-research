param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

function Read-MIRText {
  param([Parameter(Mandatory)][string]$RelativePath)
  $path = Join-Path $repo $RelativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing required settings visibility file: $RelativePath"
  }
  return Get-Content -Raw -LiteralPath $path
}

function Assert-Contains {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Needle
  )
  if (-not $Text.Contains($Needle)) {
    throw "$RelativePath is missing required settings visibility snippet: $Needle"
  }
}

function Assert-NoPattern {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Pattern
  )
  if ($Text -match $Pattern) {
    throw "$RelativePath contains forbidden settings visibility pattern: $Pattern"
  }
}

function Assert-NoPatternInTree {
  param(
    [Parameter(Mandatory)][string]$RelativeRoot,
    [Parameter(Mandatory)][string]$Pattern,
    [Parameter(Mandatory)][string]$Message
  )

  $root = Join-Path $repo $RelativeRoot
  if (-not (Test-Path -LiteralPath $root)) { return }

  $matches = @(
    Get-ChildItem -LiteralPath $root -Recurse -File |
      Where-Object { $_.Extension -in @(".lua", ".yml", ".md", ".ps1") } |
      Select-String -Pattern $Pattern
  )

  if ($matches.Count -gt 0) {
    $matches | Write-Host
    throw $Message
  }
}

$settingsManifestText = Read-MIRText -RelativePath ".mir/settings.yml"
$legacySettingsText = Read-MIRText -RelativePath "prototypes/mir/legacy/settings.lua"
$registryText = Read-MIRText -RelativePath "prototypes/mir/settings/registry.lua"
$visibilityText = Read-MIRText -RelativePath "prototypes/mir/settings/visibility.lua"
$builderText = Read-MIRText -RelativePath "prototypes/mir/settings/builder.lua"
$adapterText = Read-MIRText -RelativePath "prototypes/mir/settings/legacy_adapter.lua"
$productivityText = Read-MIRText -RelativePath "prototypes/streams/productivity.lua"
$directEffectsText = Read-MIRText -RelativePath "prototypes/streams/direct-effects.lua"
$fixtureText = Read-MIRText -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua"
$fixtureInfoText = Read-MIRText -RelativePath "fixtures/assert-hidden-setting-readability/info.json"

Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "schema: 1"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "hidden_means_unavailable_not_deleted: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "do_not_force_hidden_values_by_default: true"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "research_air_scrubbing_clean_filter:"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "research_tungsten:"
Assert-Contains -RelativePath ".mir/settings.yml" -Text $settingsManifestText -Needle "research_belts:"

Assert-Contains -RelativePath "prototypes/mir/settings/registry.lua" -Text $registryText -Needle "setting_ids_are_stable = true"
Assert-Contains -RelativePath "prototypes/mir/settings/registry.lua" -Text $registryText -Needle 'enable = "ips-enable-%s"'
Assert-Contains -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Needle "function M.evaluate(spec, ctx)"
Assert-Contains -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Needle 'mode == "visible-if-mods-any"'
Assert-Contains -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Needle 'mode == "visible-if-mods-all"'
Assert-Contains -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Needle 'mode == "visible-if-mods-any-or-always-on-base"'
Assert-Contains -RelativePath "prototypes/mir/settings/builder.lua" -Text $builderText -Needle "setting.hidden = true"
Assert-Contains -RelativePath "prototypes/mir/settings/legacy_adapter.lua" -Text $adapterText -Needle "factorio_mods.snapshot()"
Assert-Contains -RelativePath "prototypes/mir/legacy/settings.lua" -Text $legacySettingsText -Needle 'local settings_adapter = require("prototypes.mir.settings.legacy_adapter")'
Assert-Contains -RelativePath "prototypes/mir/legacy/settings.lua" -Text $legacySettingsText -Needle "settings_adapter.visibility_for_stream(stream, settings_context)"
Assert-Contains -RelativePath "prototypes/mir/legacy/settings.lua" -Text $legacySettingsText -Needle "settings_adapter.apply(setting, group and group.ui_visibility)"

Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle "ui_visibility = {"
Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle 'mods_any = air_scrubbing_overlay.applies_when.mods'
Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle 'mods_any = atan_ash_overlay.applies_when.mods'
Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle 'mods_any = {"space-age"}'
Assert-Contains -RelativePath "prototypes/streams/productivity.lua" -Text $productivityText -Needle "generation_requirements = {"
Assert-Contains -RelativePath "prototypes/streams/direct-effects.lua" -Text $directEffectsText -Needle "ui_visibility = {"
Assert-Contains -RelativePath "prototypes/streams/direct-effects.lua" -Text $directEffectsText -Needle "generation_requirements = {"

Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/info.json" -Text $fixtureInfoText -Needle '"name": "mir-fixture-assert-hidden-setting-readability"'
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle "assert_startup_setting_readable"
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"ips-enable-research_tungsten"'
Assert-Contains -RelativePath "fixtures/assert-hidden-setting-readability/data-final-fixes.lua" -Text $fixtureText -Needle '"ips-enable-research_air_scrubbing_clean_filter"'

Assert-NoPattern -RelativePath "prototypes/mir/settings/visibility.lua" -Text $visibilityText -Pattern "\bdata\.raw\b|data:extend|settings\.startup"
Assert-NoPattern -RelativePath "prototypes/mir/settings/builder.lua" -Text $builderText -Pattern "forced_value"
Assert-NoPattern -RelativePath "prototypes/mir/legacy/settings.lua" -Text $legacySettingsText -Pattern "forced_value"

Assert-NoPatternInTree `
  -RelativeRoot "prototypes" `
  -Pattern "settings_required_mods" `
  -Message "Stream setting visibility must use ui_visibility, not settings_required_mods."

Write-Host "[ok] MIR settings visibility lint passed."
