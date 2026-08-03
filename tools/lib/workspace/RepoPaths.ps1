Set-StrictMode -Version Latest

function Assert-MIRDurableRepoPath {
  param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$AllowDot
  )

  if ([string]::IsNullOrWhiteSpace($Path)) { throw "Durable repository path is empty." }
  if ($AllowDot -and $Path -eq ".") { return }
  if ([IO.Path]::IsPathRooted($Path) -or $Path -match "^[A-Za-z]:") {
    throw "Durable repository path must be relative: $Path"
  }
  if ($Path.Contains("\")) { throw "Durable repository path must use '/': $Path" }
  if ($Path.StartsWith("/") -or $Path.Split("/") -contains "..") {
    throw "Durable repository path cannot traverse outside the repository: $Path"
  }
}

function Read-MIRRepoPathCatalog {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $catalogPath = Join-Path $RepoRoot ".mir/control/paths.yml"
  if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "Repository path catalog is missing: $catalogPath"
  }

  [int]$schema = 0
  [string]$authority = ""
  $paths = [ordered]@{}
  [bool]$inPaths = $false
  foreach ($line in Get-Content -LiteralPath $catalogPath) {
    if ($line -match "^schema:\s*([0-9]+)\s*$") { $schema = [int]$Matches[1]; continue }
    if ($line -match "^authority:\s*(\S+)\s*$") { $authority = $Matches[1]; continue }
    if ($line -match "^paths:\s*$") { $inPaths = $true; continue }
    if (-not $inPaths -or [string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) { continue }
    if ($line -notmatch "^\s{2}([a-z][a-z0-9.-]+):\s*(\S+)\s*$") {
      throw "Unsupported repository path catalog line: $line"
    }
    $id = $Matches[1]
    $value = $Matches[2]
    if ($paths.Contains($id)) { throw "Duplicate repository path ID: $id" }
    Assert-MIRDurableRepoPath -Path $value -AllowDot
    $paths[$id] = $value
  }

  if ($schema -ne 1 -or $authority -ne "mir-repository-paths-v1" -or $paths.Count -eq 0) {
    throw "Repository path catalog header is invalid."
  }
  return [pscustomobject][ordered]@{schema=$schema;authority=$authority;paths=[pscustomobject]$paths}
}

function Read-MIRRepoAliasCatalog {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    $PathCatalog = $null
  )

  if ($null -eq $PathCatalog) { $PathCatalog = Read-MIRRepoPathCatalog -RepoRoot $RepoRoot }
  $aliasPath = Join-Path $RepoRoot ".mir/control/aliases.yml"
  if (-not (Test-Path -LiteralPath $aliasPath -PathType Leaf)) {
    throw "Repository alias catalog is missing: $aliasPath"
  }

  [int]$schema = 0
  [string]$authority = ""
  $aliases = [Collections.Generic.List[object]]::new()
  $current = $null
  foreach ($line in Get-Content -LiteralPath $aliasPath) {
    if ($line -match "^schema:\s*([0-9]+)\s*$") { $schema = [int]$Matches[1]; continue }
    if ($line -match "^authority:\s*(\S+)\s*$") { $authority = $Matches[1]; continue }
    if ($line -match "^\s{2}-\s+from:\s*(\S+)\s*$") {
      if ($null -ne $current) { $aliases.Add([pscustomobject]$current) }
      $current = [ordered]@{from=$Matches[1];to="";mode="";introduced=""}
      continue
    }
    if ($null -ne $current -and $line -match "^\s{4}(to|mode|introduced):\s*(\S+)\s*$") {
      $current[$Matches[1]] = $Matches[2]
    }
  }
  if ($null -ne $current) { $aliases.Add([pscustomobject]$current) }

  if ($schema -ne 1 -or $authority -ne "mir-repository-path-aliases-v1") {
    throw "Repository alias catalog header is invalid."
  }
  $seen = @{}
  foreach ($alias in $aliases) {
    Assert-MIRDurableRepoPath -Path ([string]$alias.from)
    if (-not $PathCatalog.paths.PSObject.Properties[[string]$alias.to]) {
      throw "Alias '$($alias.from)' targets unknown path ID '$($alias.to)'."
    }
    if ([string]$alias.mode -notin @("historical-read-only", "read-only", "local-read-only")) {
      throw "Alias '$($alias.from)' has invalid mode '$($alias.mode)'."
    }
    $key = ([string]$alias.from).ToLowerInvariant()
    if ($seen.ContainsKey($key)) { throw "Case-insensitive duplicate alias: $($alias.from)" }
    $seen[$key] = $true
  }
  return [pscustomobject][ordered]@{schema=$schema;authority=$authority;aliases=@($aliases)}
}

