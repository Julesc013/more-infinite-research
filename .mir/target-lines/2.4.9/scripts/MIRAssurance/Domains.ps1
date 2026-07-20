$script:MIRAssuranceDomainManifestCache = @{}

function Get-MIRAssuranceVerificationProfilePath {
  param([Parameter(Mandatory)][string]$Target)
  return Join-Path $repo "validation\profiles\factorio-$Target.json"
}

function Get-MIRAssuranceVerificationProfile {
  param([Parameter(Mandatory)][string]$Target)
  $path = Get-MIRAssuranceVerificationProfilePath -Target $Target
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Verification profile not found for Factorio $Target`: $path"
  }
  $profile = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if ([int]$profile.schema -ne 1 -or [string]$profile.target -ne $Target) {
    throw "Verification profile is invalid for Factorio $Target`: $path"
  }
  return $profile
}

function Get-MIRAssuranceDomainPolicy {
  if (-not (Test-Path -LiteralPath $domainsPath -PathType Leaf)) {
    throw "Verification domain policy not found: $domainsPath"
  }
  $policy = Get-Content -Raw -LiteralPath $domainsPath | ConvertFrom-Json
  if ([int]$policy.schema -ne 1) { throw "Verification domain policy schema must be 1." }
  return $policy
}

function Get-MIRAssuranceStreamSha256 {
  param([Parameter(Mandatory)][System.IO.Stream]$Stream)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace("-", "") }
  finally { $sha.Dispose() }
}

function Get-MIRAssuranceZipEntryText {
  param([Parameter(Mandatory)]$Entry)
  $stream = $Entry.Open()
  try {
    $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
    try { return $reader.ReadToEnd() }
    finally { $reader.Dispose() }
  } finally { $stream.Dispose() }
}

function Resolve-MIRAssuranceDomainId {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)]$Policy
  )
  foreach ($domain in @($Policy.domains)) {
    foreach ($pattern in @($domain.patterns)) {
      if (Test-MIRAssurancePathPattern -Path $RelativePath -Pattern ([string]$pattern)) {
        return [string]$domain.id
      }
    }
  }
  return "unknown"
}

function Get-MIRAssuranceDependencyContract {
  param([Parameter(Mandatory)]$Info)
  $dependencies = @($Info.dependencies | ForEach-Object { [string]$_ } | Sort-Object)
  return [ordered]@{
    name=[string]$Info.name
    factorio_version=[string]$Info.factorio_version
    dependencies=$dependencies
  }
}

