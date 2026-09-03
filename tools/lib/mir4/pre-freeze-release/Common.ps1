$script:MIR4FinalMilePlaytestCandidateAuthorityRelativePath = '.mir/releases/waves/mir4-r0/MIR4-Final-Mile-Playtest-Candidate-AuthorityV1.json'
$script:MIR4FinalMilePlaytestCandidateAuthoritySchemaRelativePath = 'spec/schemas/mir4-final-mile-playtest-candidate-authority-v1.schema.json'
$script:MIR4MaintainerFinalGitHubReleaseAuthorizationRelativePath = '.mir/releases/waves/mir4-r0/MIR4-Maintainer-Final-GitHub-Release-AuthorizationV1.json'
$script:MIR4MaintainerFinalGitHubReleaseAuthorizationSchemaRelativePath = 'spec/schemas/mir4-maintainer-final-github-release-authorization-v1.schema.json'

function Get-MIR4PreFreezeRepoRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Get-MIR4PreFreezeFileSha256 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [ValidateSet('raw-bytes','canonical-text-v1')][string]$Mode='raw-bytes'
  )
  if ($Mode -ceq 'raw-bytes') {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
  }
  $utf8 = [Text.UTF8Encoding]::new($false,$true)
  $text = $utf8.GetString([IO.File]::ReadAllBytes($Path))
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
  $canonical = $text.Replace("`r`n","`n").Replace("`r","`n").Normalize([Text.NormalizationForm]::FormC)
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($canonical)))
}

function Test-MIR4T14HistoricalDocumentationSha256 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$ExpectedSha256
  )
  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $path = Join-Path $repo $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or $ExpectedSha256 -notmatch '^[A-F0-9]{64}$') { return $false }
  if ((Get-MIR4PreFreezeFileSha256 -Path $path) -ceq $ExpectedSha256) { return $true }

  $authority = Read-MIR4PreFreezeJson -RepoRoot $repo `
    -RelativePath '.mir/releases/waves/mir4-r0/MIR4-Documentation-Continuity-T14V1.json' `
    -Kind 'MIR4DocumentationContinuityT14V1'
  if ([string]$authority.result -cne 'completed' -or
      [string]$authority.metadata_authority -cne 'markdown-frontmatter' -or
      [string]$authority.compatibility_projection -cne '.mir/docs.yml' -or
      -not [bool]$authority.queue_generation_authority_preserved) {
    return $false
  }

  $utf8 = [Text.UTF8Encoding]::new($false, $true)
  $text = $utf8.GetString([IO.File]::ReadAllBytes($path))
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
  $lf = [string][char]10
  $text = $text.Replace(([string][char]13 + $lf), $lf).Replace([string][char]13, $lf)
  $lines = [regex]::Split($text, $lf)
  $historical = [Collections.Generic.List[string]]::new()
  $insideFrontMatter = $false
  $skipSourceIds = $false
  $removedSourceIdLines = 0
  foreach ($line in $lines) {
    if ($line -ceq '---') {
      $insideFrontMatter = -not $insideFrontMatter
      $skipSourceIds = $false
      $historical.Add($line)
      continue
    }
    if ($insideFrontMatter -and $line -match '^source_of_truth_for:\s*$') {
      $skipSourceIds = $true
      $removedSourceIdLines++
      continue
    }
    if ($skipSourceIds -and $line -match '^\s+-\s+\S') {
      $removedSourceIdLines++
      continue
    }
    $skipSourceIds = $false
    $historical.Add($line)
  }
  if ($removedSourceIdLines -lt 2) { return $false }
  $historicalBytes = $utf8.GetBytes(($historical -join $lf).Normalize([Text.NormalizationForm]::FormC))
  $historicalSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($historicalBytes))
  return $historicalSha256 -ceq $ExpectedSha256
}

function Read-MIR4PreFreezeJson {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Kind
  )
  $path = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "[mir4-prefreeze-input] Missing $RelativePath" }
  $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
  if ([string]$record.kind -cne $Kind) { throw "[mir4-prefreeze-kind] $RelativePath" }
  return $record
}

