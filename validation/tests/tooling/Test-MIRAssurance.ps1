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
  "scripts/Invoke-MIRAssurance.ps1",
  "tools/lib/assurance/Evidence.ps1",
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
foreach ($profileName in @("fast", "full", "backport")) {
  if (@($config.profiles.$profileName) -notcontains "static.release-history") {
    throw "The $profileName assurance profile must include static.release-history."
  }
}

foreach ($requiredStaticRoutingPath in @(
  ".mir/assurance.json",
  ".mir/test-impact.yml",
  "validation/tests/tooling/Test-MIRAssurance.ps1",
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
    [string]$ecosystemTest[0].command -notmatch '--skip-build(?:\s|$)' -or
    [string]$ecosystemTest[0].command -notmatch '--skip-clean-git-status(?:\s|$)') {
  throw "runtime.ecosystem must execute the exact candidate ZIP and must not rebuild distribution bytes."
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
  "-TrustClass protected-release -EvidenceRoot .work/artifacts/evidence",
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
  'Isolate exact development candidate from historical distributions',
  'path: .work/candidate/*.zip',
  'path: .work/candidate',
  'Remove-Item -LiteralPath $source -Force',
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
if ($validateWorkflow -match '(?m)^\s+path:\s+dist(?:/\*\.zip)?\s*$') {
  throw "Hosted validation workers must not materialize the active development candidate in immutable historical dist authority."
}
if (@([regex]::Matches($validateWorkflow, '--candidate \$env:MIR_DEVELOPMENT_CANDIDATE')).Count -ne 3) {
  throw "Hosted planning, exact workers, and the aggregate gate must all bind the isolated development candidate explicitly."
}

Write-Host "[ok] MIR assurance manifests, domain policy, target profiles, and stable test catalog passed."
