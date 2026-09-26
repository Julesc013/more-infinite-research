# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = "")
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $MirLegacyScriptRoot "..")).Path }
. (Join-Path $RepoRoot 'tools/lib/validation/CurrentTargetPackage.ps1')

& (Join-Path $RepoRoot "scripts\Invoke-MIRAssurance.ps1") self-test
if ($LASTEXITCODE -ne 0) { throw "MIR assurance self-test failed." }
& (Join-Path $RepoRoot "tests\tooling\Test-MIRVerificationSchemas.ps1") -RepoRoot $RepoRoot
if ($LASTEXITCODE -ne 0) { throw "MIR verification schema validation failed." }
& (Join-Path $RepoRoot "tests\release\Test-MIRTerminalGovernance.ps1") -RepoRoot $RepoRoot
if ($LASTEXITCODE -ne 0) { throw "MIR terminal governance validation failed." }

$config = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\assurance.json") | ConvertFrom-Json
$impact = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\test-impact.yml") | ConvertFrom-Json
$catalog = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\tests.yml") | ConvertFrom-Json
$domains = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\domains.yml") | ConvertFrom-Json
$trust = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\trust.json") | ConvertFrom-Json
if ([int]$config.schema -ne 1 -or [int]$impact.schema -ne 1 -or [int]$catalog.schema -ne 2 -or [int]$domains.schema -ne 1 -or [int]$trust.schema -ne 1) {
  throw "Unsupported assurance manifest schema."
}
$releaseAssuranceFacadeSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\Release.ps1")
$releaseAssuranceSource = @(
  $releaseAssuranceFacadeSource
  Get-ChildItem -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\release") -File -Filter "*.ps1" |
    Sort-Object Name |
    ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }
) -join "`n"
$assuranceSelfTestSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tests\tooling\support\MIRAssuranceSelfTest.ps1")
$assuranceEntryPointSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\Invoke-MIRAssurance.ps1")
$releaseCandidateWorkflowSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".github\workflows\release-candidate.yml")
. (Join-Path $RepoRoot 'tools/lib/validation/CurrentTargetPackage.ps1')
$assuranceEvidenceSource = @(
  Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\Evidence.ps1")
  Get-ChildItem -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\evidence") -File -Filter "*.ps1" |
    Sort-Object Name |
    ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }
) -join "`n"
foreach ($requiredTrustSelfTestSnippet in @(
  '$differentTrustClass = if ([string]$Context.trust_class -eq "untrusted-pr")',
  '{ "protected-integration" } else { "untrusted-pr" }',
  '$differentTrustCapsule.producer.trust_class = $differentTrustClass'
)) {
  if (-not $assuranceSelfTestSource.Contains($requiredTrustSelfTestSnippet)) {
    throw "Assurance trust-class self-test does not guarantee a different decoy class: $requiredTrustSelfTestSnippet"
  }
}

if ($releaseAssuranceFacadeSource.Contains('function Invoke-MIRAssuranceSelfTest')) { throw 'Release authority still embeds assurance self-test implementation.' }
if (-not $assuranceEntryPointSource.Contains('tests/tooling/support/MIRAssuranceSelfTest.ps1')) { throw 'Assurance self-test command does not load canonical test support.' }
if (([regex]::Matches($releaseCandidateWorkflowSource, [regex]::Escape('CurrentTargetPackage.ps1'))).Count -lt 3 -or
    ([regex]::Matches($releaseCandidateWorkflowSource, [regex]::Escape('Get-MIR4CurrentTargetPackageOutputText'))).Count -lt 3 -or
    $releaseCandidateWorkflowSource.Contains('Get-Content info.json -Raw') -or
    $releaseCandidateWorkflowSource.Contains("Join-Path `$candidate 'info.json'") -or
    $releaseCandidateWorkflowSource.Contains("Join-Path `$controller 'info.json'")) {
  throw 'Release-candidate workflow must derive current package metadata from the canonical materialized target, not a retired repository-root info.json.'
}
foreach ($requiredExactArchiveSnippet in @(
  '$build = @(./tools/commands/package/Build-MIRPackage.ps1)',
  '$candidateArchive = [IO.Path]::GetFullPath([string]$build[0].archive_path)',
  'MIR_RC_CANDIDATE_ARCHIVE=$candidateArchive',
  ". (Join-Path `$controller 'tools/lib/validation/CurrentTargetPackage.ps1')",
  'Get-MIR4ExactRetainedCandidateArchive',
  '-ExpectedSha256 $env:MIR_RC_ARCHIVE_SHA256',
  'sha256 = [string]$retainedCandidate.sha256',
  "kind = 'MIRProtectedReleaseCandidateRunV2'",
  "archive_origin = 'candidate-build-result'",
  'role = [string]$retainedCandidate.role'
)) {
  if (-not $releaseCandidateWorkflowSource.Contains($requiredExactArchiveSnippet)) {
    throw "Release-candidate workflow does not retain its exact candidate build result: $requiredExactArchiveSnippet"
  }
}

function Assert-MIR4ExactRetainedCandidateArchiveRegression {
  $root=Join-Path ([IO.Path]::GetTempPath()) ('mir-retained-candidate-'+[guid]::NewGuid().ToString('N'))
  $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  if(-not[IO.Path]::GetFullPath($root).StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir-retained-candidate-test-root]' }
  try {
    $candidate=Join-Path $root 'candidate'
    New-Item -ItemType Directory -Path $candidate -Force|Out-Null
    $archive=Join-Path $candidate 'candidate.zip'
    [IO.File]::WriteAllBytes($archive,[byte[]](80,75,3,4,77,73,82,52))
    $sha=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    $row=Get-MIR4ExactRetainedCandidateArchive -EvidenceRoot $root -CandidateDirectory $candidate -ExpectedSha256 $sha
    if([string]$row.path-cne'candidate/candidate.zip'-or[string]$row.sha256-cne$sha-or[int64]$row.bytes-ne8){throw '[mir-retained-candidate-test-positive]'}

    [IO.File]::WriteAllBytes($archive,[byte[]](80,75,3,4,77,73,82,52,0))
    $rejected=$false
    try{Get-MIR4ExactRetainedCandidateArchive -EvidenceRoot $root -CandidateDirectory $candidate -ExpectedSha256 $sha|Out-Null}catch{$rejected=$_.Exception.Message-match'mir4-retained-candidate-sha256'}
    if(-not$rejected){throw '[mir-retained-candidate-test-corruption]'}

    [IO.File]::WriteAllBytes($archive,[byte[]](80,75,3,4,77,73,82,52))
    [IO.File]::WriteAllBytes((Join-Path $candidate 'extra.zip'),[byte[]](80,75,3,4))
    $rejected=$false
    try{Get-MIR4ExactRetainedCandidateArchive -EvidenceRoot $root -CandidateDirectory $candidate -ExpectedSha256 $sha|Out-Null}catch{$rejected=$_.Exception.Message-match'mir4-retained-candidate-count'}
    if(-not$rejected){throw '[mir-retained-candidate-test-extra-archive]'}

    $outside=Join-Path $root 'outside'
    New-Item -ItemType Directory -Path $outside|Out-Null
    [IO.File]::WriteAllBytes((Join-Path $outside 'candidate.zip'),[byte[]](80,75,3,4,77,73,82,52))
    $rejected=$false
    try{Get-MIR4ExactRetainedCandidateArchive -EvidenceRoot $root -CandidateDirectory $outside -ExpectedSha256 $sha|Out-Null}catch{$rejected=$_.Exception.Message-match'mir4-retained-candidate-directory'}
    if(-not$rejected){throw '[mir-retained-candidate-test-directory]'}
  } finally {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
  }
}
Assert-MIR4ExactRetainedCandidateArchiveRegression
foreach ($forbiddenDistCandidateSnippet in @(
  'Join-Path $candidate "dist/more-infinite-research_',
  'Join-Path $controller "dist/more-infinite-research_'
)) {
  if ($releaseCandidateWorkflowSource.Contains($forbiddenDistCandidateSnippet)) {
    throw "Release-candidate workflow must not substitute a dist archive for the candidate build result: $forbiddenDistCandidateSnippet"
  }
}
$ids = @($catalog.tests | ForEach-Object { [string]$_.id })
$duplicates = @($ids | Group-Object | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw "Duplicate assurance test IDs: $($duplicates.Name -join ', ')" }

$developmentContractsTest = @($catalog.tests | Where-Object { [string]$_.id -eq 'static.mir4-development-contracts' })
if ($developmentContractsTest.Count -ne 1 -or
    [string]$developmentContractsTest[0].command -cne './tests/repository/Test-MIR4DevelopmentContracts.ps1 -ExpectedSourceCommit <source-commit> -ExpectedSourceTree <source-tree> -ExpectedPackageSourceSha256 <package-source-sha256> -ReceiptPath <test-output>' -or
    @($developmentContractsTest[0].inputs) -notcontains 'source-identity' -or
    @($developmentContractsTest[0].captured_artifacts).Count -ne 1 -or
    [string]$developmentContractsTest[0].captured_artifacts[0].path_pattern -cne '<test-output>' -or
    [string]$developmentContractsTest[0].captured_artifacts[0].schema -cne 'contracts/repository/mir4-development-contracts-local-result-v1.schema.json' -or
    [string]$developmentContractsTest[0].captured_artifacts[0].kind -cne 'MIR4DevelopmentContractsLocalResultV1') {
  throw 'static.mir4-development-contracts must bind a clean exact plan source and one worker-private receipt output.'
}

$releaseHistoryClassificationCases = [ordered]@{
  ".mir/portable-return.yml" = "release-governance"
  ".mir/control-plane/package-locks.json" = "release-governance"
  ".mir/releases/transitions/3.2.5-c32-source-frozen.json" = "release-governance"
  ".mir/releases/transitions/3.2.5-c32-package-built.json" = "release-governance"
  ".mir/releases/sources/published-source-locks.json" = "release-evidence"
  ".mir/target-lines/2.4.9/info.json" = "release-evidence"
  ".mir/evidence/2.4.9/publication.json" = "release-evidence"
  ".mir/releases/deltas/2.4.5-to-2.4.9.json" = "release-evidence"
  "dist/more-infinite-research_2.4.9.zip" = "release-evidence"
}
foreach ($case in $releaseHistoryClassificationCases.GetEnumerator()) {
  $matchedClasses = @(
    $config.classes | Where-Object {
      $class = $_
      @($class.patterns | Where-Object { [string]$case.Key -match [string]$_ }).Count -gt 0
    } | ForEach-Object { [string]$_.id }
  )
  if ($matchedClasses -notcontains [string]$case.Value) {
    throw "Release-history assurance classification is missing '$($case.Value)' for '$($case.Key)'."
  }
  if (@($matchedClasses | Where-Object { $_ -in @("runtime-or-migration", "settings", "compiler-data-stage", "balance", "metadata-dependencies", "test-harness") }).Count -gt 0) {
    throw "Release-history path '$($case.Key)' incorrectly selects a runtime-impact assurance class: $($matchedClasses -join ', ')."
  }
}

$assuranceToolingClassificationCases = @(
  ".mir/assurance.json",
  ".mir/test-impact.yml",
  ".mir/views/publication-checklist.json",
  ".github/workflows/validate.yml",
  ".github/workflows/assurance-targeted.yml",
  ".github/workflows/assurance-scheduled.yml",
  "scripts/Invoke-MIRAssurance.ps1",
  "tools/mir.ps1",
  "tools/commands/control/Invoke-MIRControlPlaneWork.ps1",
  "tools/commands/release/Test-MIRGitHubAdministration.ps1",
  "tools/lib/assurance/Evidence.ps1",
  "tools/lib/control/Evidence.ps1",
  "tools/lib/control/Planner.ps1",
  "tools/lib/control/Views.ps1",
  ".mir/control-plane/approved-delta-policies.json",
  "tools/maintenance/Move-MIRValidationDefinitions.ps1",
  "tests/tooling/Test-MIRAssurance.ps1",
  "tests/tooling/Test-MIRLayout.ps1",
  "tests/release/Test-MIRGitHubAdministration.ps1",
  "tests/release/Test-MIRReleaseAuthority.ps1",
  "validation/tests.yml"
)
foreach ($path in $assuranceToolingClassificationCases) {
  $matchedClasses = @(
    $config.classes | Where-Object {
      $class = $_
      @($class.patterns | Where-Object { $path -match [string]$_ }).Count -gt 0
    } | ForEach-Object { [string]$_.id }
  )
  if ($matchedClasses -notcontains "assurance-tooling" -or $matchedClasses -contains "test-harness") {
    throw "Static assurance path '$path' must select assurance-tooling without selecting the Factorio test harness: $($matchedClasses -join ', ')."
  }
}

