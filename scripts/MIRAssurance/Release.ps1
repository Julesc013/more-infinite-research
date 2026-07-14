. (Join-Path $PSScriptRoot "Hashing.ps1")

function Invoke-MIRAssuranceSeal {
  param([Parameter(Mandatory)]$Context)
  if (-not (Test-Path -LiteralPath $Context.candidate -PathType Leaf)) { throw "Candidate does not exist: $($Context.candidate)" }
  $summaryPath = Resolve-MIRAssurancePath -Path (Get-MIRAssuranceOption -Name "--evidence")
  if (-not $summaryPath -or -not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) { throw "seal requires --evidence <passing qualification summary>." }
  $summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
  if ([string]$summary.status -ne "passed") { throw "Qualification summary is not passing." }
  $commit = (& git -C $repo rev-parse HEAD).Trim()
  $branch = (& git -C $repo branch --show-current).Trim()
  $status = @(& git -C $repo status --porcelain --untracked-files=all)
  if ($status.Count -ne 0) { throw "Refusing to seal a dirty source tree. Commit the exact candidate and tracked qualification summary first." }
  $factorioHash = if ($Context.factorio -and (Test-Path -LiteralPath $Context.factorio -PathType Leaf)) { Get-MIRAssuranceSha256 -Path $Context.factorio } else { "none" }
  $seal = [ordered]@{
    schema=1
    state="SEALED-RC"
    release_status="NOT RELEASED"
    version=[string]$Context.info.version
    factorio_target=$Context.target
    branch=$branch
    source_commit=$commit
    source_clean=($status.Count -eq 0)
    candidate=(Get-MIRAssuranceRepoRelativePath -Path $Context.candidate)
    candidate_sha256=(Get-MIRAssuranceSha256 -Path $Context.candidate)
    candidate_content_sha256=(Get-MIRAssuranceZipContentHash -Path $Context.candidate)
    package_source_sha256=(Get-MIRAssuranceTreeHash -Paths (Get-MIRAssurancePackageFiles))
    target_profile_sha256=(Get-MIRAssuranceRepositoryFileHash -Path $targetsPath)
    test_catalog_sha256=(Get-MIRAssuranceRepositoryFileHash -Path $catalogPath)
    validation_harness_sha256=(Get-MIRAssuranceTreeHash -Paths (Get-MIRAssuranceHarnessFiles))
    factorio_binary=$Context.factorio
    factorio_sha256=$factorioHash
    qualification_summary=(Get-MIRAssuranceRepoRelativePath -Path (Resolve-Path $summaryPath).Path)
    qualification_summary_sha256=(Get-MIRAssuranceRepositoryFileHash -Path $summaryPath)
    sealed_at=(Get-Date).ToUniversalTime().ToString("o")
  }
  $default = ".mir/evidence/candidate-seals/mir-$($Context.info.version)-factorio-$($Context.target).json"
  Write-MIRAssuranceJson -Value $seal -DefaultPath $default
}

