param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$RecordedAt = '2026-09-02T21:00:00+10:00',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/tooling/CommandInventory.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/tooling/ExecutableTestAuthority.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/tooling/TestWorkflowCatalogues.ps1')

function Get-MIR4201BHash([string]$RelativePath) {
  return Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot $RelativePath)
}

function Invoke-MIR4201BGitText([string[]]$Arguments) {
  $start = [Diagnostics.ProcessStartInfo]::new()
  $start.FileName = 'git'
  $start.WorkingDirectory = $RepoRoot
  $start.UseShellExecute = $false
  $start.RedirectStandardOutput = $true
  $start.RedirectStandardError = $true
  foreach ($argument in $Arguments) { [void]$start.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $start
  if (-not $process.Start()) { throw '[mir4-m42-01b-git-start]' }
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) { throw "[mir4-m42-01b-git] $($Arguments -join ' '): $stderr" }
  return $stdout
}

function Get-MIR4201BBaseTextHash([string]$Commit,[string]$RelativePath) {
  $text = Invoke-MIR4201BGitText @('show',("$Commit`:$RelativePath"))
  return Get-MIR4Sha256String -Value $text.Replace("`r`n","`n").Replace("`r","`n")
}

$baseCommit = '36c0f510ef09f5489df7ac5c5f6eb6f5fa9b93cc'
$baseTree = 'b13d310630cf1932a3870fcef3982b5f309155cc'
$outputRelative = 'releases/migrations/MIR4-M42-01B-Test-Workflow-ConvergenceV1.json'
$outputPath = Join-Path $RepoRoot $outputRelative
$schemaPath = Join-Path $RepoRoot 'contracts/repository/mir4-m42-01b-test-workflow-convergence-v1.schema.json'
$predecessor = 'releases/migrations/MIR4-M42-01A-CLI-Release-ConvergenceV1.json'

$projection = Update-MIR4ExecutableTestAuthorityProjectionsV1 -RepoRoot $RepoRoot -Check
$tests = Update-MIR4ToolingCatalogueV1 -RepoRoot $RepoRoot -Catalogue tests -Check
$workflows = Update-MIR4ToolingCatalogueV1 -RepoRoot $RepoRoot -Catalogue workflows -Check
$inventory = Update-MIR4CommandInventoryV1 -RepoRoot $RepoRoot -Check

$standardEvolved = @(
  '.mir/control/aliases.yml',
  'CHANGELOG.md',
  'docs/releases/mir4-post-4.0-roadmap.md',
  'governance/automation/mir4-command-inventory-v1.json',
  'releases/governance/MIR4-Source-Changelog-PlanV1.json',
  'scripts/Invoke-MIRAssurance.ps1',
  'spec/programmes/mir4-4x-operating-programme-v1.json',
  'tests/assurance/Test-MIR4AssuranceOfflineCustodyMigration.ps1',
  'tests/history/Test-MIR4HistoricalToolingMigration.ps1',
  'tests/release-tooling/Test-MIR4ReleaseToolingMigration.ps1',
  'todo.md',
  'tools/lib/mir4/PreFreezeRelease.ps1',
  'tools/mir/application/package/RuntimeReplay.ps1',
  'tools/mir/cli/Invoke-MIR4ToolingConvergence.ps1',
  'tools/mir/cli/Invoke-MIRCommandRouter.ps1',
  'validation/tests.yml'
)
$projectionPaths = @(Get-MIR4ExecutableTestAuthorityProjectionPathsV1 -RepoRoot $RepoRoot)
$baseTestText = Invoke-MIR4201BGitText @('ls-tree','-r','--name-only',$baseCommit,'--','validation/tests')
$baseTests = @($baseTestText -split "`n" |
  Where-Object { $_ -match '^validation/tests/.+\.ps1$' } | Sort-Object)
$relocations = @(
  foreach ($fromPath in $baseTests) {
    $relative = $fromPath.Substring('validation/tests/'.Length)
    $toPath = 'tests/' + $relative
    if (Test-Path -LiteralPath (Join-Path $RepoRoot $fromPath)) { continue }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $toPath) -PathType Leaf)) { throw "[mir4-m42-01b-relocation-target] $toPath" }
    [pscustomobject][ordered]@{
      from_path=$fromPath
      to_path=$toPath
      previous_git_blob=(Invoke-MIR4201BGitText @('rev-parse',("$baseCommit`:$fromPath"))).Trim()
      previous_sha256=Get-MIR4201BBaseTextHash -Commit $baseCommit -RelativePath $fromPath
      current_sha256=Get-MIR4201BHash $toPath
      hash_mode='canonical-text-v1'
      package_visible=$false
      release_authority=$false
    }
  }
)
if ($relocations.Count -ne 137) { throw "[mir4-m42-01b-relocation-count] $($relocations.Count)" }

