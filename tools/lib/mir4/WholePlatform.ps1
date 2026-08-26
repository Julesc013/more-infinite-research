. (Join-Path $PSScriptRoot 'TargetKey.ps1')

function Get-MIR4WholePlatformRepoRoot {
  param([Parameter(Mandatory)][string]$RepoRoot)
  return (Resolve-Path -LiteralPath $RepoRoot).Path
}

function Get-MIR4WholePlatformProgramme {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = Get-MIR4WholePlatformRepoRoot -RepoRoot $RepoRoot
  $authorityPath = Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json'
  $schemaPath = Join-Path $repo 'spec/schemas/mir4-whole-platform-programme-v1.schema.json'
  $raw = Get-Content -Raw -LiteralPath $authorityPath
  if (-not ($raw | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) {
    throw '[mir4-whole-platform-schema] Whole-platform authority failed schema validation.'
  }
  return $raw | ConvertFrom-Json -Depth 100
}

function Get-MIR4WholePlatformMatrix {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = Get-MIR4WholePlatformRepoRoot -RepoRoot $RepoRoot
  $programme = Get-MIR4WholePlatformProgramme -RepoRoot $repo
  $expectedSlots = @(0..17 | ForEach-Object { "4.$_" })
  $actualSlots = @($programme.areas.former_slot)
  if ((@($actualSlots | Sort-Object -Unique).Count -ne 18) -or
      (@(Compare-Object $expectedSlots $actualSlots).Count -ne 0)) {
    throw '[mir4-whole-platform-slots] The programme must account for each former slot from 4.0 through 4.17 exactly once.'
  }

  $rows = @()
  foreach ($area in @($programme.areas)) {
    $missing = @()
    foreach ($relativePath in @($area.authorities) + @($area.implementations) + @($area.verification)) {
      if (-not (Test-Path -LiteralPath (Join-Path $repo ([string]$relativePath)))) {
        $missing += [string]$relativePath
      }
    }
    if ($missing.Count -gt 0) {
      throw "[mir4-whole-platform-path] $([string]$area.former_slot):$($missing -join ',')"
    }
    $rows += [pscustomobject][ordered]@{
      former_slot = [string]$area.former_slot
      id = [string]$area.id
      release_destination = [string]$area.release_destination
      maturity = [string]$area.maturity
      completion_state = [string]$area.completion_state
      authority_count = @($area.authorities).Count
      implementation_count = @($area.implementations).Count
      verification_count = @($area.verification).Count
      cutover = [string]$area.cutover
      blockers = @($area.blockers)
    }
  }

  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4WholePlatformMatrixV1'
    programme_id = [string]$programme.programme_id
    source_version = [string]$programme.source_version
    area_count = $rows.Count
    later_release_area_count = @($rows | Where-Object release_destination -ne '4.0.0').Count
    executable_area_count = @($rows | Where-Object { $_.implementation_count -gt 0 -and $_.verification_count -gt 0 }).Count
    target_key_examples = @($programme.target_key_contract.canonical_examples)
    areas = $rows
    package_visible = $false
    publication_authorized = $false
  }
}

function ConvertTo-MIR4WholePlatformMarkdown {
  param([Parameter(Mandatory)]$Matrix)

  $lines = @(
    '---',
    'title: "MIR 4 Whole Platform Matrix"',
    'status: current',
    'applies_to: "4.0.0 M4C10"',
    'audience: developer',
    'doc_type: reference',
    'owner: mir-maintainers',
    'last_reviewed: 2026-08-26',
    'supersedes: []',
    'superseded_by: []',
    '---',
    '# MIR 4 whole platform matrix',
    '',
    'Generated from `.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json`. Every former 4.0 through 4.17 area is assigned to source release 4.0.0; maturity and cutover remain explicit.',
    '',
    '| Former slot | Platform area | 4.0 maturity | Completion | Blockers |',
    '| --- | --- | --- | --- | --- |'
  )
  foreach ($area in @($Matrix.areas)) {
    $blockers = if (@($area.blockers).Count -eq 0) { 'none' } else { @($area.blockers) -join ', ' }
    $lines += "| ``$($area.former_slot)`` | ``$($area.id)`` | $($area.maturity) | $($area.completion_state) | $blockers |"
  }
  $lines += @(
    '',
    'Canonical human-facing target keys use uppercase `F`, for example `F210` and `F200`. Existing lowercase target IDs remain accepted only as compatibility inputs and inside immutable historical evidence.',
    '',
    'Source inclusion is not player-authority promotion. Preview, shadow, experimental, omitted, and blocked surfaces remain fail-closed until their named cutover gates pass.'
  )
  return ($lines -join "`n") + "`n"
}

function Test-MIR4WholePlatformProgramme {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $repo = Get-MIR4WholePlatformRepoRoot -RepoRoot $RepoRoot
  $programme = Get-MIR4WholePlatformProgramme -RepoRoot $repo
  $matrix = Get-MIR4WholePlatformMatrix -RepoRoot $repo
  if ($matrix.area_count -ne 18 -or $matrix.executable_area_count -ne 18 -or $matrix.later_release_area_count -ne 0) {
    throw '[mir4-whole-platform-completeness] Every former 4.x area must be executable, verified, and assigned to 4.0.0.'
  }
  foreach ($example in @($programme.target_key_contract.canonical_examples)) {
    $projection = New-MIR4TargetKeyProjection -Target ([string]$example).ToLowerInvariant()
    if ([string]$projection.target -cne [string]$example -or [string]$projection.legacy_target -cne ([string]$example).ToLowerInvariant()) {
      throw "[mir4-target-key-round-trip] $example"
    }
  }
  $generated = ConvertTo-MIR4WholePlatformMarkdown -Matrix $matrix
  $generatedPath = Join-Path $repo 'docs/reference/generated/mir4-whole-platform-matrix.md'
  if (-not (Test-Path -LiteralPath $generatedPath -PathType Leaf) -or
      (Get-Content -Raw -LiteralPath $generatedPath).Replace("`r`n", "`n") -cne $generated.Replace("`r`n", "`n")) {
    throw '[mir4-whole-platform-generated-doc] Generated whole-platform matrix is stale.'
  }
  return $matrix
}