$ecosystemProfileClass = @($config.classes | Where-Object { [string]$_.id -eq "ecosystem-profile" })
if ($ecosystemProfileClass.Count -ne 1 -or
    @($ecosystemProfileClass[0].tests) -notcontains "runtime.ecosystem" -or
    @($ecosystemProfileClass[0].tests) -notcontains "static.full") {
  throw "The ecosystem-profile assurance class must select static.full and runtime.ecosystem."
}
foreach ($path in @("fixtures/run-profiles/release-targeted-2.1.json", "validation/scenarios/local-2.1.json")) {
  if (@($ecosystemProfileClass[0].patterns | Where-Object { $path -match [string]$_ }).Count -eq 0) {
    throw "Ecosystem authority path '$path' does not select the ecosystem-profile assurance class."
  }
}

$autoSealClasses = @($config.classes | Where-Object { @($_.tests) -contains "seal.verify" } | ForEach-Object { [string]$_.id })
if ($autoSealClasses.Count -ne 0) {
  throw "seal.verify must be reserved for explicit promotion checks, not auto-selected by change classes: $($autoSealClasses -join ', ')."
}
if (@($config.profiles.'promotion-check').Count -ne 1 -or [string]$config.profiles.'promotion-check'[0] -ne "seal.verify") {
  throw "The promotion-check profile must contain exactly seal.verify."
}

$releaseHistoryTest = @($catalog.tests | Where-Object { [string]$_.id -eq "static.release-history" })
if ($releaseHistoryTest.Count -ne 1 -or
    [string]$releaseHistoryTest[0].command -ne "./tests/release/Test-MIRPublishedSnapshotIntegrity.ps1 -Index" -or
    @($releaseHistoryTest[0].inputs) -notcontains "release-history") {
  throw "static.release-history must bind the staged release-history fingerprint and run compact source-lock integrity."
}

$assuranceEntryPoint = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\Invoke-MIRAssurance.ps1")
$assuranceReleaseLibrary = $releaseAssuranceSource
foreach ($source in @($assuranceEntryPoint, $assuranceReleaseLibrary)) {
  if (-not $source.Contains('(@(& git -C $repo branch --show-current) -join "").Trim()') -or
      $source.Contains('([string](& git -C $repo branch --show-current)).Trim()')) {
    throw "Assurance inventory must represent detached HEAD as an empty branch without dereferencing null."
  }
}
if ((@() -join "").Trim() -ne "") {
  throw "Detached-HEAD branch normalization must produce empty optional metadata."
}
foreach ($profileName in @("fast", "development-breadth", "full", "backport")) {
  if (@($config.profiles.$profileName) -notcontains "static.release-history") {
    throw "The $profileName assurance profile must include static.release-history."
  }
}

$developmentBreadthExpected = @(
  "docs.check", "tooling.self-test", "static.architecture", "static.compiler", "static.settings",
  "static.locales", "static.balance", "static.museum", "static.release-history", "static.package",
  "static.full", "performance.static", "runtime.exact-zip", "runtime.full", "runtime.upgrade",
  "runtime.ecosystem", "release.approved-delta"
)
$developmentBreadthActual = @($config.profiles.'development-breadth' | ForEach-Object { [string]$_ })
if (($developmentBreadthActual -join "`n") -cne ($developmentBreadthExpected -join "`n")) {
  throw "The development-breadth profile must contain every development-valid broad row in canonical order."
}
foreach ($candidateOnlyTest in @("runtime.performance-regression", "manual.release-review", "seal.verify")) {
  if ($developmentBreadthActual -contains $candidateOnlyTest) {
    throw "The development-breadth profile must not claim candidate-only authority through $candidateOnlyTest."
  }
}

foreach ($requiredStaticRoutingPath in @(
  ".mir/assurance.json",
  ".mir/test-impact.yml",
  ".mir/views/**",
  ".mir/lifecycle/incidents/**",
  ".mir/releases/records/**",
  ".github/workflows/validate.yml",
  ".github/workflows/assurance-*.yml",
  ".github/workflows/control-plane-v5.yml",
  "tools/commands/control/**",
  "tools/commands/release/**",
  "tools/lib/control/Evidence.ps1",
  "tools/mir.ps1",
  "tools/lib/control/Views.ps1",
  "tools/maintenance/**",
  "tests/docs/Test-MIRMarkdownFormatting.ps1",
  "tests/package/Test-MIRArtifactCleanup.ps1",
  "tests/tooling/Test-MIRAssurance.ps1",
  "tests/tooling/Test-MIRLayout.ps1",
  "tests/tooling/Test-MIRControlPlane.ps1",
  "tests/release/Test-MIRGitHubAdministration.ps1",
  "tests/release/Test-MIRReleaseAuthority.ps1"
)) {
  $matchingRules = @($impact.paths | Where-Object { [string]$_.pattern -eq $requiredStaticRoutingPath })
  if ($matchingRules.Count -ne 1) {
    throw "Static assurance routing path '$requiredStaticRoutingPath' must have exactly one explicit impact rule."
  }
  if (@($matchingRules[0].groups).Count -ne 0 -or @($matchingRules[0].scenarios).Count -ne 0 -or @($matchingRules[0].tags).Count -ne 0) {
    throw "Static assurance routing path '$requiredStaticRoutingPath' must not select unrelated runtime impact."
  }
}

foreach ($required in @(
  "tooling.self-test", "static.full", "performance.static", "runtime.full", "runtime.upgrade",
  "static.release-history", "runtime.exact-zip", "runtime.ecosystem", "release.approved-delta",
  "runtime.performance-regression", "manual.release-review", "seal.verify"
)) {
  if ($ids -notcontains $required) { throw "Missing release-blocking assurance test ID: $required" }
}

$approvedDeltaTest = @($catalog.tests | Where-Object { [string]$_.id -eq "release.approved-delta" })
if ($approvedDeltaTest.Count -ne 1 -or
    [string]$approvedDeltaTest[0].command -notmatch '-Path\s+<approved-delta-path>' -or
    @($approvedDeltaTest[0].inputs) -notcontains "approved-delta-transition" -or
    @($approvedDeltaTest[0].inputs | Where-Object { [string]$_ -match '^(approved-delta|\.mir/releases/deltas)/[0-9]' }).Count -ne 0) {
  throw "release.approved-delta must fingerprint the dynamically resolved release transition, not a version-specific path."
}

$portableMuseumTest = @($catalog.tests | Where-Object { [string]$_.id -eq "static.museum" })
$exactMuseumTest = @($catalog.tests | Where-Object { [string]$_.id -eq "runtime.museum-exact" })
if ($portableMuseumTest.Count -ne 1 -or
    [bool]$portableMuseumTest[0].requires_factorio -or
    [string]$portableMuseumTest[0].command -ne "./tests/runtime/Test-MIRMuseumCompiler.ps1" -or
    @($portableMuseumTest[0].inputs) -notcontains "fixtures/museum/synthetic-installation/**") {
  throw "static.museum must remain portable and bind the repository-owned synthetic installation fixture."
}
if ($exactMuseumTest.Count -ne 1 -or
    [string]$exactMuseumTest[0].kind -ne "runtime" -or
    [string]$exactMuseumTest[0].command -ne "./tests/runtime/Test-MIRMuseumExact.ps1" -or
    @($exactMuseumTest[0].inputs) -notcontains "museum-installations") {
  throw "runtime.museum-exact must be a separately fingerprinted exact-installation runtime test."
}
if (@($config.profiles.'museum-exact').Count -ne 2 -or
    @($config.profiles.'museum-exact') -notcontains "static.museum" -or
    @($config.profiles.'museum-exact') -notcontains "runtime.museum-exact") {
  throw "The museum-exact profile must contain only portable museum validation and exact target runtime execution."
}
foreach ($modernProfile in @("fast", "full", "backport")) {
  if (@($config.profiles.$modernProfile) -contains "runtime.museum-exact") {
    throw "runtime.museum-exact must not block the modern $modernProfile profile."
  }
}
$museumCatalogText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\museum-targets.json")
if ($museumCatalogText -match '"(binary|base_data)"\s*:' -or $museumCatalogText -match '(?i)[A-Z]:[/\\]') {
  throw "Tracked museum target policy contains a workstation-specific installation path."
}

$ecosystemTest = @($catalog.tests | Where-Object { [string]$_.id -eq "runtime.ecosystem" })
if ($ecosystemTest.Count -ne 1 -or
    [string]$ecosystemTest[0].command -notmatch '--candidate\s+<candidate>' -or
    [string]$ecosystemTest[0].command -notmatch '--candidate-source\s+<package-source-commit>' -or
    [string]$ecosystemTest[0].command -notmatch '--mods\s+<mods>' -or
    @($ecosystemTest[0].inputs) -notcontains "package-source" -or
    @($ecosystemTest[0].inputs) -notcontains "mod-lock" -or
    [string]$ecosystemTest[0].command -notmatch '--skip-build(?:\s|$)' -or
    [string]$ecosystemTest[0].command -notmatch '--skip-clean-git-status(?:\s|$)') {
  throw "runtime.ecosystem must bind the exact candidate ZIP, package source, and planned mod closure and must not rebuild distribution bytes."
}
$mirCliText = @(
  Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\mir\cli\Invoke-MIRCommandRouter.ps1")
  Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\mir\cli\router\RunProfiles.ps1")
) -join "`n"
foreach ($sourceBindingSnippet in @(
  'Get-MIRArgValue -Items $Items -Name "--candidate-source"',
  '$overrides.candidate_source_commit = $candidateSource',
  '$params.CandidateSourceCommit = [string]$candidateSourceCommit'
)) {
  if (-not $mirCliText.Contains($sourceBindingSnippet)) {
    throw "MIR CLI does not forward the ecosystem candidate-source binding: $sourceBindingSnippet"
  }
}

$performanceTest = @($catalog.tests | Where-Object { [string]$_.id -eq "runtime.performance-regression" })
if ($performanceTest.Count -ne 1 -or
    [string]$performanceTest[0].command -notmatch 'Invoke-MIRPerformanceQualification\.ps1' -or
    [string]$performanceTest[0].command -notmatch '-ExpectedSourceCommit\s+<source-commit>' -or
    [string]$performanceTest[0].command -notmatch '-LocalModZipDir\s+<mods>' -or
    [string]$performanceTest[0].command -notmatch '-OutputPath\s+<test-output>(?:\s|$)' -or
    [string]$performanceTest[0].command -match '\.mir/evidence/' -or
    @($performanceTest[0].inputs) -notcontains "mod-closure" -or
    @($performanceTest[0].inputs) -notcontains "scripts/Invoke-MIRPerformanceQualification.ps1" -or
    @($performanceTest[0].inputs) -contains ".mir/evidence/*-performance-regression.json") {
  throw "runtime.performance-regression must produce fresh evidence inside its unique assurance work root without reading or writing tracked historical evidence."
}
foreach ($requiredPerformanceIsolationSnippet in @(
  '"<test-output>"={ [string]$TestOutput }',
  '$testOutputPath = Join-Path $workRoot "test-output.json"',
  '-TestOutput $testOutputPath',
  '-CampaignPath (Resolve-MIRAssurancePerformanceCampaignPath -Context $Context)',
  '-Kind "runtime-performance-evidence"'
)) {
  if (-not $assuranceEvidenceSource.Contains($requiredPerformanceIsolationSnippet)) {
    throw "Assurance execution does not isolate and capture fresh performance evidence: $requiredPerformanceIsolationSnippet"
  }
}
foreach ($requiredPerformanceSealSnippet in @(
  'Get-MIRAssurancePerformanceEvidenceArtifact',
  'Copy-Item -LiteralPath $performanceArtifactPath -Destination $performanceEvidencePath -Force'
)) {
  if (-not $releaseAssuranceSource.Contains($requiredPerformanceSealSnippet)) {
    throw "Release sealing does not promote the exact captured performance artifact: $requiredPerformanceSealSnippet"
  }
}
if ($releaseAssuranceSource.Contains('Join-Path $repo ".mir\evidence\$($Context.info.version)-performance-regression.json"')) {
  throw "Release sealing still consumes the mutable tracked historical performance-evidence path."
}