function Get-MIRAssuranceDomainManifest {
  param(
    [Parameter(Mandatory)]$Context,
    [switch]$RequireCandidate
  )
  $candidateExists = $Context.candidate -and (Test-Path -LiteralPath $Context.candidate -PathType Leaf)
  if ($RequireCandidate -and -not $candidateExists) {
    throw "Exact candidate archive is required to calculate scenario domains: $($Context.candidate)"
  }
  $candidateIdentity = if ($candidateExists) {
    $item = Get-Item -LiteralPath $Context.candidate
    "$($item.FullName)|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
  } else {
    "source|$(Get-MIRAssuranceTreeHash -Paths (Get-MIRAssurancePackageFiles))"
  }
  if ($script:MIRAssuranceDomainManifestCache.ContainsKey($candidateIdentity)) {
    return $script:MIRAssuranceDomainManifestCache[$candidateIdentity]
  }

  $policy = Get-MIRAssuranceDomainPolicy
  $rowsByDomain = @{}
  foreach ($domain in @($policy.domains)) { $rowsByDomain[[string]$domain.id] = @() }
  $rowsByDomain["unknown"] = @()
  $info = $Context.info
  $artifact = [ordered]@{
    state=if ($candidateExists) { "present" } else { "source-fallback" }
    path=if ($candidateExists) { Get-MIRAssuranceRepoRelativePath -Path $Context.candidate } else { "" }
    sha256=if ($candidateExists) { Get-MIRAssuranceSha256 -Path $Context.candidate } else { "" }
    content_sha256=if ($candidateExists) { Get-MIRAssuranceZipContentHash -Path $Context.candidate } else { Get-MIRAssuranceTreeHash -Paths (Get-MIRAssurancePackageFiles) }
  }

  if ($candidateExists) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Context.candidate)
    try {
      $fileEntries = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith("/") } | Sort-Object FullName)
      $rootPrefix = ""
      if ($fileEntries.Count -gt 0 -and $fileEntries[0].FullName.Contains("/")) {
        $rootPrefix = $fileEntries[0].FullName.Substring(0, $fileEntries[0].FullName.IndexOf("/") + 1)
      }
      foreach ($entry in $fileEntries) {
        $relative = [string]$entry.FullName
        if ($rootPrefix -and $relative.StartsWith($rootPrefix)) { $relative = $relative.Substring($rootPrefix.Length) }
        $stream = $entry.Open()
        try { $sha256 = Get-MIRAssuranceStreamSha256 -Stream $stream }
        finally { $stream.Dispose() }
        $domainId = Resolve-MIRAssuranceDomainId -RelativePath $relative -Policy $policy
        $rowsByDomain[$domainId] += "$relative`t$($entry.Length)`t$sha256"
        if ($relative -eq "info.json") {
          $info = Get-MIRAssuranceZipEntryText -Entry $entry | ConvertFrom-Json
        }
      }
    } finally { $archive.Dispose() }
  } else {
    foreach ($relative in @(Get-MIRAssurancePackageFiles)) {
      $full = Join-Path $repo $relative
      $domainId = Resolve-MIRAssuranceDomainId -RelativePath $relative -Policy $policy
      $rowsByDomain[$domainId] += "$relative`t$(Get-MIRAssuranceRepositoryBlobId -Path $full)"
    }
  }

  $domains = [ordered]@{}
  foreach ($domainId in @($rowsByDomain.Keys | Sort-Object)) {
    $rows = @($rowsByDomain[$domainId] | Sort-Object)
    $domains[$domainId] = [ordered]@{
      file_count=$rows.Count
      sha256=(Get-MIRAssuranceTextHash -Text $(if ($rows.Count -gt 0) { $rows -join "`n" } else { "EMPTY:$domainId" }))
    }
  }
  $dependencyContract = Get-MIRAssuranceDependencyContract -Info $info
  $domains["dependency-contract"] = [ordered]@{
    file_count=1
    sha256=(Get-MIRAssuranceJsonHash -Value $dependencyContract)
  }
  $domains["artifact"] = [ordered]@{
    file_count=if ($candidateExists) { 1 } else { 0 }
    sha256=[string]$artifact.sha256
    content_sha256=[string]$artifact.content_sha256
  }

  $manifest = [ordered]@{
    schema=1
    policy_id=[string]$policy.policy_id
    target=[string]$Context.target
    version=[string]$info.version
    artifact=$artifact
    dependency_contract=$dependencyContract
    domains=$domains
  }
  $manifest["manifest_sha256"] = Get-MIRAssuranceJsonHash -Value $manifest
  $script:MIRAssuranceDomainManifestCache[$candidateIdentity] = $manifest
  return $manifest
}

function Get-MIRAssuranceScenarioDomainDependencies {
  param(
    [Parameter(Mandatory)]$Scenario,
    [Parameter(Mandatory)]$DomainManifest
  )
  $policy = Get-MIRAssuranceDomainPolicy
  $property = $policy.scenario_dependencies.PSObject.Properties[[string]$Scenario.kind]
  if ($null -eq $property) { throw "No domain dependency policy exists for scenario kind '$($Scenario.kind)'." }
  $dependencies = @($property.Value | ForEach-Object { [string]$_ })
  if ([bool]$policy.always_include_unknown -and [int]$DomainManifest.domains["unknown"].file_count -gt 0) {
    $dependencies += "unknown"
  }
  return @($dependencies | Sort-Object -Unique)
}