function Join-MIRRepoRelativePath {
  param([string]$Base, [string]$Suffix)
  if ([string]::IsNullOrWhiteSpace($Suffix)) { return $Base.TrimEnd("/") }
  if ($Base -eq ".") { return $Suffix.TrimStart("/") }
  return "$($Base.TrimEnd("/"))/$($Suffix.TrimStart("/"))"
}

function Test-MIRRepoAliasMatch {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$From)
  if ($From.EndsWith("/")) {
    return $Path.StartsWith($From, [StringComparison]::Ordinal)
  }
  return $Path.Equals($From, [StringComparison]::Ordinal)
}

function Resolve-MIRRepoPath {
  [CmdletBinding(DefaultParameterSetName="Id")]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory,ParameterSetName="Id")][string]$Id,
    [Parameter(Mandatory,ParameterSetName="Path")][string]$Path
  )

  $catalog = Read-MIRRepoPathCatalog -RepoRoot $RepoRoot
  if ($PSCmdlet.ParameterSetName -eq "Id") {
    $property = $catalog.paths.PSObject.Properties[$Id]
    if ($null -eq $property) { throw "Unknown repository path ID: $Id" }
    return [pscustomobject][ordered]@{
      input=$Id
      id=$Id
      relative_path=[string]$property.Value
      alias=$false
      mode="canonical"
    }
  }

  Assert-MIRDurableRepoPath -Path $Path
  $aliases = Read-MIRRepoAliasCatalog -RepoRoot $RepoRoot -PathCatalog $catalog
  $invalidExactDescendant = @($aliases.aliases | Where-Object {
    -not ([string]$_.from).EndsWith("/") -and
    $Path.StartsWith("$([string]$_.from)/", [StringComparison]::Ordinal)
  } | Select-Object -First 1)
  if ($invalidExactDescendant.Count -eq 1) {
    throw "Path cannot descend through exact file alias '$($invalidExactDescendant[0].from)': $Path"
  }
  $match = @($aliases.aliases | Where-Object { Test-MIRRepoAliasMatch -Path $Path -From ([string]$_.from) } |
    Sort-Object { ([string]$_.from).Length } -Descending | Select-Object -First 1)
  if ($match.Count -eq 1) {
    $target = $catalog.paths.PSObject.Properties[[string]$match[0].to]
    $suffix = $Path.Substring(([string]$match[0].from).Length)
    return [pscustomobject][ordered]@{
      input=$Path
      id=[string]$match[0].to
      relative_path=(Join-MIRRepoRelativePath -Base ([string]$target.Value) -Suffix $suffix)
      alias=$true
      mode=[string]$match[0].mode
    }
  }

  $direct = @($catalog.paths.PSObject.Properties |
    Where-Object {
      [string]$_.Value -ne "." -and
      ($Path -eq [string]$_.Value -or $Path.StartsWith("$([string]$_.Value)/", [StringComparison]::Ordinal))
    } |
    Sort-Object { ([string]$_.Value).Length } -Descending |
    Select-Object -First 1)
  if ($direct.Count -eq 0) { throw "Path is neither canonical nor a registered historical alias: $Path" }
  return [pscustomobject][ordered]@{
    input=$Path
    id=[string]$direct[0].Name
    relative_path=$Path
    alias=$false
    mode="canonical"
  }
}

function Test-MIRLayoutGlob {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Pattern)
  $regex = [Regex]::Escape($Pattern).Replace("\*\*", "__MIR_DOUBLE_STAR__").Replace("\*", "[^/]*").Replace("__MIR_DOUBLE_STAR__", ".*")
  return $Path -match "^$regex$"
}