$manualTest = @($catalog.tests | Where-Object { [string]$_.id -eq "manual.release-review" })
if ($manualTest.Count -ne 1 -or
    [string]$manualTest[0].command -notmatch '-ExpectedSourceCommit\s+<package-source-commit>' -or
    @($manualTest[0].inputs) -notcontains "manual-review-attestation" -or
    @($manualTest[0].inputs | Where-Object { [string]$_ -match 'manual-review-attestation\.json' }).Count -ne 0) {
  throw "manual.release-review must bind the package-source commit and dynamically fingerprint the exact versioned attestation."
}
. (Join-Path $RepoRoot "tools\lib\validation\ReleaseAttestations.ps1")
$portableHashRoot = Join-Path ([IO.Path]::GetTempPath()) ("mir-portable-hash-" + [Guid]::NewGuid().ToString("N"))
$portableLf = Join-Path $portableHashRoot "evidence.md"
$portableCrLf = Join-Path $portableHashRoot "evidence-crlf.md"
try {
  $null = New-Item -ItemType Directory -Path $portableHashRoot
  [IO.File]::WriteAllText($portableLf, "line one`nline two`n", [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($portableCrLf, "line one`r`nline two`r`n", [Text.UTF8Encoding]::new($false))
  if ((Get-MIRReleasePortableArtifactSha256 -Path $portableLf) -ne
      (Get-MIRReleasePortableArtifactSha256 -Path $portableCrLf)) {
    throw "Portable manual-review text hashes must be invariant across LF and CRLF checkouts."
  }
} finally {
  if (Test-Path -LiteralPath $portableHashRoot) {
    Remove-Item -LiteralPath $portableHashRoot -Recurse -Force
  }
}
foreach ($target in @("2.0", "2.1")) {
  $profilePath = Join-Path $RepoRoot "validation\profiles\factorio-$target.json"
  $profile = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json
  if ([int]$profile.schema -ne 1 -or [string]$profile.target -ne $target -or [string]$profile.policy_id -ne [string]$domains.policy_id) {
    throw "Verification profile is not bound to the canonical domain policy: $profilePath"
  }
}
$publishedRelease = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\records\3.2.5.json") | ConvertFrom-Json
$terminalRelease = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\records\3.2.9.json") | ConvertFrom-Json
$currentRelease = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\records\3.2.11.json") | ConvertFrom-Json
$currentProfile = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\profiles\factorio-2.1.json") | ConvertFrom-Json
$mir41Authority = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "spec\execution\mir4-4.1-development-context-v1.json") | ConvertFrom-Json
$mir42Authority = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "spec\execution\mir4-4.2-development-context-v1.json") | ConvertFrom-Json
$mir4Targets = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\waves\mir4-r0\MIR4-Target-RegistryV5.json") | ConvertFrom-Json
$mir4F210 = @($mir4Targets.payload.targets | Where-Object id -eq 'factorio-2.1')
$currentReleaseBoundary = "{0}|{1}" -f [string]$currentRelease.state, [string]$currentRelease.candidate_id
if ($currentReleaseBoundary -ne 'publicly-verified|C35' -or [string]$currentRelease.candidate_floor -ne 'C35' -or
    [string]$currentProfile.execution_context_mode -ne 'development-context' -or
    [string]$currentProfile.execution_context -ne 'spec/execution/mir4-4.2-development-context-v1.json' -or
    [string]$mir41Authority.kind -ne 'MIR4DevelopmentExecutionContextV1' -or
    [string]$mir41Authority.status -ne 'active-private-mir4.1-qualification-no-release-authority' -or
    [string]$mir42Authority.kind -ne 'MIR4DevelopmentExecutionContextV2' -or
    [string]$mir42Authority.status -ne 'active-private-mir4.2-verification-plan-no-release-authority' -or
    @($mir42Authority.targets).Count -ne 2 -or @($mir42Authority.targets) -notcontains 'f210' -or @($mir42Authority.targets) -notcontains 'f200' -or
    [bool]$mir42Authority.transition_gate.source_freeze -or [bool]$mir42Authority.transition_gate.version_allocation -or
    [bool]$mir42Authority.transition_gate.tagging -or [bool]$mir42Authority.transition_gate.signing -or
    [bool]$mir42Authority.transition_gate.sealing -or [bool]$mir42Authority.transition_gate.publication -or $mir4F210.Count -ne 1 -or
    [string]$mir4F210[0].mir3_predecessor -ne [string]$currentProfile.upgrade.from_version -or
    [string]$currentProfile.upgrade.from_version -ne '3.2.11' -or
    [string]$currentProfile.upgrade.to_version -ne '4.0.21000' -or
    [string]$currentProfile.upgrade.fixture -ne 'assert-upgrade-3-2-11-to-4-0-21000') {
  throw "Factorio 2.1 assurance profile must bind the exact private MIR 4.2 development context, preserve the MIR 4.1 boundary, and retain the 3.2.11 to MIR 4 transition fixture."
}
if ([string]$terminalRelease.state -ne "publicly-verified" -or
    [string]$terminalRelease.candidate_id -ne "C33" -or
    [string]$terminalRelease.package.archive_sha256 -ne "0E833FCDDA3017641CA99D0EBD2FA226938A1CEE91D2EBB4007E94B29787AE20") {
  throw "The immutable 3.2.9 public release authority changed while advancing the 3.2.10 upgrade profile."
}
if ([string]$publishedRelease.state -ne "publicly-verified" -or
    [string]$publishedRelease.candidate_id -ne "C32" -or
    [string]$publishedRelease.package.archive_sha256 -ne "AC81CAD1AC37F20E27A46BFAD243611DB251CACCF52E1AB4DA5D06CFDAA11ADF") {
  throw "The immutable 3.2.5 public release authority changed while advancing the 3.2.9 upgrade profile."
}
$upgradeFixtureRoot = Join-Path $RepoRoot "fixtures\assert-upgrade-3-2-3-to-3-2-5"
$upgradeSettings = Get-Content -Raw -LiteralPath (Join-Path $upgradeFixtureRoot "settings.lua")
$upgradeControl = Get-Content -Raw -LiteralPath (Join-Path $upgradeFixtureRoot "control.lua")
$upgradeDataFinal = Get-Content -Raw -LiteralPath (Join-Path $upgradeFixtureRoot "data-final-fixes.lua")
foreach ($archetype in @("base-default", "space-age-native-owner", "automatic-family-creation", "base-continuations", "mod-set-configuration-change")) {
  if (-not $upgradeSettings.Contains(('"' + $archetype + '"')) -or
      -not $upgradeControl.Contains(('[' + '"' + $archetype + '"' + ']'))) {
    throw "3.2.5 upgrade fixture does not bind archetype $archetype."
  }
}
foreach ($requiredUpgradeText in @(
  'script.active_mods["more-infinite-research"] ~= "3.2.3"',
  'script.active_mods["more-infinite-research"] ~= "3.2.5"',
  'game.server_save("mir-325-upgraded")',
  '3.2.5 upgraded save reload proof complete'
)) {
  if (-not $upgradeControl.Contains($requiredUpgradeText)) {
    throw "3.2.5 upgrade fixture is missing governed runtime contract: $requiredUpgradeText"
  }
}
foreach ($requiredCostText in @(
  'ips-cost-linear-increment-research_gears',
  'mir-cost-linear-increment-worker-robots-storage',
  '4321*1.25^(L-1)'
)) {
  if (-not $upgradeDataFinal.Contains($requiredCostText)) {
    throw "3.2.5 upgrade fixture is missing cost-transition contract: $requiredCostText"
  }
}

$terminalUpgradeFixtureRoot = Join-Path $RepoRoot "fixtures\assert-upgrade-3-2-5-to-3-2-9"
$terminalUpgradeSettings = Get-Content -Raw -LiteralPath (Join-Path $terminalUpgradeFixtureRoot "settings.lua")
$terminalUpgradeControl = Get-Content -Raw -LiteralPath (Join-Path $terminalUpgradeFixtureRoot "control.lua")
foreach ($archetype in @("base-default", "space-age-native-owner", "automatic-family-creation", "base-continuations", "mod-set-configuration-change")) {
  if (-not $terminalUpgradeSettings.Contains(('"' + $archetype + '"')) -or
      -not $terminalUpgradeControl.Contains(('[' + '"' + $archetype + '"' + ']'))) {
    throw "3.2.9 upgrade fixture does not bind archetype $archetype."
  }
}
foreach ($requiredUpgradeText in @(
  'script.active_mods["more-infinite-research"] ~= "3.2.5"',
  'script.active_mods["more-infinite-research"] ~= "3.2.9"',
  'game.server_save("mir-329-upgraded")',
  '3.2.9 upgraded save reload proof complete'
)) {
  if (-not $terminalUpgradeControl.Contains($requiredUpgradeText)) {
    throw "3.2.9 upgrade fixture is missing governed runtime contract: $requiredUpgradeText"
  }
}

$hotfixUpgradeFixtureRoot = Join-Path $RepoRoot "fixtures\assert-upgrade-3-2-9-to-3-2-10"
$hotfixUpgradeSettings = Get-Content -Raw -LiteralPath (Join-Path $hotfixUpgradeFixtureRoot "settings.lua")
$hotfixUpgradeControl = Get-Content -Raw -LiteralPath (Join-Path $hotfixUpgradeFixtureRoot "control.lua")
foreach ($archetype in @("base-default", "space-age-native-owner", "automatic-family-creation", "base-continuations", "mod-set-configuration-change")) {
  if (-not $hotfixUpgradeSettings.Contains(('"' + $archetype + '"')) -or
      -not $hotfixUpgradeControl.Contains(('[' + '"' + $archetype + '"' + ']'))) {
    throw "3.2.10 upgrade fixture does not bind archetype $archetype."
  }
}
foreach ($requiredUpgradeText in @(
  'script.active_mods["more-infinite-research"] ~= "3.2.9"',
  'script.active_mods["more-infinite-research"] ~= "3.2.10"',
  'tech.prototype.max_level < 4294967295',
  'game.server_save("mir-3210-upgraded")',
  '3.2.10 upgraded save reload proof complete'
)) {
  if (-not $hotfixUpgradeControl.Contains($requiredUpgradeText)) {
    throw "3.2.10 upgrade fixture is missing governed runtime contract: $requiredUpgradeText"
  }
}

$releaseAssurance = $releaseAssuranceSource
foreach ($requiredSealField in @(
  "mir_version",
  "target",
  "canonical_dev_anchor",
  "candidate_id",
  "package_source_commit",
  "package_source_sha256",
  "package_source_material",
  "qualification_source_commit",
  "qualification_source_tree",
  "candidate_descriptor_sha256",
  "plan_material_sha256",
  "required_test_set_sha256",
  "evidence_bundle_sha256",
  "capsule_set_sha256",
  "performance_source_commit",
  "performance_evidence_sha256",
  "performance_status",
  "manual_review_attestation_sha256",
  "manual_review_status",
  "verifier_release_sha256",
  "producer_attestation"
)) {
  if ($releaseAssurance -notmatch ("(?m)^\s+" + [regex]::Escape($requiredSealField) + "=")) {
    throw "Candidate seal implementation omits required field: $requiredSealField"
  }
}
if ($releaseAssurance -match 'Get-MIRAssuranceOption\s+-Name\s+"--evidence"') {
  throw "Candidate sealing still accepts an arbitrary evidence summary."
}
foreach ($requiredSourceCheck in @(
  "package_source_is_ancestor",
  "package_source_identity",
  "qualification_package_source_identity",
  "package_roots_unchanged",
  "package_source_candidate",
  "qualification_source_candidate",
  "performance_source_is_ancestor",
  "performance_package_roots_unchanged",
  "performance_source_candidate"
)) {
  if ($releaseAssurance -notmatch [regex]::Escape($requiredSourceCheck)) {
    throw "Candidate seal verification omits source-authority check: $requiredSourceCheck"
  }
}
$publishedSnapshotIntegrity = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tests\release\Test-MIRPublishedSnapshotIntegrity.ps1")
if ($publishedSnapshotIntegrity -notmatch 'git ls-tree -r -l' -or
  $publishedSnapshotIntegrity -match 'Measure-Object -Property Length -Sum') {
  throw "Published snapshot byte counts must come from canonical Git blobs, not checkout line endings."
}
foreach ($requiredSuccessorCheck in @(
  'Test-MIR4PreFreezeAuthorities',
  'MIR4-T14-Authority-Evolution-ReceiptV1.json',
  'MIR4-T15-Authority-Evolution-ReceiptV1.json',
  'MIR4-T17-Machine-Preparation-Authority-Evolution-ReceiptV1.json',
  'MIR4-Target-Compiler-Tooling-MigrationV1.json',
  'MIR4TargetCompilerMigrationReceiptV1',
  'MIR4-Semantic-Compiler-Policy-Tooling-MigrationV1.json',
  'MIR4SemanticCompilerPolicyMigrationReceiptV1',
  'MIR4-Runtime-Continuity-Tooling-MigrationV1.json',
  'MIR4RuntimeContinuityMigrationReceiptV1',
  'MIR4-Module-Sdk-Mep-Tooling-MigrationV1.json',
  'MIR4ModuleSdkMepMigrationReceiptV1',
  'MIR4-ProcessIR-Exact-Tooling-MigrationV1.json',
  'MIR4ProcessIRExactMigrationReceiptV1',
  'MIR4-Inspector-Compatibility-Tooling-MigrationV1.json',
  'MIR4InspectorCompatibilityMigrationReceiptV1',
  'MIR4-Assurance-Offline-Custody-Tooling-MigrationV1.json',
  'MIR4AssuranceOfflineCustodyMigrationReceiptV1',
  'MIR4-Historical-Tooling-MigrationV1.json',
  'MIR4HistoricalToolingMigrationReceiptV1',
  'MIR4-Release-Tooling-MigrationV1.json',
  'MIR4ReleaseToolingMigrationReceiptV1',
  'player_executable_sources_unchanged',
  'human_gate.acceptance_inferred'
)) {
  if ($publishedSnapshotIntegrity -notmatch [regex]::Escape($requiredSuccessorCheck)) {
    throw "Published snapshot integrity omits append-only successor proof: $requiredSuccessorCheck"
  }
}
foreach ($requiredSuccessorFingerprint in @(
  '.gitattributes',
  '.mir/assurance.json',
  '.mir/compatibility.yml',
  '.mir/control',
  '.mir/control-plane/ownership.json',
  '.mir/docs.yml',
  '.mir/modules.yml',
  '.mir/releases/governance/mir4/supply-chain.json',
  '.mir/releases/waves/mir4-r0',
  'assurance/.mir-root.json',
  'releases/migrations',
  'contracts/repository',
  'governance/.mir-root.json',
  'governance/repository/migrations',
  'assurance/repository',
  'tests/.mir-root.json',
  'validation/tests.yml',
  'tools/mir.ps1',
  'mir.lock',
  'spec/compatibility/claims.json',
  'spec/schemas',
  'tools/mir/application/migration',
  'tools/mir/application/targets',
  'tools/mir/application/compiler',
  'tools/mir/application/runtime',
  'tools/mir/application/extensions',
  'tools/mir/application/processir',
  'tools/mir/application/inspection',
  'tools/mir/application/assurance',
  'tools/mir/application/custody',
  'tools/mir/application/history',
  'tools/mir/application/release',
  'tools/mir/application/technology',
  'tools/mir/domain/safety',
  'tools/mir/domain/policy',
  'tools/mir/cli',
  'tools/lib/assurance',
  'tools/lib/mir4',
  'tools/commands/mir4',
  'tests/compiler',
  'tests/runtime',
  'tests/extensions',
  'tests/processir',
  'tests/inspection',
  'tests/assurance',
  'tests/history',
  'tests/release-tooling',
  'tests/targets',
  'tests/technology',
  'tests/mir4',
  'tests/release/Test-MIRPublishedSnapshotIntegrity.ps1',
  'tests/release/Test-MIR4OfflineCandidateCustody.ps1',
  'tests/tooling/Test-MIRAssurance.ps1',
  'docs/architecture',
  'docs/compatibility',
  'docs/developer/environment-locks.md',
  'docs/reference/generated',
  'docs/releases',
  'sdk/preview/mir4/reference/t13'
)) {
  if ($assuranceEvidenceSource -notmatch [regex]::Escape($requiredSuccessorFingerprint)) {
    throw "Release-history fingerprint omits successor authority input: $requiredSuccessorFingerprint"
  }
}

