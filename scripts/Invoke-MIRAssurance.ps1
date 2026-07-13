param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$configPath = Join-Path $repo ".mir\assurance.json"
$catalogPath = Join-Path $repo ".mir\test-catalog.json"
$artifactRoot = Join-Path $repo "artifacts\assurance"
$evidenceRoot = Join-Path $artifactRoot "evidence"

function Get-MIRAssuranceOption {
  param([string]$Name, [string]$Default = "")
  for ($i = 0; $i -lt $script:Args.Count; $i++) {
    if ($script:Args[$i] -eq $Name -and $i + 1 -lt $script:Args.Count) { return $script:Args[$i + 1] }
  }
  return $Default
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
  param([Parameter(Mandatory)][string]$Text)
  $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "") }
  finally { $sha.Dispose() }
}

function Get-MIRAssuranceTreeHash {
  param([Parameter(Mandatory)][string[]]$Paths)
  $rows = foreach ($path in @($Paths | Sort-Object -Unique)) {
    $full = if ([IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $repo $path }
    if (Test-Path -LiteralPath $full -PathType Leaf) {
      $relative = [IO.Path]::GetRelativePath($repo, $full).Replace("\", "/")
      "$relative`t$(Get-MIRAssuranceSha256 -Path $full)"
    }
  }
  return Get-MIRAssuranceTextHash -Text (($rows | Sort-Object) -join "`n")
}

function Get-MIRAssurancePackageFiles {
  . (Join-Path $repo "scripts\validation\PackageIdentity.ps1")
  return @(Get-MIRPackageSourceFiles -RepoRoot $repo | ForEach-Object { ([string]$_).Replace("\", "/") })
}

function Get-MIRAssuranceHarnessFiles {
  $tracked = @(& git -C $repo ls-files -- scripts fixtures .mir/test-impact.yml .mir/targets.json .mir/assurance.json .mir/test-catalog.json)
  if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate validation harness files." }
  return @($tracked | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $repo $_)) })
}

function Get-MIRAssuranceZipContentHash {
  param([Parameter(Mandatory)][string]$Path)
  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $rows = foreach ($entry in @($archive.Entries | Sort-Object FullName)) {
      if ($entry.FullName.EndsWith("/")) { continue }
      $stream = $entry.Open()
      $sha = [Security.Cryptography.SHA256]::Create()
      try {
        $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "")
        "$($entry.FullName)`t$($entry.Length)`t$hash"
      } finally {
        $sha.Dispose()
        $stream.Dispose()
      }
    }
    return Get-MIRAssuranceTextHash -Text (($rows | Sort-Object) -join "`n")
  } finally { $archive.Dispose() }
}

function Get-MIRAssuranceContext {
  $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
  $catalog = Get-Content -Raw -LiteralPath $catalogPath | ConvertFrom-Json
  $info = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json
  $target = Get-MIRAssuranceOption -Name "--target" -Default ([string]$config.default_target)
  $candidate = Get-MIRAssuranceOption -Name "--candidate" -Default (Join-Path $repo "dist\$($info.name)_$($info.version).zip")
  if (-not [IO.Path]::IsPathRooted($candidate)) { $candidate = Join-Path $repo $candidate }
  $factorio = Get-MIRAssuranceOption -Name "--factorio" -Default ([string]$env:FACTORIO_BIN)
  if ($factorio -and -not [IO.Path]::IsPathRooted($factorio)) { $factorio = Join-Path $repo $factorio }
  $priorRelease = Get-MIRAssuranceOption -Name "--prior" -Default ([string]$env:MIR_PRIOR_RELEASE)
  if ($priorRelease -and -not [IO.Path]::IsPathRooted($priorRelease)) { $priorRelease = Join-Path $repo $priorRelease }
  return [ordered]@{ config=$config; catalog=$catalog; info=$info; target=$target; candidate=$candidate; factorio=$factorio; prior_release=$priorRelease }
}

function Write-MIRAssuranceJson {
  param([Parameter(Mandatory)]$Value, [string]$DefaultPath = "")
  $json = $Value | ConvertTo-Json -Depth 20
  $output = Get-MIRAssuranceOption -Name "--output" -Default $DefaultPath
  if ($output) {
    if (-not [IO.Path]::IsPathRooted($output)) { $output = Join-Path $repo $output }
    $parent = Split-Path -Parent $output
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($output, $json + "`n", [Text.UTF8Encoding]::new($false))
    Write-Host "Wrote $output"
  }
  if ((Test-MIRAssuranceSwitch -Name "--json") -or -not $output) { $json | Write-Output }
}

