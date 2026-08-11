param(
  [Parameter(Mandatory)][string]$ArchivePath,
  [Parameter(Mandatory)][ValidateSet("2.1", "2.0")][string]$TargetLine,
  [Parameter(Mandatory)][string]$ExpectedPortalSha1,
  [Parameter(Mandatory)][string]$ObservedAt,
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

function Assert-MIRHexDigest {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Value,
    [Parameter(Mandatory)][int]$Length
  )

  if ($Value -notmatch "^[A-Fa-f0-9]{$Length}$") {
    throw "$Name must be a $Length-character hexadecimal digest."
  }
}

function Read-MIRZipEntryText {
  param([Parameter(Mandatory)]$Entry)

  $stream = $Entry.Open()
  $buffer = [IO.MemoryStream]::new()
  try {
    $stream.CopyTo($buffer)
  } finally {
    $stream.Dispose()
  }
  $bytes = $buffer.ToArray()
  $buffer.Dispose()

  try {
    return [pscustomobject]@{
      text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
      encoding = "utf-8"
    }
  } catch [Text.DecoderFallbackException] {
    return [pscustomobject]@{
      text = [Text.Encoding]::GetEncoding(1252).GetString($bytes)
      encoding = "windows-1252-fallback"
    }
  }
}

function Get-MIRSurfaceObservation {
  param(
    [Parameter(Mandatory)][object[]]$Sources,
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][string[]]$Patterns
  )

  $files = [Collections.Generic.List[string]]::new()
  $matches = 0
  foreach ($source in $Sources) {
    $fileMatched = $false
    foreach ($pattern in $Patterns) {
      $regex = [regex]::new($pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
      $count = $regex.Matches([string]$source.text).Count
      if ($count -gt 0) {
        $matches += $count
        $fileMatched = $true
      }
    }
    if ($fileMatched) { $files.Add([string]$source.path) }
  }

  return [ordered]@{
    id = $Id
    observed = ($matches -gt 0)
    match_count = $matches
    files = @($files | Sort-Object -Unique)
  }
}

$resolvedArchive = (Resolve-Path -LiteralPath $ArchivePath).Path
if ([IO.Path]::GetExtension($resolvedArchive) -ne ".zip") { throw "ArchivePath must identify a zip archive." }
Assert-MIRHexDigest -Name "ExpectedPortalSha1" -Value $ExpectedPortalSha1 -Length 40

