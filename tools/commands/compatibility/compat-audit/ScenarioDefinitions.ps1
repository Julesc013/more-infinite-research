$knownOfficialBuiltinMods = @("space-age", "quality", "elevated-rails", "recycler")
function Get-MIROfficialBuiltinFullMods {
  param(
    [string]$FactorioBinary,
    [string[]]$Candidates
  )

  $index = @{}
  if (-not [string]::IsNullOrWhiteSpace($FactorioBinary) -and (Test-Path -LiteralPath $FactorioBinary)) {
    $factorioExe = (Resolve-Path -LiteralPath $FactorioBinary).Path
    $factorioRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $factorioExe))
    $dataRoot = Join-Path $factorioRoot "data"
    if (Test-Path -LiteralPath $dataRoot) {
      foreach ($candidate in @($Candidates)) {
        $infoPath = Join-Path $dataRoot ("{0}\info.json" -f $candidate)
        if (-not (Test-Path -LiteralPath $infoPath)) { continue }
        $info = Read-MIRJsonFile -Path $infoPath
        $index[[string]$candidate] = [pscustomobject]@{
          name = [string]$candidate
          title = if ([string]::IsNullOrWhiteSpace([string]$info.title)) { [string]$candidate } else { [string]$info.title }
          releases = @([pscustomobject]@{
            version = [string]$info.version
            info_json = $info
          })
        }
      }
      return $index
    }
  }

  foreach ($candidate in @($Candidates)) {
    $index[[string]$candidate] = [pscustomobject]@{
      name = [string]$candidate
      title = [string]$candidate
      releases = @([pscustomobject]@{
        version = ""
        info_json = [pscustomobject]@{
          name = [string]$candidate
          version = ""
          dependencies = @()
        }
      })
    }
  }
  return $index
}

$officialBuiltinFullModsByName = Get-MIROfficialBuiltinFullMods -FactorioBinary $FactorioBin -Candidates $knownOfficialBuiltinMods
$officialBuiltinMods = @($officialBuiltinFullModsByName.Keys | Sort-Object)
$specialLocalMods = @("base", "more-infinite-research")
$officialBuiltinLookup = @{}
foreach ($officialMod in $knownOfficialBuiltinMods) {
  $officialBuiltinLookup[$officialMod] = $true
}
$availableOfficialBuiltinLookup = @{}
foreach ($officialMod in $officialBuiltinMods) {
  $availableOfficialBuiltinLookup[$officialMod] = $true
}
$localModLookup = @{}
foreach ($name in @($knownOfficialBuiltinMods + $specialLocalMods)) {
  $localModLookup[$name] = $true
}

function Add-MIROfficialBuiltinDependencyClosure {
  param(
    [Parameter(Mandatory)][hashtable]$Enabled,
    [switch]$IncludeRecommendedDependencies
  )

  $queue = [System.Collections.Generic.Queue[string]]::new()
  foreach ($name in @($Enabled.Keys)) { $queue.Enqueue([string]$name) }

  while ($queue.Count -gt 0) {
    $name = $queue.Dequeue()
    if (-not $officialBuiltinFullModsByName.ContainsKey($name)) { continue }
    $full = $officialBuiltinFullModsByName[$name]
    $release = @($full.releases)[0]
    foreach ($dep in @(Get-MIRReleaseDependencies -Release $release)) {
      $includeDependency = $dep.required -or ($IncludeRecommendedDependencies -and $dep.kind -eq "recommended")
      if (-not $includeDependency -or -not $officialBuiltinLookup.ContainsKey([string]$dep.name)) { continue }
      if (-not $Enabled.ContainsKey([string]$dep.name)) {
        $Enabled[[string]$dep.name] = $true
        $queue.Enqueue([string]$dep.name)
      }
    }
  }
}

function Get-MIRPortalRootModNames {
  param([string[]]$ModNames)
  @($ModNames | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and -not $localModLookup.ContainsKey([string]$_)
  } | Sort-Object -Unique)
}

function Get-MIRExplicitOfficialMods {
  param([string[]]$ModNames)
  @($ModNames | Where-Object { $officialBuiltinLookup.ContainsKey([string]$_) } | Sort-Object -Unique)
}