$coreScript = Join-Path $RepoRoot "tools\lib\assurance\Core.ps1"
$repo = $RepoRoot
. $coreScript
. (Join-Path $RepoRoot "tools\lib\assurance\Hashing.ps1")
$nfcText = "caf$([char]0x00E9)`npolicy`n"
$nfdCrLfText = ([char]0xFEFF) + "cafe$([char]0x0301)`r`npolicy`r`n`r`n"
$nfcDigest = Get-MIRAssuranceCanonicalTextDigest -Text $nfcText
$nfdDigest = Get-MIRAssuranceCanonicalTextDigest -Text $nfdCrLfText
if ([string]$nfcDigest.policy_id -ne "utf8-nfc-lf-final-newline-v1" -or
    [string]$nfcDigest.sha256 -ne [string]$nfdDigest.sha256) {
  throw "Canonical text identity must bind UTF-8/NFC/LF/stable-final-newline semantics across checkout forms."
}
$jsonA = '{"z":2,"a":{"y":1,"x":"caf\u00e9"}}' | ConvertFrom-Json
$jsonB = "{`r`n  `"a`": {`"x`": `"cafe$([char]0x0301)`", `"y`": 1},`r`n  `"z`": 2`r`n}" | ConvertFrom-Json
$jsonDigestA = Get-MIRAssuranceCanonicalJsonDigest -Value $jsonA
$jsonDigestB = Get-MIRAssuranceCanonicalJsonDigest -Value $jsonB
if ([string]$jsonDigestA.policy_id -ne "json-sorted-properties-utf8-nfc-lf-final-newline-v1" -or
    [string]$jsonDigestA.sha256 -ne [string]$jsonDigestB.sha256) {
  throw "Canonical JSON identity must ignore property order, formatting, line endings, and Unicode composition."
}
$script:repo = $RepoRoot
. (Join-Path $RepoRoot "tools\lib\assurance\Evidence.ps1")
. (Join-Path $RepoRoot "tools\lib\assurance\Domains.ps1")
. (Join-Path $RepoRoot "tools\lib\validation\ScenarioRegistry.ps1")
$scenarioRegistryPath = Join-Path $RepoRoot "validation\scenarios\runtime.json"
$evidenceSchema = 4
$assuranceRunnerVersion = '4'

