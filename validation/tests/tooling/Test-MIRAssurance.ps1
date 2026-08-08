param([string]$RepoRoot = "")
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $MirLegacyScriptRoot "..")).Path }

& (Join-Path $RepoRoot "scripts\Invoke-MIRAssurance.ps1") self-test
if ($LASTEXITCODE -ne 0) { throw "MIR assurance self-test failed." }
& (Join-Path $RepoRoot "validation\tests\tooling\Test-MIRVerificationSchemas.ps1") -RepoRoot $RepoRoot
if ($LASTEXITCODE -ne 0) { throw "MIR verification schema validation failed." }

$config = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\assurance.json") | ConvertFrom-Json
$impact = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\test-impact.yml") | ConvertFrom-Json
$catalog = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\tests.yml") | ConvertFrom-Json
$domains = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\domains.yml") | ConvertFrom-Json
$trust = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\trust.json") | ConvertFrom-Json
if ([int]$config.schema -ne 1 -or [int]$impact.schema -ne 1 -or [int]$catalog.schema -ne 2 -or [int]$domains.schema -ne 1 -or [int]$trust.schema -ne 1) {
  throw "Unsupported assurance manifest schema."
}
$releaseAssuranceSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\Release.ps1")
foreach ($requiredTrustSelfTestSnippet in @(
  '$differentTrustClass = if ([string]$Context.trust_class -eq "untrusted-pr")',
  '{ "protected-integration" } else { "untrusted-pr" }',
  '$differentTrustCapsule.producer.trust_class = $differentTrustClass'
)) {
  if (-not $releaseAssuranceSource.Contains($requiredTrustSelfTestSnippet)) {
    throw "Assurance trust-class self-test does not guarantee a different decoy class: $requiredTrustSelfTestSnippet"
  }
}

$ids = @($catalog.tests | ForEach-Object { [string]$_.id })
$duplicates = @($ids | Group-Object | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw "Duplicate assurance test IDs: $($duplicates.Name -join ', ')" }

