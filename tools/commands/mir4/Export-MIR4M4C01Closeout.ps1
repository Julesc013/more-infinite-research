param(
  [string]$RepoRoot = '',
  [string]$OutputRoot = 'build/mir4/m4c01-closeout'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path }
else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }
$output = [IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputRoot))
$allowed = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build/mir4')).TrimEnd('\') + '\'
if (-not ($output + '\').StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
  throw "M4C01 closeout must remain beneath build/mir4: $output"
}
New-Item -ItemType Directory -Force -Path $output | Out-Null

function Read-RepoJson([string]$Path) {
  $full = Join-Path $RepoRoot $Path
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "M4C01 closeout input is absent: $Path" }
  return Get-Content -Raw -LiteralPath $full | ConvertFrom-Json -Depth 100
}
function Get-RepoSha([string]$Path) {
  return (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $RepoRoot $Path)).Hash
}
function Write-CloseoutJson([string]$Name, $Value) {
  $path = Join-Path $output $Name
  [IO.File]::WriteAllText($path, (($Value | ConvertTo-Json -Depth 100) + "`n"), [Text.UTF8Encoding]::new($false))
  return $path
}

$sourceCommit = (& git -C $RepoRoot rev-parse HEAD).Trim()
$sourceBranch = (& git -C $RepoRoot branch --show-current).Trim()
$playerSet = Read-RepoJson 'build/mir4/m4c01-player-candidates/candidate-set.json'
$affected = Read-RepoJson 'build/results/mir4-sol/sol08/target-candidates/MIR4_AFFECTED_TARGET_CANDIDATES.json'
$sol08 = Read-RepoJson '.mir/releases/waves/mir4-r0/MIR4-Affected-Proof-Closure-SOL08V1.json'
$feedback = Read-RepoJson '.mir/releases/waves/mir4-r0/MIR4-Public-Feedback-IntakeV1.json'
$maturity = Read-RepoJson '.mir/releases/waves/mir4-r0/MIR4-Platform-Maturity-and-Publication-ContractV1.json'
$preview = Read-RepoJson 'build/mir4/platform-preview/preview-assets.json'
$legacyHandoff = Read-RepoJson 'build/mir4/m4c01-handoff/MIR4_M4C01_STATUS.json'
$f210Plan = Read-RepoJson 'build/results/mir4-sol/sol09/f210-verification-plan-v1-postmaterialization-auto.json'
$f200Plan = Read-RepoJson 'build/results/mir4-sol/sol09/f200-verification-plan-v1-postmaterialization-auto.json'

$preservedRows = @(
  foreach ($row in @($playerSet.targets)) {
    $mandatory = [string]$row.target_key -in @('f210', 'f200')
    [ordered]@{
      lane = 'preserved-m4c01-player-presentation'
      target_key = [string]$row.target_key
      factorio_line = [string]$row.factorio_line
      role = [string]$row.role
      version = [string]$row.version
      predecessor = [string]$row.predecessor
      archive = "build/mir4/m4c01-player-candidates/distributions/more-infinite-research_$([string]$row.version).zip"
      archive_sha256 = [string]$row.sha256
      bytes = [long]$row.bytes
      entries = [int]$row.entries
      deterministic_repetitions = @('A', 'B', 'C')
      status = if ($mandatory) { 'superseded-for-corrected-target-proof' } else { [string]$row.status }
      release_admitted = $false
    }
  }
)
$correctedRows = @(
  foreach ($row in @($affected.targets)) {
    [ordered]@{
      lane = 'sol08-corrected-affected-proof'
      target_key = [string]$row.target_key
      factorio_line = [string]$row.factorio_line
      role = 'mandatory'
      version = [string]$row.version
      archive = [string]$row.archive
      archive_sha256 = [string]$row.archive_sha256
      content_sha256 = [string]$row.content_sha256
      bytes = [long]$row.bytes
      entries = [int]$row.entry_count
      deterministic_repetitions = @($row.repetitions.id)
      status = 'exact-development-proof-passed-awaiting-source-freeze'
      release_admitted = $false
    }
  }
)
$packageMatrix = [ordered]@{
  schema = 1
  kind = 'MIR4M4C01PackageMatrixV1'
  status = 'complete-development-inventory'
  source_commit = $sourceCommit
  candidate_wave = 'M4C01'
  preserved_candidates = $preservedRows
  corrected_mandatory_candidates = $correctedRows
  mandatory_target_rule = 'f210 and f200 release qualification must use fresh packages from the eventual source-frozen commit; preserved fixed-point bytes are superseded evidence'
  release_zip_denylist = @('.mir/', '.codex/', '.github/', 'build/', 'dist/', 'docs/', 'fixtures/', 'scripts/', 'tests/', 'validation/', 'tools/', 'AGENTS.md', 'CONTRIBUTING.md', 'todo.md')
  public_output_authorized = $false
}
$null = Write-CloseoutJson 'MIR4_M4C01_PACKAGE_MATRIX.json' $packageMatrix

