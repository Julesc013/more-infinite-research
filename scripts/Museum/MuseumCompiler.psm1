Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-MIRMuseumCatalog {
  param([Parameter(Mandatory)][string]$Path)

  $catalogPath = (Resolve-Path -LiteralPath $Path).Path
  $repoRoot = Split-Path -Parent (Split-Path -Parent $catalogPath)
  $catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
  if ([int]$catalog.schema -ne 1) { throw "Unsupported museum catalog schema '$($catalog.schema)'." }
  if ([string]::IsNullOrWhiteSpace([string]$catalog.canonical_feature_model)) { throw "Museum catalog does not name the canonical feature model." }
  $modelPath = if ([IO.Path]::IsPathRooted([string]$catalog.canonical_feature_model)) {
    [string]$catalog.canonical_feature_model
  } else {
    Join-Path $repoRoot ([string]$catalog.canonical_feature_model).Replace('/', '\')
  }
  $model = Get-Content -Raw -LiteralPath $modelPath | ConvertFrom-Json
  if ([int]$model.schema -ne 1 -or [string]$model.kind -ne "mir-canonical-lower-feature-model") { throw "Unsupported canonical lower-feature model." }
  $catalog | Add-Member -NotePropertyName canonical_model -NotePropertyValue $model -Force

  foreach ($target in @($catalog.targets)) {
    $projectionName = [string]$target.feature_projection
    $projection = $model.projections.PSObject.Properties[$projectionName]
    if ($null -eq $projection) { throw "Unknown canonical feature projection '$projectionName' for Factorio $($target.factorio)." }
    $families = @()
    foreach ($featureId in @($projection.Value)) {
      $feature = $model.features.PSObject.Properties[[string]$featureId]
      if ($null -eq $feature) { throw "Projection '$projectionName' names unknown canonical feature '$featureId'." }
      $spec = $feature.Value
      $families += [pscustomobject][ordered]@{
        canonical_feature_id = [string]$featureId
        stream_id = [string]$spec.stream_id
        id = [string]$featureId
        label = [string]$spec.label
        levels = [int]$spec.maximum_level
        base_count = [int]$spec.cost_model.base_count
        count_step = [int]$spec.cost_model.count_step
        time = [int]$spec.research_time
        icon = [string]$spec.finite_reconstruction.icon
        prerequisite = [string]$spec.finite_reconstruction.prerequisite
        evidence_file = [string]$spec.finite_reconstruction.evidence_file
        effect = ($spec.per_level_effect | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
      }
    }
    $target | Add-Member -NotePropertyName families -NotePropertyValue $families -Force
  }

  return $catalog
}

function Get-MIRMuseumTarget {
  param(
    [Parameter(Mandatory)]$Catalog,
    [Parameter(Mandatory)][string]$FactorioVersion
  )

  $matches = @($Catalog.targets | Where-Object { [string]$_.factorio -eq $FactorioVersion })
  if ($matches.Count -ne 1) { throw "Expected one museum target '$FactorioVersion'; found $($matches.Count)." }
  return $matches[0]
}

function Get-MIRSha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Set-MIRUtf8Text {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Text
  )

  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
  [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-MIRLuaString {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
  return '"' + $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n') + '"'
}

function ConvertTo-MIRLuaNumber {
  param([Parameter(Mandatory)]$Value)
  return ([Convert]::ToDouble($Value, [Globalization.CultureInfo]::InvariantCulture)).ToString("0.################", [Globalization.CultureInfo]::InvariantCulture)
}

function Get-MIRMuseumExpandedRows {
  param([Parameter(Mandatory)]$Target)

  $rows = @()
  foreach ($family in @($Target.families)) {
    for ($level = 1; $level -le [int]$family.levels; $level++) {
      $id = "mir-$($family.id)-$level"
      $prerequisite = if ($level -eq 1) { [string]$family.prerequisite } else { "mir-$($family.id)-$($level - 1)" }
      $rows += [pscustomobject][ordered]@{
        id = $id
        family = [string]$family.id
        label = [string]$family.label
        level = $level
        prerequisite = $prerequisite
        count = [int]$family.base_count + (($level - 1) * [int]$family.count_step)
        time = [int]$family.time
        icon = [string]$family.icon
        effect = $family.effect
        science = @($Target.science)
      }
    }
  }
  return $rows
}

function Test-MIRMuseumTarget {
  param(
    [Parameter(Mandatory)]$Catalog,
    [Parameter(Mandatory)]$Target,
    [switch]$RequireExactPatch
  )

  $errors = [System.Collections.Generic.List[string]]::new()
  $warnings = [System.Collections.Generic.List[string]]::new()
  $factorio = [string]$Target.factorio
  $expectedVersion = "$factorio.0"
  if ([string]$Target.version -ne $expectedVersion) { $errors.Add("MIR version must be $expectedVersion for target $factorio.") }
  if ([string]$Target.branch -ne "tmp/$factorio") { $errors.Add("Branch must be tmp/$factorio.") }
  if ([string]$Target.locale_format -ne "cfg-sections") { $errors.Add("Unsupported locale format '$($Target.locale_format)'.") }
  if ([string]$Target.configuration -ne "loaded-config-lua") { $errors.Add("Configuration must be loaded-config-lua.") }

  $binaryPath = ([string]$Target.binary).Replace('/', '\')
  $baseData = ([string]$Target.base_data).Replace('/', '\')
  if (-not (Test-Path -LiteralPath $binaryPath -PathType Leaf)) { $errors.Add("Missing target binary: $binaryPath") }
  $baseExists = Test-Path -LiteralPath $baseData -PathType Container
  if (-not $baseExists) { $errors.Add("Missing target base data: $baseData") }

  if ($baseExists -and (Test-Path -LiteralPath (Join-Path $baseData "info.json"))) {
    $baseInfo = Get-Content -Raw -LiteralPath (Join-Path $baseData "info.json") | ConvertFrom-Json
    if ([string]$baseInfo.version -ne [string]$Target.exact_patch) {
      $message = "Installed base patch $($baseInfo.version) does not match required $($Target.exact_patch)."
      if ($RequireExactPatch) { $errors.Add($message) } else { $warnings.Add($message) }
    }
  }

  $allowedScience = @("science-pack-1", "science-pack-2", "science-pack-3", "alien-science-pack")
  $science = @($Target.science | ForEach-Object { [string]$_ })
  if ($science.Count -ne ($science | Sort-Object -Unique).Count) { $errors.Add("Duplicate science pack in target $factorio.") }
  foreach ($pack in $science) {
    if ($pack -notin $allowedScience) { $errors.Add("Unsupported museum science pack '$pack'.") }
  }

  $familyIds = @($Target.families | ForEach-Object { [string]$_.id })
  if ($familyIds.Count -ne ($familyIds | Sort-Object -Unique).Count) { $errors.Add("Duplicate family ID in target $factorio.") }
  foreach ($family in @($Target.families)) {
    $canonicalId = [string]$family.canonical_feature_id
    $canonical = $Catalog.canonical_model.features.PSObject.Properties[$canonicalId]
    if ($null -eq $canonical) {
      $errors.Add("Unknown canonical feature '$canonicalId' in target $factorio.")
    } else {
      $spec = $canonical.Value
      if ([string]$family.stream_id -ne [string]$spec.stream_id -or
          [string]$family.id -ne $canonicalId -or
          [string]$family.label -ne [string]$spec.label -or
          [int]$family.levels -ne [int]$spec.maximum_level -or
          [int]$family.base_count -ne [int]$spec.cost_model.base_count -or
          [int]$family.count_step -ne [int]$spec.cost_model.count_step -or
          [int]$family.time -ne [int]$spec.research_time -or
          [string]$family.icon -ne [string]$spec.finite_reconstruction.icon -or
          [string]$family.prerequisite -ne [string]$spec.finite_reconstruction.prerequisite -or
          [string]$family.evidence_file -ne [string]$spec.finite_reconstruction.evidence_file -or
          ($family.effect | ConvertTo-Json -Depth 10 -Compress) -ne ($spec.per_level_effect | ConvertTo-Json -Depth 10 -Compress)) {
        $errors.Add("Canonical feature projection drifted for '$canonicalId'.")
      }
    }
    if ([string]$family.id -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { $errors.Add("Invalid family ID '$($family.id)'.") }
    if ([int]$family.levels -lt 1 -or [int]$family.levels -gt 20) { $errors.Add("Family '$($family.id)' must have 1-20 finite levels.") }
    if ([int]$family.base_count -le 0 -or [int]$family.count_step -lt 0) { $errors.Add("Family '$($family.id)' has invalid research counts.") }
    if ([int]$family.time -le 0) { $errors.Add("Family '$($family.id)' has invalid research time.") }
    if ([string]::IsNullOrWhiteSpace([string]$family.prerequisite)) { $errors.Add("Family '$($family.id)' has no prerequisite.") }
    if ([string]$family.effect.type -notin @($Target.allowed_effects | ForEach-Object { [string]$_ })) { $errors.Add("Unsupported effect '$($family.effect.type)' for target $factorio.") }
    if ([double]$family.effect.modifier -le 0) { $errors.Add("Family '$($family.id)' has a nonpositive modifier.") }
    if ([string]$family.effect.type -in @("ammo-damage", "gun-speed") -and [string]::IsNullOrWhiteSpace([string]$family.effect.ammo_category)) { $errors.Add("Family '$($family.id)' requires ammo_category.") }
    if ([string]$family.effect.type -eq "turret-attack" -and [string]::IsNullOrWhiteSpace([string]$family.effect.turret_id)) { $errors.Add("Family '$($family.id)' requires turret_id.") }

    if ($baseExists) {
      $evidencePath = Join-Path $baseData ([string]$family.evidence_file).Replace('/', '\')
      if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
        $errors.Add("Missing evidence file for '$($family.id)': $evidencePath")
      } else {
        $evidence = Get-Content -Raw -LiteralPath $evidencePath
        if ($evidence -notmatch [regex]::Escape('name = "' + [string]$family.prerequisite + '"')) { $errors.Add("Evidence does not contain prerequisite '$($family.prerequisite)'.") }
        if ($evidence -notmatch [regex]::Escape('type = "' + [string]$family.effect.type + '"')) { $errors.Add("Evidence does not contain effect '$($family.effect.type)'.") }
      }

      $iconPath = Join-Path $baseData ("graphics\technology\" + [string]$family.icon)
      if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) { $errors.Add("Missing icon '$($family.icon)' for target $factorio.") }
    }
  }

  $rows = @(Get-MIRMuseumExpandedRows -Target $Target)
  $ids = @($rows | ForEach-Object { $_.id })
  if ($ids.Count -ne ($ids | Sort-Object -Unique).Count) { $errors.Add("Duplicate generated technology ID in target $factorio.") }
  $generated = @{}; foreach ($row in $rows) { $generated[$row.id] = $true }
  foreach ($row in $rows) {
    if ($row.level -gt 1 -and -not $generated.ContainsKey($row.prerequisite)) { $errors.Add("Missing generated prerequisite '$($row.prerequisite)'.") }
    if ($row.prerequisite -eq $row.id) { $errors.Add("Self-cycle at '$($row.id)'.") }
    if ($row.count -le 0 -or $row.time -le 0) { $errors.Add("Nonpositive balance at '$($row.id)'.") }
  }

  return [pscustomobject][ordered]@{
    target = $factorio
    errors = @($errors)
    warnings = @($warnings)
    passed = $errors.Count -eq 0
    generated_count = $rows.Count
  }
}

function ConvertTo-MIRTechnologyLua {
  param([Parameter(Mandatory)]$Row)

  $effectLines = @("        type = $(ConvertTo-MIRLuaString ([string]$Row.effect.type))")
  if ($Row.effect.PSObject.Properties.Name -contains "ammo_category") { $effectLines += "        ammo_category = $(ConvertTo-MIRLuaString ([string]$Row.effect.ammo_category))" }
  if ($Row.effect.PSObject.Properties.Name -contains "turret_id") { $effectLines += "        turret_id = $(ConvertTo-MIRLuaString ([string]$Row.effect.turret_id))" }
  $effectLines += "        modifier = $(ConvertTo-MIRLuaNumber $Row.effect.modifier)"
  $effectBlock = ($effectLines -join ",`n")
  $ingredients = @($Row.science | ForEach-Object { "      {$(ConvertTo-MIRLuaString ([string]$_)), 1}" }) -join ",`n"
  $order = "z[mir]-$($Row.family)-$('{0:d2}' -f [int]$Row.level)"

  return @"
if mir_family_enabled($(ConvertTo-MIRLuaString $Row.family), $($Row.level)) then
  table.insert(mir_technologies, {
    type = "technology",
    name = $(ConvertTo-MIRLuaString $Row.id),
    icon = $(ConvertTo-MIRLuaString ("__base__/graphics/technology/" + $Row.icon)),
    effects = {
      {
$effectBlock
      }
    },
    prerequisites = {$(ConvertTo-MIRLuaString $Row.prerequisite)},
    unit = {
      count = $($Row.count),
      ingredients = {
$ingredients
      },
      time = $($Row.time)
    },
    upgrade = true,
    order = $(ConvertTo-MIRLuaString $order)
  })
end
"@
}

function New-MIRMuseumTargetSource {
  param(
    [Parameter(Mandatory)]$Catalog,
    [Parameter(Mandatory)]$Target,
    [Parameter(Mandatory)][string]$OutputRoot
  )

  $validation = Test-MIRMuseumTarget -Catalog $Catalog -Target $Target
  if (-not $validation.passed) { throw ($validation.errors -join "`n") }
  if (Test-Path -LiteralPath $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

  $rows = @(Get-MIRMuseumExpandedRows -Target $Target)
  $configLines = @(
    "-- More Infinite Research museum configuration.",
    "-- This file is loaded by data.lua. Values above the compiled hard limits are clamped.",
    "mir_config = {"
  )
  for ($i = 0; $i -lt @($Target.families).Count; $i++) {
    $family = @($Target.families)[$i]
    $comma = if ($i -lt @($Target.families).Count - 1) { "," } else { "" }
    $configLines += "  [$(ConvertTo-MIRLuaString ([string]$family.id))] = { enabled = true, levels = $([int]$family.levels) }$comma"
  }
  $configLines += "}"
  Set-MIRUtf8Text -Path (Join-Path $OutputRoot "config.lua") -Text (($configLines -join "`n") + "`n")

  $data = [System.Text.StringBuilder]::new()
  [void]$data.AppendLine('require("config")')
  [void]$data.AppendLine("")
  [void]$data.AppendLine("local mir_hard_limits = {")
  for ($i = 0; $i -lt @($Target.families).Count; $i++) {
    $family = @($Target.families)[$i]
    $comma = if ($i -lt @($Target.families).Count - 1) { "," } else { "" }
    [void]$data.AppendLine("  [$(ConvertTo-MIRLuaString ([string]$family.id))] = $([int]$family.levels)$comma")
  }
  [void]$data.AppendLine("}")
  [void]$data.AppendLine("local function mir_family_enabled(id, level)")
  [void]$data.AppendLine("  local configured = mir_config[id]")
  [void]$data.AppendLine("  local hard_limit = mir_hard_limits[id]")
  [void]$data.AppendLine('  return configured and configured.enabled == true and type(configured.levels) == "number" and configured.levels >= level and level <= hard_limit')
  [void]$data.AppendLine("end")
  [void]$data.AppendLine("local mir_technologies = {}")
  [void]$data.AppendLine("")
  foreach ($row in $rows) { [void]$data.AppendLine((ConvertTo-MIRTechnologyLua -Row $row).TrimEnd()) }
  [void]$data.AppendLine("")
  [void]$data.AppendLine("data:extend(mir_technologies)")
  Set-MIRUtf8Text -Path (Join-Path $OutputRoot "data.lua") -Text $data.ToString()

  $info = [ordered]@{
    name = [string]$Catalog.mod_name
    version = [string]$Target.version
    title = [string]$Catalog.title
    author = [string]$Catalog.author
    description = [string]$Catalog.description
    dependencies = @("base >= $($Target.exact_patch)")
  }
  Set-MIRUtf8Text -Path (Join-Path $OutputRoot "info.json") -Text (($info | ConvertTo-Json -Depth 5) + "`n")

  $locale = @("[technology-name]")
  foreach ($row in $rows) { $locale += "$($row.id)=$($row.label) $($row.level)" }
  $locale += ""
  $locale += "[technology-description]"
  foreach ($row in $rows) { $locale += "$($row.id)=Finite museum continuation $($row.level) for $($row.label.ToLowerInvariant())." }
  Set-MIRUtf8Text -Path (Join-Path $OutputRoot "locale\en\more-infinite-research.cfg") -Text (($locale -join "`n") + "`n")

  $streams = [ordered]@{
    schema = 1
    factorio = [string]$Target.factorio
    mir_version = [string]$Target.version
    rows = @($rows | ForEach-Object { [ordered]@{ technology_id = $_.id; family = $_.family; level = $_.level; effect = $_.effect.type; prerequisite = $_.prerequisite } })
  }
  Set-MIRUtf8Text -Path (Join-Path $OutputRoot "..\stream-manifest.json") -Text (($streams | ConvertTo-Json -Depth 10) + "`n")

  $balance = [ordered]@{
    schema = 1
    factorio = [string]$Target.factorio
    mir_version = [string]$Target.version
    rows = @($rows | ForEach-Object { [ordered]@{ technology_id = $_.id; count = $_.count; time = $_.time; science = @($_.science); effect = $_.effect } })
  }
  Set-MIRUtf8Text -Path (Join-Path $OutputRoot "..\balance.json") -Text (($balance | ConvertTo-Json -Depth 10) + "`n")

  return [pscustomobject][ordered]@{
    target = [string]$Target.factorio
    output_root = (Resolve-Path -LiteralPath $OutputRoot).Path
    generated_count = $rows.Count
    warnings = @($validation.warnings)
  }
}

function Test-MIRMuseumRenderedSource {
  param(
    [Parameter(Mandatory)]$Target,
    [Parameter(Mandatory)][string]$SourceRoot
  )

  $required = @("config.lua", "data.lua", "info.json", "locale\en\more-infinite-research.cfg")
  foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot $relative) -PathType Leaf)) { throw "Missing rendered file '$relative'." }
  }
  $data = Get-Content -Raw -LiteralPath (Join-Path $SourceRoot "data.lua")
  $forbidden = @("max_level", "count_formula", "recipe-productivity", "mining-drill-productivity-bonus", "space-science-pack", "utility-science-pack", "settings.startup", "data.raw")
  foreach ($token in $forbidden) {
    if ($data.Contains($token)) { throw "Rendered target $($Target.factorio) leaked forbidden token '$token'." }
  }
  $ids = [regex]::Matches($data, 'name = "(mir-[a-z0-9-]+)"') | ForEach-Object { $_.Groups[1].Value }
  if ($ids.Count -ne ($ids | Sort-Object -Unique).Count) { throw "Rendered target has duplicate technology IDs." }
  $locale = Get-Content -LiteralPath (Join-Path $SourceRoot "locale\en\more-infinite-research.cfg")
  $keys = @($locale | Where-Object { $_ -match '^[a-z0-9-]+=' } | ForEach-Object { ($_ -split '=', 2)[0] })
  foreach ($id in $ids) {
    if (@($keys | Where-Object { $_ -eq $id }).Count -ne 2) { throw "Technology '$id' must have one name and one description locale row." }
  }
  $info = Get-Content -Raw -LiteralPath (Join-Path $SourceRoot "info.json") | ConvertFrom-Json
  if ([string]$info.version -ne [string]$Target.version) { throw "Rendered info.json version mismatch." }
  if ($info.PSObject.Properties.Name -contains "factorio_version") { throw "Museum metadata must not leak the modern factorio_version field." }
  return $true
}

function Get-MIRMuseumZipIdentity {
  param([Parameter(Mandatory)][string]$Path)

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $zip = [IO.Compression.ZipFile]::OpenRead($resolved)
  try {
    $entries = @($zip.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | Sort-Object FullName)
    $contentLines = @()
    foreach ($entry in $entries) {
      $entryStream = $entry.Open()
      try {
        $memory = [IO.MemoryStream]::new()
        $entryStream.CopyTo($memory)
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($memory.ToArray()))
        $contentLines += "$($entry.FullName)|$hash"
      } finally { $entryStream.Dispose() }
    }
  } finally { $zip.Dispose() }
  $contentBytes = [Text.UTF8Encoding]::new($false).GetBytes(($contentLines -join "`n") + "`n")
  $contentHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($contentBytes))
  return [pscustomobject][ordered]@{
    path = $resolved
    size = (Get-Item -LiteralPath $resolved).Length
    entries = $entries.Count
    sha256 = Get-MIRSha256 $resolved
    package_content_sha256 = $contentHash
  }
}

function New-MIRMuseumPackage {
  param(
    [Parameter(Mandatory)]$Catalog,
    [Parameter(Mandatory)]$Target,
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$OutputDir = "dist"
  )

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $packageName = "$($Catalog.mod_name)_$($Target.version)"
  $targetBuild = Join-Path $RepoRoot ("build\museum\" + [string]$Target.factorio)
  $sourceRoot = Join-Path $targetBuild "runtime"
  New-MIRMuseumTargetSource -Catalog $Catalog -Target $Target -OutputRoot $sourceRoot | Out-Null
  Test-MIRMuseumRenderedSource -Target $Target -SourceRoot $sourceRoot | Out-Null

  $outputRoot = if ([IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $RepoRoot $OutputDir }
  New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
  $zipPath = Join-Path $outputRoot "$packageName.zip"
  $temporary = Join-Path $targetBuild "$packageName.new.zip"
  if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
  $files = @("config.lua", "data.lua", "info.json", "locale\en\more-infinite-research.cfg")
  $fixedTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
  $fileStream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew)
  $archive = [IO.Compression.ZipArchive]::new($fileStream, [IO.Compression.ZipArchiveMode]::Create, $false)
  try {
    foreach ($relative in @($files | Sort-Object)) {
      $entryName = "$packageName/" + $relative.Replace('\', '/')
      $entry = $archive.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
      $entry.LastWriteTime = $fixedTimestamp
      $entry.ExternalAttributes = 0
      $stream = $entry.Open()
      try {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $sourceRoot $relative))
        $stream.Write($bytes, 0, $bytes.Length)
      } finally { $stream.Dispose() }
    }
  } finally {
    $archive.Dispose()
    $fileStream.Dispose()
  }
  if ((Test-Path -LiteralPath $zipPath) -and (Get-MIRSha256 $zipPath) -eq (Get-MIRSha256 $temporary)) {
    Remove-Item -LiteralPath $temporary -Force
  } else {
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Move-Item -LiteralPath $temporary -Destination $zipPath
  }

  $identity = Get-MIRMuseumZipIdentity -Path $zipPath

  return [pscustomobject][ordered]@{
    target = [string]$Target.factorio
    version = [string]$Target.version
    path = $identity.path
    size = $identity.size
    entries = $identity.entries
    sha256 = $identity.sha256
    package_content_sha256 = $identity.package_content_sha256
    generated_count = @(Get-MIRMuseumExpandedRows -Target $Target).Count
  }
}

Export-ModuleMember -Function Get-MIRMuseumCatalog, Get-MIRMuseumTarget, Get-MIRSha256, Get-MIRMuseumExpandedRows, Test-MIRMuseumTarget, New-MIRMuseumTargetSource, Test-MIRMuseumRenderedSource, Get-MIRMuseumZipIdentity, New-MIRMuseumPackage, Set-MIRUtf8Text