$releaseHistoryClassificationCases = [ordered]@{
  ".mir/portable-return.yml" = "release-governance"
  ".mir/control-plane/package-locks.json" = "release-governance"
  ".mir/releases/transitions/3.2.5-c32-source-frozen.json" = "release-governance"
  ".mir/releases/transitions/3.2.5-c32-package-built.json" = "release-governance"
  ".mir/target-lines/index.json" = "release-evidence"
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
  "tools/lib/assurance/Evidence.ps1",
  "tools/lib/control/Evidence.ps1",
  "tools/lib/control/Planner.ps1",
  "tools/lib/control/Views.ps1",
  ".mir/control-plane/approved-delta-policies.json",
  "tools/maintenance/Move-MIRValidationDefinitions.ps1",
  "validation/tests/tooling/Test-MIRAssurance.ps1",
  "validation/tests/release/Test-MIRReleaseAuthority.ps1",
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
    [string]$releaseHistoryTest[0].command -ne "./validation/tests/release/Test-MIRPublishedSnapshotIntegrity.ps1 -Index" -or
    @($releaseHistoryTest[0].inputs) -notcontains "release-history") {
  throw "static.release-history must bind the staged release-history fingerprint and run indexed snapshot integrity."
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
  "tools/lib/control/Evidence.ps1",
  "tools/mir.ps1",
  "tools/lib/control/Views.ps1",
  "tools/maintenance/**",
  "validation/tests/docs/Test-MIRMarkdownFormatting.ps1",
  "validation/tests/package/Test-MIRArtifactCleanup.ps1",
  "validation/tests/tooling/Test-MIRAssurance.ps1",
  "validation/tests/tooling/Test-MIRControlPlane.ps1",
  "validation/tests/release/Test-MIRReleaseAuthority.ps1"
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
    [string]$portableMuseumTest[0].command -ne "./validation/tests/runtime/Test-MIRMuseumCompiler.ps1" -or
    @($portableMuseumTest[0].inputs) -notcontains "fixtures/museum/synthetic-installation/**") {
  throw "static.museum must remain portable and bind the repository-owned synthetic installation fixture."
}
if ($exactMuseumTest.Count -ne 1 -or
    [string]$exactMuseumTest[0].kind -ne "runtime" -or
    [string]$exactMuseumTest[0].command -ne "./validation/tests/runtime/Test-MIRMuseumExact.ps1" -or
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
    @($ecosystemTest[0].inputs) -notcontains "package-source" -or
    [string]$ecosystemTest[0].command -notmatch '--skip-build(?:\s|$)' -or
    [string]$ecosystemTest[0].command -notmatch '--skip-clean-git-status(?:\s|$)') {
  throw "runtime.ecosystem must bind the exact candidate ZIP and package source and must not rebuild distribution bytes."
}
$mirCliText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\mir.ps1")
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
    [string]$performanceTest[0].command -notmatch '-OutputPath\s+\.mir/evidence/<upgrade-to>-performance-regression\.json' -or
    @($performanceTest[0].inputs) -notcontains "mod-closure" -or
    @($performanceTest[0].inputs) -notcontains "scripts/Invoke-MIRPerformanceQualification.ps1" -or
    @($performanceTest[0].inputs) -contains ".mir/evidence/*-performance-regression.json") {
  throw "runtime.performance-regression must produce and validate fresh evidence without fingerprinting its mutable output as an input."
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
$currentRelease = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".mir\releases\records\3.2.5.json") | ConvertFrom-Json
$currentProfile = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\profiles\factorio-2.1.json") | ConvertFrom-Json
$currentReleaseBoundary = "{0}|{1}" -f [string]$currentRelease.state, [string]$currentRelease.candidate_id
if ($currentReleaseBoundary -notin @(
      "planned|not-assigned", "source-frozen|C32", "package-built|C32",
      "focused-qualified|C32", "candidate-qualified|C32", "manually-accepted|C32",
      "protected-qualified|C32", "sealed|C32", "promoted|C32", "tagged|C32",
      "published|C32", "publicly-verified|C32"
    ) -or [string]$currentRelease.candidate_floor -ne "C32" -or
    [string]$currentProfile.upgrade.from_version -ne [string]$currentRelease.upgrade.from_version -or
    [string]$currentProfile.upgrade.to_version -ne [string]$currentRelease.upgrade.to_version -or
    [string]$currentProfile.upgrade.fixture -ne [string]$currentRelease.upgrade.fixture) {
  throw "Factorio 2.1 assurance profile must bind the current 3.2.5 public upgrade authority."
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

$releaseAssurance = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\Release.ps1")
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
$publishedSnapshotIntegrity = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "validation\tests\release\Test-MIRPublishedSnapshotIntegrity.ps1")
if ($publishedSnapshotIntegrity -notmatch 'git ls-tree -r -l' -or
  $publishedSnapshotIntegrity -match 'Measure-Object -Property Length -Sum') {
  throw "Published snapshot byte counts must come from canonical Git blobs, not checkout line endings."
}