# A13: the runtime selector must leave a candidate-bound, deterministic
# account of both the propositions it selected and every proposition it
# deliberately omitted as unaffected.  Exercise the actual plan decoration
# path with real registry records, but use no Factorio process or mutable
# evidence store.
$a13Registry = Import-MIRScenarioRegistry -Path $scenarioRegistryPath -TargetProfile '2.1'
$a13Records = @($a13Registry.records | Where-Object kind -ne 'gate' | Sort-Object name)
$a13Baseline = @($a13Records | Where-Object { [string]$_.name -eq 'compiler-contracts' })
if ($a13Records.Count -lt 2 -or $a13Baseline.Count -ne 1) {
  throw 'A13 impact-selection regression requires the named compiler-contracts baseline and at least one omittable scenario.'
}
$a13Impact = [ordered]@{
  schema=1
  scenarios=@('compiler-contracts')
  groups=@()
  tags=@()
  mapped_paths=@('source/prototypes/mir/settings/automatic_compiler_policy.lua')
  unmapped_runtime_paths=@()
  requires_full=$false
}
$a13Expected = @(Select-MIRAssuranceMatrixScenarios -Registry $a13Registry -Selector 'affected' -ImpactSelection $a13Impact)
if ($a13Expected.Count -ne 1 -or [string]$a13Expected[0].name -ne 'compiler-contracts') {
  throw 'A13 impact-selection regression did not isolate the declared compiler-contracts proposition.'
}
$a13NewPlan = {
  param(
    [Parameter(Mandatory)]$Impact,
    [Parameter(Mandatory)]$Records,
    [string]$TemplateId = 'runtime.affected',
    [string]$SourceCommit = ('A' * 40),
    [string]$SourceTree = ('B' * 40),
    [string]$PackageSourceCommit = ('C' * 40),
    [string]$PackageSourceSha256 = ('D' * 64),
    [string]$CandidateDescriptorSha256 = ('E' * 64),
    [string]$VerificationProfileSha = ('F' * 64)
  )
  $tests = @(
    foreach ($record in @($Records)) {
      [pscustomobject][ordered]@{
        id="scenario/2.1/$([string]$record.name)"
        template_id=$TemplateId
        safe_test_id=("scenario_2.1_" + ([string]$record.name -replace '[^A-Za-z0-9._-]', '_'))
        kind='factorio-scenario'
        layer='F3'
        command='./synthetic-a13.ps1'
        requires_factorio=$false
        requires_candidate=$false
        inputs=@('spec/programmes/mir4-4x-operating-programme-v1.json')
        domain_dependencies=@()
        scenario=$record
      }
    }
  )
  return [ordered]@{
    target='2.1'
    profile='auto'
    source_commit=$SourceCommit
    source_tree=$SourceTree
    package_source_commit=$PackageSourceCommit
    package_source_sha256=$PackageSourceSha256
    verification_profile_sha256=$VerificationProfileSha
    candidate_descriptor=[ordered]@{descriptor_sha256=$CandidateDescriptorSha256}
    impact_selection=$Impact
    tests=$tests
  }
}
$a13Context = [pscustomobject][ordered]@{
  target='2.1'
  candidate=''
  reuse_enabled=$false
  rerun_tests=@()
}
$a13Plan = & $a13NewPlan -Impact $a13Impact -Records $a13Expected
$null = Add-MIRAssurancePlanDecisions -Plan $a13Plan -Context $a13Context
$a13NoRuntimePlan = & $a13NewPlan -Impact $a13Impact -Records @() -TemplateId 'static.synthetic'
$null = Add-MIRAssurancePlanDecisions -Plan $a13NoRuntimePlan -Context $a13Context
if ($a13NoRuntimePlan.Contains('impact_proposition_ledger')) {
  throw 'A13 non-runtime plan incorrectly claimed a runtime impact selection or unaffected omissions.'
}
$a13Repeat = & $a13NewPlan -Impact $a13Impact -Records $a13Expected
$null = Add-MIRAssurancePlanDecisions -Plan $a13Repeat -Context $a13Context
$a13Ledger = $a13Plan.impact_proposition_ledger
$a13RepeatLedger = $a13Repeat.impact_proposition_ledger
$a13SelectedNames = @($a13Ledger.selected | ForEach-Object { [string]$_.scenario } | Sort-Object -Unique)
$a13OmittedNames = @($a13Ledger.omitted_unaffected | ForEach-Object { [string]$_.scenario } | Sort-Object -Unique)
$a13AllNames = @($a13Records | ForEach-Object { [string]$_.name } | Sort-Object -Unique)
if ([string]$a13Ledger.selection_mode -ne 'declared-semantic-impact' -or
    [string]$a13Ledger.ledger_sha256 -ne [string]$a13RepeatLedger.ledger_sha256 -or
    @(Compare-Object $a13SelectedNames @('compiler-contracts')).Count -ne 0 -or
    @(Compare-Object (@($a13SelectedNames + $a13OmittedNames | Sort-Object -Unique)) $a13AllNames).Count -ne 0 -or
    @($a13Ledger.omitted_unaffected | Where-Object {
      [string]$_.proposition -ne "scenario/2.1/$([string]$_.scenario)" -or
      [string]$_.reason -ne 'unaffected-by-declared-semantic-impact'
    }).Count -ne 0 -or
    @($a13Ledger.selected | Where-Object { @($_.selected_by).Count -eq 0 }).Count -ne 0 -or
    [string]$a13Ledger.candidate_binding.target -ne '2.1' -or
    [string]$a13Ledger.candidate_binding.source_commit -ne ('A' * 40) -or
    [string]$a13Ledger.candidate_binding.source_tree -ne ('B' * 40) -or
    [string]$a13Ledger.candidate_binding.package_source_commit -ne ('C' * 40) -or
    [string]$a13Ledger.candidate_binding.package_source_sha256 -ne ('D' * 64) -or
    [string]$a13Ledger.candidate_binding.candidate_descriptor_sha256 -ne ('E' * 64)) {
  throw 'A13 impact selection did not produce a deterministic candidate-bound selected/omitted proposition ledger.'
}
$a13Extra = @($a13Expected + @($a13Records | Where-Object { [string]$_.name -ne 'compiler-contracts' } | Select-Object -First 1))
$a13OverSelectionRejected = $false
try {
  $a13OverSelectedPlan = & $a13NewPlan -Impact $a13Impact -Records $a13Extra
  $null = Add-MIRAssurancePlanDecisions -Plan $a13OverSelectedPlan -Context $a13Context
} catch { $a13OverSelectionRejected = $_.Exception.Message -match '\[mir-assurance-impact-selection-mismatch\]' }
if (-not $a13OverSelectionRejected) {
  throw 'A13 impact selection accepted a runtime proposition outside the declared semantic impact.'
}
$a13FullImpact = [ordered]@{
  schema=1
  scenarios=@('compiler-contracts')
  groups=@()
  tags=@()
  mapped_paths=@()
  unmapped_runtime_paths=@('source/prototypes/mir/unknown-runtime.lua')
  requires_full=$true
}
$a13FullPlan = & $a13NewPlan -Impact $a13FullImpact -Records $a13Records -TemplateId 'runtime.full'
$null = Add-MIRAssurancePlanDecisions -Plan $a13FullPlan -Context $a13Context
if ([string]$a13FullPlan.impact_proposition_ledger.selection_mode -ne 'full-escalation' -or
    @($a13FullPlan.impact_proposition_ledger.selected).Count -ne $a13Records.Count -or
    @($a13FullPlan.impact_proposition_ledger.omitted_unaffected).Count -ne 0) {
  throw 'A13 full escalation incorrectly made a scoped unaffected-omission claim.'
}
$a13FullProfilePlan = & $a13NewPlan -Impact $a13Impact -Records $a13Records -TemplateId 'runtime.full'
$null = Add-MIRAssurancePlanDecisions -Plan $a13FullProfilePlan -Context $a13Context
if ([string]$a13FullProfilePlan.impact_proposition_ledger.selection_mode -ne 'full-profile' -or
    @($a13FullProfilePlan.impact_proposition_ledger.selected).Count -ne $a13Records.Count -or
    @($a13FullProfilePlan.impact_proposition_ledger.omitted_unaffected).Count -ne 0) {
  throw 'A13 runtime.full without escalation did not record full-profile coverage without scoped omissions.'
}
$a13Fingerprint = $a13Plan.tests[0].fingerprint
$a13CandidateMutations = @(
  [ordered]@{ field='source_commit'; parameter='SourceCommit'; value=('1' * 40) },
  [ordered]@{ field='source_tree'; parameter='SourceTree'; value=('2' * 40) },
  [ordered]@{ field='package_source_commit'; parameter='PackageSourceCommit'; value=('3' * 40) },
  [ordered]@{ field='package_source_sha256'; parameter='PackageSourceSha256'; value=('4' * 64) },
  [ordered]@{ field='candidate_descriptor_sha256'; parameter='CandidateDescriptorSha256'; value=('5' * 64) }
)
$a13CandidateMutationFingerprints = @(
  foreach ($mutation in $a13CandidateMutations) {
    $arguments = @{ Impact=$a13Impact; Records=$a13Expected }
    $arguments[[string]$mutation.parameter] = [string]$mutation.value
    $mutationPlan = & $a13NewPlan @arguments
    $null = Add-MIRAssurancePlanDecisions -Plan $mutationPlan -Context $a13Context
    [pscustomobject][ordered]@{
      field=[string]$mutation.field
      fingerprint_sha256=[string]$mutationPlan.tests[0].fingerprint.fingerprint_sha256
    }
  }
)
$a13ChangedEnvironmentPlan = & $a13NewPlan -Impact $a13Impact -Records $a13Expected -VerificationProfileSha ('8' * 64)
$null = Add-MIRAssurancePlanDecisions -Plan $a13ChangedEnvironmentPlan -Context $a13Context
$a13ChangedCommand = $a13Plan.tests[0].PSObject.Copy()
$a13ChangedCommand.command = './synthetic-a13-different-command.ps1'
$a13ChangedCommandFingerprint = Get-MIRAssuranceTestFingerprint -Test $a13ChangedCommand -Plan $a13Plan -Context $a13Context
$a13ChangedTargetContext = $a13Context.PSObject.Copy()
$a13ChangedTargetContext.target = '2.0'
$a13ChangedTargetFingerprint = Get-MIRAssuranceTestFingerprint -Test $a13Plan.tests[0] -Plan $a13Plan -Context $a13ChangedTargetContext
$a13ChangedInput = $a13Plan.tests[0].PSObject.Copy()
$a13ChangedInput.inputs = @('spec/programmes/evidence/mir42/a13-exact-fingerprint-reuse.json')
$a13ChangedInputFingerprint = Get-MIRAssuranceTestFingerprint -Test $a13ChangedInput -Plan $a13Plan -Context $a13Context
$a13EvaluatorPatterns = @(
  'scripts/Invoke-MIRAssurance.ps1',
  'tools/mir.ps1',
  'tools/lib/assurance/**',
  'tools/lib/validation/CurrentTargetPackage.ps1',
  'tools/lib/validation/FactorioVersionPolicy.ps1',
  'tools/lib/validation/ScenarioRegistry.ps1',
  'tools/mir_verify/**',
  'spec/schemas/**'
)
$a13EvaluatorCacheKey = @($a13EvaluatorPatterns | ForEach-Object { ([string]$_).Replace("\", "/") } | Sort-Object -Unique) -join "`n"
$a13OriginalEvaluator = $script:MIRAssurancePatternFingerprintCache[$a13EvaluatorCacheKey]
$script:MIRAssurancePatternFingerprintCache[$a13EvaluatorCacheKey] = [ordered]@{
  kind='repository-patterns'
  patterns=@($a13EvaluatorPatterns | Sort-Object -Unique)
  file_count=[int]$a13OriginalEvaluator.file_count
  sha256=('7' * 64)
}
try {
  $a13ChangedEvaluatorFingerprint = Get-MIRAssuranceTestFingerprint -Test $a13Plan.tests[0] -Plan $a13Plan -Context $a13Context
} finally {
  $script:MIRAssurancePatternFingerprintCache[$a13EvaluatorCacheKey] = $a13OriginalEvaluator
}
if ([string]$a13Fingerprint.inputs.'candidate-source'.kind -ne 'candidate-source' -or
    [string]$a13Fingerprint.inputs.'assurance-environment'.kind -ne 'assurance-environment' -or
    [string]$a13Fingerprint.inputs.'assurance-evaluator'.kind -ne 'assurance-evaluator' -or
    [string]$a13Fingerprint.inputs.'candidate-source'.source_tree -ne ('B' * 40) -or
    [string]$a13Fingerprint.inputs.'spec/programmes/mir4-4x-operating-programme-v1.json'.kind -ne 'repository-patterns' -or
    @($a13CandidateMutationFingerprints).Count -ne $a13CandidateMutations.Count -or
    @($a13CandidateMutationFingerprints | Where-Object { [string]$_.fingerprint_sha256 -eq [string]$a13Fingerprint.fingerprint_sha256 }).Count -ne 0 -or
    [string]$a13Fingerprint.fingerprint_sha256 -eq [string]$a13ChangedEnvironmentPlan.tests[0].fingerprint.fingerprint_sha256 -or
    [string]$a13Fingerprint.fingerprint_sha256 -eq [string]$a13ChangedCommandFingerprint.fingerprint_sha256 -or
    [string]$a13Fingerprint.fingerprint_sha256 -eq [string]$a13ChangedTargetFingerprint.fingerprint_sha256 -or
    [string]$a13Fingerprint.fingerprint_sha256 -eq [string]$a13ChangedInputFingerprint.fingerprint_sha256 -or
    [string]$a13Fingerprint.fingerprint_sha256 -eq [string]$a13ChangedEvaluatorFingerprint.fingerprint_sha256) {
  throw 'A13 exact-reuse fingerprint did not bind target, candidate source, environment, command, evaluator, and declared input components.'
}
$a13Programme = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'spec/programmes/mir4-4x-operating-programme-v1.json') | ConvertFrom-Json -Depth 100
$a13Task = @($a13Programme.synthesis.tasks | Where-Object { [string]$_.id -eq 'A13' })
$a13ImpactReceiptPath = Join-Path $RepoRoot 'spec/programmes/evidence/mir42/a13-impact-selection.json'
$a13ReuseReceiptPath = Join-Path $RepoRoot 'spec/programmes/evidence/mir42/a13-exact-fingerprint-reuse.json'
if ($a13Task.Count -ne 1 -or [string]$a13Task[0].state -ne 'active' -or
    (@($a13Task[0].evidence | ForEach-Object { [string]$_ }) -join '|') -ne
      'spec/programmes/evidence/mir42/a13-impact-selection.json|spec/programmes/evidence/mir42/a13-exact-fingerprint-reuse.json' -or
    -not (Test-Path -LiteralPath $a13ImpactReceiptPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $a13ReuseReceiptPath -PathType Leaf)) {
  throw 'A13 programme state does not retain the two candidate-bound implementation receipts without claiming candidate completion.'
}
$a13ImpactReceipt = Get-Content -Raw -LiteralPath $a13ImpactReceiptPath | ConvertFrom-Json -Depth 100
$a13ReuseReceipt = Get-Content -Raw -LiteralPath $a13ReuseReceiptPath | ConvertFrom-Json -Depth 100
if ([int]$a13ImpactReceipt.schema -ne 1 -or [string]$a13ImpactReceipt.kind -ne 'MIR42A13ImpactSelectionReceiptV1' -or
    [string]$a13ImpactReceipt.candidate_bound_plan.ledger_schema -ne 'mir-assurance-impact-proposition-ledger-v1' -or
    @($a13ImpactReceipt.candidate_bound_plan.candidate_fields).Count -ne 6 -or
    @($a13ImpactReceipt.candidate_bound_plan.selection_modes).Count -ne 3 -or
    [bool]$a13ImpactReceipt.release_authority -or [bool]$a13ImpactReceipt.publication_authority -or
    [int]$a13ReuseReceipt.schema -ne 1 -or [string]$a13ReuseReceipt.kind -ne 'MIR42A13ExactFingerprintReuseReceiptV1' -or
    [string]$a13ReuseReceipt.fingerprint_contract.candidate_source -ne 'fingerprint.inputs.candidate-source' -or
    [string]$a13ReuseReceipt.fingerprint_contract.environment -notmatch 'assurance-environment' -or
    [string]$a13ReuseReceipt.fingerprint_contract.command -ne 'fingerprint.definition.command' -or
    [string]$a13ReuseReceipt.fingerprint_contract.evaluator -ne 'fingerprint.inputs.assurance-evaluator' -or
    [string]$a13ReuseReceipt.contradiction_policy.required_action -ne 'independent-fresh-reproduction-required' -or
    @($a13ReuseReceipt.timing.observed_fields).Count -ne 3 -or
    [bool]$a13ReuseReceipt.release_authority -or [bool]$a13ReuseReceipt.publication_authority) {
  throw 'A13 receipts do not state the selected/omitted, exact-reuse, timing, and no-release-authority contract.'
}
$retiredCurrentInputPattern = '^(?:src(?:/|$)|prototypes(?:/|$)|locale(?:/|$)|settings[^/]*\.lua$|info\.json$)'
$typedInputCounts = [ordered]@{ source = 0; package = 0; historical = 0 }
foreach ($test in @($catalog.tests)) {
  $testInputs = Get-MIRAssuranceOptionalObjectValue -Object $test -Name 'inputs'
  foreach ($input in @($testInputs)) {
    $inputName = [string]$input
    if ($inputName -match $retiredCurrentInputPattern) {
      throw "Current assurance input revives a retired product root: $($test.id) -> $inputName"
    }
    if ($inputName.StartsWith('source/', [StringComparison]::Ordinal)) {
      throw "Current source assurance input must declare source: authority: $($test.id) -> $inputName"
    }
    if ($inputName.StartsWith('source:', [StringComparison]::Ordinal)) {
      $typedInputCounts.source++
      if (-not $inputName.Substring('source:'.Length).StartsWith('source/', [StringComparison]::Ordinal)) {
        throw "Current source assurance input is outside the canonical source root: $($test.id) -> $inputName"
      }
    } elseif ($inputName.StartsWith('package:', [StringComparison]::Ordinal)) {
      $typedInputCounts.package++
    } elseif ($inputName.StartsWith('historical:', [StringComparison]::Ordinal)) {
      $typedInputCounts.historical++
      if ($inputName -notmatch '^historical:[0-9a-f]{40}:[^:]+$') {
        throw "Historical assurance input is not commit-pinned: $($test.id) -> $inputName"
      }
    }
  }
}
foreach ($kind in $typedInputCounts.Keys) {
  if ([int]$typedInputCounts[$kind] -eq 0) {
    throw "Assurance catalog must exercise explicit $kind proof-input authority."
  }
}
$typedFingerprintContext = [pscustomobject]@{ target = '2.1' }
$typedFingerprintPlan = [pscustomobject]@{}
$typedFingerprintTest = [pscustomobject]@{}
$sourceFingerprint = Get-MIRAssuranceInputFingerprint -InputName 'source:source/prototypes/mir/settings/**' -Plan $typedFingerprintPlan -Context $typedFingerprintContext -Test $typedFingerprintTest
$packageFingerprint = Get-MIRAssuranceInputFingerprint -InputName 'package:info.json' -Plan $typedFingerprintPlan -Context $typedFingerprintContext -Test $typedFingerprintTest
$historicalFingerprint = Get-MIRAssuranceInputFingerprint -InputName 'historical:297aa5cc902da96847165a4f9caa1048608839fb:prototypes/mir/compatibility/repairs/factorio_2_1_ambient_sound_schema.lua' -Plan $typedFingerprintPlan -Context $typedFingerprintContext -Test $typedFingerprintTest
$balanceFingerprint = Get-MIRAssuranceBalanceContractFingerprint
if ([string]$sourceFingerprint.kind -ne 'current-source' -or [int]$sourceFingerprint.file_count -le 0 -or
    [string]$packageFingerprint.kind -ne 'materialized-package' -or [string]$packageFingerprint.target -ne 'f210' -or [int]$packageFingerprint.file_count -ne 1 -or
    [string]$historicalFingerprint.kind -ne 'pinned-historical' -or [string]$historicalFingerprint.commit -ne '297aa5cc902da96847165a4f9caa1048608839fb' -or
    [string]$balanceFingerprint.kind -ne 'balance-contract' -or @($balanceFingerprint.source.Keys).Count -ne 5) {
  throw 'Typed assurance proof-input fingerprints did not retain their distinct current-source, materialized-package, and pinned-historical authorities.'
}
try {
  $null = Get-MIRAssuranceInputFingerprint -InputName 'source:source/does-not-exist/**' -Plan $typedFingerprintPlan -Context $typedFingerprintContext -Test $typedFingerprintTest
  throw 'A required missing current-source assurance input was accepted.'
} catch {
  if ($_.Exception.Message -notmatch '^\[mir-assurance-required-source-input-no-match\] source/does-not-exist/\*\*$') { throw }
}
try {
  $null = Get-MIRAssuranceInputFingerprint -InputName 'source:source\..\README.md' -Plan $typedFingerprintPlan -Context $typedFingerprintContext -Test $typedFingerprintTest
  throw 'A Windows-separator source traversal assurance input was accepted.'
} catch {
  if ($_.Exception.Message -cne '[mir-assurance-source-input-path] source\..\README.md') { throw }
}
$currentTargetContext = Get-MIRAssuranceMaterializedPackageContext -Target 'f210'
$ambientRepairOutput = Resolve-MIR4CurrentTargetPackageOutputPath -Context $currentTargetContext -RelativePath 'prototypes/mir/compatibility/repairs/factorio_2_1_ambient_sound_schema.lua' -AllowMissing
$currentCompatibilitySource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.mir/compatibility.yml')
$currentCompilerDiagnosticsSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'tools/lib/validation/runner/StaticCompilerDiagnostics.ps1')
if ($null -ne $ambientRepairOutput -or
    $currentCompatibilitySource.Contains('factorio_2_1_ambient_sound_schema') -or
    $currentCompilerDiagnosticsSource.Contains('factorio_2_1_ambient_sound_schema')) {
  throw 'Current source or F210 materialization revived the retired ambient-sound schema repair instead of preserving it as historical-only evidence.'
}
$campaignFingerprintRoot = Join-Path ([IO.Path]::GetTempPath()) ("mir-assurance-performance-campaign-" + [guid]::NewGuid().ToString("N"))
$originalAssuranceRepo = $script:repo
$originalAssuranceRepositoryFilesCache = $script:MIRAssuranceRepositoryFilesCache
$originalAssurancePatternFingerprintCache = $script:MIRAssurancePatternFingerprintCache
$originalAssuranceGitIndexBlobs = $script:MIRAssuranceGitIndexBlobs
$originalAssuranceDirtyPaths = $script:MIRAssuranceDirtyPaths
$originalAssuranceBlobCache = $script:MIRAssuranceBlobCache
$originalAssuranceTreeHashCache = $script:MIRAssuranceTreeHashCache
try {
  $campaignRoot = Join-Path $campaignFingerprintRoot ".mir"
  $versionedCampaignRoot = Join-Path $campaignRoot "performance-campaigns"
  New-Item -ItemType Directory -Force -Path $versionedCampaignRoot | Out-Null
  [IO.File]::WriteAllText((Join-Path $campaignRoot "releases.json"), '{"schema":1,"authority":"canonical-release-ledger","development":{"factorio-2.1":{"mir_version":"3.2.5","candidate_id":"C32"}}}', [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $campaignRoot "performance-campaign.json"), '{"schema":2,"release":"3.2.2"}', [Text.UTF8Encoding]::new($false))
  $activeCampaignPath = Join-Path $versionedCampaignRoot "3.2.5-C32.json"
  $unrelatedCampaignPath = Join-Path $versionedCampaignRoot "3.2.4-C31.json"
  [IO.File]::WriteAllText($activeCampaignPath, '{"schema":2,"factorio_version":"2.1.12"}', [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($unrelatedCampaignPath, '{"schema":2,"factorio_version":"2.1.12"}', [Text.UTF8Encoding]::new($false))
  & git -C $campaignFingerprintRoot init --quiet
  & git -C $campaignFingerprintRoot add -- .mir
  if ($LASTEXITCODE -ne 0) { throw "Unable to materialize the performance campaign fingerprint fixture Git index." }
  $script:repo = $campaignFingerprintRoot
  $script:MIRAssuranceRepositoryFilesCache = $null
  $script:MIRAssurancePatternFingerprintCache = @{}
  $script:MIRAssuranceGitIndexBlobs = $null
  $script:MIRAssuranceDirtyPaths = $null
  $script:MIRAssuranceBlobCache = $null
  $script:MIRAssuranceTreeHashCache = $null
  $campaignContext = [pscustomobject]@{target="2.1"}
  $resolvedCampaignPath = Resolve-MIRAssurancePerformanceCampaignPath -Context $campaignContext
  $beforeCampaignFingerprint = Get-MIRAssurancePerformanceCampaignFingerprint -Context $campaignContext
  [IO.File]::WriteAllText($unrelatedCampaignPath, '{"schema":2,"factorio_version":"2.1.13"}', [Text.UTF8Encoding]::new($false))
  $script:MIRAssurancePatternFingerprintCache = @{}
  $script:MIRAssuranceGitIndexBlobs = $null
  $script:MIRAssuranceDirtyPaths = $null
  $script:MIRAssuranceBlobCache = $null
  $script:MIRAssuranceTreeHashCache = $null
  $afterUnrelatedCampaignFingerprint = Get-MIRAssurancePerformanceCampaignFingerprint -Context $campaignContext
  [IO.File]::WriteAllText($activeCampaignPath, '{"schema":2,"factorio_version":"2.1.13"}', [Text.UTF8Encoding]::new($false))
  $script:MIRAssurancePatternFingerprintCache = @{}
  $script:MIRAssuranceGitIndexBlobs = $null
  $script:MIRAssuranceDirtyPaths = $null
  $script:MIRAssuranceBlobCache = $null
  $script:MIRAssuranceTreeHashCache = $null
  $afterActiveCampaignFingerprint = Get-MIRAssurancePerformanceCampaignFingerprint -Context $campaignContext
  if ($resolvedCampaignPath -ne ".mir/performance-campaigns/3.2.5-C32.json" -or
      ($beforeCampaignFingerprint.patterns -join "|") -ne ".mir/performance-campaign.json|.mir/performance-campaigns/3.2.5-C32.json" -or
      [string]$beforeCampaignFingerprint.sha256 -ne [string]$afterUnrelatedCampaignFingerprint.sha256 -or
      [string]$beforeCampaignFingerprint.sha256 -eq [string]$afterActiveCampaignFingerprint.sha256) {
    throw "Performance assurance execution and fingerprints must bind the root calibration and exact active versioned campaign, but no unrelated campaign: resolved=$resolvedCampaignPath patterns=$($beforeCampaignFingerprint.patterns -join '|') before=$($beforeCampaignFingerprint.sha256) unrelated=$($afterUnrelatedCampaignFingerprint.sha256) active=$($afterActiveCampaignFingerprint.sha256)."
  }
} finally {
  $script:repo = $originalAssuranceRepo
  $script:MIRAssuranceRepositoryFilesCache = $originalAssuranceRepositoryFilesCache
  $script:MIRAssurancePatternFingerprintCache = $originalAssurancePatternFingerprintCache
  $script:MIRAssuranceGitIndexBlobs = $originalAssuranceGitIndexBlobs
  $script:MIRAssuranceDirtyPaths = $originalAssuranceDirtyPaths
  $script:MIRAssuranceBlobCache = $originalAssuranceBlobCache
  $script:MIRAssuranceTreeHashCache = $originalAssuranceTreeHashCache
  if (Test-Path -LiteralPath $campaignFingerprintRoot) { Remove-Item -LiteralPath $campaignFingerprintRoot -Recurse -Force }
}
$candidateContext = New-MIR4CurrentTargetPackageContext -RepoRoot $RepoRoot -Target f210
$candidateInfo = Get-MIR4CurrentTargetPackageOutputText -Context $candidateContext -RelativePath 'info.json' | ConvertFrom-Json
$candidateSourceTree = (& git -C $RepoRoot rev-parse "HEAD^{tree}").Trim()
$candidatePath = (Get-MIRAssuranceDevelopmentCandidatePath -Info $candidateInfo -SourceTree $candidateSourceTree -Target '2.1').Replace("\", "/")
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
$candidateAuthority = Get-MIR4CanonicalPackageAuthority -RepoRoot $RepoRoot
$candidateTarget = @($candidateAuthority.targets | Where-Object { [string]$_.target -ceq 'f210' })
if ($candidateTarget.Count -ne 1) { throw 'F210 is absent from canonical package authority.' }
$candidateIdentity = Resolve-MIR4CanonicalPackageIdentity -RepoRoot $RepoRoot -Target f210 -SourceVersion ([string]$candidateTarget[0].baseline_source_version)
$expectedCandidatePattern = "/build/packages/assurance/f210/MIR4-ASSURANCE-[A-F0-9]{40}/$([regex]::Escape([string]$candidateIdentity.package_name))$"
if ($candidatePath -notmatch $expectedCandidatePattern -or
    $candidatePath -match "/dist/") {
  throw "Default MIR 4 assurance candidates must be target/source-tree addressed below canonical build/packages authority."
}
$externalTreeRoot = Join-Path ([IO.Path]::GetTempPath()) ("mir-assurance-tree-cache-" + [guid]::NewGuid().ToString("N"))
try {
  New-Item -ItemType Directory -Force -Path (Join-Path $externalTreeRoot "data") | Out-Null
  Set-Content -LiteralPath (Join-Path $externalTreeRoot "data\sample.txt") -Value "stable" -Encoding UTF8
  $script:MIRAssuranceExternalTreeFingerprintCache = @{}
  $firstTreeFingerprint = Get-MIRAssuranceExternalTreeFingerprint -Root $externalTreeRoot -RelativeRoots @("data") -MissingLabel "test-tree"
  $secondTreeFingerprint = Get-MIRAssuranceExternalTreeFingerprint -Root $externalTreeRoot -RelativeRoots @("data") -MissingLabel "test-tree"
  if ($firstTreeFingerprint.sha256 -ne $secondTreeFingerprint.sha256 -or $script:MIRAssuranceExternalTreeFingerprintCache.Count -ne 1) {
    throw "External-tree fingerprints are not reused within one assurance process."
  }
} finally {
  if (Test-Path -LiteralPath $externalTreeRoot) { Remove-Item -LiteralPath $externalTreeRoot -Recurse -Force }
}

$factorioFingerprintRoots = @(
  (Join-Path ([IO.Path]::GetTempPath()) ("mir-assurance-factorio-a-" + [guid]::NewGuid().ToString("N"))),
  (Join-Path ([IO.Path]::GetTempPath()) ("mir-assurance-factorio-b-" + [guid]::NewGuid().ToString("N")))
)
try {
  foreach ($factorioRoot in $factorioFingerprintRoots) {
    $factorioBinaryDir = Join-Path $factorioRoot "bin/x64"
    $factorioDataDir = Join-Path $factorioRoot "data/base"
    New-Item -ItemType Directory -Force -Path $factorioBinaryDir, $factorioDataDir | Out-Null
    [IO.File]::WriteAllText((Join-Path $factorioBinaryDir "factorio.exe"), "same-binary", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $factorioDataDir "info.json"), "same-data", [Text.UTF8Encoding]::new($false))
  }
  $script:MIRAssuranceExternalFileFingerprintCache = @{}
  $script:MIRAssuranceExternalTreeFingerprintCache = @{}
  $factorioFingerprintA = Get-MIRAssuranceFactorioInstallationFingerprint -FactorioPath (Join-Path $factorioFingerprintRoots[0] "bin/x64/factorio.exe")
  $factorioFingerprintB = Get-MIRAssuranceFactorioInstallationFingerprint -FactorioPath (Join-Path $factorioFingerprintRoots[1] "bin/x64/factorio.exe")
  if ([string]$factorioFingerprintA.sha256 -ne [string]$factorioFingerprintB.sha256 -or
      [string]$factorioFingerprintA.installation_sha256 -ne [string]$factorioFingerprintB.installation_sha256 -or
      [string]$factorioFingerprintA.sha256 -ne [string]$factorioFingerprintA.installation_sha256 -or
      [string]$factorioFingerprintA.legacy_installation_sha256 -eq [string]$factorioFingerprintB.legacy_installation_sha256) {
    throw "Assurance Factorio installation identity is not path-independent with an explicit legacy alias."
  }
} finally {
  foreach ($factorioRoot in $factorioFingerprintRoots) {
    if (Test-Path -LiteralPath $factorioRoot) { Remove-Item -LiteralPath $factorioRoot -Recurse -Force }
  }
}

$wrapper = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".github\workflows\assurance-full.yml")
foreach ($requiredWrapperSnippet in @(
  "uses: ./.github/workflows/control-plane-v5.yml",
  'source_ref: ${{ inputs.source_ref }}',
  'release: ${{ inputs.release }}',
  'target: ${{ inputs.target }}',
  'mode: ${{ inputs.mode }}',
  'prior_release: ${{ inputs.prior_release }}',
  'local_mod_zip_dir: ${{ inputs.local_mod_zip_dir }}',
  "secrets: inherit"
)) {
  if (-not $wrapper.Contains($requiredWrapperSnippet)) {
    throw "Assurance dispatch wrapper does not bind the reusable v5 workflow input: $requiredWrapperSnippet"
  }
}

$workflow = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".github\workflows\control-plane-v5.yml")
foreach ($requiredWorkflowSnippet in @(
  "MIR_CP_TRUST_CLASS: ci",
  "MIR_PROTECTED_ENVIRONMENT: release-candidate",
  "environment: release-candidate",
  "needs: [context, package, environments]",
  "needs: [context, static, package, environments, transitions, ecosystem]",
  "needs: [context, transitions, ecosystem, performance]",
  "needs: [context, static, package, environments, transitions, ecosystem, performance, manual]",
  "-TrustClass protected-release -EvidenceRoot build/results/evidence",
  "-AggregateTaskId qualification.full -TrustClass protected-release",
  "Invoke-MIRControlPlane.ps1 seal",
  "-TaskId shadow.equivalence",
  "Invoke-MIRControlPlane.ps1 promotion",
  'ref: ${{ inputs.source_ref }}',
  "pattern: mir-v5-evidence-*",
  "mir-v5-qualification-"
)) {
  if (-not $workflow.Contains($requiredWorkflowSnippet)) {
    throw "Reusable v5 workflow does not enforce the required protected evidence chain: $requiredWorkflowSnippet"
  }
}
if ($wrapper -match 'dist/\*\.zip' -or $workflow -match 'dist/\*\.zip') {
  throw "Protected qualification must transfer the exact context candidate rather than select an arbitrary distribution glob."
}

$releaseCandidateWorkflow = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".github\workflows\release-candidate.yml")
foreach ($requiredReleaseCandidateSnippet in @(
  'local_authority_repo:',
  'git clone --quiet --shared --no-checkout',
  'git -C $authority cat-file -e',
  'Checked-out controller does not match the workflow source commit.',
  'Built archive SHA mismatch:',
  'resume_exact_dist_evidence_run:',
  'Admit prior passing exact-dist evidence',
  'Prior exact-dist evidence was invalidated by controller changes',
  'Join-Path $controller ".mir/releases/records/$version.json"',
  "'.github/workflows/release-candidate.yml'",
  "'scripts/Invoke-MIRCompatAudit.ps1'",
  "'tools/commands/compatibility/Invoke-MIRCompatAudit.ps1'",
  "'tests/release/Test-MIRPerformanceBudgets.ps1'",
  "'tests/tooling/Test-MIRAssurance.ps1'",
  "@(`$summary.expected_scenarios).Count -ne 124",
  "@(`$summary.scenarios).Count -ne 124",
  'Run complete exact-dist validation',
  '-CandidateZip $candidateArchive',
  'Run strict targeted compatibility gate',
  'MIR_COMPAT_RUNTIME_ROOT: ''C:\tmp\mir-compat-runtime\${{ github.run_id }}-${{ github.run_attempt }}''',
  'MIR_RC_CANDIDATE_SHA: ${{ inputs.candidate_sha }}',
  "--candidate `$candidateArchive",
  '--candidate-source $env:MIR_RC_CANDIDATE_SHA',
  "--output 'build/results/release-gate'",
  'MIRProtectedReleaseCandidateRunV2',
  'MIR_RC_CANDIDATE_ARCHIVE=$candidateArchive',
  'build/results/protected-release-candidate/${{ github.run_id }}-${{ github.run_attempt }}',
  "runtime-evidence",
  'runtime_evidence = $runtimeEvidenceRows'
)) {
  if (-not $releaseCandidateWorkflow.Contains($requiredReleaseCandidateSnippet)) {
    throw "Protected release-candidate workflow omits its offline exact-root contract: $requiredReleaseCandidateSnippet"
  }
}
if ($releaseCandidateWorkflow -match '(?m)^\s*uses:\s*actions/(checkout|upload-artifact)@') {
  throw "The self-hosted release-candidate lane must not depend on remote checkout or artifact actions."
}

