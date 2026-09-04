# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/mir/application/repository/RepositoryCharacterization.ps1')

function Assert-MIR4CharacterizationV1 {
  param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Code,[string]$Detail='')
  if(-not$Condition){throw "[$Code] $Detail"}
}

$expectedPackage=Get-MIRPackageSourceFingerprint -RepoRoot $repo
$expectedReadme='5E8C683E39E76B65487344221B947A0C9A0E04D463433C49C0DC4454F3CFA115'
$output='build/reports/repository-characterization'

$authority=Get-MIR4RepositoryCharacterizationAuthorityV1 -RepoRoot $repo
Assert-MIR4CharacterizationV1 (@($authority.writers).Count -eq 1) 'mir4-characterization-single-writer'
Assert-MIR4CharacterizationV1 (@($authority.report_files).Count -eq 8) 'mir4-characterization-report-contract'
Assert-MIR4CharacterizationV1 (-not[bool]$authority.release_transition_authority.publication) 'mir4-characterization-publication-firewall'

$first=Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $repo -OutputPath $output
$firstManifest=[IO.File]::ReadAllText((Join-Path $repo "$output/manifest.json"))
$second=Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $repo -OutputPath $output
$secondManifest=[IO.File]::ReadAllText((Join-Path $repo "$output/manifest.json"))
$check=Invoke-MIR4RepositoryCharacterizationV1 -RepoRoot $repo -OutputPath $output -Check
Assert-MIR4CharacterizationV1 ($firstManifest -ceq $secondManifest) 'mir4-characterization-determinism'
Assert-MIR4CharacterizationV1 ([int]$check.reports -eq 8) 'mir4-characterization-report-count'
Assert-MIR4CharacterizationV1 ([int]$check.invariants.unknown_paths -eq 0) 'mir4-characterization-unknown-path'
Assert-MIR4CharacterizationV1 ([int]$check.invariants.duplicate_current_bindings -eq 0) 'mir4-characterization-duplicate-binding'
Assert-MIR4CharacterizationV1 ([int]$check.invariants.invalid_current_writer_bindings -eq 0) 'mir4-characterization-invalid-current-writer'
Assert-MIR4CharacterizationV1 ([bool]$check.invariants.package_source_unchanged) 'mir4-characterization-package-source-invariant'
Assert-MIR4CharacterizationV1 ([bool]$check.invariants.root_readme_byte_stable) 'mir4-characterization-readme-invariant'

$manifest=$firstManifest|ConvertFrom-Json -Depth 100
Assert-MIR4CharacterizationV1 ([string]$manifest.source.package_source_sha256 -ceq $expectedPackage) 'mir4-characterization-package-source'
Assert-MIR4CharacterizationV1 ([string]$manifest.source.root_readme_sha256 -ceq $expectedReadme) 'mir4-characterization-readme'
Assert-MIR4CharacterizationV1 ([int]$manifest.source.migration_count -eq 17) 'mir4-characterization-migration-import'
Assert-MIR4CharacterizationV1 ([int]$manifest.summary.package_files -gt 0) 'mir4-characterization-package-membership'
Assert-MIR4CharacterizationV1 (-not[bool]$manifest.invariants.deletion_authorized) 'mir4-characterization-deletion-firewall'
Assert-MIR4CharacterizationV1 (@($manifest.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count -eq 0) 'mir4-characterization-transition-firewall'

$package=Get-Content -Raw -LiteralPath (Join-Path $repo "$output/package-membership.json")|ConvertFrom-Json -Depth 100
Assert-MIR4CharacterizationV1 (@($package.files|Where-Object{[string]$_.path -ceq 'README.md'}).Count -eq 0) 'mir4-characterization-readme-membership'
Assert-MIR4CharacterizationV1 (-not [bool]$package.root_readme.package_visible -and [string]$package.root_readme.disposition -ceq 'repository-documentation-package-excluded-m41-05b-complete') 'mir4-characterization-readme-disposition'

$bridge=Get-Content -Raw -LiteralPath (Join-Path $repo "$output/bridge-expiry.json")|ConvertFrom-Json -Depth 100
Assert-MIR4CharacterizationV1 (@($bridge.bridges|Where-Object{[bool]$_.deletion_authorized}).Count -eq 0) 'mir4-characterization-bridge-deletion'
Assert-MIR4CharacterizationV1 ([int]$bridge.summary.current_product -eq 0 -and [int]$bridge.summary.dual_write_authority -eq 0 -and [int]$bridge.summary.package_authority_bridge -eq 0 -and [int]$bridge.summary.release_current_state_authority_bridge -eq 0 -and [int]$bridge.summary.runtime_state_migration_authority_bridge -eq 0 -and [int]$bridge.summary.public_claim_authority_bridge -eq 0 -and [int]$bridge.summary.unowned -eq 0 -and [int]$bridge.summary.unbounded -eq 0) 'mir4-characterization-bridge-retirement'

$programme=Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/programmes/mir4-4x-operating-programme-v1.json')|ConvertFrom-Json
$m43 = @($programme.work_packages | Where-Object id -eq 'M43-00')
Assert-MIR4CharacterizationV1 (
  @($programme.work_packages|Where-Object{$_.id -eq 'M41-05' -and $_.state -eq 'complete'}).Count -eq 1 -and
  @($programme.work_packages|Where-Object{$_.id -eq 'M42-00' -and $_.state -eq 'complete'}).Count -eq 1 -and
  @($programme.work_packages|Where-Object{$_.id -eq 'M42-01' -and $_.state -eq 'complete'}).Count -eq 1 -and
  @($programme.work_packages|Where-Object{$_.id -eq 'M42-02' -and $_.state -eq 'complete'}).Count -eq 1 -and
  @($programme.work_packages|Where-Object{$_.id -eq 'M41-07' -and $_.state -eq 'complete'}).Count -eq 1 -and
  @($programme.work_packages|Where-Object{$_.id -eq 'M41-08' -and $_.state -eq 'active'}).Count -eq 1 -and
  $m43.Count -eq 1 -and [string]$m43[0].state -ceq 'blocked-dependency' -and 'M41-08' -in @($m43[0].depends_on)
) 'mir4-characterization-programme-successor-state'
Assert-MIR4CharacterizationV1 (@($programme.work_packages|Where-Object{$_.id -in @('M42-00','M42-01','M42-02','M41-07','M41-08') -and $_.completion_boundary -eq '4.1.0'}).Count -eq 5) 'mir4-41-physical-fixed-point-boundary'
Assert-MIR4CharacterizationV1 ([string]@($programme.outcome_trains|Where-Object candidate -eq '4.2.0')[0].outcome -match 'Integration kernel') 'mir4-42-integration-boundary'

$facade=(& pwsh -NoProfile -File (Join-Path $repo 'tools/mir.ps1') mir4 repository characterization-check 2>&1|Out-String).Trim()
if($LASTEXITCODE-ne 0){throw "[mir4-characterization-facade] $facade"}
$facadeResult=$facade|ConvertFrom-Json
Assert-MIR4CharacterizationV1 ([string]$facadeResult.status -ceq 'current') 'mir4-characterization-facade-result'

[pscustomobject][ordered]@{status='passed';test_id='static.mir4-repository-characterization-m42-00a';reports=[int]$check.reports;physical_files=[int]$check.summary.physical_files;authority_facts=[int]$check.summary.authority_facts;package_files=[int]$check.summary.package_files;package_source_sha256=$expectedPackage;root_readme_sha256=$expectedReadme;release_transition_authority=$false}