$coreScript = Join-Path $RepoRoot "tools\lib\assurance\Core.ps1"
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
$candidateInfo = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "info.json") | ConvertFrom-Json
$candidateSourceTree = (& git -C $RepoRoot rev-parse "HEAD^{tree}").Trim()
$candidatePath = (Get-MIRAssuranceDevelopmentCandidatePath -Info $candidateInfo -SourceTree $candidateSourceTree).Replace("\", "/")
if ($candidatePath -notmatch "/build/candidates/3\.2\.5/C32/[0-9a-f]{40}/more-infinite-research_3\.2\.5\.zip$" -or
    $candidatePath -match "/dist/") {
  throw "Default assurance candidates must be release/allocation/source-tree addressed outside immutable dist."
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
  "needs: [context, package]",
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

$validateWorkflow = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".github\workflows\validate.yml")
foreach ($requiredWorkflowSnippet in @(
  'Resolve content-addressed development candidate',
  'build/candidates/[0-9]+\.[0-9]+\.[0-9]+/',
  'path: ${{ env.MIR_DEVELOPMENT_CANDIDATE }}',
  'mir-verification-plan-${{ github.run_id }}-${{ github.run_attempt }}',
  'mir-development-candidate-${{ github.run_id }}-${{ github.run_attempt }}',
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
  '${{ always() && matrix.no_op != true }}'
)) {
  if (-not $validateWorkflow.Contains($requiredWorkflowSnippet)) {
    throw "Hosted validation workflow does not safely handle an all-reuse plan: $requiredWorkflowSnippet"
  }
}
if ($validateWorkflow.Contains('Remove-Item -LiteralPath $source -Force')) {
  throw "Hosted planning must preserve the tracked candidate source so every clean worker reconstructs the same canonical repository state."
}
if ($validateWorkflow.Contains('$candidate = Join-Path $PWD ([string]$plan.candidate)') -or
    @([regex]::Matches($validateWorkflow, '\$plan\.candidate_descriptor\.path')).Count -ne 2 -or
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
    "--artifact-prefix $($fanInCase.Prefix)",
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

$assuranceEvidence = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\Evidence.ps1")
foreach ($requiredIngestionGuard in @(
  'mir-assurance-worker-receipt-v2',
  'stale-ignored',
  'ReparsePoint',
  'max_entries_per_artifact',
  'max_expanded_bytes_per_artifact',
  'max_file_bytes',
  'duplicate canonical object paths'
)) {
  if (-not $assuranceEvidence.Contains($requiredIngestionGuard)) {
    throw "Assurance worker ingestion omits structural guard: $requiredIngestionGuard"
  }
}
$assuranceCore = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "tools\lib\assurance\Core.ps1")
foreach ($generatedOutputExclusion in @('build/results/*', 'build/*', 'build/results/*')) {
  if (-not $assuranceCore.Contains($generatedOutputExclusion)) {
    throw "Generated runtime summaries could enter their own future input fingerprint: $generatedOutputExclusion"
  }
}

$equivalenceRoot = Join-Path ([IO.Path]::GetTempPath()) ("mir-clean-root-equivalence-" + [guid]::NewGuid().ToString("N"))
$plannerRoot = Join-Path $equivalenceRoot "planner"
$workerRoot = Join-Path $equivalenceRoot "worker"
$pwshPath = (Get-Process -Id $PID).Path
try {
  New-Item -ItemType Directory -Force -Path $equivalenceRoot | Out-Null
  & git -c core.autocrlf=false clone --quiet --no-hardlinks $RepoRoot $plannerRoot
  if ($LASTEXITCODE -ne 0) { throw "Unable to create the LF planner root." }
  & git -c core.autocrlf=true clone --quiet --no-hardlinks $RepoRoot $workerRoot
  if ($LASTEXITCODE -ne 0) { throw "Unable to create the CRLF worker root." }

  foreach ($root in @($plannerRoot, $workerRoot)) {
    & $pwshPath -NoProfile -File (Join-Path $root "tools\mir.ps1") assurance build --target 2.1 --output build/results/assurance/development-build.json
    if ($LASTEXITCODE -ne 0) { throw "Content-addressed candidate build failed in separate root: $root" }
  }

  # A normal planner must not consume mutable worktree bytes from published
  # dist. Corrupt one worker-root copy after the isolated candidate exists.
  $dirtyPublicDist = Join-Path $workerRoot "dist\more-infinite-research_3.2.5.zip"
  $stream = [IO.File]::Open($dirtyPublicDist, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try { $stream.WriteByte(0) } finally { $stream.Dispose() }
  if (@(& git -C $workerRoot status --porcelain -- dist).Count -ne 1) {
    throw "Separate-root regression did not create the intended dirty published-dist decoy."
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
} finally {
  if (Test-Path -LiteralPath $equivalenceRoot) { Remove-Item -LiteralPath $equivalenceRoot -Recurse -Force }
}

Write-Host "[ok] MIR assurance manifests, domain policy, target profiles, and stable test catalog passed."