$validateWorkflow = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".github\workflows\validate.yml")
foreach ($requiredWorkflowSnippet in @(
  'Resolve content-addressed development candidate',
  'build/candidates/[0-9]+\.[0-9]+\.[0-9]+/',
  'path: ${{ env.MIR_DEVELOPMENT_CANDIDATE }}',
  'mir-verification-plan-${{ github.run_id }}-${{ github.run_attempt }}',
  'mir-development-candidate-${{ github.run_id }}-${{ github.run_attempt }}',
  'plan_artifact: ${{ steps.artifact-names.outputs.plan_artifact }}',
  'candidate_artifact: ${{ steps.artifact-names.outputs.candidate_artifact }}',
  'name: ${{ needs.plan.outputs.plan_artifact }}',
  'name: ${{ needs.plan.outputs.candidate_artifact }}',
  'mir-evidence-${{ github.run_id }}-${{ github.run_attempt }}-${{ matrix.safe_test_id }}-${{ matrix.fingerprint }}',
  '$plan.candidate_descriptor.path',
  '[IO.Path]::IsPathRooted($candidateRelative)',
  'Plan candidate descriptor is not a governed repository-relative path',
  '--candidate $env:MIR_DEVELOPMENT_CANDIDATE',
  '$work = @($plan.work)',
  'if ($work.Count -eq 0)',
  'test_id = "reuse-only"',
  'no_op = $true',
  '${{ matrix.no_op != true }}',
  '${{ matrix.no_op == true }}',
  '${{ always() && matrix.no_op != true }}',
  'pattern: mir-evidence-${{ github.run_id }}-*',
  '--artifact-prefix mir-evidence-${{ github.run_id }}- --retry-across-attempts --current-run-attempt ${{ github.run_attempt }}'
)) {
  if (-not $validateWorkflow.Contains($requiredWorkflowSnippet)) {
    throw "Hosted validation workflow does not safely handle an all-reuse plan: $requiredWorkflowSnippet"
  }
}
if ($validateWorkflow.Contains('pattern: mir-evidence-${{ github.run_id }}-${{ github.run_attempt }}-*')) {
  throw "Hosted aggregate fan-in must retain verified worker artifacts from earlier attempts of the same workflow run."
}
if ($validateWorkflow.Contains('Remove-Item -LiteralPath $source -Force')) {
  throw "Hosted planning must preserve the tracked candidate source so every clean worker reconstructs the same canonical repository state."
}
if ($validateWorkflow -match "github\.(ref|head_ref|base_ref)\s*==\s*'[^']*legacy'" -or
    $validateWorkflow -notmatch "github\.base_ref\s*==\s*'tmp/2\.0'") {
  throw "Hosted validation must treat legacy as the Factorio 2.1 terminal alias and reserve the Factorio 2.0 lane for tmp/2.0."
}
if ($validateWorkflow.Contains('$candidate = Join-Path $PWD ([string]$plan.candidate)') -or
    @([regex]::Matches($validateWorkflow, '\$plan\.candidate_descriptor\.path')).Count -ne 6 -or
    @([regex]::Matches($validateWorkflow, '\[IO\.Path\]::IsPathRooted\(\$candidateRelative\)')).Count -ne 2) {
  throw "Hosted workers and aggregate verification must reconstruct the candidate from the governed repo-relative descriptor path, never the planner checkout's absolute path."
}
foreach ($typedStatus in @("upstream-plan-failed", "infrastructure-failed", "worker-artifacts-received")) {
  if (-not $validateWorkflow.Contains($typedStatus)) {
    throw "Hosted validation workflow does not preserve typed aggregate status: $typedStatus"
  }
}
if ($validateWorkflow -notmatch "needs\.plan\.result == 'success'" -or
    $validateWorkflow -notmatch "needs\.plan\.result != 'success'") {
  throw "Hosted validation must not reinterpret an upstream plan failure as missing worker evidence."
}
if ($validateWorkflow -match '(?m)^\s+path:\s+dist(?:/\*\.zip)?\s*$') {
  throw "Hosted validation workers must not materialize the active development candidate in immutable historical dist authority."
}
if (@([regex]::Matches($validateWorkflow, '--candidate \$env:MIR_DEVELOPMENT_CANDIDATE')).Count -ne 4) {
  throw "Hosted planning, exact workers, deterministic import, and the aggregate gate must all bind the isolated development candidate explicitly."
}