function Get-MIRAssuranceScenarioDomainFingerprint {
  param(
    [Parameter(Mandatory)]$Test,
    [Parameter(Mandatory)]$Context
  )
  $manifest = Get-MIRAssuranceDomainManifest -Context $Context -RequireCandidate
  $dependencies = @($Test.domain_dependencies | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  $selected = [ordered]@{}
  foreach ($dependency in $dependencies) {
    if (-not $manifest.domains.Contains($dependency)) { throw "Scenario '$($Test.id)' references unknown domain '$dependency'." }
    $selected[$dependency] = $manifest.domains[$dependency]
  }
  $material = [ordered]@{
    policy_id=[string]$manifest.policy_id
    target=[string]$Context.target
    dependencies=$dependencies
    domains=$selected
  }
  return [ordered]@{
    kind="scenario-domains"
    dependencies=$dependencies
    domains=$selected
    sha256=(Get-MIRAssuranceJsonHash -Value $material)
  }
}

function Get-MIRAssuranceScenarioRecordFingerprint {
  param([Parameter(Mandatory)]$Test)
  if ($null -eq $Test.scenario) { throw "Scenario record is missing for $($Test.id)." }
  return [ordered]@{
    kind="scenario-record"
    name=[string]$Test.scenario.name
    sha256=(Get-MIRAssuranceJsonHash -Value $Test.scenario)
  }
}

function Get-MIRAssuranceScenarioFixtureFingerprint {
  param([Parameter(Mandatory)]$Test)
  $patterns = @(".mir/fixtures.yml")
  foreach ($fixture in @($Test.scenario.fixtures)) {
    $patterns += "fixtures/$([string]$fixture)/**"
  }
  if ([string]$Test.scenario.group -eq "local-mod-library") {
    $patterns += @(
      "fixtures/local-mod-library/**",
      "fixtures/compat-matrix/local-library-scenarios*.json"
    )
  }
  return Get-MIRAssurancePatternFingerprint -Patterns @($patterns | Sort-Object -Unique)
}

function Get-MIRAssuranceScenarioHarnessFingerprint {
  return Get-MIRAssurancePatternFingerprint -Patterns @(
    "scripts/Invoke-MIRValidation.ps1",
    "scripts/validation/**",
    "fixtures/compat-matrix/expected-scenarios.json"
  )
}

function Get-MIRAssuranceBalanceContractFingerprint {
  return Get-MIRAssurancePatternFingerprint -Patterns @(
    "prototypes/streams/**",
    "prototypes/mir/planner/costs.lua",
    "prototypes/mir/domain/native_owner/**",
    "prototypes/mir/planner/native_owner_binding.lua",
    "prototypes/mir/emit/transactions/productivity_family_adoption.lua",
    ".mir/streams.yml",
    ".mir/settings.yml",
    ".mir/native-owner-cost-models.json"
  )
}

function Select-MIRAssuranceMatrixScenarios {
  param(
    [Parameter(Mandatory)]$Registry,
    [Parameter(Mandatory)][string]$Selector,
    [Parameter(Mandatory)]$ImpactSelection
  )
  $records = @($Registry.records | Where-Object kind -ne "gate")
  switch ($Selector) {
    "full" { return @($records | Sort-Object name) }
    "smoke" { return @($records | Where-Object { @($_.tags) -contains "smoke" } | Sort-Object name) }
    "affected" {
      return @($records | Where-Object {
        $record = $_
        @($ImpactSelection.scenarios) -contains [string]$record.name -or
        @($ImpactSelection.groups) -contains [string]$record.group -or
        @($record.tags | Where-Object { @($ImpactSelection.tags) -contains [string]$_ }).Count -gt 0
      } | Sort-Object name)
    }
    default { throw "Unsupported scenario matrix selector: $Selector" }
  }
}

function Expand-MIRAssuranceTests {
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()]$Tests,
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$ImpactSelection
  )
  . (Join-Path $repo "scripts\validation\ScenarioRegistry.ps1")
  $registry = Import-MIRScenarioRegistry -Path $scenarioRegistryPath -TargetProfile $Context.target
  $expanded = @()
  $seen = @{}
  foreach ($test in @($Tests)) {
    if ([string]$test.kind -ne "matrix") {
      $id = [string]$test.id
      if (-not $seen.ContainsKey($id)) {
        $seen[$id] = $true
        $expanded += $test
      }
      continue
    }
    if ([string]$test.matrix.source -ne "scenario-registry") {
      throw "Unsupported test matrix source for $($test.id): $($test.matrix.source)"
    }
    $records = Select-MIRAssuranceMatrixScenarios -Registry $registry -Selector ([string]$test.matrix.selector) -ImpactSelection $ImpactSelection
    foreach ($record in $records) {
      $id = "scenario/$($Context.target)/$($record.name)"
      if ($seen.ContainsKey($id)) { continue }
      $seen[$id] = $true
      $safeId = $id -replace '[^A-Za-z0-9._-]', '_'
      $layer = switch ([string]$record.kind) {
        "package" { "F2" }
        "runtime" { "F3" }
        "configuration-change" { "F4" }
        default { "F3" }
      }
      $domainManifest = Get-MIRAssuranceDomainManifest -Context $Context -RequireCandidate
      $dependencies = Get-MIRAssuranceScenarioDomainDependencies -Scenario $record -DomainManifest $domainManifest
      $inputs = @("factorio", "verification-profile", "scenario-record", "scenario-fixtures", "scenario-harness")
      if ([string]$record.kind -eq "package") { $inputs += "candidate" }
      else { $inputs += "scenario-domains" }
      $expanded += [pscustomobject][ordered]@{
        id=$id
        template_id=[string]$test.id
        safe_test_id=$safeId
        kind="factorio-scenario"
        layer=$layer
        command="./scripts/Invoke-MIRValidation.ps1 -ScenarioWorker -FactorioBin <factorio> -CandidateZip <candidate> -Scenario '$($record.name)' -ValidationSummaryPath 'artifacts/validation/$safeId.json'"
        requires_factorio=$true
        requires_candidate=$true
        inputs=@($inputs)
        domain_dependencies=@($dependencies)
        scenario=$record
      }
    }
  }
  return @($expanded)
}