$parsedObservedAt = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse(
    $ObservedAt,
    [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::RoundtripKind,
    [ref]$parsedObservedAt
  ) -or $ObservedAt -notmatch '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$') {
  throw "ObservedAt must be an RFC 3339 timestamp."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($resolvedArchive)
try {
  $entries = @($zip.Entries | Sort-Object FullName)
  $luaSources = [Collections.Generic.List[object]]::new()
  $infoEntries = @($entries | Where-Object { $_.FullName -match '(^|/)info\.json$' })
  if ($infoEntries.Count -ne 1) { throw "Archive must contain exactly one info.json file." }
  $infoSource = Read-MIRZipEntryText -Entry $infoEntries[0]
  $info = $infoSource.text | ConvertFrom-Json -Depth 100

  foreach ($entry in @($entries | Where-Object { $_.FullName -match '\.lua$' })) {
    $luaSource = Read-MIRZipEntryText -Entry $entry
    $luaSources.Add([pscustomobject]@{
      path = [string]$entry.FullName
      text = [string]$luaSource.text
      encoding = [string]$luaSource.encoding
    })
  }

  $stageFiles = foreach ($source in $luaSources) {
    $leaf = [IO.Path]::GetFileName([string]$source.path)
    $stage = switch -Regex ($leaf) {
      '^settings\.lua$' { "settings"; break }
      '^settings-updates\.lua$' { "settings-updates"; break }
      '^settings-final-fixes\.lua$' { "settings-final-fixes"; break }
      '^data\.lua$' { "data"; break }
      '^data-updates\.lua$' { "data-updates"; break }
      '^data-final-fixes\.lua$' { "data-final-fixes"; break }
      '^control\.lua$' { "control"; break }
      default {
        if ([string]$source.path -match '(^|/)migrations/') { "migration" } else { "module" }
      }
    }
    [ordered]@{ path = [string]$source.path; stage = $stage; encoding = [string]$source.encoding }
  }

  $surfaceDefinitions = @(
    @{ id = "technology-prototype-create-or-replace"; patterns = @('type\s*=\s*["'']technology["'']', 'data\s*:\s*extend\s*\(', 'data\.extend\s*\(') },
    @{ id = "technology-prototype-read-or-mutate"; patterns = @('data\.raw\s*\[?\s*["'']technology["'']', 'data\.raw\.technology') },
    @{ id = "technology-prerequisite-or-science"; patterns = @('\bprerequisites\b', '\bunit\s*=\s*\{', '\bingredients\s*=') },
    @{ id = "technology-effect-productivity"; patterns = @('change-recipe-productivity', 'productivity[_-](bonus|research|technology)', 'productivity\s*=') },
    @{ id = "recipe-prototype-create-or-mutate"; patterns = @('type\s*=\s*["'']recipe["'']', 'data\.raw\s*\[?\s*["'']recipe["'']', 'data\.raw\.recipe') },
    @{ id = "recipe-maximum-productivity"; patterns = @('maximum_productivity') },
    @{ id = "module-permission-or-category"; patterns = @('\blimitation(_blacklist)?\b', '\bmodule_category\b', '\ballowed_effects\b', 'data\.raw\s*\[?\s*["'']module["'']') },
    @{ id = "beacon-prototype"; patterns = @('data\.raw\s*\[?\s*["'']beacon["'']', 'type\s*=\s*["'']beacon["'']') },
    @{ id = "recycler-or-recycling"; patterns = @('\brecycler\b', '\brecycling\b') },
    @{ id = "runtime-research-state"; patterns = @('on_research_(finished|started|cancelled)', 'current_research', 'research_progress', 'force\.technologies') },
    @{ id = "runtime-productivity-bonus"; patterns = @('productivity_bonus', 'change-recipe-productivity') },
    @{ id = "runtime-configuration-change-or-reset"; patterns = @('on_configuration_changed', 'reset_technology_effects', 'reset_technologies') },
    @{ id = "runtime-interface-or-command"; patterns = @('remote\.add_interface', 'commands\.add_command') },
    @{ id = "startup-setting-definition-or-read"; patterns = @('setting_type\s*=\s*["'']startup["'']', 'settings\.startup') },
    @{ id = "runtime-global-setting-definition-or-read"; patterns = @('setting_type\s*=\s*["'']runtime-global["'']', 'settings\.global') },
    @{ id = "runtime-per-user-setting-definition-or-read"; patterns = @('setting_type\s*=\s*["'']runtime-per-user["'']', 'settings\.get_player_settings') }
  )

  $surfaces = foreach ($definition in $surfaceDefinitions) {
    Get-MIRSurfaceObservation -Sources @($luaSources) -Id ([string]$definition.id) -Patterns @($definition.patterns)
  }

  $archiveSha1 = (Get-FileHash -LiteralPath $resolvedArchive -Algorithm SHA1).Hash.ToLowerInvariant()
  $archiveSha256 = (Get-FileHash -LiteralPath $resolvedArchive -Algorithm SHA256).Hash.ToUpperInvariant()
  $record = [ordered]@{
    schema = 1
    kind = "MIR3ModMutationSurfaceScanV1"
    observed_at = $ObservedAt
    target_line = $TargetLine
    archive = [ordered]@{
      file_name = [IO.Path]::GetFileName($resolvedArchive)
      bytes = (Get-Item -LiteralPath $resolvedArchive).Length
      entries = $entries.Count
      sha1 = $archiveSha1
      sha256 = $archiveSha256
      expected_portal_sha1 = $ExpectedPortalSha1.ToLowerInvariant()
      exact_portal_byte_match = ($archiveSha1 -eq $ExpectedPortalSha1.ToLowerInvariant())
    }
    mod = [ordered]@{
      name = [string]$info.name
      version = [string]$info.version
      factorio_version = [string]$info.factorio_version
      dependencies = @($info.dependencies)
    }
    lua = [ordered]@{
      file_count = $luaSources.Count
      stage_files = @($stageFiles)
      surfaces = @($surfaces)
    }
    interpretation = [ordered]@{
      authority = "static-source-observation-only"
      compatibility_claim = "none"
      runtime_behavior_proven = $false
      owner_precedence_proven = $false
      limitation = "Pattern matches identify review surfaces; they do not establish semantic conflict, compatibility, or runtime ownership."
    }
  }
} finally {
  $zip.Dispose()
}

$json = $record | ConvertTo-Json -Depth 100
if ($OutputPath) {
  $parent = Split-Path -Parent $OutputPath
  if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  [IO.File]::WriteAllText($OutputPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
$json