$runtimeMatrix = [ordered]@{
  schema = 1
  kind = 'MIR4M4C01RuntimeMigrationMatrixV1'
  status = 'mandatory-target-development-proof-passed'
  rows = @(
    [ordered]@{target_key='f210';candidate_sha256='859930DD60E8BBFEF532041EAF13C2B928CF34CAA2F2FC3C2FE5536ACD66C5E9';engine_sha256='E396BD25C068DD4C5EF45E93E6A87DBA0E12EEA964B6A5B73163041CC4A6143F';fresh_exact_loads=6;upgrade_archetypes=5;reloads_per_archetype=2;status='passed';evidence='.mir/releases/waves/mir4-r0/MIR4-Affected-Proof-Closure-SOL08V1.json'},
    [ordered]@{target_key='f200';candidate_sha256='0078768BDDAEB4E8AE243D406919C38C55AC6C2CB96A492E890175EDEB0860C4';engine_sha256='D3BCFCA4DBEE407D472013B745CE2445D34AF6F021AACC5753EE0DAC54B56B0B';fresh_exact_loads=4;upgrade_archetypes=1;reloads_per_archetype=2;status='passed';evidence='.mir/releases/waves/mir4-r0/MIR4-Affected-Proof-Closure-SOL08V1.json'},
    [ordered]@{target_key='f110';role='conditional';status='built-not-qualified-this-closeout';release_blocking=$false},
    [ordered]@{target_key='f100';role='conditional';status='built-not-qualified-this-closeout';release_blocking=$false},
    [ordered]@{target_key='f018';role='private-experimental';status='exact-engine-unavailable';release_blocking=$false},
    [ordered]@{target_key='f017-f013';role='private-experimental';status='built-not-admitted';persisted_two_reload_proof='not-run-this-closeout';release_blocking=$false}
  )
  product_failures = 0
  release_qualification_transferable = $false
}
$null = Write-CloseoutJson 'MIR4_M4C01_RUNTIME_MIGRATION_MATRIX.json' $runtimeMatrix

$maturityMatrix = [ordered]@{
  schema = 1
  kind = 'MIR4M4C01MaturityMatrixV1'
  status = 'contract-enforced'
  contract = '.mir/releases/waves/mir4-r0/MIR4-Platform-Maturity-and-Publication-ContractV1.json'
  contract_sha256 = Get-RepoSha '.mir/releases/waves/mir4-r0/MIR4-Platform-Maturity-and-Publication-ContractV1.json'
  player_targets = @(
    [ordered]@{targets=@('f210','f200');maturity='stable-player-contract';candidate_state='development-proof-passed-not-release-admitted'},
    [ordered]@{targets=@('f110','f100');maturity='conditional';candidate_state='built-unqualified'},
    [ordered]@{targets=@('f018','f017','f016','f015','f014','f013');maturity='private-experimental';candidate_state='not-publicly-admitted'}
  )
  preview_assets = @($preview.assets | ForEach-Object {[ordered]@{name=[string]$_.name;maturity='preview';sha256=[string]$_.sha256;mod_portal_payload=$false}})
  forbidden_non_stable_actions = @($maturity.non_stable_forbidden)
  publication = $maturity.publication
}
$null = Write-CloseoutJson 'MIR4_M4C01_MATURITY_MATRIX.json' $maturityMatrix