function Get-MIREnabledOfficialModsFromEntries {
  param(
    [object[]]$LockEntries,
    [bool]$EnableSpaceAgeBundle,
    [string[]]$ExplicitOfficialMods = @(),
    [switch]$IncludeRecommendedDependencies
  )

  $enabled = @{}
  if ($EnableSpaceAgeBundle) {
    foreach ($name in $officialBuiltinMods) { $enabled[$name] = $true }
  }
  foreach ($name in @($ExplicitOfficialMods)) {
    if ($officialBuiltinLookup.ContainsKey([string]$name)) { $enabled[[string]$name] = $true }
  }

  foreach ($entry in @($LockEntries)) {
    foreach ($dep in @($entry.dependencies)) {
      $includeDependency = $dep.required -or ($IncludeRecommendedDependencies -and $dep.kind -eq "recommended")
      if ($includeDependency -and $officialBuiltinLookup.ContainsKey([string]$dep.name)) {
        $enabled[[string]$dep.name] = $true
      }
    }
  }

  if ($enabled.ContainsKey("space-age")) {
    foreach ($name in $officialBuiltinMods) { $enabled[$name] = $true }
  }
  Add-MIROfficialBuiltinDependencyClosure -Enabled $enabled -IncludeRecommendedDependencies:$IncludeRecommendedDependencies

  return @($enabled.Keys | Sort-Object)
}

function Get-MIRUnavailableOfficialMods {
  param(
    [object[]]$LockEntries,
    [bool]$EnableSpaceAgeBundle,
    [string[]]$ExplicitOfficialMods = @(),
    [switch]$IncludeRecommendedDependencies
  )

  $required = @{}
  if ($EnableSpaceAgeBundle) {
    $required["space-age"] = $true
  }
  foreach ($name in @($ExplicitOfficialMods)) {
    if ($officialBuiltinLookup.ContainsKey([string]$name)) { $required[[string]$name] = $true }
  }
  foreach ($entry in @($LockEntries)) {
    foreach ($dep in @($entry.dependencies)) {
      $includeDependency = $dep.required -or ($IncludeRecommendedDependencies -and $dep.kind -eq "recommended")
      if ($includeDependency -and $officialBuiltinLookup.ContainsKey([string]$dep.name)) {
        $required[[string]$dep.name] = $true
      }
    }
  }
  Add-MIROfficialBuiltinDependencyClosure -Enabled $required -IncludeRecommendedDependencies:$IncludeRecommendedDependencies
  @($required.Keys | Where-Object { -not $availableOfficialBuiltinLookup.ContainsKey([string]$_) } | Sort-Object)
}

function Resolve-MIRLockDependencyNames {
  param(
    [Parameter(Mandatory)][string[]]$RootModNames,
    [Parameter(Mandatory)]$LockEntriesByName,
    [switch]$IncludeRecommendedDependencies
  )

  $queue = [System.Collections.Generic.Queue[string]]::new()
  foreach ($name in @($RootModNames | Sort-Object -Unique)) {
    if (-not $localModLookup.ContainsKey([string]$name)) { $queue.Enqueue([string]$name) }
  }

  $resolved = @{}
  $failures = @()
  while ($queue.Count -gt 0) {
    $name = $queue.Dequeue()
    if ($localModLookup.ContainsKey($name) -or $resolved.ContainsKey($name)) { continue }
    if (-not $LockEntriesByName.ContainsKey($name)) {
      $failures += [pscustomobject]@{
        name = $name
        error = "Dependency '$name' is not present in the lockfile."
      }
      continue
    }

    $entry = $LockEntriesByName[$name]
    $resolved[$name] = $true
    foreach ($dep in @($entry.dependencies)) {
      $includeDependency = $dep.required -or ($IncludeRecommendedDependencies -and $dep.kind -eq "recommended")
      if ($includeDependency -and -not $localModLookup.ContainsKey([string]$dep.name) -and -not $resolved.ContainsKey([string]$dep.name)) {
        $queue.Enqueue([string]$dep.name)
      }
    }
  }

  [pscustomobject]@{
    names = @($resolved.Keys | Sort-Object)
    failures = $failures
  }
}