function Invoke-MIRAssuranceCheckSeal {
  param([Parameter(Mandatory)]$Context)
  $sealPath = $Context.seal
  if (-not $sealPath -or -not (Test-Path -LiteralPath $sealPath -PathType Leaf)) { throw "check-seal requires --seal <path>." }
  $seal = Get-Content -Raw -LiteralPath $sealPath | ConvertFrom-Json
  $candidate = Resolve-MIRAssurancePath -Path ([string]$seal.candidate)
  $checks = [ordered]@{
    candidate_exists=(Test-Path -LiteralPath $candidate -PathType Leaf)
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
  $checks.target_profile_sha256=((Get-MIRAssuranceRepositoryFileHash -Path $targetsPath) -eq [string]$seal.target_profile_sha256)
  $checks.test_catalog_sha256=((Get-MIRAssuranceRepositoryFileHash -Path $catalogPath) -eq [string]$seal.test_catalog_sha256)
  $checks.validation_harness_sha256=((Get-MIRAssuranceTreeHash -Paths (Get-MIRAssuranceHarnessFiles)) -eq [string]$seal.validation_harness_sha256)
  & git -C $repo merge-base --is-ancestor ([string]$seal.source_commit) HEAD
  $checks.source_is_ancestor=($LASTEXITCODE -eq 0)
  $summaryPath = Resolve-MIRAssurancePath -Path ([string]$seal.qualification_summary)
  $checks.evidence_sha256=((Test-Path -LiteralPath $summaryPath -PathType Leaf) -and ((Get-MIRAssuranceRepositoryFileHash -Path $summaryPath) -eq [string]$seal.qualification_summary_sha256))
  $passed = @($checks.Values | Where-Object { -not $_ }).Count -eq 0
  $result = [ordered]@{ schema=1; status=if ($passed) { "passed" } else { "failed" }; seal=$sealPath; checks=$checks }
  Write-MIRAssuranceJson -Value $result
  if (-not $passed) { throw "Candidate seal verification failed." }
}

function Invoke-MIRAssuranceSelfTest {
  param([Parameter(Mandatory)]$Context)
  $cases = @(
    @{path="control.lua"; class="runtime-or-migration"},
    @{path="migrations/more-infinite-research_3.1.9.json"; class="runtime-or-migration"},
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

  $baseMaterial = [ordered]@{test="a"; candidate="a"; binary="a"; harness="a"; settings="a"}
  $base = Get-MIRAssuranceJsonHash -Value $baseMaterial
  foreach ($field in @("candidate", "binary", "harness", "settings")) {
    $changed = [ordered]@{test="a"; candidate="a"; binary="a"; harness="a"; settings="a"}
    $changed[$field] = "b"
    if ((Get-MIRAssuranceJsonHash -Value $changed) -eq $base) { throw "Evidence invalidation self-test failed for $field." }
  }

  $selfTestId = "self-test.synthetic"
  $selfTestKey = Get-MIRAssuranceTextHash -Text ([guid]::NewGuid().ToString("N"))
  $fingerprint = [ordered]@{
    schema=$evidenceSchema
    test_id=$selfTestId
    target=[string]$Context.target
    input_key=$selfTestKey
    fingerprint_sha256=$selfTestKey
    definition_sha256=(Get-MIRAssuranceTextHash -Text "definition")
  }
  $capsule = [ordered]@{
    schema=$evidenceSchema
    test_id=$selfTestId
    status="passed"
    disposition="executed"
    input_key=$selfTestKey
    fingerprint_sha256=$selfTestKey
    definition_sha256=$fingerprint.definition_sha256
    target=[string]$Context.target
    command="synthetic"
    resolved_command="synthetic"
    inputs=[ordered]@{}
    started_at=(Get-Date).ToUniversalTime().ToString("o")
    completed_at=(Get-Date).ToUniversalTime().ToString("o")
    duration_seconds=0
    message=""
  }
  $null = Write-MIRAssuranceAttempt -Capsule $capsule
  if ($null -eq (Get-MIRAssuranceReusableEvidence -Fingerprint $fingerprint)) { throw "Passing exact-input evidence was not reusable." }
  $paths = Get-MIRAssuranceEvidencePaths -TestId $selfTestId -InputKey $selfTestKey
  [IO.File]::WriteAllText($paths.blocked, "{}`n", [Text.UTF8Encoding]::new($false))
  if ($null -ne (Get-MIRAssuranceReusableEvidence -Fingerprint $fingerprint)) { throw "Blocked evidence was incorrectly reusable." }
  Remove-Item -LiteralPath $paths.root -Recurse -Force

  $plan = [ordered]@{baseline="abc123"}
  $resolved = Resolve-MIRAssuranceCommandText -Command "./scripts/Invoke-MIRValidation.ps1 -ChangedSince <baseline> -CandidateZip <candidate>" -Context $Context -Plan $plan
  if ($resolved -notmatch "abc123" -or $resolved -match "<baseline>") { throw "Baseline command propagation self-test failed." }

  Write-Host "[ok] MIR assurance classifier, impact escalation, exact-input reuse, blocking, and invalidation tests passed."
}