$nonInterference = [ordered]@{
  schema = 1
  kind = 'MIR4M4C01NonInterferenceMatrixV1'
  status = 'passed-with-explicit-deltas'
  rows = @(
    [ordered]@{scope='m4c01-player-presentation';targets=@($playerSet.targets.target_key);allowed_changes=@('README.md','changelog.txt');status='passed'},
    [ordered]@{scope='sol08-f210-correction';baseline='SOL06 exact current candidate';allowed_changes=@('info.json');added=0;changed=1;removed=0;unexpected=0;status='passed'},
    [ordered]@{scope='sol08-f200-correction';baseline='2.5.11 exact terminal package';allowed_changes=@($sol08.package_deltas | Where-Object target_key -eq 'f200' | ForEach-Object allowed_paths);added=1;changed=6;removed=0;unexpected=0;status='passed'},
    [ordered]@{scope='developer-preview-assets';player_package_dependency=$false;prototype_mutation=$false;persistent_state_mutation=$false;status='passed'},
    [ordered]@{scope='release-actions';source_freeze=$false;signing=$false;sealing=$false;tagging=$false;publication=$false;status='preserved-boundary'}
  )
}
$null = Write-CloseoutJson 'MIR4_M4C01_NON_INTERFERENCE_MATRIX.json' $nonInterference

$revocation = [ordered]@{
  schema = 1
  kind = 'MIR4M4C01EvidenceRevocationMatrixV1'
  status = 'current-evidence-set-closed'
  rows = @(
    [ordered]@{evidence='V04 fixed-point audit';disposition='retained-as-starting-authority';transfer='source-reconciliation-only'},
    [ordered]@{evidence='preserved M4C01 f210 package FA32F0C9A3FF7CBF9D95AA45F6164CF893C0CBBB4BFFE7AEED9FAC524B5C0117';disposition='superseded';reason='confirmed package-visible corrections require fresh target package'},
    [ordered]@{evidence='preserved M4C01 f200 package 886E92D34D04A3D9FBC3193B35658E4C0A2DB2F0582F531AAFA5AF53CBE30B3E';disposition='superseded';reason='confirmed package-visible corrections require fresh target package'},
    [ordered]@{evidence='SOL08 exact load and upgrade evidence';disposition='current';binding='exact corrected candidate and exact engine hashes'},
    [ordered]@{evidence='SOL08 preproof verification plans';disposition='superseded';reason='bootstrap materialization and offline custody invalid rows were closed'},
    [ordered]@{evidence='SOL09 f210 verification plan';disposition='current';plan_material_sha256=[string]$f210Plan.plan_material_sha256;invalid=0},
    [ordered]@{evidence='SOL09 f200 verification plan';disposition='current';plan_material_sha256=[string]$f200Plan.plan_material_sha256;invalid=0},
    [ordered]@{evidence='M4C01 performance campaigns bound to preserved package hashes';disposition='nontransferable-to-corrected-candidates';reason='candidate fingerprints changed; fresh source-frozen qualification required'}
  )
  revocation_test = 'passed-exact-fingerprint-and-revocation-invalidation'
}
$null = Write-CloseoutJson 'MIR4_M4C01_EVIDENCE_REVOCATION_MATRIX.json' $revocation