function Get-MIRDependencyNamesFromFullMod {
  param($FullMod)

  $names = @()
  foreach ($release in @($FullMod.releases)) {
    foreach ($dependency in @($release.info_json.dependencies)) {
      if ([string]::IsNullOrWhiteSpace([string]$dependency)) { continue }
      $parsed = ConvertFrom-MIRDependencyString -Dependency ([string]$dependency)
      $names += [string]$parsed.name
    }
  }
  @($names | Sort-Object -Unique)
}

function Test-MIRLocalModHasCompatibleRelease {
  param([Parameter(Mandatory)]$FullMod)

  $release = Select-MIRCompatibleRelease -FullMod $FullMod -FactorioVersions $FactorioVersions
  return $null -ne $release
}

function Get-MIRCompatibleLocalModNames {
  param([Parameter(Mandatory)]$FullModsByName)

  @(
    foreach ($name in @($FullModsByName.Keys | Sort-Object)) {
      if (Test-MIRLocalModHasCompatibleRelease -FullMod $FullModsByName[$name]) {
        [string]$name
      }
    }
  )
}

function Test-MIRLocalNameMatches {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)]$FullMod,
    [Parameter(Mandatory)][string]$Pattern
  )

  $title = [string]$FullMod.title
  $deps = (Get-MIRDependencyNamesFromFullMod -FullMod $FullMod) -join " "
  return (($Name + " " + $title + " " + $deps) -match $Pattern)
}