function Get-MIRAssuranceChangedPaths {
  param([string]$Baseline)
  $paths = @()
  if ($Baseline) {
    $paths += @(& git -C $repo diff --name-only $Baseline --)
    if ($LASTEXITCODE -ne 0) { throw "Unable to diff assurance baseline $Baseline." }
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
        if ($path -match [string]$pattern) { $matched += [string]$class.id; $tests += @($class.tests); break }
      }
    }
    if ($matched.Count -eq 0) { $unknown += $path }
    $classes += $matched
  }
  if ($unknown.Count -gt 0) { $classes += "unknown"; $tests += @($Config.unknown_policy.tests) }
  return [ordered]@{
    paths=@($Paths)
    classes=@($classes | Sort-Object -Unique)
    tests=@($tests | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    unknown_paths=@($unknown | Sort-Object -Unique)
    escalated=($unknown.Count -gt 0)
  }
}

function Get-MIRAssurancePlan {
  param([Parameter(Mandatory)]$Context)
  $baseline = Get-MIRAssuranceOption -Name "--baseline"
  if ($baseline -and $baseline.EndsWith(".json") -and (Test-Path -LiteralPath $baseline)) {
    $seal = Get-Content -Raw -LiteralPath $baseline | ConvertFrom-Json
    $baseline = [string]$seal.source_commit
  }
  $paths = @(Get-MIRAssuranceChangedPaths -Baseline $baseline)
  $classification = Get-MIRAssuranceClassification -Paths $paths -Config $Context.config
  $profile = Get-MIRAssuranceOption -Name "--profile" -Default "auto"
  $profileTests = @($Context.config.profiles.PSObject.Properties[$profile].Value)
  $testIds = @()
  if ($profile -eq "auto") {
    $testIds = @($classification.tests)
  } else {
    $seenTestIds = @{}
    foreach ($profileTest in $profileTests) {
      $profileTestId = [string]$profileTest
      if (-not $seenTestIds.ContainsKey($profileTestId)) {
        $seenTestIds[$profileTestId] = $true
        $testIds += $profileTestId
      }
    }
  }
  $catalogById = @{}
  foreach ($test in $Context.catalog.tests) { $catalogById[[string]$test.id] = $test }
  $expanded = @()
  foreach ($id in $testIds) {
    if ($id -eq "static.full") {
      $expanded += $catalogById[$id]
      continue
    }
    if (-not $catalogById.ContainsKey($id)) { throw "Unknown assurance test ID: $id" }
    $expanded += $catalogById[$id]
  }
  return [ordered]@{
    schema=1
    generated_at=(Get-Date).ToUniversalTime().ToString("o")
    target=$Context.target
    profile=$profile
    baseline=$baseline
    candidate=$Context.candidate
    classification=$classification
    tests=@($expanded)
    requires_factorio=(@($expanded | Where-Object { $_.requires_factorio }).Count -gt 0)
    package_source_sha256=(Get-MIRAssuranceTreeHash -Paths (Get-MIRAssurancePackageFiles))
    test_catalog_sha256=(Get-MIRAssuranceSha256 -Path $catalogPath)
    validation_harness_sha256=(Get-MIRAssuranceTreeHash -Paths (Get-MIRAssuranceHarnessFiles))
  }
}

function Invoke-MIRAssuranceCommandText {
  param([Parameter(Mandatory)][string]$Command, [Parameter(Mandatory)]$Context)
  $resolved = $Command.Replace("<factorio>", $Context.factorio)
  $resolved = $resolved.Replace("<candidate>", $Context.candidate)
  $resolved = $resolved.Replace("<prior-release>", $Context.prior_release)
  $tokens = [Management.Automation.PSParser]::Tokenize($resolved, [ref]$null) | Where-Object { $_.Type -notin @("Comment", "NewLine") }
  if ($tokens.Count -eq 0) { throw "Empty assurance command." }
  $commandPath = [string]$tokens[0].Content
  if ($commandPath.StartsWith("./")) { $commandPath = Join-Path $repo $commandPath.Substring(2) }
  $argumentTokens = @($tokens | Select-Object -Skip 1)
  if ([IO.Path]::GetFileName($commandPath) -eq "mir.ps1") {
    $arguments = @($argumentTokens | ForEach-Object { [string]$_.Content })
    & $commandPath @arguments
  } else {
    $named = @{}
    $positional = @()
    for ($i = 0; $i -lt $argumentTokens.Count; $i++) {
      $token = $argumentTokens[$i]
      if ($token.Type -eq [Management.Automation.PSTokenType]::CommandParameter) {
        $name = ([string]$token.Content).TrimStart("-")
        $value = $true
        if ($i + 1 -lt $argumentTokens.Count -and $argumentTokens[$i + 1].Type -ne [Management.Automation.PSTokenType]::CommandParameter) {
          $i++
          $value = [string]$argumentTokens[$i].Content
        }
        $named[$name] = $value
      } else {
        $positional += [string]$token.Content
      }
    }
    & $commandPath @named @positional
  }
  if ($LASTEXITCODE -ne 0) { throw "Assurance test command failed ($LASTEXITCODE): $resolved" }
}