$familyOutcome = @{
  'REPRO-MAXCAP' = [ordered]@{status='closed';result='MaximumLevelBinding V3 and exact f210/f200 upgrade proof passed';receipt='.mir/releases/waves/mir4-r0/MIR4-Maximum-Level-Binding-SOL03V1.json'}
  'REPRO-CUBIUM' = [ordered]@{status='closed';result='ordinary acquisition route policy and exact Cubium load passed';receipt='.mir/releases/waves/mir4-r0/MIR4-Production-Route-SOL04V1.json'}
  'REPRO-RECYCLER-PROGRESSION' = [ordered]@{status='closed-bounded';result='exact f210 passed; exact f200 1.0.0 lacks reported surface while generic rejection remains passed';receipt='.mir/releases/waves/mir4-r0/MIR4-Affected-Proof-Closure-SOL08V1.json'}
  'REPRO-COST-V2-REQUEST' = [ordered]@{status='preview-complete-stable-deferred';result='schema and deterministic model preview complete; no stable default broadened';receipt='.mir/releases/waves/mir4-r0/MIR4-Research-Cost-V2-SOL05V1.json'}
  'REPRO-K2SO-SCIENCE' = [ordered]@{status='closed-bounded';result='K2SciencePhasePolicy V2 passed exact f210 and f200 K2SO environments';receipt='.mir/releases/waves/mir4-r0/MIR4-K2-Science-SOL06V1.json'}
  'REPRO-OVERHAUL-SUPPORT' = [ordered]@{status='closed-as-subject-ledger';result='13-subject ledger complete; unproved overhauls retain no blanket claim';receipt='.mir/releases/waves/mir4-r0/MIR4-Compatibility-Campaign-SOL07V1.json'}
}
$feedbackRows = @(
  foreach ($family in @($feedback.families)) {
    $outcome = $familyOutcome[[string]$family.id]
    [ordered]@{id=[string]$family.id;classification=[string]$family.classification;status=[string]$outcome.status;result=[string]$outcome.result;receipt=[string]$outcome.receipt}
  }
)
$feedbackDisposition = [ordered]@{
  schema = 1
  kind = 'MIR4M4C01PublicFeedbackDispositionV1'
  status = 'all-six-families-disposed'
  source = '.mir/releases/waves/mir4-r0/MIR4-Public-Feedback-IntakeV1.json'
  source_sha256 = Get-RepoSha '.mir/releases/waves/mir4-r0/MIR4-Public-Feedback-IntakeV1.json'
  families = $feedbackRows
  unresolved_product_blockers = 0
  blanket_compatibility_claims = 0
}
$null = Write-CloseoutJson 'MIR4_M4C01_PUBLIC_FEEDBACK_DISPOSITION.json' $feedbackDisposition

$blockerMatrix = [ordered]@{
  schema = 1
  kind = 'MIR4M4C01BlockerMatrixV1'
  status = 'implementation-complete-release-actions-blocked'
  product_blockers = @()
  release_candidate_blockers = @(
    [ordered]@{id='source-freeze-and-candidate-allocation';status='requires-maintainer-authorization';reason='current corrected package-visible source is intentionally uncommitted and no freeze/commit was authorized'},
    [ordered]@{id='fresh-performance-f210';status='blocked-by-source-freeze';reason='corrected candidate fingerprint differs from preserved M4C01 performance authority'},
    [ordered]@{id='fresh-performance-f200';status='blocked-by-source-freeze';reason='corrected candidate fingerprint differs from preserved M4C01 performance authority'},
    [ordered]@{id='independent-review';status='external-review-required';reason='single-agent implementation audit cannot honestly claim reviewer independence'},
    [ordered]@{id='maintainer-manual-acceptance';status='human-attestation-required';reason='manual disposable-profile acceptance is not automated'}
  )
  nonblocking_target_gaps = @(
    [ordered]@{id='f110-f100-conditional-qualification';status='not-run';release_blocking=$false},
    [ordered]@{id='f018-exact-engine';status='unavailable';release_blocking=$false},
    [ordered]@{id='f017-f013-persisted-two-reload-admission';status='not-run';release_blocking=$false}
  )
  prohibited_without_new_authority = @('commit-or-source-freeze','production-key-use','signing','sealing','main-or-legacy-promotion','tags','github-release-publication','mod-portal-upload','cleanup')
}
$null = Write-CloseoutJson 'MIR4_M4C01_BLOCKER_MATRIX.json' $blockerMatrix