$record = [pscustomobject][ordered]@{
  schema=1
  kind='MIR4M4201BTestWorkflowConvergenceV1'
  status='M42-01-TOOLING-TEST-WORKFLOW-CONVERGENCE-COMPLETE'
  recorded_at=$RecordedAt
  programme_id='M42-01B-TEST-WORKFLOW-CONVERGENCE'
  change_id='MIR4-CHG-2026-0016'
  predecessor_receipt=[pscustomobject][ordered]@{path=$predecessor;sha256=(Get-MIR4201BHash $predecessor)}
  base=[pscustomobject][ordered]@{commit=$baseCommit;tree=$baseTree}
  test_catalogue=[pscustomobject][ordered]@{path='assurance/catalog/tests.json';sha256=(Get-MIR4201BHash 'assurance/catalog/tests.json');digest=[string]$tests.digest;test_count=[int]$tests.test_count;compatibility_selected=[int]$tests.summary.compatibility_selected}
  workflow_catalogue=[pscustomobject][ordered]@{path='governance/automation/mir4-workflow-purposes-v1.json';sha256=(Get-MIR4201BHash 'governance/automation/mir4-workflow-purposes-v1.json');digest=[string]$workflows.digest;workflow_count=[int]$workflows.workflow_count;public_purposes=@($workflows.public_purposes);publisher_can_build=[bool]$workflows.summary.publisher_can_build}
  command_inventory=[pscustomobject][ordered]@{path='governance/automation/mir4-command-inventory-v1.json';sha256=(Get-MIR4201BHash 'governance/automation/mir4-command-inventory-v1.json');digest=[string]$inventory.digest;command_count=[int]$inventory.command_count;unknown_count=[int]$inventory.summary.unknown;duplicate_command_keys=[int]$inventory.summary.duplicate_command_keys}
  package_source_sha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot
  evolved_bindings=@(
    foreach ($path in $standardEvolved) {
      [pscustomobject][ordered]@{path=$path;previous_sha256=(Get-MIR4201BBaseTextHash -Commit $baseCommit -RelativePath $path);current_sha256=(Get-MIR4201BHash $path);hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    }
  )
  projection_bindings=@(
    foreach ($path in $projectionPaths) {
      [pscustomobject][ordered]@{path=$path;previous_sha256=(Get-MIR4201BBaseTextHash -Commit $baseCommit -RelativePath $path);current_sha256=(Get-MIR4201BHash $path);hash_mode='canonical-text-v1';package_visible=$false;release_authority=$false}
    }
  )
  relocated_bindings=$relocations
  current_authorities=@(
    foreach ($binding in @(
      @{path='tools/mir/application/tooling/ExecutableTestAuthority.ps1';role='test-authority-projection-generator'},
      @{path='tools/mir/application/tooling/TestWorkflowCatalogues.ps1';role='test-and-workflow-catalogue-generator'},
      @{path='assurance/catalog/tests.json';role='generated-executable-proof-catalogue'},
      @{path='governance/automation/mir4-workflow-purposes-v1.json';role='generated-workflow-purpose-catalogue'},
      @{path='tests/tooling/Test-MIR4TestWorkflowConvergence.ps1';role='canonical-convergence-proof'},
      @{path='tools/commands/mir4/Update-MIR4M4201BTestWorkflowConvergenceAuthority.ps1';role='successor-receipt-writer'},
      @{path='contracts/repository/mir4-m42-01b-test-workflow-convergence-v1.schema.json';role='successor-receipt-schema'}
    )) {
      [pscustomobject][ordered]@{path=[string]$binding.path;sha256=(Get-MIR4201BHash ([string]$binding.path));hash_mode='canonical-text-v1';role=[string]$binding.role;package_visible=$false;release_authority=$false}
    }
  )
  invariants=[pscustomobject][ordered]@{one_public_cli=$true;one_executable_test_authority=$true;one_generated_proof_catalogue=$true;five_public_workflow_purposes=$true;stable_required_checks_retained=$true;publisher_cannot_build=$true;three_bounded_compatibility_forwarders=$true;player_executable_sources_unchanged=$true}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;promotion=$false;publication=$false}
  next_fixed_point='M42-02-BOUNDED-IMPLEMENTATION-DECOMPOSITION'
  record_sha256=''
}
$record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
$json = (($record | ConvertTo-Json -Depth 100) + [string][char]10).Replace(([string][char]13+[char]10),[string][char]10).Replace([string][char]13,[string][char]10)
if (-not ($json | Test-Json -SchemaFile $schemaPath)) { throw '[mir4-m42-01b-schema]' }
if ($Check) {
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf) -or [IO.File]::ReadAllText($outputPath).Replace(([string][char]13+[char]10),[string][char]10) -cne $json) { throw '[mir4-m42-01b-receipt-stale]' }
  Write-Host '[ok] M42-01B test and workflow convergence receipt is current.'
  return $record
}
[IO.File]::WriteAllText($outputPath,$json,[Text.UTF8Encoding]::new($false))
return $record