function Get-MIROwnershipPatternSpecificity {
  param([Parameter(Mandatory)][string]$Pattern)

  $normalized = $Pattern.Replace("\", "/")
  $segments = @($normalized.Split("/") | Where-Object { $_ -ne "" })
  $literal = [regex]::Replace($normalized, "[\*\?]", "")
  return [pscustomobject][ordered]@{
    literal_characters = $literal.Length
    literal_segments = @($segments | Where-Object { $_ -notmatch "[\*\?]" }).Count
    segment_count = $segments.Count
    wildcard_count = [regex]::Matches($normalized, "\*\*|\*|\?").Count
  }
}

function Resolve-MIRPathOwnership {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Ownership
  )

  $normalized = $Path.Replace("\", "/")
  $compiledProperty = $Ownership.PSObject.Properties["__mir_compiled_ownership_rules"]
  if ($null -eq $compiledProperty) {
    $compiledRules = @(
      foreach ($row in @($Ownership.owners)) {
        $pattern = [string]$row.pattern
        $regex = [Regex]::Escape($pattern).Replace("\*\*", "__MIR_DOUBLE_STAR__").Replace("\*", "[^/]*").Replace("__MIR_DOUBLE_STAR__", ".*")
        $specificity = Get-MIROwnershipPatternSpecificity -Pattern $pattern
        [pscustomobject][ordered]@{
          row = $row
          regex = "^$regex$"
          literal_characters = $specificity.literal_characters
          literal_segments = $specificity.literal_segments
          segment_count = $specificity.segment_count
          wildcard_count = $specificity.wildcard_count
        }
      }
    )
    Add-Member -InputObject $Ownership -MemberType NoteProperty -Name "__mir_compiled_ownership_rules" -Value $compiledRules
    $compiledProperty = $Ownership.PSObject.Properties["__mir_compiled_ownership_rules"]
  }
  $matches = @(
    foreach ($compiled in @($compiledProperty.Value)) {
      if ($normalized -notmatch [string]$compiled.regex) { continue }
      [pscustomobject][ordered]@{
        row = $compiled.row
        literal_characters = $compiled.literal_characters
        literal_segments = $compiled.literal_segments
        segment_count = $compiled.segment_count
        wildcard_count = $compiled.wildcard_count
      }
    }
  )
  if ($matches.Count -eq 0) { return $null }

  $ordered = @($matches | Sort-Object `
    @{Expression="literal_characters";Descending=$true}, `
    @{Expression="literal_segments";Descending=$true}, `
    @{Expression="segment_count";Descending=$true}, `
    @{Expression="wildcard_count";Descending=$false}, `
    @{Expression={ [string]$_.row.pattern };Descending=$false})
  $winner = $ordered[0]
  $best = @($ordered | Where-Object {
    $_.literal_characters -eq $winner.literal_characters -and
    $_.literal_segments -eq $winner.literal_segments -and
    $_.segment_count -eq $winner.segment_count -and
    $_.wildcard_count -eq $winner.wildcard_count
  })

  if ($best.Count -eq 1) {
    return [pscustomobject][ordered]@{
      path = $normalized
      module = [string]$best[0].row.module
      writes = @($best[0].row.writes | ForEach-Object { [string]$_ } | Sort-Object -Unique)
      patterns = @([string]$best[0].row.pattern)
      composed = $false
      specificity = [pscustomobject][ordered]@{
        literal_characters = $winner.literal_characters
        literal_segments = $winner.literal_segments
        segment_count = $winner.segment_count
        wildcard_count = $winner.wildcard_count
      }
    }
  }

  $winningPatterns = @($best | ForEach-Object { [string]$_.row.pattern } | Sort-Object -Unique)
  $composition = @(@($Ownership.compositions) | Where-Object {
    $declared = @($_.patterns | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    ($declared -join "`n") -ceq ($winningPatterns -join "`n")
  })
  if ($composition.Count -ne 1) {
    throw "Ambiguous equal-specificity ownership for '$normalized': $($winningPatterns -join ', ')."
  }
  return [pscustomobject][ordered]@{
    path = $normalized
    module = [string]$composition[0].module
    writes = @($composition[0].writes | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    patterns = $winningPatterns
    composed = $true
    specificity = [pscustomobject][ordered]@{
      literal_characters = $winner.literal_characters
      literal_segments = $winner.literal_segments
      segment_count = $winner.segment_count
      wildcard_count = $winner.wildcard_count
    }
  }
}

function Test-MIRPackagePath {
  param([Parameter(Mandatory)][string]$Path)
  if ($Path -in @("info.json", "changelog.txt", "thumbnail.png", "control.lua", "data.lua", "data-updates.lua", "data-final-fixes.lua", "settings.lua", "settings-updates.lua", "settings-final-fixes.lua", "README.md", "LICENSE")) {
    return $true
  }
  return $Path -match "^(locale|migrations|prototypes|graphics|sound)/"
}

function Get-MIRLayoutClass {
  param([Parameter(Mandatory)][string]$Path)
  if (Test-MIRPackagePath -Path $Path) { return "product-package" }
  foreach ($row in @(
    @("spec/", "product-specification"),
    @("validation/", "validation"),
    @("verification/", "legacy-validation"),
    @("tools/", "tooling"),
    @("scripts/", "legacy-tooling"),
    @("fixtures/", "fixtures"),
    @("docs/", "documentation"),
    @("approved-delta/", "legacy-release-delta"),
    @(".mir/", "control-plane"),
    @("dist/", "distribution"),
    @(".github/", "automation"),
    @(".agents/", "agent-configuration"),
    @(".codex/", "agent-configuration")
  )) {
    if ($Path.StartsWith($row[0], [StringComparison]::Ordinal)) { return $row[1] }
  }
  if ($Path -in @(".gitattributes", ".gitignore", "AGENTS.md", "CONTRIBUTING.md", "todo.md")) { return "repository-policy" }
  return "unclassified"
}

function Get-MIRCanonicalTarget {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Aliases, [Parameter(Mandatory)]$Paths)
  $alias = @($Aliases.aliases | Where-Object { Test-MIRRepoAliasMatch -Path $Path -From ([string]$_.from) } |
    Sort-Object { ([string]$_.from).Length } -Descending | Select-Object -First 1)
  if ($alias.Count -eq 1) {
    $base = [string]$Paths.paths.PSObject.Properties[[string]$alias[0].to].Value
    return Join-MIRRepoRelativePath -Base $base -Suffix $Path.Substring(([string]$alias[0].from).Length)
  }
  if ($Path -eq "todo.md") { return ".mir/views/tasks.md" }
  if ($Path.StartsWith("scripts/", [StringComparison]::Ordinal)) { return "tools/" }
  if ($Path.StartsWith(".mir/target-lines/", [StringComparison]::Ordinal)) { return ".mir/releases/sources/" }
  return $Path
}

function Get-MIRLayoutOwnership {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Ownership)
  $resolved = Resolve-MIRPathOwnership -Path $Path -Ownership $Ownership
  if ($null -ne $resolved) {
    return [pscustomobject]@{
      owner=[string]$resolved.module
      writer=(@($resolved.writes) -join ",")
    }
  }
  return [pscustomobject]@{owner="unowned";writer="none"}
}

function Get-MIRLayoutGitEntries {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $entries = [ordered]@{}
  foreach ($line in @(& git -C $RepoRoot ls-files -s)) {
    if ($line -notmatch "^([0-9]{6})\s+[0-9a-f]{40}\s+[0-9]\t(.+)$") { continue }
    $entries[$Matches[2]] = $Matches[1]
  }
  foreach ($path in @(& git -C $RepoRoot ls-files --others --exclude-standard)) {
    if (-not $entries.Contains($path)) { $entries[$path] = "100644" }
  }
  return $entries
}

function New-MIRLayoutManifest {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $paths = Read-MIRRepoPathCatalog -RepoRoot $repo
  $aliases = Read-MIRRepoAliasCatalog -RepoRoot $repo -PathCatalog $paths
  $ownership = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir/control-plane/ownership.json") | ConvertFrom-Json
  $gitEntries = Get-MIRLayoutGitEntries -RepoRoot $repo
  $rows = [Collections.Generic.List[object]]::new()

  foreach ($item in $gitEntries.GetEnumerator() | Sort-Object Key) {
    $path = ([string]$item.Key).Replace("\", "/")
    $full = Join-Path $repo $path
    [long]$bytes = if (Test-Path -LiteralPath $full -PathType Leaf) { (Get-Item -LiteralPath $full).Length } else { 0 }
    $class = Get-MIRLayoutClass -Path $path
    $owner = Get-MIRLayoutOwnership -Path $path -Ownership $ownership
    $target = Get-MIRCanonicalTarget -Path $path -Aliases $aliases -Paths $paths
    $status = if ($class -eq "unclassified" -or $owner.owner -eq "unowned") {
      "unclassified"
    } elseif ($target -ne $path -or $class.StartsWith("legacy-")) {
      "legacy"
    } else {
      "canonical"
    }
    $generated = $path -match "^(?:\.mir/(?:generated|views)/|validation/generated/|docs/reference/generated/)" -or $path -eq "todo.md"
    $rows.Add([pscustomobject][ordered]@{
      path=$path
      class=$class
      owner=$owner.owner
      writer=$owner.writer
      package_included=[bool](Test-MIRPackagePath -Path $path)
      generated=[bool]$generated
      status=$status
      canonical_target=$target
      bytes=$bytes
      git_mode=[string]$item.Value
    })
  }

  $caseCollisions = @($rows | Group-Object { $_.path.ToLowerInvariant() } | Where-Object Count -gt 1)
  $gitLinks = @($rows | Where-Object git_mode -eq "120000")
  $junctions = @(
    Get-ChildItem -LiteralPath $repo -Directory -Force -Recurse -ErrorAction SilentlyContinue |
      Where-Object {
        $_.FullName -notlike "$(Join-Path $repo '.git')*" -and
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
      }
  )
  $head = (& git -C $repo rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or $head -notmatch "^[0-9a-f]{40}$") { throw "Cannot resolve repository HEAD." }

  return [pscustomobject][ordered]@{
    schema=1
    authority="mir-layout-manifest-v1"
    generated_at=[DateTime]::UtcNow.ToString("o")
    head=$head
    entries=@($rows)
    summary=[pscustomobject][ordered]@{
      tracked=$rows.Count
      bytes=[long](($rows | Measure-Object bytes -Sum).Sum)
      package=@($rows | Where-Object package_included).Count
      legacy=@($rows | Where-Object status -eq "legacy").Count
      unclassified=@($rows | Where-Object status -eq "unclassified").Count
      case_collisions=$caseCollisions.Count
      links=($gitLinks.Count + $junctions.Count)
    }
  }
}