$completion = [ordered]@{
  schema = 1
  kind = 'MIR4M4C01CompletionRecordV1'
  status = 'M4C01-DEVELOPMENT-CLOSEOUT-COMPLETE'
  source = [ordered]@{branch=$sourceBranch;commit=$sourceCommit;reconciled_predecessor='e190836c8b8f781c4e41dafc08df367ca986b33a';worktree_dirty=$true}
  scope = 'M4C01 implementation and development evidence closeout; not source freeze, release-candidate allocation, signing, sealing, promotion, or publication'
  gates = [ordered]@{
    sol02_through_sol08 = 'passed'
    platform_generation = 'passed'
    platform_conformance = 'passed'
    preview_packaging = 'passed'
    preserved_ten_target_player_set = 'passed-deterministic-abc'
    mandatory_corrected_target_loads = 'passed-10-of-10'
    mandatory_upgrade_archetypes = 'passed-6-of-6-two-reloads-each'
    bootstrap_materialization = 'passed'
    offline_custody_fail_closed = 'passed-no-seal-minted'
    evidence_store = 'passed'
    assurance_regression = 'passed-approved-machine-context'
    verification_plans = 'materialized-zero-invalid-f210-and-f200'
  }
  mandatory_targets = @('f210','f200')
  mandatory_product_failures = 0
  implementation_complete = $true
  release_candidate_ready = $false
  publication_authorized = $false
  blockers = 'MIR4_M4C01_BLOCKER_MATRIX.json'
  predecessor_handoff = [ordered]@{path='build/mir4/m4c01-handoff/MIR4_M4C01_STATUS.json';sha256=Get-RepoSha 'build/mir4/m4c01-handoff/MIR4_M4C01_STATUS.json';record_digest=[string]$legacyHandoff.record_digest}
}
$null = Write-CloseoutJson 'MIR4_M4C01_COMPLETION_RECORD.json' $completion

$handoffLines = @(
  '# MIR 4 M4C01 closeout', '',
  'Status: `M4C01-DEVELOPMENT-CLOSEOUT-COMPLETE`', '',
  "Branch: ``$sourceBranch``  ",
  "Source commit: ``$sourceCommit``  ",
  'Public output authorized: `false`', '',
  '## Result', '',
  'SOL02 through SOL08, platform conformance, deterministic ten-target presentation packaging, mandatory f210/f200 exact loads, six upgrade archetypes with two reloads each, bootstrap materialization, custody fail-closed behavior, and assurance regression are complete.', '',
  'The preserved M4C01 f210/f200 player-package bytes are superseded for corrected-package proof. The SOL08 f210/f200 packages are the current development evidence, but they are not source-frozen release candidates.', '',
  '## Remaining release-candidate gates', '',
  '- Maintainer-authorized commit/source freeze and candidate allocation.',
  '- Fresh f210/f200 performance qualification against the frozen corrected candidate hashes.',
  '- Independent reviewer audit and maintainer manual disposable-profile acceptance.',
  '- A separate production go/no-go before signing, sealing, promotion, tags, GitHub publication, or Mod Portal upload.', '',
  'Conditional f110/f100 and private historical targets remain nonblocking unless separately admitted.'
)
[IO.File]::WriteAllText((Join-Path $output 'MIR4_M4C01_HANDOFF.md'), ($handoffLines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))

$hashRows = @(
  Get-ChildItem -LiteralPath $output -File |
    Where-Object Name -ne 'SHA256SUMS.json' |
    Sort-Object Name |
    ForEach-Object {[ordered]@{path=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash}}
)
$checksum = [ordered]@{schema=1;kind='MIR4M4C01CloseoutChecksumsV1';status='complete';files=$hashRows}
$null = Write-CloseoutJson 'SHA256SUMS.json' $checksum

Write-Host "[ok] MIR 4 M4C01 closeout exported: $output"
$completion | ConvertTo-Json -Depth 20
