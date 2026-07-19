. (Join-Path $PSScriptRoot "..\validation\PackageIdentity.ps1")

function Get-MIRAssuranceOption {
  param([string]$Name, [string]$Default = "")
  for ($i = 0; $i -lt $script:Args.Count; $i++) {
    if ($script:Args[$i] -eq $Name -and $i + 1 -lt $script:Args.Count) { return $script:Args[$i + 1] }
  }
  return $Default
}

function Get-MIRAssuranceOptionValues {
  param([string]$Name)
  $values = @()
  for ($i = 0; $i -lt $script:Args.Count; $i++) {
    if ($script:Args[$i] -eq $Name -and $i + 1 -lt $script:Args.Count) {
      $values += [string]$script:Args[$i + 1]
      $i++
    }
  }
  return @($values)
}

function Test-MIRAssuranceSwitch {
  param([string]$Name)
  return $script:Args -contains $Name
}

function Get-MIRAssuranceSha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-MIRAssuranceTextHash {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "") }
  finally { $sha.Dispose() }
}

function Get-MIRAssuranceJsonHash {
  param([Parameter(Mandatory)]$Value)
  return Get-MIRAssuranceTextHash -Text ($Value | ConvertTo-Json -Depth 40 -Compress)
}

function ConvertTo-MIRAssuranceDateTimeOffset {
  param([Parameter(Mandatory)]$Value)
  if ($Value -is [DateTimeOffset]) { return [DateTimeOffset]$Value }
  if ($Value -is [DateTime]) { return [DateTimeOffset]::new([DateTime]$Value) }
  return [DateTimeOffset]::Parse(
    [string]$Value,
    [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::RoundtripKind
  )
}

function ConvertTo-MIRAssuranceTimestampText {
  param([Parameter(Mandatory)]$Value)
  if ($Value -is [DateTimeOffset] -or $Value -is [DateTime]) {
    return (ConvertTo-MIRAssuranceDateTimeOffset -Value $Value).ToUniversalTime().ToString("o")
  }
  return [string]$Value
}

function Get-MIRAssuranceRepoRelativePath {
  param([Parameter(Mandatory)][string]$Path)
  $full = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repo $Path }
  return [IO.Path]::GetRelativePath($repo, $full).Replace("\", "/")
}

function Get-MIRAssuranceRepositoryFiles {
  if ($null -ne $script:MIRAssuranceRepositoryFilesCache) {
    return @($script:MIRAssuranceRepositoryFilesCache)
  }
  $files = @(& git -C $repo ls-files)
  if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate tracked repository files." }
  $files += @(& git -C $repo ls-files --others --exclude-standard)
  if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate untracked repository files." }
  $script:MIRAssuranceRepositoryFilesCache = @(
    $files |
      ForEach-Object { ([string]$_).Replace("\", "/") } |
      Where-Object {
        $_ -and
        $_ -notlike ".mir/target-lines/*" -and
        $_ -notlike ".mir/evidence/*" -and
        $_ -notlike "artifacts/*" -and
        $_ -notlike "build/*" -and
        $_ -notlike "out/*"
      } |
      Sort-Object -Unique
  )
  return @($script:MIRAssuranceRepositoryFilesCache)
}

function Get-MIRAssuranceEvidenceFiles {
  # Evidence is deliberately excluded from the general repository and harness
  # inventories to prevent self-invalidating fingerprints. Explicit evidence
  # inputs must still resolve to their tracked or newly authored files.
  $files = @(& git -C $repo ls-files -- .mir/evidence)
  if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate tracked release evidence files." }
  $files += @(& git -C $repo ls-files --others --exclude-standard -- .mir/evidence)
  if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate untracked release evidence files." }
  return @(
    $files |
      ForEach-Object { ([string]$_).Replace("\", "/") } |
      Where-Object { $_ -like ".mir/evidence/*" } |
      Sort-Object -Unique
  )
}

function Test-MIRAssurancePathPattern {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Pattern)
  $normalizedPath = $Path.Replace("\", "/")
  $normalizedPattern = $Pattern.Replace("\", "/")
  return $normalizedPath -like $normalizedPattern
}

function Resolve-MIRAssurancePatternFiles {
  param([Parameter(Mandatory)][string[]]$Patterns)
  $allFiles = @(Get-MIRAssuranceRepositoryFiles)
  $evidenceFiles = $null
  $matches = @()
  foreach ($patternValue in @($Patterns)) {
    $pattern = ([string]$patternValue).Replace("\", "/")
    $candidateFiles = $allFiles
    if ($pattern -like ".mir/evidence/*") {
      if ($null -eq $evidenceFiles) { $evidenceFiles = @(Get-MIRAssuranceEvidenceFiles) }
      $candidateFiles = $evidenceFiles
    }
    foreach ($file in $candidateFiles) {
      if (Test-MIRAssurancePathPattern -Path $file -Pattern $pattern) { $matches += $file }
    }
    $direct = if ([IO.Path]::IsPathRooted($pattern)) { $pattern } else { Join-Path $repo $pattern }
    if ((Test-Path -LiteralPath $direct -PathType Leaf) -and $matches -notcontains (Get-MIRAssuranceRepoRelativePath -Path $direct)) {
      $matches += Get-MIRAssuranceRepoRelativePath -Path $direct
    }
  }
  return @($matches | Sort-Object -Unique)
}

function Get-MIRAssuranceTreeHash {
  param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Paths)
  $rows = @()
  foreach ($path in @($Paths | Sort-Object -Unique)) {
    $full = if ([IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $repo $path }
    if (Test-Path -LiteralPath $full -PathType Leaf) {
      $relative = Get-MIRAssuranceRepoRelativePath -Path $full
      $item = Get-Item -LiteralPath $full
      $rows += "$relative`t$($item.Length)`t$(Get-MIRAssuranceSha256 -Path $full)"
    } else {
      $rows += "$(([string]$path).Replace('\','/'))`tMISSING"
    }
  }
  if ($rows.Count -eq 0) { $rows += "EMPTY" }
  return Get-MIRAssuranceTextHash -Text (($rows | Sort-Object) -join "`n")
}

function Get-MIRAssurancePatternHash {
  param([Parameter(Mandatory)][string[]]$Patterns)
  $files = @(Resolve-MIRAssurancePatternFiles -Patterns $Patterns)
  if ($files.Count -eq 0) {
    return Get-MIRAssuranceTextHash -Text ("NO_MATCH`n" + (($Patterns | Sort-Object -Unique) -join "`n"))
  }
  return Get-MIRAssuranceTreeHash -Paths $files
}

function Get-MIRAssuranceExternalFileFingerprint {
  param([string]$Path, [string]$MissingLabel)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return [ordered]@{ kind="external-file"; state="missing"; sha256=(Get-MIRAssuranceTextHash -Text "MISSING:$MissingLabel") }
  }
  $item = Get-Item -LiteralPath $Path
  if ($null -eq $script:MIRAssuranceExternalFileFingerprintCache) { $script:MIRAssuranceExternalFileFingerprintCache = @{} }
  $cacheKey = "$($item.FullName)|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
  if ($script:MIRAssuranceExternalFileFingerprintCache.ContainsKey($cacheKey)) {
    return $script:MIRAssuranceExternalFileFingerprintCache[$cacheKey]
  }
  $fingerprint = [ordered]@{
    kind="external-file"
    state="present"
    name=$item.Name
    size_bytes=$item.Length
    sha256=(Get-MIRAssuranceSha256 -Path $Path)
  }
  $script:MIRAssuranceExternalFileFingerprintCache[$cacheKey] = $fingerprint
  return $fingerprint
}

function Get-MIRAssuranceExternalTreeFingerprint {
  param(
    [string]$Root,
    [string[]]$RelativeRoots,
    [string]$MissingLabel
  )
  if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root -PathType Container)) {
    return [ordered]@{ kind="external-tree"; state="missing"; sha256=(Get-MIRAssuranceTextHash -Text "MISSING:$MissingLabel") }
  }
  if ($null -eq $script:MIRAssuranceExternalTreeFingerprintCache) {
    $script:MIRAssuranceExternalTreeFingerprintCache = @{}
  }
  $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
  $normalizedRoots = @($RelativeRoots | ForEach-Object { ([string]$_).Replace("\", "/") } | Sort-Object -Unique)
  $cacheKey = "$resolvedRoot`n$($normalizedRoots -join "`n")"
  if ($script:MIRAssuranceExternalTreeFingerprintCache.ContainsKey($cacheKey)) {
    return $script:MIRAssuranceExternalTreeFingerprintCache[$cacheKey]
  }
  $files = @()
  foreach ($relative in $normalizedRoots) {
    $path = Join-Path $resolvedRoot $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $files += Get-Item -LiteralPath $path
    } elseif (Test-Path -LiteralPath $path -PathType Container) {
      $files += Get-ChildItem -LiteralPath $path -Recurse -File
    }
  }
  $rows = @(
    foreach ($file in @($files | Sort-Object FullName -Unique)) {
      $relative = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace("\", "/")
      "$relative`t$($file.Length)`t$(Get-MIRAssuranceSha256 -Path $file.FullName)"
    }
  )
  $fingerprint = [ordered]@{
    kind="external-tree"
    state="present"
    root=$resolvedRoot
    file_count=$rows.Count
    sha256=(Get-MIRAssuranceTextHash -Text $(if ($rows.Count -gt 0) { $rows -join "`n" } else { "EMPTY:$MissingLabel" }))
  }
  $script:MIRAssuranceExternalTreeFingerprintCache[$cacheKey] = $fingerprint
  return $fingerprint
}

function Get-MIRAssuranceFactorioInstallationFingerprint {
  param([string]$FactorioPath)
  $binary = Get-MIRAssuranceExternalFileFingerprint -Path $FactorioPath -MissingLabel "factorio"
  if ([string]$binary.state -ne "present") {
    return [ordered]@{ kind="factorio-installation"; state="missing"; binary=$binary; sha256=[string]$binary.sha256 }
  }
  $binaryItem = Get-Item -LiteralPath $FactorioPath
  $installRoot = $binaryItem.Directory.Parent.Parent.FullName
  $data = Get-MIRAssuranceExternalTreeFingerprint -Root $installRoot -RelativeRoots @(
    "data/core",
    "data/base",
    "data/quality",
    "data/elevated-rails",
    "data/space-age"
  ) -MissingLabel "factorio-official-data"
  $material = [ordered]@{binary=$binary; official_data=$data}
  return [ordered]@{
    kind="factorio-installation"
    state="present"
    root=$installRoot
    binary=$binary
    official_data=$data
    sha256=(Get-MIRAssuranceJsonHash -Value $material)
  }
}

function Get-MIRAssuranceModClosureFingerprint {
  param([string]$ModsRoot)
  if ([string]::IsNullOrWhiteSpace($ModsRoot) -or -not (Test-Path -LiteralPath $ModsRoot -PathType Container)) {
    return [ordered]@{ kind="mod-closure"; state="missing"; mods=@(); sha256=(Get-MIRAssuranceTextHash -Text "MISSING:mod-closure") }
  }
  $mods = @(
    foreach ($file in @(Get-ChildItem -LiteralPath $ModsRoot -File -Filter "*.zip" | Sort-Object Name)) {
      [ordered]@{
        name=$file.Name
        bytes=$file.Length
        sha256=(Get-MIRAssuranceSha256 -Path $file.FullName)
        source=$file.FullName
      }
    }
  )
  return [ordered]@{
    kind="mod-closure"
    state="present"
    root=$ModsRoot
    mods=$mods
    sha256=(Get-MIRAssuranceJsonHash -Value $mods)
  }
}

function Get-MIRAssuranceCandidateDescriptor {
  param([Parameter(Mandatory)]$Context)
  if (-not $Context.candidate -or -not (Test-Path -LiteralPath $Context.candidate -PathType Leaf)) {
    $descriptor = [ordered]@{
      state="missing"
      path=[string]$Context.candidate
      sha256=(Get-MIRAssuranceTextHash -Text "MISSING:candidate")
      content_sha256=(Get-MIRAssuranceTextHash -Text "MISSING:candidate-content")
      bytes=0
    }
    $descriptor["descriptor_sha256"] = Get-MIRAssuranceJsonHash -Value $descriptor
    return $descriptor
  }
  $item = Get-Item -LiteralPath $Context.candidate
  $descriptor = [ordered]@{
    state="present"
    path=(Get-MIRAssuranceRepoRelativePath -Path $item.FullName)
    bytes=$item.Length
    sha256=(Get-MIRAssuranceSha256 -Path $item.FullName)
    content_sha256=(Get-MIRAssuranceZipContentHash -Path $item.FullName)
  }
  $descriptor["descriptor_sha256"] = Get-MIRAssuranceJsonHash -Value $descriptor
  return $descriptor
}

function Get-MIRAssurancePackageSourceCommit {
  $head = (& git -C $repo rev-parse HEAD).Trim()
  $sourceLockPath = Join-Path $repo ".mir\backport-source-lock.json"
  if (-not (Test-Path -LiteralPath $sourceLockPath -PathType Leaf)) { return $head }
  $sourceLock = Get-Content -Raw -LiteralPath $sourceLockPath | ConvertFrom-Json
  $candidateCommit = [string]$sourceLock.candidate_package_source_commit
  if ($candidateCommit -notmatch '^[0-9a-f]{40}$') { return $head }
  & git -C $repo merge-base --is-ancestor $candidateCommit HEAD
  if ($LASTEXITCODE -ne 0) { throw "Candidate package-source commit is not an ancestor of HEAD: $candidateCommit" }
  . (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
  $roots = @(Get-MIRPackageSourceRoots)
  & git -C $repo diff --quiet $candidateCommit HEAD -- @roots
  if ($LASTEXITCODE -ne 0) { throw "Package-visible source changed after the locked candidate package-source commit." }
  if (Test-MIRPackageSourceGitDirty -RepoRoot $repo) {
    throw "Package-visible source is dirty relative to the locked candidate package-source commit."
  }
  return $candidateCommit
}

function Get-MIRAssurancePackageFiles {
  . (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
  return @(Get-MIRPackageSourceFiles -RepoRoot $repo | ForEach-Object { ([string]$_).Replace("\", "/") })
}

function Get-MIRAssuranceRunnerHash {
  if ($script:MIRAssuranceRunnerHashCache) { return $script:MIRAssuranceRunnerHashCache }
  $files = @(Resolve-MIRAssurancePatternFiles -Patterns @("scripts/**", "tools/mir_verify/**", "verification/schema/**"))
  $script:MIRAssuranceRunnerHashCache = Get-MIRAssuranceTreeHash -Paths $files
  return $script:MIRAssuranceRunnerHashCache
}

function Get-MIRAssuranceHarnessFiles {
  return @(Resolve-MIRAssurancePatternFiles -Patterns @(
    "scripts/**",
    "fixtures/**",
    ".mir/test-impact.yml",
    ".mir/targets.json",
    ".mir/assurance.json",
    "validation/tests.yml",
    "validation/domains.yml",
    "validation/profiles/**",
    "validation/trust.json",
    "verification/schema/**",
    "tools/mir_verify/**"
  ))
}

function Get-MIRAssuranceZipContentHash {
  param([Parameter(Mandatory)][string]$Path)
  return Get-MIRZipContentFingerprint -Path $Path
}

function Resolve-MIRAssurancePath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  if ([IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $repo $Path
}

function Get-MIRAssuranceContext {
  $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
  $catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
  $info = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json
  $target = Get-MIRAssuranceOption -Name "--target" -Default ([string]$config.default_target)
  $candidate = Resolve-MIRAssurancePath -Path (Get-MIRAssuranceOption -Name "--candidate" -Default (Join-Path $repo "dist\$($info.name)_$($info.version).zip"))
  $factorio = Resolve-MIRAssurancePath -Path (Get-MIRAssuranceOption -Name "--factorio" -Default ([string]$env:FACTORIO_BIN))
  $priorRelease = Resolve-MIRAssurancePath -Path (Get-MIRAssuranceOption -Name "--prior" -Default ([string]$env:MIR_PRIOR_RELEASE))
  $seal = Resolve-MIRAssurancePath -Path (Get-MIRAssuranceOption -Name "--seal")
  $mods = Resolve-MIRAssurancePath -Path (Get-MIRAssuranceOption -Name "--mods" -Default ([string]$env:MIR_MOD_LIBRARY))
  if (-not $mods) {
    $defaultMods = "C:\Projects\Factorio\testmods_$target"
    if (Test-Path -LiteralPath $defaultMods -PathType Container) { $mods = $defaultMods }
  }
  $trustPolicy = Get-Content -Raw -LiteralPath $trustPath | ConvertFrom-Json
  if ([int]$trustPolicy.schema -ne 1) { throw "Verification trust policy schema must be 1." }
  $verificationProfile = Get-MIRAssuranceVerificationProfile -Target $target
  return [pscustomobject]@{
    config=$config
    catalog=$catalog
    info=$info
    target=$target
    candidate=$candidate
    factorio=$factorio
    prior_release=$priorRelease
    seal=$seal
    mods=$mods
    trust_policy=$trustPolicy
    trust_class=(Get-MIRAssuranceCurrentTrustClass)
    verification_profile=$verificationProfile
    reuse_enabled=(-not (Test-MIRAssuranceSwitch -Name "--no-reuse"))
    rerun_tests=@(Get-MIRAssuranceOptionValues -Name "--rerun")
  }
}

function Write-MIRAssuranceJsonFile {
  param(
    [Parameter(Mandatory)]$Value,
    [Parameter(Mandatory)][string]$Path
  )
  $json = $Value | ConvertTo-Json -Depth 40
  $output = Resolve-MIRAssurancePath -Path $Path
  $parent = Split-Path -Parent $output
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  [IO.File]::WriteAllText($output, $json + "`n", [Text.UTF8Encoding]::new($false))
  Write-Host "Wrote $output"
  return $output
}

function Write-MIRAssuranceTiming {
  param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)]$Stopwatch)
  if ($env:MIR_ASSURANCE_TIMING) {
    Write-Host ("[assurance-timing] {0} {1:N3}s" -f $Label, $Stopwatch.Elapsed.TotalSeconds)
  }
}

function Write-MIRAssuranceJson {
  param([Parameter(Mandatory)]$Value, [string]$DefaultPath = "")
  $json = $Value | ConvertTo-Json -Depth 40
  $output = Get-MIRAssuranceOption -Name "--output" -Default $DefaultPath
  if ($output) { $output = Write-MIRAssuranceJsonFile -Value $Value -Path $output }
  if ((Test-MIRAssuranceSwitch -Name "--json") -or -not $output) { $json | Write-Output }
}

function Resolve-MIRAssuranceBaseline {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
  $path = Resolve-MIRAssurancePath -Path $Value
  if ($Value.EndsWith(".json") -and (Test-Path -LiteralPath $path -PathType Leaf)) {
    $seal = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$seal.source_commit)) { throw "Baseline seal has no source_commit: $Value" }
    return [string]$seal.source_commit
  }
  return $Value
}

function Get-MIRAssuranceChangedPaths {
  param([string]$Baseline)
  $paths = @()
  if ($Baseline) {
    $paths += @(& git -C $repo diff --name-only "$Baseline...HEAD" --)
    if ($LASTEXITCODE -ne 0) { throw "Unable to diff assurance baseline $Baseline." }
    $paths += @(& git -C $repo diff --name-only HEAD --)
    $paths += @(& git -C $repo diff --cached --name-only)
  } else {
    $paths += @(& git -C $repo diff --name-only HEAD --)
    $paths += @(& git -C $repo diff --cached --name-only)
  }
  $status = @(& git -C $repo status --porcelain --untracked-files=all)
  foreach ($line in $status) {
    if ($line.Length -ge 4) {
      $value = $line.Substring(3)
      if ($value -match " -> ") { $value = ($value -split " -> ")[-1] }
      $paths += $value
    }
  }
  return @($paths | ForEach-Object { ([string]$_).Replace("\", "/") } | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-MIRAssuranceClassification {
  param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Paths, [Parameter(Mandatory)]$Config)
  $classes = @()
  $tests = @()
  $unknown = @()
  foreach ($path in $Paths) {
    $matched = @()
    foreach ($class in $Config.classes) {
      foreach ($pattern in $class.patterns) {
        if ($path -match [string]$pattern) {
          $matched += [string]$class.id
          $tests += @($class.tests)
          break
        }
      }
    }
    if ($matched.Count -eq 0) { $unknown += $path }
    $classes += $matched
  }
  if ($unknown.Count -gt 0) {
    $classes += "unknown"
    $tests += @($Config.unknown_policy.tests)
  }
  return [ordered]@{
    paths=@($Paths)
    classes=@($classes | Sort-Object -Unique)
    tests=@($tests | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    unknown_paths=@($unknown | Sort-Object -Unique)
    escalated=($unknown.Count -gt 0)
  }
}

function Get-MIRAssuranceImpactSelection {
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Paths,
    [Parameter(Mandatory)]$Config
  )
  $manifest = Get-Content -Raw -LiteralPath $impactPath | ConvertFrom-Json
  if ([int]$manifest.schema -ne 1) { throw "Test-impact manifest schema must be 1." }
  $scenarios = @($manifest.baseline_scenarios | ForEach-Object { [string]$_ })
  $groups = @()
  $tags = @()
  $mapped = @()
  $unmappedRuntimePaths = @()
  $runtimeImpactClasses = @("runtime-or-migration", "settings", "compiler-data-stage", "balance", "metadata-dependencies", "test-harness")
  foreach ($path in $Paths) {
    $matchedRule = $false
    foreach ($rule in @($manifest.paths)) {
      if (Test-MIRAssurancePathPattern -Path $path -Pattern ([string]$rule.pattern)) {
        $matchedRule = $true
        $mapped += $path
        $scenarios += @($rule.scenarios | ForEach-Object { [string]$_ })
        $groups += @($rule.groups | ForEach-Object { [string]$_ })
        $tags += @($rule.tags | ForEach-Object { [string]$_ })
      }
    }
    if (-not $matchedRule) {
      $pathClassification = Get-MIRAssuranceClassification -Paths @($path) -Config $Config
      if (@($pathClassification.classes | Where-Object { $runtimeImpactClasses -contains [string]$_ }).Count -gt 0) {
        $unmappedRuntimePaths += $path
      }
    }
  }
  return [ordered]@{
    schema=1
    scenarios=@($scenarios | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
    groups=@($groups | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
    tags=@($tags | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
    mapped_paths=@($mapped | Sort-Object -Unique)
    unmapped_runtime_paths=@($unmappedRuntimePaths | Sort-Object -Unique)
    requires_full=($unmappedRuntimePaths.Count -gt 0)
  }
}

function Get-MIRAssurancePlan {
  param([Parameter(Mandatory)]$Context)
  $timing = [Diagnostics.Stopwatch]::StartNew()
  $baseline = Resolve-MIRAssuranceBaseline -Value (Get-MIRAssuranceOption -Name "--baseline")
  $paths = @(Get-MIRAssuranceChangedPaths -Baseline $baseline)
  Write-MIRAssuranceTiming -Label "changed-paths" -Stopwatch $timing
  $classification = Get-MIRAssuranceClassification -Paths $paths -Config $Context.config
  $impactSelection = Get-MIRAssuranceImpactSelection -Paths $paths -Config $Context.config
  Write-MIRAssuranceTiming -Label "classification" -Stopwatch $timing
  $profile = Get-MIRAssuranceOption -Name "--profile" -Default "auto"
  $profileProperty = $Context.config.profiles.PSObject.Properties[$profile]
  if ($null -eq $profileProperty) { throw "Unknown assurance profile: $profile" }
  $testIds = @()
  if ($profile -eq "auto") {
    $testIds = @($classification.tests)
  } else {
    $testIds = @($profileProperty.Value | ForEach-Object { [string]$_ })
  }
  if ($classification.escalated) {
    $testIds += @($Context.config.unknown_policy.tests | ForEach-Object { [string]$_ })
  }
  if ($impactSelection.requires_full -and $testIds -contains "runtime.affected") {
    $expandedImpactTests = @()
    foreach ($testIdValue in $testIds) {
      if ([string]$testIdValue -eq "runtime.affected") { $expandedImpactTests += "runtime.full" }
      else { $expandedImpactTests += [string]$testIdValue }
    }
    $testIds = $expandedImpactTests
  }
  $orderedTestIds = @()
  $seenTestIds = @{}
  foreach ($testIdValue in $testIds) {
    $testId = [string]$testIdValue
    if (-not $seenTestIds.ContainsKey($testId)) {
      $seenTestIds[$testId] = $true
      $orderedTestIds += $testId
    }
  }
  $testIds = $orderedTestIds
  $catalogById = @{}
  foreach ($test in $Context.catalog.tests) { $catalogById[[string]$test.id] = $test }
  $selectedDefinitions = @()
  foreach ($id in $testIds) {
    if (-not $catalogById.ContainsKey($id)) { throw "Unknown assurance test ID: $id" }
    $selectedDefinitions += $catalogById[$id]
  }
  $expanded = @(Expand-MIRAssuranceTests -Tests $selectedDefinitions -Context $Context -ImpactSelection $impactSelection)
  Write-MIRAssuranceTiming -Label "expanded-tests" -Stopwatch $timing
  $plan = [ordered]@{
    schema=4
    policy_id=[string]$Context.verification_profile.policy_id
    generated_at=(Get-Date).ToUniversalTime().ToString("o")
    target=$Context.target
    profile=$profile
    baseline=$baseline
    candidate=$Context.candidate
    classification=$classification
    impact_selection=$impactSelection
    tests=@($expanded)
    requires_factorio=(@($expanded | Where-Object { $_.requires_factorio }).Count -gt 0)
    reuse_enabled=[bool]$Context.reuse_enabled
    rerun_tests=@($Context.rerun_tests)
    source_commit=(& git -C $repo rev-parse HEAD).Trim()
    source_tree=(& git -C $repo rev-parse "HEAD^{tree}").Trim()
    package_source_commit=(Get-MIRAssurancePackageSourceCommit)
    candidate_descriptor=(Get-MIRAssuranceCandidateDescriptor -Context $Context)
    package_source_sha256=(Get-MIRAssuranceTreeHash -Paths (Get-MIRAssurancePackageFiles))
    test_catalog_sha256=(Get-MIRAssuranceSha256 -Path $catalogPath)
    validation_harness_sha256=(Get-MIRAssuranceTreeHash -Paths (Get-MIRAssuranceHarnessFiles))
    verification_profile_sha256=(Get-MIRAssuranceSha256 -Path (Get-MIRAssuranceVerificationProfilePath -Target $Context.target))
    domain_policy_sha256=(Get-MIRAssuranceSha256 -Path $domainsPath)
    trust_policy_sha256=(Get-MIRAssuranceSha256 -Path $trustPath)
    producer=(Get-MIRAssuranceProducer)
  }
  Write-MIRAssuranceTiming -Label "plan-inputs" -Stopwatch $timing
  if (@($expanded | Where-Object { $_.kind -eq "factorio-scenario" }).Count -gt 0) {
    $plan["domain_manifest"] = Get-MIRAssuranceDomainManifest -Context $Context -RequireCandidate
  }
  $plan = Add-MIRAssurancePlanDecisions -Plan $plan -Context $Context
  Write-MIRAssuranceTiming -Label "fingerprints" -Stopwatch $timing
  $plan = Complete-MIRAssurancePlan -Plan $plan -Context $Context
  Write-MIRAssuranceTiming -Label "complete-plan" -Stopwatch $timing
  return $plan
}