foreach ($fanInCase in @(
  @{Path=".github\workflows\validate.yml"; Prefix="mir-evidence-"},
  @{Path=".github\workflows\assurance-targeted.yml"; Prefix="mir-targeted-evidence-"},
  @{Path=".github\workflows\assurance-scheduled.yml"; Prefix="mir-scheduled-evidence-"}
)) {
  $fanInWorkflow = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $fanInCase.Path)
  foreach ($requiredFanInSnippet in @(
    'path: build/results/assurance/evidence/${{ matrix.safe_test_id }}/${{ matrix.fingerprint }}',
    'path: build/results/assurance/worker-evidence',
    'verify import-workers',
    ('name: ' + $fanInCase.Prefix + '${{ github.run_id }}-${{ github.run_attempt }}-${{ matrix.safe_test_id }}-${{ matrix.fingerprint }}'),
    ('pattern: ' + $fanInCase.Prefix + '${{ github.run_id }}-*'),
    ('--artifact-prefix ' + $fanInCase.Prefix + '${{ github.run_id }}- --retry-across-attempts --current-run-attempt ${{ github.run_attempt }}'),
    'build/results/assurance/worker-import.json'
  )) {
    if (-not $fanInWorkflow.Contains($requiredFanInSnippet)) {
      throw "Assurance workflow '$($fanInCase.Path)' omits deterministic worker fan-in: $requiredFanInSnippet"
    }
  }
  if ($fanInWorkflow.Contains("merge-multiple: true")) {
    throw "Assurance workflow '$($fanInCase.Path)' still extracts mutable worker pointers into one shared directory."
  }
}

foreach ($planTransportCase in @(
  @{Path=".github\workflows\validate.yml"; Artifact="mir-verification-plan-"},
  @{Path=".github\workflows\assurance-targeted.yml"; Artifact="mir-targeted-plan-and-candidate-"},
  @{Path=".github\workflows\assurance-scheduled.yml"; Artifact="mir-scheduled-plan-and-candidate-"}
)) {
  $planTransportWorkflow = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $planTransportCase.Path)
  foreach ($requiredPlanTransportSnippet in @(
    'plan_artifact: ${{ steps.artifact-names.outputs.plan_artifact }}',
    'id: artifact-names',
    ('"plan_artifact=' + $planTransportCase.Artifact + '${{ github.run_id }}-${{ github.run_attempt }}"'),
    'name: ${{ steps.artifact-names.outputs.plan_artifact }}',
    'name: ${{ needs.plan.outputs.plan_artifact }}'
  )) {
    if (-not $planTransportWorkflow.Contains($requiredPlanTransportSnippet)) {
      throw "Assurance workflow '$($planTransportCase.Path)' omits attempt-qualified exact plan/candidate transport: $requiredPlanTransportSnippet"
    }
  }
  $attemptInvariantName = [regex]::Escape([string]$planTransportCase.Artifact.TrimEnd('-'))
  if ($planTransportWorkflow -match "(?m)^\s*name:\s*$attemptInvariantName\s*$") {
    throw "Assurance workflow '$($planTransportCase.Path)' retains an attempt-invariant plan/candidate artifact name."
  }
}

$protectedWorkflow = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".github\workflows\control-plane-v5.yml")
foreach ($requiredProtectedFanInSnippet in @(
  'path: build/results/control-plane-worker-evidence',
  'Import content-addressed worker objects deterministically',
  '-Operation import-workers',
  'build/results/control-plane-v5/worker-import.json'
)) {
  if (-not $protectedWorkflow.Contains($requiredProtectedFanInSnippet)) {
    throw "Protected qualification omits isolated content-addressed worker import: $requiredProtectedFanInSnippet"
  }
}
if ($protectedWorkflow.Contains("merge-multiple: true")) {
  throw "Protected qualification still merges worker artifact trees by extraction order."
}

