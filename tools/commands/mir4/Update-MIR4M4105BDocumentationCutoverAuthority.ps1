param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$RecordedAt = '2026-09-02T18:20:00+10:00',
  [switch]$Check
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')

function Get-MIR4105BHash([string]$RelativePath) {
  return Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot $RelativePath)
}
$outputRelative = 'releases/migrations/MIR4-M41-05B-Documentation-CutoverV1.json'
$outputPath = Join-Path $RepoRoot $outputRelative
$schemaPath = Join-Path $RepoRoot 'contracts/repository/mir4-m41-05b-documentation-cutover-v1.schema.json'
$predecessorPath = 'releases/migrations/MIR4-M41-F2E-Package-Authority-CutoverV1.json'
$references = @(
  [pscustomobject][ordered]@{path='docs/reference/generated/runtime-pipeline.md';source='prototypes/mir/pipeline/commands.lua';sha256=(Get-MIR4105BHash 'docs/reference/generated/runtime-pipeline.md');package_visible=$false},
  [pscustomobject][ordered]@{path='docs/reference/generated/stream-defaults.md';source='prototypes/mir/settings/defaults.lua';sha256=(Get-MIR4105BHash 'docs/reference/generated/stream-defaults.md');package_visible=$false}
)
$packageDocuments = @(
  foreach ($target in @('f210','f200','f110','f100')) {
    $readme = "targets/$target/generation/README.md.template"
    $changelog = "targets/$target/generation/changelog.txt.template"
    [pscustomobject][ordered]@{target=$target;readme_path=$readme;readme_sha256=(Get-MIR4105BHash $readme);changelog_path=$changelog;changelog_sha256=(Get-MIR4105BHash $changelog);baseline_bytes_preserved=$true}
  }
)
$previousHashes = [ordered]@{
  '.mir/docs.yml'='36757482428B198AFB57123D0BDD3A70B029FAC77EB97D9E73DD0D2F11AA465E'
  'docs/reference/generated/documentation-index.md'='F88C15D1D3022B2240F3604EA789BB587F510FFF2B967D3B0A682A078F2A129B'
  'docs/reference/generated/documentation-navigation.md'='5851012CC5E3310A20284A2202487D1B0CF30155DA19281EF708DDA1BE6A35DC'
  'docs/reference/generated/documentation-owner-dashboard.md'='DD826426801B1E7291326F931FBC31E7814B6D11E5FFDE536C0C44902EF44108'
  'docs/reference/generated/documentation-review-age.md'='2E4CF8F92C6B067E4922ABCF80599966C5AC99535C26D5AF0A7759550BBB6519'
  'mir.lock'='654BB1A91D33825C5308B77892EC1BFA9E4148278075C397492140BE802932F3'
  'README.md'='DF5D4D801DC4A416E4F7C9826EB2E3AE6CFD915937C8599CA7307CCEB343F947'
  'sdk/preview/mir4/reference/compilation-runs.json'='AFEC35742C22691BB6C1E1407193FC97E1CF270B406AF8F33BA9112BFD1DD6FE'
  'sdk/preview/mir4/reference/continuity-bundle-template.json'='37516F8D427AC8E6E4E7D15CA718D0C846AD192B17CFDE0531C007B41D982352'
  'sdk/preview/mir4/reference/inspection-bundle-v1.json'='A9C78929B862FF3E3E6268CA494B5702ABC4BB4EF5839204F5599F66DD42D6FD'
  'sdk/preview/mir4/reference/inspector-workbench-result-v1.json'='E1CB65E48286ADC0B59E0A2CC77320BEBD6F17C19297570616E3F37033D678D8'
  'sdk/preview/mir4/reference/merge-law-catalogue.json'='EC717111C5FE63EF90A9035DB8F91773676DE84910861E1FEDCD7329F3271BD8'
  'sdk/preview/mir4/reference/migration-graph-matrix.json'='AC9AF55B9395E9642E85C6FBBF501D7A3E7991597EE148F36A912286B0757F46'
  'sdk/preview/mir4/reference/query-snapshot-f210.json'='729F62D339ABD5E384DDAA633491AB2203733EB160E45795196114C2AE552F79'
  'validation/tests/mir4/Test-MIR4DocumentationContinuityT14.ps1'='005E124D7D156F61D2252A392E52484F59AE550454D40CEC6C86AB1BF66D2428'
}
$evolved = @(
  foreach ($entry in $previousHashes.GetEnumerator()) {
    [pscustomobject][ordered]@{
      path=[string]$entry.Key
      previous_sha256=[string]$entry.Value
      current_sha256=Get-MIR4105BHash ([string]$entry.Key)
      hash_mode='canonical-text-v1'
      reason='Advance the current package-excluded documentation and preview projections through the M41-05B fixed point.'
      scope='package-excluded-documentation-cutover'
      package_visible=$false
      release_authority=$false
    }
  }
)
$currentRoles = [ordered]@{
  'CHANGELOG.md'='generated-source-changelog'
  'changes/unreleased/MIR4-CHG-2026-0014.json'='documentation-cutover-change-fact'
  'contracts/repository/mir4-m41-05b-documentation-cutover-v1.schema.json'='documentation-cutover-schema'
  'docs/reference/generated/runtime-pipeline.md'='generated-runtime-pipeline'
  'docs/reference/generated/stream-defaults.md'='generated-stream-defaults'
  'releases/governance/MIR4-Source-Changelog-PlanV1.json'='source-changelog-plan'
  'spec/programmes/mir4-4x-operating-programme-v1.json'='current-operating-programme'
  'todo.md'='generated-operating-queue'
  'tools/commands/docs/Update-MIRPipelineDocumentation.ps1'='runtime-pipeline-writer'
  'tools/commands/docs/Update-MIRREADMEStreamDefaults.ps1'='stream-default-writer'
  'tools/commands/mir4/Update-MIR4M4105BDocumentationCutoverAuthority.ps1'='documentation-cutover-receipt-writer'
  'tools/lib/mir4/PreFreezeRelease.ps1'='append-only-authority-validator'
  'validation/tests.yml'='executable-test-catalogue'
  'validation/tests/compiler/Test-MIRSettingsVisibility.ps1'='stream-default-conformance'
  'validation/tests/mir4/Test-MIR4DocumentationCutoverM4105B.ps1'='documentation-cutover-conformance'
  'validation/tests/mir4/Test-MIR4PreFreezeHardening.ps1'='historical-custody-and-current-succession-conformance'
}
$currentAuthorities = @(
  foreach ($entry in $currentRoles.GetEnumerator()) {
    [pscustomobject][ordered]@{path=[string]$entry.Key;sha256=(Get-MIR4105BHash ([string]$entry.Key));hash_mode='canonical-text-v1';role=[string]$entry.Value;package_visible=$false;release_authority=$false}
  }
)
$readmePath = Join-Path $RepoRoot 'README.md'
$record = [pscustomobject][ordered]@{
  schema=1
  kind='MIR4M4105BDocumentationCutoverV1'
  status='M41-05B-DOCUMENTATION-CUTOVER-COMPLETE'
  recorded_at=$RecordedAt
  programme_id='M41-05B-DOCUMENTATION-CUTOVER'
  change_id='MIR4-CHG-2026-0014'
  predecessor_receipt=[pscustomobject][ordered]@{path=$predecessorPath;sha256=(Get-MIR4105BHash $predecessorPath)}
  base=[pscustomobject][ordered]@{commit='fed9ae76cdb99b1dcfacfaf263f612d9c6f01a31';tree='15b2df204cac33121000c36b741738ebfc611237'}
  repository_landing=[pscustomobject][ordered]@{path='README.md';sha256=(Get-MIR4105BHash 'README.md');bytes=[IO.FileInfo]::new($readmePath).Length;maximum_bytes=12288;package_visible=$false}
  generated_references=$references
  baseline_package_documents=$packageDocuments
  package_source_sha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot
  programme_sha256=Get-MIR4105BHash 'spec/programmes/mir4-4x-operating-programme-v1.json'
  evolved_bindings=$evolved
  current_authorities=$currentAuthorities
  invariants=[pscustomobject][ordered]@{root_readme_package_excluded=$true;repository_and_package_docs_separate=$true;historical_4_0_package_docs_preserved=$true;source_changelog_generated=$true;target_changelog_generated_from_release_inventory=$true;player_executable_sources_unchanged=$true}
  transition_gate=[pscustomobject][ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  next_fixed_point='M42-01-TOOLING-TEST-WORKFLOW-CONVERGENCE'
  record_sha256=''
}
$record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
$json = ($record | ConvertTo-Json -Depth 100).Replace("`r`n","`n") + "`n"
if (-not ($json | Test-Json -SchemaFile $schemaPath)) { throw '[mir4-m41-05b-schema]' }
if ($Check) {
  if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw '[mir4-m41-05b-receipt-missing]' }
  if ([IO.File]::ReadAllText($outputPath).Replace("`r`n","`n") -cne $json) { throw '[mir4-m41-05b-receipt-stale]' }
  Write-Host '[ok] M41-05B documentation cutover receipt is current.'
  return $record
}
[IO.File]::WriteAllText($outputPath,$json,[Text.UTF8Encoding]::new($false))
return $record