function New-MIRGeneratedLocalScenarioDefinition {
  param(
    [Parameter(Mandatory)][string]$Name,
    [string[]]$Mods = @(),
    [bool]$IncludeSpaceAge,
    [Parameter(Mandatory)][string]$Notes
  )

  $modList = @($Mods | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
  if ($modList.Count -eq 0) { return $null }
  [pscustomobject]@{
    name = $Name
    include_space_age = $IncludeSpaceAge
    mods = $modList
    notes = $Notes
  }
}

function New-MIRGeneratedLocalScenarioDefinitions {
  param([Parameter(Mandatory)]$FullModsByName)

  $compatibleNames = @(Get-MIRCompatibleLocalModNames -FullModsByName $FullModsByName)
  $definitions = @()
  $scenarioLineSlug = $FactorioLine.Replace(".", "-")

  if ($GenerateLocalMegaScenario -or (-not $GenerateLocalClusterScenarios -and -not $GenerateLocalPairwiseScenarios)) {
    $definitions += New-MIRGeneratedLocalScenarioDefinition `
      -Name "generated-local-$scenarioLineSlug-mega-all" `
      -Mods $compatibleNames `
      -IncludeSpaceAge $true `
      -Notes "Generated stress scenario: all locally available compatible mods enabled together with the official Space Age bundle."
  }

  if ($GenerateLocalClusterScenarios) {
    $clusterPatterns = @(
      [pscustomobject]@{
        name = "generated-local-$scenarioLineSlug-cluster-planets"
        include_space_age = $true
        pattern = "(?i)(planet|moon|space-age|Cerys|Fulgora|corrundum|cubium|lignumis|Moshine|muluna|rubia|secretas|panglia|Paracelsin|rabbasca|vesta|aquilo|gleba|Muria|carna|linox|foliax|nauv|Small-Space-Age|warptorio)"
        notes = "Generated cluster scenario for locally available planet and Space Age content mods."
      },
      [pscustomobject]@{
        name = "generated-local-$scenarioLineSlug-cluster-bz-resources"
        include_space_age = $true
        pattern = "(?i)^(bz|bzt|bzz)|resource|ore|carbon|lead|silicon|tin|titanium|zirconium"
        notes = "Generated cluster scenario for locally available BZ/resource-chain mods."
      },
      [pscustomobject]@{
        name = "generated-local-$scenarioLineSlug-cluster-bob"
        include_space_age = $false
        pattern = "(?i)^bob"
        notes = "Generated cluster scenario for locally available Bob mods."
      },
      [pscustomobject]@{
        name = "generated-local-$scenarioLineSlug-cluster-krastorio"
        include_space_age = $true
        pattern = "(?i)Krastorio|k2so|K2"
        notes = "Generated cluster scenario for locally available Krastorio and K2SO mods."
      },
      [pscustomobject]@{
        name = "generated-local-$scenarioLineSlug-cluster-production-fluids"
        include_space_age = $true
        pattern = "(?i)refin|chem|fluid|casting|foundry|molten|metal|ore|plutonium|carbon|mineral|hot-metals|more-casting"
        notes = "Generated cluster scenario for locally available production, fluid, casting, and resource-flow mods."
      },
      [pscustomobject]@{
        name = "generated-local-$scenarioLineSlug-cluster-logistics-transport"
        include_space_age = $true
        pattern = "(?i)train|cargo|ship|loader|inserter|belt|logistic|transport|rail|space-platform"
        notes = "Generated cluster scenario for locally available logistics, transport, rail, cargo, and inserter mods."
      }
    )

    foreach ($cluster in $clusterPatterns) {
      $mods = @(
        foreach ($name in $compatibleNames) {
          if (Test-MIRLocalNameMatches -Name $name -FullMod $FullModsByName[$name] -Pattern $cluster.pattern) {
            [string]$name
          }
        }
      )
      $definition = New-MIRGeneratedLocalScenarioDefinition -Name $cluster.name -Mods $mods -IncludeSpaceAge ([bool]$cluster.include_space_age) -Notes ([string]$cluster.notes)
      if ($null -ne $definition) { $definitions += $definition }
    }
  }

  if ($GenerateLocalPairwiseScenarios) {
    $pairPool = @(
      foreach ($name in $compatibleNames) {
        if (Test-MIRLocalNameMatches -Name $name -FullMod $FullModsByName[$name] -Pattern "(?i)planet|moon|space-age|bz|bob|Krastorio|refin|chem|casting|ore|resource|train|cargo|ship|logistic|inserter") {
          [string]$name
        }
      }
    ) | Sort-Object -Unique

    $pairCount = 0
    for ($i = 0; $i -lt $pairPool.Count; $i++) {
      for ($j = $i + 1; $j -lt $pairPool.Count; $j++) {
        if ($pairCount -ge $GeneratedLocalPairwiseLimit) { break }
        $pairCount++
        $definitions += New-MIRGeneratedLocalScenarioDefinition `
          -Name ("generated-local-$scenarioLineSlug-pair-{0:D3}" -f $pairCount) `
          -Mods @($pairPool[$i], $pairPool[$j]) `
          -IncludeSpaceAge $true `
          -Notes ("Generated capped pairwise local-library scenario: {0} + {1}." -f $pairPool[$i], $pairPool[$j])
      }
      if ($pairCount -ge $GeneratedLocalPairwiseLimit) { break }
    }
  }

  @($definitions | Where-Object { $null -ne $_ })
}

$exclusions = Read-MIRJsonFile -Path $KnownExclusions -Fallback ([pscustomobject]@{
  mod_names = @()
  categories = @("localizations", "internal")
})
$manualScenarioPaths = @($ManualScenariosPath)
if (-not $PSBoundParameters.ContainsKey("ManualScenariosPath")) {
  $lineManifest = if ($FactorioLine -eq "2.0") {
    Join-Path $compatAuditCommandRoot "..\..\..\validation\scenarios\local-2.0.json"
  } else {
    Join-Path $compatAuditCommandRoot "..\..\..\validation\scenarios\local-2.1.json"
  }
  $manualScenarioPaths += $lineManifest
}

$manualScenarios = @()
foreach ($scenarioManifestPath in @($manualScenarioPaths | Select-Object -Unique)) {
  $manifest = Read-MIRJsonFile -Path $scenarioManifestPath -Fallback ([pscustomobject]@{ schema = 0; scenarios = @() })
  if ([int](Get-MIRObjectProperty -Object $manifest -Name "schema" -Default 0) -ne 2) {
    throw "Scenario manifest must use schema 2: $scenarioManifestPath"
  }
  foreach ($scenario in @($manifest.scenarios)) {
    $targets = @((Get-MIRObjectProperty -Object $scenario -Name "targets" -Default @()) | ForEach-Object { [string]$_ })
    if ($targets.Count -gt 0 -and $FactorioLine -notin $targets) { continue }
    $scenario | Add-Member -NotePropertyName "_source_manifest" -NotePropertyValue $scenarioManifestPath -Force
    $manualScenarios += $scenario
  }
}
$manual = [pscustomobject]@{ scenarios = @($manualScenarios) }
