function Get-MIR4ExecutableTestAuthorityProjectionPathsV1 {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $paths = @(
    '.mir/assurance.json',
    '.mir/compatibility.yml',
    '.mir/control/paths.yml',
    '.mir/control-plane/ownership.json',
    '.mir/fixtures.yml',
    '.mir/modules.yml',
    '.mir/test-impact.yml',
    '.mir/technology-lifecycle.json',
    '.mir/releases/waves/mir4-r0/MIR4-Runtime-Continuity-ProgrammeV1.json',
    '.mir/releases/waves/mir4-r0/MIR4-Whole-Platform-ProgrammeV1.json'
  )
  $paths += @(Get-ChildItem -LiteralPath (Join-Path $repo '.mir/lifecycle/tasks') -File -Filter '*.json' |
    Sort-Object Name | ForEach-Object { '.mir/lifecycle/tasks/' + $_.Name })
  return $paths
}

function ConvertTo-MIR4CanonicalExecutableTestProjectionV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Text
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  if ($RelativePath -in @('.mir/assurance.json','.mir/test-impact.yml')) {
    return $Text.Replace('validation/tests/','tests/')
  }
  return [regex]::Replace($Text,'validation/tests/(?<relative>[A-Za-z0-9._/-]+\.ps1)',{
    param($match)
    $relative = [string]$match.Groups['relative'].Value
    $compatibilityPath = Join-Path $repo ('validation/tests/' + $relative)
    if (Test-Path -LiteralPath $compatibilityPath) { return [string]$match.Value }
    $canonicalPath = Join-Path $repo ('tests/' + $relative)
    if (-not (Test-Path -LiteralPath $canonicalPath)) {
      throw "[mir4-test-authority-unresolved-path] $($match.Value) in $RelativePath"
    }
    return 'tests/' + $relative
  })
}

function Update-MIR4ExecutableTestAuthorityProjectionsV1 {
  param([Parameter(Mandatory)][string]$RepoRoot,[switch]$Check)
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $changed = @()
  foreach ($relative in @(Get-MIR4ExecutableTestAuthorityProjectionPathsV1 -RepoRoot $repo)) {
    $path = Join-Path $repo $relative
    $actual = Get-Content -Raw -LiteralPath $path
    $expected = ConvertTo-MIR4CanonicalExecutableTestProjectionV1 -RepoRoot $repo -RelativePath $relative -Text $actual
    if ($actual -cne $expected) {
      if ($Check) { throw "[mir4-test-authority-projection-stale] $relative" }
      [IO.File]::WriteAllText($path,$expected,[Text.UTF8Encoding]::new($false))
      $changed += $relative
    }
  }
  $compatibilityFiles = @(Get-ChildItem -LiteralPath (Join-Path $repo 'validation/tests') -File -Filter '*.ps1' -Recurse |
    ForEach-Object { [IO.Path]::GetRelativePath($repo,$_.FullName).Replace('\','/') } | Sort-Object)
  $expectedCompatibility = @(
    'validation/tests/mir4/Test-MIR4CanonicalizationDiagnosticsT07.ps1',
    'validation/tests/mir4/Test-MIR4RepositoryFixedPointW01.ps1',
    'validation/tests/mir4/Test-MIR4WholePlatform.ps1'
  )
  if (($compatibilityFiles -join '|') -cne ($expectedCompatibility -join '|')) {
    throw "[mir4-test-authority-compatibility-surface] $($compatibilityFiles -join ',')"
  }
  $registry = Get-Content -Raw -LiteralPath (Join-Path $repo 'validation/tests.yml') | ConvertFrom-Json -Depth 100
  if (@($registry.tests | Where-Object {
    $_.PSObject.Properties['command'] -and [string]$_.command -match 'validation/tests[/\\].*\.ps1'
  }).Count -ne 0) { throw '[mir4-test-authority-registry-selects-compatibility]' }
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR4ExecutableTestAuthorityProjectionResultV1'
    state = 'M42-01-CANONICAL'
    mode = if ($Check) { 'check' } else { 'generate' }
    canonical_root = 'tests'
    compatibility_root = 'validation/tests'
    compatibility_forwarders = $compatibilityFiles
    projections = @(Get-MIR4ExecutableTestAuthorityProjectionPathsV1 -RepoRoot $repo).Count
    changed = $changed
    transition_gate = [ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  }
}
