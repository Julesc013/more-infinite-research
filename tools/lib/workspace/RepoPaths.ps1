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
    if (-not ([string]$alias.from).EndsWith("/")) { throw "Alias prefix must end in '/': $($alias.from)" }
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
  $match = @($aliases.aliases | Where-Object { $Path.StartsWith([string]$_.from, [StringComparison]::Ordinal) } |
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
  $alias = @($Aliases.aliases | Where-Object { $Path.StartsWith([string]$_.from, [StringComparison]::Ordinal) } |
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
  foreach ($row in @($Ownership.owners)) {
    if (Test-MIRLayoutGlob -Path $Path -Pattern ([string]$row.pattern)) {
      return [pscustomobject]@{
        owner=[string]$row.module
        writer=(@($row.writes | ForEach-Object { [string]$_ }) -join ",")
      }
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