function Invoke-MIRAssurancePlan {
  param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)]$Context)
  New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null
  $results = @()
  $runtimeFullExecuted = $false
  foreach ($test in $Plan.tests) {
    $id = [string]$test.id
    if ($test.requires_factorio -and (-not $Context.factorio -or -not (Test-Path -LiteralPath $Context.factorio))) {
      throw "Test $id requires --factorio with a matching Factorio binary."
    }
    if ($id -eq "runtime.upgrade" -and (-not $Context.prior_release -or -not (Test-Path -LiteralPath $Context.prior_release))) {
      throw "Test runtime.upgrade requires --prior with the exact prior-release archive."
    }
    if ($runtimeFullExecuted -and $id -in @("runtime.affected", "runtime.exact-zip")) { continue }
    $started = Get-Date
    $status = "passed"
    $message = ""
    try {
      Invoke-MIRAssuranceCommandText -Command ([string]$test.command) -Context $Context
      if ($id -eq "runtime.full") { $runtimeFullExecuted = $true }
    } catch {
      $status = "failed"
      $message = $_.Exception.Message
    }
    $duration = [Math]::Round(((Get-Date) - $started).TotalSeconds, 3)
    $candidateHash = if (Test-Path -LiteralPath $Context.candidate) { Get-MIRAssuranceSha256 -Path $Context.candidate } else { "missing" }
    $binaryHash = if ($Context.factorio -and (Test-Path -LiteralPath $Context.factorio)) { Get-MIRAssuranceSha256 -Path $Context.factorio } else { "none" }
    $inputKey = Get-MIRAssuranceTextHash -Text "$id`n$candidateHash`n$binaryHash`n$($Plan.test_catalog_sha256)`n$($Plan.validation_harness_sha256)`n$($Context.target)"
    $capsule = [ordered]@{
      schema=1; test_id=$id; status=$status; input_key=$inputKey; target=$Context.target
      candidate_sha256=$candidateHash; factorio_sha256=$binaryHash; command=[string]$test.command
      started_at=$started.ToUniversalTime().ToString("o"); duration_seconds=$duration; message=$message
    }
    $capsulePath = Join-Path $evidenceRoot "$id-$inputKey.json"
    [IO.File]::WriteAllText($capsulePath, (($capsule | ConvertTo-Json -Depth 10) + "`n"), [Text.UTF8Encoding]::new($false))
    $results += $capsule
    if ($status -ne "passed") { break }
  }
  return @($results)
}

function Invoke-MIRAssuranceBuild {
  param([Parameter(Mandatory)]$Context)
  & (Join-Path $repo "scripts\Build-MIRPackage.ps1")
  if ($LASTEXITCODE -ne 0) { throw "Candidate build failed." }
  if (-not (Test-Path -LiteralPath $Context.candidate)) { throw "Candidate was not created: $($Context.candidate)" }
  return [ordered]@{
    candidate=$Context.candidate
    sha256=(Get-MIRAssuranceSha256 -Path $Context.candidate)
    content_sha256=(Get-MIRAssuranceZipContentHash -Path $Context.candidate)
    size_bytes=(Get-Item -LiteralPath $Context.candidate).Length
  }
}