function Get-MIR4FinalMilePlaytestCandidateAuthorityV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = Get-MIR4PreFreezeRepoRoot $RepoRoot
  $externalEvidenceMode = [string]$env:MIR4_EXTERNAL_EVIDENCE_MODE
  $hostedReceiptOnly = $externalEvidenceMode -ceq 'hosted-receipt'
  if (-not [string]::IsNullOrWhiteSpace($externalEvidenceMode) -and -not $hostedReceiptOnly) {
    throw '[mir4-final-mile-playtest-external-evidence-mode]'
  }
  if ($hostedReceiptOnly -and [string]$env:GITHUB_ACTIONS -cne 'true') {
    throw '[mir4-final-mile-playtest-hosted-receipt-context]'
  }
  $path = Join-Path $repo $script:MIR4FinalMilePlaytestCandidateAuthorityRelativePath
  $schema = Join-Path $repo $script:MIR4FinalMilePlaytestCandidateAuthoritySchemaRelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not (Test-Path -LiteralPath $schema -PathType Leaf)) {
    throw '[mir4-final-mile-playtest-authority-missing]'
  }
  $text = Get-Content -Raw -LiteralPath $path
  if (-not ($text | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)) {
    throw '[mir4-final-mile-playtest-authority-schema]'
  }
  $authority = $text | ConvertFrom-Json -Depth 100
  if ((@($authority.targets | ForEach-Object { [string]$_.target } | Sort-Object) -join '|') -cne 'F200|F210') {
    throw '[mir4-final-mile-playtest-authority-targets]'
  }
  if (-not (Get-Command Get-MIRPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
    . (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
  }
  if ((Get-MIRPackageSourceFingerprint -RepoRoot $repo) -cne [string]$authority.source_baseline.package_source_sha256) {
    throw '[mir4-final-mile-playtest-authority-package-source]'
  }
  $authorizationDescriptorPath = Join-Path $repo ([string]$authority.authorization.path)
  if (-not (Test-Path -LiteralPath $authorizationDescriptorPath -PathType Leaf) -or
      (Get-MIR4PreFreezeFileSha256 $authorizationDescriptorPath) -cne [string]$authority.authorization.sha256 -or
      [long](Get-Item -LiteralPath $authorizationDescriptorPath).Length -ne [long]$authority.authorization.bytes) {
    throw "[mir4-final-mile-playtest-authority-descriptor] $($authority.authorization.path)"
  }
  foreach ($descriptor in @($authority.targets | ForEach-Object { $_.candidate_manifest; $_.assurance })) {
    $relative = ([string]$descriptor.path).Replace('\', '/')
    $allowedPrivateRoot = $relative.StartsWith('build/mir4/', [StringComparison]::Ordinal) -or
      $relative.StartsWith('build/results/assurance/', [StringComparison]::Ordinal)
    if ([IO.Path]::IsPathRooted([string]$descriptor.path) -or $relative -match '(^|/)\.\.(/|$)' -or
        -not $allowedPrivateRoot -or [string]$descriptor.sha256 -cnotmatch '^[A-F0-9]{64}$' -or
        [long]$descriptor.bytes -le 0) {
      throw "[mir4-final-mile-playtest-authority-external-descriptor] $($descriptor.path)"
    }
    if (-not $hostedReceiptOnly) {
      $descriptorPath = Join-Path $repo ([string]$descriptor.path)
      if (-not (Test-Path -LiteralPath $descriptorPath -PathType Leaf) -or
          (Get-MIR4PreFreezeFileSha256 $descriptorPath) -cne [string]$descriptor.sha256 -or
          [long](Get-Item -LiteralPath $descriptorPath).Length -ne [long]$descriptor.bytes) {
        throw "[mir4-final-mile-playtest-authority-descriptor] $($descriptor.path)"
      }
    }
  }
  if ([string]$authority.authorization.path -cne $script:MIR4MaintainerFinalGitHubReleaseAuthorizationRelativePath) {
    throw '[mir4-final-mile-playtest-authorization-path]'
  }
  $authorizationPath = Join-Path $repo $script:MIR4MaintainerFinalGitHubReleaseAuthorizationRelativePath
  $authorizationSchema = Join-Path $repo $script:MIR4MaintainerFinalGitHubReleaseAuthorizationSchemaRelativePath
  if (-not (Test-Path -LiteralPath $authorizationSchema -PathType Leaf)) { throw '[mir4-final-mile-playtest-authorization-schema-missing]' }
  $authorizationText = Get-Content -Raw -LiteralPath $authorizationPath
  if (-not ($authorizationText | Test-Json -SchemaFile $authorizationSchema -ErrorAction SilentlyContinue)) {
    throw '[mir4-final-mile-playtest-authorization-schema]'
  }
  $authorization = $authorizationText | ConvertFrom-Json -Depth 100
  foreach ($property in @('branch','commit','tree','package_source_sha256')) {
    if ([string]$authorization.starting_source.$property -cne [string]$authority.source_baseline.$property) {
      throw "[mir4-final-mile-playtest-authorization-source] $property"
    }
  }
  foreach ($target in @($authority.targets)) {
    $decision = @($authorization.playtest_decisions | Where-Object { [string]$_.target -ceq [string]$target.target })
    $expectedAssuranceTarget = if ([string]$target.target -ceq 'F210') { '2.1' } else { '2.0' }
    if ($hostedReceiptOnly) {
      $externalEvidenceCurrent = [string]$target.assurance.status -ceq 'passed' -and
        [int]$target.assurance.expected -gt 0 -and [int]$target.assurance.failed -eq 0 -and
        [int]$target.assurance.incomplete -eq 0
    } else {
      $manifest = Get-Content -Raw -LiteralPath (Join-Path $repo ([string]$target.candidate_manifest.path)) | ConvertFrom-Json -Depth 100
      $assurance = Get-Content -Raw -LiteralPath (Join-Path $repo ([string]$target.assurance.path)) | ConvertFrom-Json -Depth 100
      $externalEvidenceCurrent = [string]$manifest.local_distribution.archive_sha256 -ceq [string]$target.development_package.sha256 -and
        [string]$manifest.local_distribution.content_sha256 -ceq [string]$target.development_package.content_sha256 -and
        [long]$manifest.local_distribution.bytes -eq [long]$target.development_package.bytes -and
        [int]$manifest.local_distribution.entry_count -eq [int]$target.development_package.entry_count -and
        [string]$assurance.status -ceq 'passed' -and [int]$assurance.counts.expected -eq [int]$target.assurance.expected -and
        [int]$assurance.counts.failed -eq 0 -and [int]$assurance.counts.incomplete -eq 0 -and
        [string]$assurance.plan.target -ceq $expectedAssuranceTarget -and
        [string]$assurance.plan.package_source_sha256 -ceq [string]$authority.source_baseline.package_source_sha256 -and
        [string]$assurance.plan.domain_manifest.artifact.sha256 -ceq [string]$target.development_package.sha256 -and
        [string]$assurance.plan.domain_manifest.artifact.content_sha256 -ceq [string]$target.development_package.content_sha256
    }
    if (-not $externalEvidenceCurrent -or $decision.Count -ne 1 -or
        [string]$decision[0].distribution -cne [string]$target.distribution_version -or
        [string]$decision[0].candidate_zip_sha256 -cne [string]$target.development_package.sha256 -or
        [string]$decision[0].content_root -cne [string]$target.development_package.content_sha256 -or
        [string]$decision[0].engine.version -cne [string]$target.engine.version -or
        [string]$decision[0].engine.build -cne [string]$target.engine.build -or
        [string]$decision[0].engine.executable_sha256 -cne [string]$target.engine.sha256) {
      throw "[mir4-final-mile-playtest-authority-binding] $($target.target)"
    }
  }
  return $authority
}