$assuranceEvidence = $assuranceEvidenceSource
foreach ($requiredIngestionGuard in @(
  'mir-assurance-worker-receipt-v3',
  'adopted-exact-trusted-capsule',
  'evidence-disposition',
  'Test-MIRAssuranceFreshCampaignEvidence',
  'Get-MIRAssuranceCampaignCheckpoint',
  'Set-MIRAssuranceAttemptPointer',
  'Get-MIRAssuranceOutcomeDigest',
  'Resolve-MIRAssuranceAttemptQuarantine',
  'mir-assurance-attempt-state-lock-v1',
  'trusted-exact-attempt-contradiction',
  'independent-fresh-reproduction-required',
  'mir-plan-execution-quarantine-v1',
  'cold_execution_seconds',
  'reused_source_seconds',
  'checkpointed_source_seconds',
  'stale-ignored',
  'ReparsePoint',
  'max_entries_per_artifact',
  'max_expanded_bytes_per_artifact',
  'max_file_bytes',
  'duplicate canonical object paths',
  'receipt_material_sha256',
  'RetryAcrossAttempts',
  'CurrentRunAttempt',
  'Publish-MIRAssuranceWorkerObject',
  'bounded tree scan',
  'superseded-by-later-run-attempt',
  'stale-plan-transport',
  'selected transport run and attempt'
)) {
  if (-not $assuranceEvidence.Contains($requiredIngestionGuard)) {
    throw "Assurance worker ingestion omits structural guard: $requiredIngestionGuard"
  }
}
$assuranceEntry = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\Invoke-MIRAssurance.ps1")
foreach ($requiredCheckpointSnippet in @('time-budget-minutes', 'status -eq "checkpointed"', 'TimeBudgetSeconds')) {
  if (-not $assuranceEntry.Contains($requiredCheckpointSnippet)) {
    throw "Assurance checkpoint facade omits required contract: $requiredCheckpointSnippet"
  }
}
foreach ($requiredRetryImportSnippet in @('--current-run-attempt', 'RetryAcrossAttempts', 'CurrentRunAttempt')) {
  if (-not $assuranceEntry.Contains($requiredRetryImportSnippet)) {
    throw "Assurance import facade omits the independently bound aggregate retry attempt: $requiredRetryImportSnippet"
  }
}
$assuranceCore = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\Core.ps1")
foreach ($canonicalPackageBinding in @(
  'targets/package-authority.json',
  'baseline_source_version',
  'build\packages\assurance'
)) {
  if (-not $assuranceCore.Contains($canonicalPackageBinding)) {
    throw "MIR 4 assurance selection is not bound to canonical package authority: $canonicalPackageBinding"
  }
}
if ($assuranceCore.Contains('build\mir4\emergency-lane\distributions\more-infinite-research_4.0.21000.zip')) {
  throw 'Current MIR 4 assurance selection still names the retired emergency-lane package writer.'
}
$bootstrapBuilder = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\commands\release\New-MIR4BootstrapLocalCandidate.ps1")
if (-not $bootstrapBuilder.Contains("foreach (`$targetPlan in `$targets) {`r`n  `$correction = Get-MIR4PlanCorrection -PlanTarget `$targetPlan") -and
    -not $bootstrapBuilder.Contains("foreach (`$targetPlan in `$targets) {`n  `$correction = Get-MIR4PlanCorrection -PlanTarget `$targetPlan")) {
  throw "MIR 4 bootstrap materialization does not bind the optional correction per target and can inherit caller scope."
}
foreach ($generatedOutputExclusion in @('build/results/*', 'build/*', 'build/results/*')) {
  if (-not $assuranceCore.Contains($generatedOutputExclusion)) {
    throw "Generated runtime summaries could enter their own future input fingerprint: $generatedOutputExclusion"
  }
}

$equivalenceParent = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build/tmp'))
$equivalenceRoot = Join-Path $equivalenceParent ("mir-clean-root-equivalence-" + [guid]::NewGuid().ToString("N").Substring(0, 16))
$plannerRoot = Join-Path $equivalenceRoot "planner"
$workerRoot = Join-Path $equivalenceRoot "worker"
$pwshPath = (Get-Process -Id $PID).Path
try {
  New-Item -ItemType Directory -Force -Path $equivalenceRoot | Out-Null
  $stagedPatchPath = Join-Path $equivalenceRoot "staged-index.patch"
  & git -C $RepoRoot diff --cached --binary --full-index --output=$stagedPatchPath
  if ($LASTEXITCODE -ne 0) { throw "Unable to capture the exact staged tree for separate-root equivalence." }
  $sourceGitRoot = (& git -c "safe.directory=$RepoRoot" -C $RepoRoot rev-parse --absolute-git-dir).Trim()
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sourceGitRoot)) {
    throw "Unable to resolve the source repository Git directory for separate-root equivalence."
  }
  # The roots need independent indexes and working trees for LF/CRLF proof, not
  # duplicate copies of the immutable repository object store. Sharing objects
  # prevents this regression from becoming a disk-capacity false failure.
  & git -c "safe.directory=$RepoRoot" -c "safe.directory=$sourceGitRoot" clone -c core.autocrlf=false --quiet --shared $RepoRoot $plannerRoot
  if ($LASTEXITCODE -ne 0) { throw "Unable to create the LF planner root." }
  if ((Get-Item -LiteralPath $stagedPatchPath).Length -gt 0) {
    & git -C $plannerRoot apply --index --whitespace=nowarn $stagedPatchPath
    if ($LASTEXITCODE -ne 0) { throw "Unable to materialize the exact staged tree in separate root: $plannerRoot" }
    # Give both line-ending configurations a real clean checkout of the same
    # staged tree. Applying a patch independently under core.autocrlf=true can
    # leave newly relocated raw-hashed files in non-canonical working bytes.
    & git -C $plannerRoot -c user.name='MIR assurance self-test' -c user.email='mir-assurance@invalid.local' commit --quiet -m 'self-test: materialize staged equivalence tree'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to commit the staged equivalence tree in the disposable planner root.' }
  }
  & git -c "safe.directory=$plannerRoot" clone -c core.autocrlf=true --quiet --shared $plannerRoot $workerRoot
  if ($LASTEXITCODE -ne 0) { throw "Unable to create the CRLF worker root from the exact staged tree." }

  foreach ($root in @($plannerRoot, $workerRoot)) {
    & $pwshPath -NoProfile -File (Join-Path $root "tools\mir.ps1") assurance build --target 2.1 --output build/results/assurance/development-build.json
    if ($LASTEXITCODE -ne 0) { throw "Content-addressed candidate build failed in separate root: $root" }
  }

  # A normal planner must not consume mutable local staging bytes from dist.
  # Create a worker-private ignored decoy after the isolated candidate exists.
  $dirtyPublicDist = Join-Path $workerRoot "dist\more-infinite-research_3.2.5.zip"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dirtyPublicDist) | Out-Null
  [IO.File]::WriteAllBytes($dirtyPublicDist, [byte[]](80,75,3,4,77,73,82,52))
  $ignoredPublishedDistPaths = @(& git -C $workerRoot check-ignore --no-index -- 'dist/more-infinite-research_3.2.5.zip')
  if ($LASTEXITCODE -ne 0 -or $ignoredPublishedDistPaths.Count -ne 1 -or
      [string]$ignoredPublishedDistPaths[0] -ne "dist/more-infinite-research_3.2.5.zip" -or
      @(& git -C $workerRoot diff --name-only -- dist).Count -ne 0) {
    throw "Separate-root regression did not create the intended ignored local-dist decoy."
  }

  & $pwshPath -NoProfile -File (Join-Path $plannerRoot "tools\mir.ps1") verify plan --target 2.1 --profile fast --output build/results/assurance/verification-plan.json
  if ($LASTEXITCODE -ne 0) { throw "Planner-root verification plan failed." }
  & $pwshPath -NoProfile -File (Join-Path $workerRoot "tools\mir.ps1") verify plan --target 2.1 --profile fast --output build/results/assurance/verification-plan.json
  if ($LASTEXITCODE -ne 0) { throw "Worker-root verification plan reconstruction failed." }

  $plannerPlan = Get-Content -Raw -LiteralPath (Join-Path $plannerRoot "build\results\assurance\verification-plan.json") | ConvertFrom-Json
  $workerPlan = Get-Content -Raw -LiteralPath (Join-Path $workerRoot "build\results\assurance\verification-plan.json") | ConvertFrom-Json
  if ([string]$plannerPlan.plan_material_sha256 -ne [string]$workerPlan.plan_material_sha256) {
    throw "Separate roots produced different canonical plan material."
  }
  $plannerFingerprints = @($plannerPlan.tests | Sort-Object id | ForEach-Object { "$($_.id)`t$($_.fingerprint.fingerprint_sha256)" })
  $workerFingerprints = @($workerPlan.tests | Sort-Object id | ForEach-Object { "$($_.id)`t$($_.fingerprint.fingerprint_sha256)" })
  if (@(Compare-Object $plannerFingerprints $workerFingerprints).Count -ne 0) {
    throw "Separate roots produced different exact test fingerprints."
  }
  if ([string]$plannerPlan.candidate_descriptor.sha256 -ne [string]$workerPlan.candidate_descriptor.sha256 -or
      [string]$plannerPlan.candidate_descriptor.content_sha256 -ne [string]$workerPlan.candidate_descriptor.content_sha256) {
    throw "Separate roots did not preserve exact isolated candidate identity."
  }

  # The development-contract proof reads command dispatch and script sources in
  # addition to the package builder.  Prove the real planner invalidates its
  # reusable row when each representative source changes; a synthetic hash
  # comparison would not exercise catalogue-to-fingerprint binding.
  function Get-MIRDevelopmentContractsPlanFingerprint {
    param([Parameter(Mandatory)]$Plan)
    $rows = @($Plan.tests | Where-Object { [string]$_.id -eq 'static.mir4-development-contracts' })
    if ($rows.Count -ne 1) { throw 'Verification plan does not contain exactly one development-contract test row.' }
    return $rows[0].fingerprint
  }
  # The development-contract test is deliberately selected by the dedicated
  # development profile, rather than the minimal `fast` profile used above for
  # the cross-platform general-plan comparison.  Exercise the profile that
  # owns this proposition so a missing row is never mistaken for reusable
  # evidence.
  & $pwshPath -NoProfile -File (Join-Path $plannerRoot "tools\mir.ps1") verify plan --target 2.1 --profile mir4-development --output build/results/assurance/verification-plan-development-contracts.json
  if ($LASTEXITCODE -ne 0) { throw 'Development-contract verification plan did not materialize.' }
  $developmentContractsPlan = Get-Content -Raw -LiteralPath (Join-Path $plannerRoot 'build\results\assurance\verification-plan-development-contracts.json') | ConvertFrom-Json
  $baselineDevelopmentContractsFingerprint = Get-MIRDevelopmentContractsPlanFingerprint -Plan $developmentContractsPlan
  $nonBuildCommandPath = Join-Path $plannerRoot 'tools\commands\workspace\Remove-MIRStaleArtifacts.ps1'
  [IO.File]::AppendAllText($nonBuildCommandPath, "`n# assurance planner invalidation: non-Build command`n", [Text.UTF8Encoding]::new($false))
  & $pwshPath -NoProfile -File (Join-Path $plannerRoot "tools\mir.ps1") verify plan --target 2.1 --profile mir4-development --output build/results/assurance/verification-plan-non-build-command.json
  if ($LASTEXITCODE -ne 0) { throw 'Verification plan did not reconstruct after non-Build command mutation.' }
  $nonBuildCommandPlan = Get-Content -Raw -LiteralPath (Join-Path $plannerRoot 'build\results\assurance\verification-plan-non-build-command.json') | ConvertFrom-Json
  $nonBuildCommandFingerprint = Get-MIRDevelopmentContractsPlanFingerprint -Plan $nonBuildCommandPlan
  if ([string]$nonBuildCommandFingerprint.fingerprint_sha256 -eq [string]$baselineDevelopmentContractsFingerprint.fingerprint_sha256 -or
      [string]$nonBuildCommandFingerprint.inputs.'tools/commands/**'.sha256 -eq [string]$baselineDevelopmentContractsFingerprint.inputs.'tools/commands/**'.sha256) {
    throw 'Development-contract assurance-plan reuse was not invalidated by a non-Build command source change.'
  }

  $scriptInputPath = Join-Path $plannerRoot 'scripts\Invoke-MIRAssurance.ps1'
  [IO.File]::AppendAllText($scriptInputPath, "`n# assurance planner invalidation: script input`n", [Text.UTF8Encoding]::new($false))
  & $pwshPath -NoProfile -File (Join-Path $plannerRoot "tools\mir.ps1") verify plan --target 2.1 --profile mir4-development --output build/results/assurance/verification-plan-scripts-input.json
  if ($LASTEXITCODE -ne 0) { throw 'Verification plan did not reconstruct after script input mutation.' }
  $scriptInputPlan = Get-Content -Raw -LiteralPath (Join-Path $plannerRoot 'build\results\assurance\verification-plan-scripts-input.json') | ConvertFrom-Json
  $scriptInputFingerprint = Get-MIRDevelopmentContractsPlanFingerprint -Plan $scriptInputPlan
  if ([string]$scriptInputFingerprint.fingerprint_sha256 -eq [string]$nonBuildCommandFingerprint.fingerprint_sha256 -or
      [string]$scriptInputFingerprint.inputs.'scripts/**'.sha256 -eq [string]$nonBuildCommandFingerprint.inputs.'scripts/**'.sha256) {
    throw 'Development-contract assurance-plan reuse was not invalidated by a scripts source change.'
  }
} finally {
  if (Test-Path -LiteralPath $equivalenceRoot) {
    $cleanupRoot = (Resolve-Path -LiteralPath $equivalenceRoot).ProviderPath
    if (-not $cleanupRoot.StartsWith($equivalenceParent.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        (Get-Item -LiteralPath $cleanupRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint -or
        (Split-Path -Leaf $cleanupRoot) -notlike 'mir-clean-root-equivalence-*') {
      throw 'Separate-root cleanup target is outside the owned scratch directory.'
    }
    Remove-Item -LiteralPath $cleanupRoot -Recurse -Force
  }
}

Write-Host "[ok] MIR assurance manifests, domain policy, target profiles, and stable test catalog passed."