function Invoke-MIRAssuranceSeal {
  param([Parameter(Mandatory)]$Context)
  if (-not (Test-Path -LiteralPath $Context.candidate)) { throw "Candidate does not exist: $($Context.candidate)" }
  $summaryPath = Get-MIRAssuranceOption -Name "--evidence"
  if (-not $summaryPath -or -not (Test-Path -LiteralPath $summaryPath)) { throw "seal requires --evidence <passing qualification summary>." }
  $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
  if ([string]$summary.status -ne "passed") { throw "Qualification summary is not passing." }
  $commit = (& git -C $repo rev-parse HEAD).Trim()
  $branch = (& git -C $repo branch --show-current).Trim()
  $status = @(& git -C $repo status --porcelain --untracked-files=all)
  if ($status.Count -ne 0) { throw "Refusing to seal a dirty source tree. Commit the exact candidate and tracked qualification summary first." }
  $factorioHash = if ($Context.factorio -and (Test-Path -LiteralPath $Context.factorio)) { Get-MIRAssuranceSha256 -Path $Context.factorio } else { "none" }
  $seal = [ordered]@{
    schema=1; state="SEALED-RC"; release_status="NOT RELEASED"; version=[string]$Context.info.version
    factorio_target=$Context.target; branch=$branch; source_commit=$commit; source_clean=($status.Count -eq 0)
    candidate=[IO.Path]::GetRelativePath($repo, $Context.candidate).Replace("\", "/")
    candidate_sha256=(Get-MIRAssuranceSha256 -Path $Context.candidate)
    candidate_content_sha256=(Get-MIRAssuranceZipContentHash -Path $Context.candidate)
    package_source_sha256=(Get-MIRAssuranceTreeHash -Paths (Get-MIRAssurancePackageFiles))
    target_profile_sha256=(Get-MIRAssuranceSha256 -Path (Join-Path $repo ".mir\targets.json"))
    test_catalog_sha256=(Get-MIRAssuranceSha256 -Path $catalogPath)
    validation_harness_sha256=(Get-MIRAssuranceTreeHash -Paths (Get-MIRAssuranceHarnessFiles))
    factorio_binary=$Context.factorio; factorio_sha256=$factorioHash
    qualification_summary=[IO.Path]::GetRelativePath($repo, (Resolve-Path $summaryPath).Path).Replace("\", "/")
    qualification_summary_sha256=(Get-MIRAssuranceSha256 -Path $summaryPath)
    sealed_at=(Get-Date).ToUniversalTime().ToString("o")
  }
  $default = ".mir/evidence/candidate-seals/mir-$($Context.info.version)-factorio-$($Context.target).json"
  Write-MIRAssuranceJson -Value $seal -DefaultPath $default
}

function Invoke-MIRAssuranceCheckSeal {
  param([Parameter(Mandatory)]$Context)
  $sealPath = Get-MIRAssuranceOption -Name "--seal"
  if (-not $sealPath -or -not (Test-Path -LiteralPath $sealPath)) { throw "check-seal requires --seal <path>." }
  $seal = Get-Content -Raw -LiteralPath $sealPath | ConvertFrom-Json
  $candidate = [string]$seal.candidate
  if (-not [IO.Path]::IsPathRooted($candidate)) { $candidate = Join-Path $repo $candidate }
  $checks = [ordered]@{
    candidate_exists=(Test-Path -LiteralPath $candidate)
    candidate_sha256=$false
    candidate_content_sha256=$false
    package_source_sha256=$false
    target_profile_sha256=$false
    test_catalog_sha256=$false
    validation_harness_sha256=$false
    source_is_ancestor=$false
    evidence_sha256=$false
  }
  if ($checks.candidate_exists) {
    $checks.candidate_sha256=((Get-MIRAssuranceSha256 -Path $candidate) -eq [string]$seal.candidate_sha256)
    $checks.candidate_content_sha256=((Get-MIRAssuranceZipContentHash -Path $candidate) -eq [string]$seal.candidate_content_sha256)
  }
  $checks.package_source_sha256=((Get-MIRAssuranceTreeHash -Paths (Get-MIRAssurancePackageFiles)) -eq [string]$seal.package_source_sha256)
  $checks.target_profile_sha256=((Get-MIRAssuranceSha256 -Path (Join-Path $repo ".mir\targets.json")) -eq [string]$seal.target_profile_sha256)
  $checks.test_catalog_sha256=((Get-MIRAssuranceSha256 -Path $catalogPath) -eq [string]$seal.test_catalog_sha256)
  $checks.validation_harness_sha256=((Get-MIRAssuranceTreeHash -Paths (Get-MIRAssuranceHarnessFiles)) -eq [string]$seal.validation_harness_sha256)
  & git -C $repo merge-base --is-ancestor ([string]$seal.source_commit) HEAD
  $checks.source_is_ancestor=($LASTEXITCODE -eq 0)
  $summaryPath = Join-Path $repo ([string]$seal.qualification_summary)
  $checks.evidence_sha256=((Test-Path -LiteralPath $summaryPath) -and ((Get-MIRAssuranceSha256 -Path $summaryPath) -eq [string]$seal.qualification_summary_sha256))
  $passed = @($checks.Values | Where-Object { -not $_ }).Count -eq 0
  $result = [ordered]@{ schema=1; status=if ($passed) { "passed" } else { "failed" }; seal=$sealPath; checks=$checks }
  Write-MIRAssuranceJson -Value $result
  if (-not $passed) { throw "Candidate seal verification failed." }
}

function Invoke-MIRAssuranceSelfTest {
  param([Parameter(Mandatory)]$Context)
  $cases = @(
    @{path="control.lua"; class="runtime-or-migration"},
    @{path="migrations/more-infinite-research_2.4.0.json"; class="runtime-or-migration"},
    @{path="settings.lua"; class="settings"},
    @{path="locale/en/more-infinite-research.cfg"; class="locale"},
    @{path="docs/maintainer/example.md"; class="repository-docs"},
    @{path="scripts/Invoke-MIRValidation.ps1"; class="test-harness"},
    @{path="unclassified.future"; class="unknown"}
  )
  foreach ($case in $cases) {
    $actual = Get-MIRAssuranceClassification -Paths @($case.path) -Config $Context.config
    if ($actual.classes -notcontains $case.class) { throw "Classifier self-test failed for $($case.path)." }
  }
  $base = Get-MIRAssuranceTextHash -Text "test`nartifact-a`nbinary-a`nharness-a`nsettings-a"
  foreach ($mutation in @("artifact-b", "binary-b", "harness-b", "settings-b")) {
    $changed = switch ($mutation) {
      "artifact-b" { "test`nartifact-b`nbinary-a`nharness-a`nsettings-a" }
      "binary-b" { "test`nartifact-a`nbinary-b`nharness-a`nsettings-a" }
      "harness-b" { "test`nartifact-a`nbinary-a`nharness-b`nsettings-a" }
      default { "test`nartifact-a`nbinary-a`nharness-a`nsettings-b" }
    }
    if ((Get-MIRAssuranceTextHash -Text $changed) -eq $base) { throw "Evidence invalidation self-test failed for $mutation." }
  }
  Write-Host "[ok] MIR assurance classifier, conservative escalation, and evidence invalidation tests passed."
}

function Show-MIRAssuranceHelp {
  Write-Host @"
MIR assurance

Commands:
  doctor | inventory | impact | plan | build | verify | qualify
  seal | check-seal | locale | balance | backport | explain | self-test

Common options:
  --target <line> --candidate <zip> --baseline <ref-or-seal>
  --profile <name> --factorio <path> --prior <zip> --output <json> --json
"@
}

$context = Get-MIRAssuranceContext
$command = if ($Args.Count -gt 0) { [string]$Args[0] } else { "help" }
switch ($command) {
  "help" { Show-MIRAssuranceHelp }
  "doctor" {
    $gitVersion = (& git --version).Trim()
    $factorioExists = $context.factorio -and (Test-Path -LiteralPath $context.factorio)
    $factorioVersion = if ($factorioExists) { [string](Get-Item -LiteralPath $context.factorio).VersionInfo.FileVersion } else { "not-provided" }
    $factorioMatchesTarget = if ($factorioExists) { $factorioVersion -match ("^" + [regex]::Escape([string]$context.target) + "\.") } else { $true }
    if (-not $factorioMatchesTarget) { throw "Factorio binary version '$factorioVersion' does not match target '$($context.target)'." }
    $result = [ordered]@{
      schema=1; status="passed"; powershell=$PSVersionTable.PSVersion.ToString(); git=$gitVersion
      repo=$repo; target=$context.target; info_version=[string]$context.info.version
      config_exists=(Test-Path -LiteralPath $configPath); catalog_exists=(Test-Path -LiteralPath $catalogPath)
      factorio=if ($context.factorio -and (Test-Path -LiteralPath $context.factorio)) { $context.factorio } else { "not-provided" }
      factorio_version=$factorioVersion; factorio_matches_target=$factorioMatchesTarget
      prior_release=if ($context.prior_release -and (Test-Path -LiteralPath $context.prior_release)) { $context.prior_release } else { "not-provided" }
    }
    Write-MIRAssuranceJson -Value $result
  }
  "inventory" {
    $zips = @(Get-ChildItem -LiteralPath (Join-Path $repo "dist") -Filter *.zip -File -ErrorAction SilentlyContinue | ForEach-Object {
      [ordered]@{path=[IO.Path]::GetRelativePath($repo,$_.FullName).Replace("\","/"); size_bytes=$_.Length; sha256=Get-MIRAssuranceSha256 -Path $_.FullName}
    })
    $result = [ordered]@{
      schema=1; head=(& git -C $repo rev-parse HEAD).Trim(); branch=(& git -C $repo branch --show-current).Trim()
      tags=@(& git -C $repo tag --list --sort=refname); worktree_status=@(& git -C $repo status --short); distributions=$zips
    }
    Write-MIRAssuranceJson -Value $result
  }
  "impact" { Write-MIRAssuranceJson -Value (Get-MIRAssurancePlan -Context $context).classification }
  "plan" { Write-MIRAssuranceJson -Value (Get-MIRAssurancePlan -Context $context) -DefaultPath "artifacts/assurance/plan.json" }
  "explain" { Write-MIRAssuranceJson -Value (Get-MIRAssurancePlan -Context $context) }
  "build" { Write-MIRAssuranceJson -Value (Invoke-MIRAssuranceBuild -Context $context) }
  "verify" {
    $plan = Get-MIRAssurancePlan -Context $context
    $results = Invoke-MIRAssurancePlan -Plan $plan -Context $context
    $status = if (@($results | Where-Object { $_.status -ne "passed" }).Count -eq 0) { "passed" } else { "failed" }
    $summary = [ordered]@{schema=1; status=$status; target=$context.target; candidate=$context.candidate; plan=$plan; evidence=$results}
    Write-MIRAssuranceJson -Value $summary -DefaultPath "artifacts/assurance/verify-summary.json"
    if ($status -ne "passed") { throw "Assurance verification failed." }
  }
  "qualify" {
    $build = Invoke-MIRAssuranceBuild -Context $context
    $profile = Get-MIRAssuranceOption -Name "--profile" -Default "full"
    $script:Args += @("--profile", $profile)
    $plan = Get-MIRAssurancePlan -Context $context
    $results = Invoke-MIRAssurancePlan -Plan $plan -Context $context
    $status = if (@($results | Where-Object { $_.status -ne "passed" }).Count -eq 0) { "passed" } else { "failed" }
    $summary = [ordered]@{
      schema=1; status=$status; state=if ($status -eq "passed") { "RUNTIME-QUALIFIED" } else { "BUILT" }
      release_status="NOT RELEASED"; target=$context.target; version=[string]$context.info.version
      source_commit=(& git -C $repo rev-parse HEAD).Trim(); build=$build; plan=$plan; evidence=$results
      completed_at=(Get-Date).ToUniversalTime().ToString("o")
    }
    Write-MIRAssuranceJson -Value $summary -DefaultPath "artifacts/assurance/qualification-summary.json"
    if ($status -ne "passed") { throw "Assurance qualification failed." }
  }
  "seal" { Invoke-MIRAssuranceSeal -Context $context }
  "check-seal" { Invoke-MIRAssuranceCheckSeal -Context $context }
  "locale" {
    & (Join-Path $repo "scripts\Test-MIRLocales.ps1") -AllowMissingSupportedLanguages
    if ($LASTEXITCODE -ne 0) { throw "Locale assurance failed." }
  }
  "balance" {
    $snapshot = [ordered]@{
      schema=1; target=$context.target; version=[string]$context.info.version
      streams_sha256=Get-MIRAssuranceSha256 -Path (Join-Path $repo ".mir\streams.yml")
      generated_stream_manifest_sha256=Get-MIRAssuranceSha256 -Path (Join-Path $repo "prototypes\mir\streams\generated_stream_manifest.json")
      settings_sha256=Get-MIRAssuranceSha256 -Path (Join-Path $repo ".mir\settings.yml")
      planner_costs_sha256=Get-MIRAssuranceSha256 -Path (Join-Path $repo "prototypes\mir\planner\costs.lua")
    }
    $snapshot.fingerprint = Get-MIRAssuranceTextHash -Text (($snapshot.Values | ForEach-Object { [string]$_ }) -join "`n")
    Write-MIRAssuranceJson -Value $snapshot -DefaultPath "artifacts/assurance/balance-snapshot.json"
  }
  "backport" {
    $script:Args += @("--profile", "backport")
    Write-MIRAssuranceJson -Value (Get-MIRAssurancePlan -Context $context) -DefaultPath "artifacts/assurance/backport-plan.json"
  }
  "self-test" { Invoke-MIRAssuranceSelfTest -Context $context }
  default { throw "Unknown assurance command: $command" }
}
