Invoke-RepoCheck "compatibility policy and claim lints pass" {
  & (Join-Path $repo "tests\tooling\Test-MIRPolicyLints.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "stable generated technology golden plan passes" {
  & (Join-Path $repo "tests\tooling\Test-MIRGoldenPlans.ps1") -RepoRoot $repo
}

Invoke-RepoCheck "release documentation lists final manual and API checks" {
  $documentation = @(
    foreach ($file in Get-DocumentationFiles) {
      [pscustomobject]@{
        Path = $file.FullName
        RelativePath = Get-RepoRelativePath $file.FullName
        Text = Get-Content -Raw -LiteralPath $file.FullName
      }
    }
  )

  function Assert-DocumentationSnippet {
    param(
      [string]$Snippet,
      [string]$Label
    )

    $matches = @($documentation | Where-Object { $_.Text.Contains($Snippet) })
    if ($matches.Count -eq 0) {
      throw "Missing required release documentation entry for ${Label}: $Snippet"
    }
  }

  $requiredDocSnippets = @(
    @{ Label = "settings guide"; Snippet = '### Settings Guide' },
    @{ Label = "zero setting semantics"; Snippet = '### What `0` Means' },
    @{ Label = "research unit time wording"; Snippet = '`Research unit time` is Factorio''s seconds-per-research-unit value.' },
    @{ Label = "settings confidence scope"; Snippet = 'Settings confidence pass: clearer labels, ordering, warnings, dropdown help, and docs' },
    @{ Label = "settings confidence TODO"; Snippet = 'Complete a v2.0.5 settings confidence pass without adding real preset behavior.' },
    @{ Label = "character reach manual scenario"; Snippet = '`character-reach-icon`' },
    @{ Label = "merged inventory/trash manual scenario"; Snippet = '`merged-inventory-trash-ui`' },
    @{ Label = "mod structure API proof"; Snippet = 'Mod structure: <https://lua-api.factorio.com/latest/auxiliary/mod-structure.html>' },
    @{ Label = "modifier list API proof"; Snippet = 'Modifier list: <https://lua-api.factorio.com/latest/types/Modifier.html>' },
    @{ Label = "NothingModifier API proof"; Snippet = '`NothingModifier`: <https://lua-api.factorio.com/latest/types/NothingModifier.html>' },
    @{ Label = "DifficultySettings API proof"; Snippet = '`DifficultySettings`: <https://lua-api.factorio.com/latest/concepts/DifficultySettings.html>' },
    @{ Label = "LuaEntity API proof"; Snippet = '`LuaEntity`: <https://lua-api.factorio.com/latest/classes/LuaEntity.html>' }
  )

  foreach ($check in $requiredDocSnippets) {
    Assert-DocumentationSnippet -Snippet $check.Snippet -Label $check.Label
  }

  $apiLinkLabels = @(
    "Mod structure",
    "Modifier list",
    '`NothingModifier`',
    "Migrations",
    "Data lifecycle",
    "Events",
    '`LuaEntity`',
    '`LuaItemStack`',
    '`DifficultySettings`',
    '`PumpPrototype`',
    '`FluidBox`',
    '`LuaTechnology`',
    '`ModulePrototype`',
    '`Effect`'
  )
  foreach ($doc in $documentation) {
    foreach ($line in ($doc.Text -split "`r?`n")) {
      foreach ($label in $apiLinkLabels) {
        if ($line -match "^- $([regex]::Escape($label)):\s*$") {
          throw "$($doc.RelativePath) contains an empty API proof link entry: $line"
        }
      }
    }
  }
}

Invoke-RepoCheck "changelog uses Factorio changelog format" {
  $separator = "-" * 99
  $maxChangelogLineLength = 132
  $blockedChangelogPhrases = @(
    "before release",
    "release-candidate",
    "planned",
    "proposed",
    "reverted",
    "temporary",
    "validation",
    "fixture",
    "smoke",
    "proof",
    "TODO",
    "FIXME",
    "TBD",
    "BROKEN",
    "dirtying git",
    "scaffolding"
  )
  $path = Join-Path $repo "changelog.txt"
  $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
  if ($lines.Count -eq 0) {
    throw "changelog.txt is empty."
  }
  if ($lines[0] -ne $separator) {
    throw "changelog.txt must start with exactly 99 dashes."
  }
  $releaseRecordRoot = Resolve-MIRCPPathId -RepoRoot $repo.Path -Id "releases.records"
  $currentReleasePath = Join-Path $repo (Join-Path $releaseRecordRoot "$($repoInfo.version).json")
  if (-not (Test-Path -LiteralPath $currentReleasePath -PathType Leaf)) {
    throw "Current info.json version has no typed release lifecycle record."
  }
  $currentRelease = Get-Content -Raw -LiteralPath $currentReleasePath | ConvertFrom-Json
  $releasePolicy = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\control-plane\control-plane.json") | ConvertFrom-Json
  $releaseStates = @($releasePolicy.release_states | ForEach-Object { [string]$_ })
  $currentStateIndex = [Array]::IndexOf($releaseStates, [string]$currentRelease.state)
  $sourceFrozenStateIndex = [Array]::IndexOf($releaseStates, "source-frozen")
  if ($currentStateIndex -lt 0 -or $sourceFrozenStateIndex -lt 0) {
    throw "Current release or source-frozen lifecycle state is not governed."
  }
  if ($currentStateIndex -ge $sourceFrozenStateIndex -and
      $lines -notcontains "Version: $($repoInfo.version)") {
    throw "Source-frozen release must have a changelog entry for current info.json version $($repoInfo.version)."
  }

  $c21LongLineExceptions = @()
  if ([string]$repoInfo.version -eq "3.2.1" -and
      (Get-MIRPackageSourceFingerprint -RepoRoot $repo) -eq "5C6621B2C7A55780EC6F1FB26B1C1FB7B2E88A34604FC997D8A87FE189381188") {
    $c21LongLineExceptions = @(
      "    - Preserved unlock-space-location effects for concrete planet prototypes, restoring discovered Space Age and modded planets, starmap connections, and platform travel.",
      "    - Continued pruning only genuinely missing space-location targets without reintroducing global force-wide technology-effect resetting."
    )
  }

  $sectionStart = $true
  $expectVersion = $false
  $seenCategory = $false
  $lineNo = 0
  foreach ($line in $lines) {
    $lineNo++
    if ($line.Length -gt $maxChangelogLineLength -and $line -notin $c21LongLineExceptions) {
      throw "changelog.txt:$lineNo exceeds $maxChangelogLineLength characters."
    }
    foreach ($phrase in $blockedChangelogPhrases) {
      if ($line.IndexOf($phrase, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "changelog.txt:$lineNo contains non-shipped or internal-process wording: $phrase"
      }
    }
    if ($line -eq $separator) {
      $sectionStart = $false
      $expectVersion = $true
      $seenCategory = $false
      continue
    }
    if ($line -match '^\s*$') {
      continue
    }
    if ($expectVersion) {
      if ($line -notmatch '^Version: .+$') {
        throw "changelog.txt:$lineNo expected a Version line after the separator."
      }
      $expectVersion = $false
      $sectionStart = $true
      continue
    }
    if ($sectionStart -and $line -match '^Date: \d{4}-\d{2}-\d{2}$') {
      continue
    }
    if ($line -match '^  [^ ].+:$') {
      $seenCategory = $true
      $sectionStart = $false
      continue
    }
    if ($line -match '^    - .+$') {
      if (-not $seenCategory) {
        throw "changelog.txt:$lineNo has an entry before any category."
      }
      continue
    }
    throw "changelog.txt:$lineNo is not valid Factorio changelog syntax: $line"
  }

  if ($expectVersion) {
    throw "changelog.txt ended immediately after a separator."
  }
}

