# MIR4-CANONICAL-EXECUTABLE-TEST
# Append-only materializer for the bounded A05/K2-03 Imersite qualification.
param(
  [string]$RepoRoot = '',
  [string]$RuntimeResult = 'build/mir4/a05-k2-materials/k2-03-runtime/result.json',
  [switch]$RequireLocalEvidence
)
$ErrorActionPreference = 'Stop'
if (-not $RequireLocalEvidence) { throw '[mir4-a05-k2-03-local-evidence-required]' }
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/tooling/CommandInventory.ps1')

function Assert-A05K203 { param([bool]$Condition,[string]$Code) if (-not $Condition) { throw $Code } }
function Resolve-A05K203Path { param([string]$Relative,[bool]$Required=$true)
  Assert-A05K203 ($Relative -cmatch '^[A-Za-z0-9._/-]+$' -and $Relative -notmatch '(^|/)\.\.(/|$)') "[mir4-a05-k2-03-relative] $Relative"
  $path = [IO.Path]::GetFullPath((Join-Path $RepoRoot $Relative))
  $prefix = $RepoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  Assert-A05K203 ($path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) "[mir4-a05-k2-03-escape] $Relative"
  if ($Required) { Assert-A05K203 (Test-Path -LiteralPath $path -PathType Leaf) "[mir4-a05-k2-03-missing] $Relative" }
  $path
}
function Get-A05K203Relative { param([string]$Path)
  $full = [IO.Path]::GetFullPath($Path)
  $prefix = $RepoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  Assert-A05K203 ($full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) '[mir4-a05-k2-03-private-path]'
  $full.Substring($prefix.Length).Replace('\','/')
}
function Get-A05K203Artifact { param([string]$Relative)
  $path = Resolve-A05K203Path $Relative $true
  [pscustomobject][ordered]@{path=$Relative;bytes=[long](Get-Item -LiteralPath $path).Length;raw_sha256=(Get-MIR4Sha256File -Path $path)}
}
function Get-A05K203Source { param([string]$Relative)
  [pscustomobject][ordered]@{path=$Relative;canonical_sha256=(Get-MIR4BootstrapTextSha256 -Path (Resolve-A05K203Path $Relative $true))}
}
function Get-A05K203RawBinding { param([string]$Relative)
  [pscustomobject][ordered]@{path=$Relative;raw_sha256=(Get-MIR4Sha256File -Path (Resolve-A05K203Path $Relative $true))}
}
function Get-A05K203RecordBinding { param([string]$Relative)
  $path = Resolve-A05K203Path $Relative $true
  $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100 -DateKind String
  Assert-A05K203 (Test-MIR4BootstrapRecordHash $record) "[mir4-a05-k2-03-lineage] $Relative"
  [pscustomobject][ordered]@{path=$Relative;raw_sha256=(Get-MIR4Sha256File -Path $path);record_sha256=[string]$record.record_sha256}
}
function Assert-A05K203Artifact { param($Artifact,[string]$Code)
  $actual = Get-A05K203Artifact ([string]$Artifact.path)
  Assert-A05K203 ($actual.bytes -eq [long]$Artifact.bytes -and $actual.raw_sha256 -eq [string]$Artifact.raw_sha256) $Code
  $actual
}
function Get-A05K203AbsoluteArtifact { param([string]$Path,[string]$ExpectedSha)
  $relative = Get-A05K203Relative $Path
  $artifact = Get-A05K203Artifact $relative
  Assert-A05K203 ($artifact.raw_sha256 -eq $ExpectedSha) "[mir4-a05-k2-03-absolute-artifact] $relative"
  $artifact
}
function Write-A05K203Immutable { param($Record,[string]$Relative,[string]$Schema)
  $target = Resolve-A05K203Path $Relative $false
  $scratchDir = Join-Path $RepoRoot 'build/a05-k2-03-closure-patch'
  [IO.Directory]::CreateDirectory($scratchDir) | Out-Null
  $scratch = Join-Path $scratchDir ([IO.Path]::GetFileName($Relative) + '.scratch')
  $null = Write-MIR4BootstrapRecord -Record $Record -Path $scratch
  $text = [IO.File]::ReadAllText($scratch)
  Assert-A05K203 ($text | Test-Json -SchemaFile (Resolve-A05K203Path $Schema $true)) "[mir4-a05-k2-03-schema] $Relative"
  Assert-A05K203 ($text -notmatch '(?i)(?:[A-Z]:[\\/]|\\\\)') "[mir4-a05-k2-03-private-record] $Relative"
  if (Test-Path -LiteralPath $target) {
    Assert-A05K203 ([IO.File]::ReadAllText($target) -ceq $text) "[mir4-a05-k2-03-immutable-overwrite] $Relative"
  } else {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
    [IO.File]::Move($scratch,$target)
  }
  Get-A05K203RecordBinding $Relative
}
function ConvertTo-A05K203Reloads { param($Contract)
  if ($null -eq $Contract) { return $null }
  Assert-A05K203 ($Contract.passed -and [int]$Contract.required_count -eq 2 -and [int]$Contract.actual_count -eq 2) '[mir4-a05-k2-03-reload-contract]'
  $marker = '[MIR4_A05_K2_03_IMERSITE_PROGRESS] technology=recipe-prod-research_material_imersite-1 progress=0.42'
  $reloads = @()
  foreach ($reload in @($Contract.reloads | Sort-Object ordinal)) {
    $log = Get-A05K203AbsoluteArtifact ([string]$reload.factorio_log) ([string]$reload.factorio_log_sha256)
    $stdout = Get-A05K203AbsoluteArtifact ([string]$reload.stdout) ([string]$reload.stdout_sha256)
    $stderr = Get-A05K203AbsoluteArtifact ([string]$reload.stderr) ([string]$reload.stderr_sha256)
    $markerCount = @(Select-String -LiteralPath (Resolve-A05K203Path $log.path $true) -SimpleMatch $marker).Count
    Assert-A05K203 ($reload.passed -and -not $reload.timed_out -and [int]$reload.exit_code -eq 0 -and $reload.save_byte_identical -and $reload.reload_log_contract_passed -and $reload.input_save_sha256 -eq $reload.save_sha256 -and $markerCount -eq 1) "[mir4-a05-k2-03-reload] $($reload.ordinal)"
    $reloads += [pscustomobject][ordered]@{ordinal=[int]$reload.ordinal;passed=$true;exit_code=0;timed_out=$false;duration_seconds=$reload.duration_seconds;maximum_duration_seconds=300;input_save_sha256=[string]$reload.input_save_sha256;save_sha256=[string]$reload.save_sha256;save_byte_identical=$true;stdout=$stdout;stderr=$stderr;factorio_log=$log;marker=$marker;marker_count=1;reload_log_contract_passed=$true}
  }
  Assert-A05K203 ($reloads.Count -eq 2) '[mir4-a05-k2-03-reload-count]'
  [pscustomobject][ordered]@{required_count=2;actual_count=2;passed=$true;reloads=$reloads}
}
function ConvertTo-A05K203Case { param($Case,[bool]$ExpectXy,[bool]$ExpectReload,[string]$Version,[string]$VersionHash,[string]$Phase)
  Assert-A05K203 ($Case.fresh_load.passed -and [string]$Case.k2so.version -eq $Version -and [string]$Case.k2so.archive_sha256 -eq $VersionHash -and [bool]$Case.xy_enabled -eq $ExpectXy) "[mir4-a05-k2-03-case] $Version"
  Assert-A05K203 ([string]$Case.observation.owner.native -eq 'kr-imersite-productivity' -and [string]$Case.observation.owner.mir -eq 'recipe-prod-research_material_imersite-1' -and [string]$Case.observation.science.science_phase_policy_status -eq $Phase) "[mir4-a05-k2-03-owner] $Version"
  Assert-A05K203 ([int]$Case.observation.route_counts.total -eq 19 -and [int]$Case.observation.route_counts.external_exact_owner -eq 1 -and [int]$Case.observation.route_counts.generated_family_covered -eq 1 -and [int]$Case.observation.route_counts.safe_skip -eq 17) "[mir4-a05-k2-03-routes] $Version"
  $reloads = ConvertTo-A05K203Reloads $Case.reloads
  Assert-A05K203 (($ExpectReload -and $null -ne $reloads) -or (-not $ExpectReload -and $null -eq $reloads)) "[mir4-a05-k2-03-reload-scope] $Version"
  foreach ($artifact in @($Case.fresh_load.save,$Case.fresh_load.stdout,$Case.fresh_load.stderr,$Case.fresh_load.factorio_log,$Case.mod_closure.candidate,$Case.mod_closure.fixture,$Case.mod_closure.mod_list,$Case.mod_closure.mod_settings)+@($Case.mod_closure.archives)) { $null = Assert-A05K203Artifact $artifact "[mir4-a05-k2-03-case-artifact] $Version" }
  [pscustomobject][ordered]@{
    case_id=[string]$Case.case_id
    k2so=[pscustomobject][ordered]@{version=$Version;archive_sha256=$VersionHash}
    xy_enabled=$ExpectXy
    fresh_load=[pscustomobject][ordered]@{passed=$true;duration_seconds=$Case.fresh_load.duration_seconds;save=$Case.fresh_load.save;stdout=$Case.fresh_load.stdout;stderr=$Case.fresh_load.stderr;factorio_log=$Case.fresh_load.factorio_log}
    reloads=$reloads
    mod_closure=[pscustomobject][ordered]@{enabled_mods=@($Case.mod_closure.enabled_mods);external_archives=@($Case.mod_closure.archives);candidate=$Case.mod_closure.candidate;fixture=$Case.mod_closure.fixture;mod_list=$Case.mod_closure.mod_list;mod_settings=$Case.mod_closure.mod_settings}
    observation=$Case.observation
  }
}

$runtimeRelative = $RuntimeResult.Replace('\','/')
$runtimePath = Resolve-A05K203Path $runtimeRelative $true
$runtime = Get-Content -Raw -LiteralPath $runtimePath | ConvertFrom-Json -Depth 100 -DateKind String
Assert-A05K203 ($runtime.kind -eq 'MIR4A05K203ImersiteRuntimeResultV1') '[mir4-a05-k2-03-runtime-kind]'
Assert-A05K203 ($runtime.engine.version -eq '2.1.17' -and $runtime.engine.executable_sha256 -eq '710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8') '[mir4-a05-k2-03-engine]'
Assert-A05K203 ($runtime.candidate.archive_sha256 -eq '99C020CBA2800179FF2D76EE35F58B27A97CF2A7D89993CFFE06403DC140090E') '[mir4-a05-k2-03-candidate]'
$null = Assert-A05K203Artifact $runtime.test '[mir4-a05-k2-03-test-artifact]'
foreach ($artifact in @($runtime.fixture)) { $null = Assert-A05K203Artifact $artifact '[mir4-a05-k2-03-fixture-artifact]' }
$locked = ConvertTo-A05K203Case $runtime.locked_2_0_13 $true $true '2.0.13' 'A2EEB2E5A6119C4117BD3653979D40D305D17539E184BFA6F4ED53EF12A5F242' 'already-normalized'
$current = ConvertTo-A05K203Case $runtime.current_2_0_17_fresh_load_only $false $false '2.0.17' '0D48E22858FB4D1259413B65FFA7E5A0C5B5C2439A4918D58BDACC9411FA9284' 'not-applicable'
Assert-A05K203 ($runtime.version_parity.owner_effects -and $runtime.version_parity.route_matrix) '[mir4-a05-k2-03-version-parity]'
Assert-A05K203 ((ConvertTo-MIR4BootstrapCanonicalJson -Value $locked.observation.effect_owners) -ceq (ConvertTo-MIR4BootstrapCanonicalJson -Value $current.observation.effect_owners)) '[mir4-a05-k2-03-owner-parity]'
Assert-A05K203 ((ConvertTo-MIR4BootstrapCanonicalJson -Value $locked.observation.routes) -ceq (ConvertTo-MIR4BootstrapCanonicalJson -Value $current.observation.routes)) '[mir4-a05-k2-03-route-parity]'

$a03ProofRelative = 'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-execution-proof.json'
$a03Proof = Get-Content -Raw -LiteralPath (Resolve-A05K203Path $a03ProofRelative $true) | ConvertFrom-Json -Depth 100 -DateKind String
Assert-A05K203 (Test-MIR4BootstrapRecordHash $a03Proof) '[mir4-a05-k2-03-a03-proof]'
$candidate = $a03Proof.candidate
Assert-A05K203 ($candidate.archive_sha256 -eq $runtime.candidate.archive_sha256 -and $candidate.source_commit -eq 'aed35814232d1ebf629f980ac98869c3e8336903' -and $candidate.source_tree -eq 'd68c32d425ae544f73f5762925c3ce429ef6cd3c') '[mir4-a05-k2-03-candidate-lineage]'

$currentLockRelative = 'build/mir4/a05-k2-materials/current-k2so-resolution/compat-candidates.lock.json'
$currentLock = Get-Content -Raw -LiteralPath (Resolve-A05K203Path $currentLockRelative $true) | ConvertFrom-Json -Depth 100 -DateKind String
$expectedResolution = @(
  'flib|0.17.2|flib_0.17.2.zip|6c7cedeefbdce89348d1e979a24e5706fd5a4311',
  'k2so-assets|1.0.7|k2so-assets_1.0.7.zip|94df2729880ed27df14918fd28ed37f448778d14',
  'Krastorio2|2.1.2|Krastorio2_2.1.2.zip|6ed03661f3887fc39d8615f9063116d41d53c427',
  'Krastorio2-spaced-out|2.0.17|Krastorio2-spaced-out_2.0.17.zip|1fed6f807ba7fec55ffd5a557efee8777510f2d2',
  'Krastorio2Assets|2.1.0|Krastorio2Assets_2.1.0.zip|754e187664fd45a4bcfce016366f0029f093a249',
  'Krastorio2MenuSimulations|2.1.0|Krastorio2MenuSimulations_2.1.0.zip|ead8df6d63241e8cb6f0f0def3894d5efa1de3b2'
)
$actualResolution = @($currentLock.mods | ForEach-Object { "$($_.name)|$($_.version)|$($_.file_name)|$($_.sha1)" })
Assert-A05K203 ($currentLock.schema -eq 1 -and $currentLock.factorio_line -eq '2.1' -and [int]$currentLock.count -eq 1 -and (@($currentLock.candidates_selected) -join '|') -ceq 'Krastorio2-spaced-out' -and (@($actualResolution) -join ';') -ceq (@($expectedResolution) -join ';')) '[mir4-a05-k2-03-current-resolution-lock]'

$proof = [pscustomobject][ordered]@{
  schema=1
  kind='MIR4A05K203ImersiteRuntimeProofV1'
  recorded_at=[string]$runtime.generated_at
  task='A05/K2-03'
  status='passed-bounded'
  source_evidence=[pscustomobject][ordered]@{runtime_result=Get-A05K203Artifact $runtimeRelative;current_resolution_lock=Get-A05K203Artifact $currentLockRelative;runtime_test=$runtime.test;fixture=@($runtime.fixture)}
  engine=[pscustomobject][ordered]@{line='2.1';version='2.1.17';executable_sha256=[string]$runtime.engine.executable_sha256}
  candidate=$candidate
  cases=[pscustomobject][ordered]@{locked_2_0_13=$locked;current_2_0_17_fresh_load_only=$current}
  version_parity=[pscustomobject][ordered]@{owner_effects=$true;route_matrix=$true}
  non_claims=@('Current K2SO 2.0.17 is a fresh-load owner-and-route-parity observation without xy enhancement, reload, or continuity qualification.','This proof does not establish infinite continuation, broader K2 or A05 completion, player mutation, public support, release, signing, or publication authority.')
  record_sha256=''
}
$proofRelative = 'spec/programmes/evidence/synthesis-2026-09-10/a05-k2-materials/k2-03/MIR4-A05-K2-03-Imersite-Runtime-ProofV1.json'
$proofBinding = Write-A05K203Immutable $proof $proofRelative 'spec/schemas/mir4-a05-k2-03-imersite-runtime-proof-v1.schema.json'

$packageManifestRelative = 'src/mod/families/modern/prototypes/mir/streams/generated_stream_manifest.json'
$rootManifestRelative = 'prototypes/mir/streams/generated_stream_manifest.json'
$packageManifest = Get-Content -Raw -LiteralPath (Resolve-A05K203Path $packageManifestRelative $true) | ConvertFrom-Json -Depth 30
$rootManifest = Get-Content -Raw -LiteralPath (Resolve-A05K203Path $rootManifestRelative $true) | ConvertFrom-Json -Depth 30
Assert-A05K203 (@($packageManifest.streams.PSObject.Properties).Count -eq 98 -and @($rootManifest.streams.PSObject.Properties).Count -eq 76) '[mir4-a05-k2-03-projection-gap]'
$lineage = [pscustomobject][ordered]@{
  a03_lock=Get-A05K203RawBinding 'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-current.lock.json'
  a03_execution_proof=Get-A05K203RecordBinding $a03ProofRelative
  a03_dossier=Get-A05K203RecordBinding 'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-intake-dossier.json'
  a03_receipt=Get-A05K203RecordBinding 'spec/programmes/evidence/synthesis-2026-09-10/a03-k2-k2so-f210-intake-receipt.json'
}
$sourcePaths = @(
  'src/mod/families/modern/prototypes/streams/productivity.lua',
  $packageManifestRelative,
  'spec/programmes/community-requests.json',
  'tests/runtime/Test-MIR4A05K203Imersite.ps1',
  'fixtures/assert-k2-03-imersite/info.json',
  'fixtures/assert-k2-03-imersite/data-final-fixes.lua',
  'fixtures/assert-k2-03-imersite/control.lua'
)
$closure = [pscustomobject][ordered]@{
  schema=1
  kind='MIR4A05K203ImersiteClosureV1'
  recorded_at=[string]$runtime.generated_at
  task='A05'
  request='K2-03'
  status='bounded-slice-passed'
  runtime_proof=$proofBinding
  candidate=$candidate
  engine=$proof.engine
  source_authorities=@($sourcePaths | ForEach-Object { Get-A05K203Source $_ })
  lineage=$lineage
  route_admission=[pscustomobject][ordered]@{material='Imersite';stream='research_material_imersite';technology='recipe-prod-research_material_imersite-1';effect_per_tier=0.02;eligible_routes=2;native_owner='kr-imersite-productivity';native_recipe='kr-imersite-crystal';mir_owner='recipe-prod-research_material_imersite-1';mir_recipe='kr-imersite-powder';effective_owner_count=2;route_counts=$locked.observation.route_counts;withheld_return_route='potential-return-path:kr-imersite-powder';weighted_process_qualification='not-proven'}
  progression=[pscustomobject][ordered]@{finite_tiers=3;science=@($locked.observation.science.mir);compatible_labs=@($locked.observation.science.compatible_labs);locked_save_continuity='two-byte-identical-reloads-at-0.42';infinite_continuation='not-proven'}
  current_qualification=[pscustomobject][ordered]@{k2so_version='2.0.17';archive_sha256='0D48E22858FB4D1259413B65FFA7E5A0C5B5C2439A4918D58BDACC9411FA9284';scope='fresh-load-owner-and-route-parity-only';xy_enhancement='not-included';reload_continuity='not-proven'}
  projection_gap=[pscustomobject][ordered]@{status='unresolved-pre-release';blocks_release=$true;package_source=[pscustomobject][ordered]@{path=$packageManifestRelative;rows=98;raw_sha256=Get-MIR4Sha256File -Path (Resolve-A05K203Path $packageManifestRelative $true)};root_projection=[pscustomobject][ordered]@{path=$rootManifestRelative;rows=76;raw_sha256=Get-MIR4Sha256File -Path (Resolve-A05K203Path $rootManifestRelative $true)};mir_projection_authority=Get-A05K203RawBinding '.mir/streams.yml';required_disposition='regenerate-whole-projection-or-authoritatively-reconcile-before-candidate'}
  remaining_obligations=@('Qualify or explicitly withhold weighted and other advanced Imersite processes.','Design and prove meaningful infinite continuation or retain an explicit finite-only cap explanation.','Qualify current K2SO 2.0.17 with the selected enhancement closure and preserved-save reloads before broad support.','Complete K2-02 and K2-04 through K2-07 before marking A05 complete.','Resolve the 98-row package-source versus 76-row root/static stream projection gap before release-candidate qualification.')
  authority_flags=[pscustomobject][ordered]@{a05_complete=$false;broad_k2_support=$false;player_mutation_authorized=$false;prototype_write_authorized=$false;public_support_authorized=$false;release_authority=$false;signing_authority=$false;publication_authority=$false}
  non_claims=@('No current K2SO 2.0.17 xy-enhancement, reload, or continuity qualification.','No infinite Imersite continuation qualification.','No weighted-process admission.','No broader K2 support or A05 completion.','No player mutation or generated-prototype write authority.','No public support, release, signing, or publication authority.')
  record_sha256=''
}
$closureRelative = 'spec/programmes/evidence/synthesis-2026-09-10/a05-k2-materials/k2-03/MIR4-A05-K2-03-Imersite-ClosureV1.json'
$closureBinding = Write-A05K203Immutable $closure $closureRelative 'spec/schemas/mir4-a05-k2-03-imersite-closure-v1.schema.json'
$a04ClosureRelative = 'spec/programmes/evidence/synthesis-2026-09-10/a04-k2-science/MIR4-A04-K2-Science-ClosureV1.json'
$a04ClosureBinding = Get-A05K203RecordBinding $a04ClosureRelative
$a04Closure = Get-Content -Raw -LiteralPath (Resolve-A05K203Path $a04ClosureRelative $true) | ConvertFrom-Json -Depth 100 -DateKind String
$historicalInventory = $a04Closure.compatibility_audit_evolution.command_inventory
Assert-A05K203 ($historicalInventory.path -eq 'governance/automation/mir4-command-inventory-v1.json' -and $historicalInventory.raw_sha256 -eq '4303B2485E5193ED711CA0863E12B3A89E1650DD94476FE7DC74DDEAC027C017' -and $historicalInventory.canonical_sha256 -eq '4303B2485E5193ED711CA0863E12B3A89E1650DD94476FE7DC74DDEAC027C017' -and $historicalInventory.digest -eq 'sha256:b273fa46baacabae62bcb78f96b48fcb468dea3c770d7cf91058f1c881ec2014' -and [int]$historicalInventory.command_count -eq 85) '[mir4-a05-k2-03-a04-inventory]'

$inventoryRelative = 'governance/automation/mir4-command-inventory-v1.json'
$inventoryPath = Resolve-A05K203Path $inventoryRelative $true
Update-MIR4CommandInventoryV1 -RepoRoot $RepoRoot -Check | Out-Null
$inventory = Get-Content -Raw -LiteralPath $inventoryPath | ConvertFrom-Json -Depth 100 -DateKind String
$added = @($inventory.implementation_files | Where-Object path -CEQ 'tools/commands/mir4/Write-MIR4A05K203ImersiteClosure.ps1')
Assert-A05K203 ($inventory.command_count -eq 85 -and $inventory.summary.canonical_public -eq 1 -and $inventory.summary.canonical_internal -eq 379 -and $inventory.summary.compatibility_wrapper -eq 168 -and $inventory.summary.migration_only -eq 48 -and $inventory.summary.historical -eq 16 -and $inventory.summary.obsolete -eq 0 -and $inventory.summary.unknown -eq 0 -and $inventory.summary.duplicate_command_keys -eq 0 -and $added.Count -eq 1 -and $added[0].classification -eq 'canonical-internal' -and -not $added[0].package_visible) '[mir4-a05-k2-03-current-inventory]'

$predecessor = [ordered]@{
  schema=[int]$inventory.schema
  kind=[string]$inventory.kind
  state=[string]$inventory.state
  public_entrypoint=[string]$inventory.public_entrypoint
  router=[string]$inventory.router
  command_count=[int]$inventory.command_count
  commands=@($inventory.commands)
  implementation_files=@($inventory.implementation_files | Where-Object path -CNE 'tools/commands/mir4/Write-MIR4A05K203ImersiteClosure.ps1')
  summary=[ordered]@{canonical_public=1;canonical_internal=378;compatibility_wrapper=168;migration_only=48;historical=16;obsolete=0;unknown=0;duplicate_command_keys=0}
  transition_gate=[ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false}
  digest=''
}
$digestMaterial = [ordered]@{}
foreach($property in $predecessor.GetEnumerator()){if([string]$property.Key -cne 'digest'){$digestMaterial[$property.Key]=$property.Value}}
$predecessor.digest = Get-MIR4CommandInventoryDigestV1 -Value $digestMaterial
$predecessorText = (($predecessor | ConvertTo-Json -Depth 100) + [string][char]10).Replace(([string][char]13+[char]10),[string][char]10).Replace([string][char]13,[string][char]10)
$predecessorScratch = Join-Path $RepoRoot 'build/a05-k2-03-closure-patch/reconstructed-a04-command-inventory.json'
[IO.File]::WriteAllText($predecessorScratch,$predecessorText,[Text.UTF8Encoding]::new($false))
$reconstructedSha = Get-MIR4Sha256File -Path $predecessorScratch
Assert-A05K203 ($predecessor.digest -eq $historicalInventory.digest -and $reconstructedSha -eq $historicalInventory.raw_sha256) '[mir4-a05-k2-03-inventory-predecessor-reconstruction]'

$inventoryEvolution = [pscustomobject][ordered]@{
  schema=1
  kind='MIR4A05K203CommandInventoryEvolutionV1'
  recorded_at=[string]$runtime.generated_at
  task='A05/K2-03'
  status='append-only-successor-passed'
  predecessor=[pscustomobject][ordered]@{a04_closure=$a04ClosureBinding;inventory=[pscustomobject][ordered]@{path=$inventoryRelative;raw_sha256=[string]$historicalInventory.raw_sha256;canonical_sha256=[string]$historicalInventory.canonical_sha256;digest=[string]$historicalInventory.digest;command_count=85;canonical_internal_count=378}}
  current=[pscustomobject][ordered]@{path=$inventoryRelative;raw_sha256=(Get-MIR4Sha256File -Path $inventoryPath);canonical_sha256=(Get-MIR4BootstrapTextSha256 -Path $inventoryPath);digest=[string]$inventory.digest;command_count=85;canonical_internal_count=379}
  transition=[pscustomobject][ordered]@{classification='append-only-one-canonical-internal-writer';added_implementation_files=$added;reconstructed_predecessor_sha256=$reconstructedSha;public_command_count_unchanged=$true;non_added_summary_counts_unchanged=$true;transition_gates_remain_closed=$true}
  authority_flags=[pscustomobject][ordered]@{public_command_authority=$false;player_mutation_authorized=$false;release_authority=$false;signing_authority=$false;publication_authority=$false}
  record_sha256=''
}
$inventoryEvolutionRelative = 'spec/programmes/evidence/synthesis-2026-09-10/a05-k2-materials/k2-03/MIR4-A05-K2-03-Command-Inventory-EvolutionV1.json'
$inventoryEvolutionBinding = Write-A05K203Immutable $inventoryEvolution $inventoryEvolutionRelative 'spec/schemas/mir4-a05-k2-03-command-inventory-evolution-v1.schema.json'
[pscustomobject][ordered]@{status='passed';runtime_proof=$proofBinding;closure=$closureBinding;command_inventory_evolution=$inventoryEvolutionBinding;projection_gap=$closure.projection_gap} | ConvertTo-Json -Depth 20