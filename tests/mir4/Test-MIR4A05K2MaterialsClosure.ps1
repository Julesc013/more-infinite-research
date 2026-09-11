# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot='',[switch]$RequireLocalEvidence)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if(-not $RepoRoot){$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path}
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/tooling/CommandInventory.ps1')
function Assert-A05K2ClosureTest { param([bool]$Condition,[string]$Code) if(-not $Condition){throw $Code} }
function Assert-A05K2ClosureTestRelative { param([string]$Relative)
  Assert-A05K2ClosureTest ($Relative -cmatch '^[A-Za-z0-9._/-]+$' -and $Relative -notmatch '(^|/)\.\.(/|$)') "[mir4-a05-k2-materials-test-relative] $Relative"
}
function Resolve-A05K2ClosureTestPath { param([string]$Relative)
  Assert-A05K2ClosureTestRelative $Relative
  $path=[IO.Path]::GetFullPath((Join-Path $RepoRoot $Relative));$prefix=$RepoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
  Assert-A05K2ClosureTest ($path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $path -PathType Leaf)) "[mir4-a05-k2-materials-test-path] $Relative";$path
}
function Get-A05K2ClosureTestGitBlob {
  param([Parameter(Mandatory)][string]$Commit,[Parameter(Mandatory)][string]$Relative,[Parameter(Mandatory)][string]$Code)
  Assert-A05K2ClosureTestRelative $Relative
  Assert-A05K2ClosureTest ($Commit -cmatch '^[a-f0-9]{40}$') "$Code-commit"
  $objectRows=@(& git -C $RepoRoot rev-parse "${Commit}:$Relative" 2>$null)
  $objectExit=$LASTEXITCODE
  $objectRows=@($objectRows|ForEach-Object{([string]$_).Trim()}|Where-Object{$_})
  Assert-A05K2ClosureTest ($objectExit-eq0 -and $objectRows.Count-eq1 -and $objectRows[0]-cmatch'^[a-f0-9]{40}$') "$Code-object"
  $git=@(Get-Command git -CommandType Application -ErrorAction Stop|Where-Object{Test-Path -LiteralPath $_.Source -PathType Leaf}|Select-Object -First 1)
  Assert-A05K2ClosureTest ($git.Count-eq1) "$Code-git"
  $start=[Diagnostics.ProcessStartInfo]::new([string]$git[0].Source)
  $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  foreach($argument in @('-C',$RepoRoot,'cat-file','blob',$objectRows[0])){[void]$start.ArgumentList.Add($argument)}
  $process=[Diagnostics.Process]::new();$process.StartInfo=$start;$memory=[IO.MemoryStream]::new()
  try {[void]$process.Start();$process.StandardOutput.BaseStream.CopyTo($memory);$errorText=$process.StandardError.ReadToEnd();$process.WaitForExit();$exitCode=$process.ExitCode} finally {$process.Dispose()}
  Assert-A05K2ClosureTest ($exitCode-eq0) "$Code-cat-file"
  $bytes=$memory.ToArray();$memory.Dispose()
  Assert-A05K2ClosureTest ((Get-MIR4GitObjectSha1 -Type blob -Bytes $bytes)-ceq$objectRows[0]) "$Code-blob"
  return [pscustomobject][ordered]@{commit=$Commit;path=$Relative;object_id=$objectRows[0];bytes=$bytes}
}
function Get-A05K2ClosureTestSnapshotText { param($Blob,[string]$Code)
  try { return [Text.UTF8Encoding]::new($false,$true).GetString([byte[]]$Blob.bytes) } catch { Assert-A05K2ClosureTest $false "$Code-utf8" }
}
function Get-A05K2ClosureTestSnapshotCanonicalSha256 { param($Blob,[string]$Code)
  $snapshotText=Get-A05K2ClosureTestSnapshotText $Blob $Code
  return Get-MIR4Sha256String -Value $snapshotText.Replace("`r`n","`n").Replace("`r","`n")
}
function Get-A05K2ClosureTestSnapshotWindowsWorktreeSha256 { param($Blob,[string]$Code)
  $snapshotText=(Get-A05K2ClosureTestSnapshotText $Blob $Code).Replace("`r`n","`n").Replace("`r","`n").Replace("`n","`r`n")
  return Get-MIR4Sha256Bytes -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($snapshotText))
}
function Get-A05K2ClosureTestSnapshotCrlfSha256 { param($Blob,[string]$Code)
  return Get-A05K2ClosureTestSnapshotWindowsWorktreeSha256 $Blob $Code
}
function Get-A05K2ClosureTestSnapshotIntroducer { param([string]$Relative)
  Assert-A05K2ClosureTestRelative $Relative
  $rows=@(& git -C $RepoRoot log --format=%H --diff-filter=A -- $Relative 2>$null)
  $exitCode=$LASTEXITCODE;$rows=@($rows|ForEach-Object{([string]$_).Trim()}|Where-Object{$_})
  Assert-A05K2ClosureTest ($exitCode-eq0 -and $rows.Count-eq1 -and $rows[0]-cmatch'^[a-f0-9]{40}$') '[mir4-a05-k2-materials-test-snapshot-introducer]'
  $headRows=@(& git -C $RepoRoot rev-parse 'HEAD^{commit}' 2>$null);$headExit=$LASTEXITCODE;$headRows=@($headRows|ForEach-Object{([string]$_).Trim()}|Where-Object{$_})
  Assert-A05K2ClosureTest ($headExit-eq0 -and $headRows.Count-eq1 -and $headRows[0]-cmatch'^[a-f0-9]{40}$') '[mir4-a05-k2-materials-test-snapshot-head]'
  & git -C $RepoRoot merge-base --is-ancestor $rows[0] $headRows[0] 2>$null
  $ancestorExit=$LASTEXITCODE
  Assert-A05K2ClosureTest ($ancestorExit-eq0) '[mir4-a05-k2-materials-test-snapshot-ancestor]'
  return $rows[0]
}
function Assert-A05K2ClosureTestArtifact { param($Artifact,[string]$Code)
  Assert-A05K2ClosureTest ($null-ne$Artifact -and [string]$Artifact.path -cmatch '^[A-Za-z0-9._/-]+$' -and [long]$Artifact.bytes-ge0 -and [string]$Artifact.raw_sha256 -cmatch '^[A-F0-9]{64}$') $Code
  if($RequireLocalEvidence){$path=Resolve-A05K2ClosureTestPath ([string]$Artifact.path);Assert-A05K2ClosureTest ((Get-MIR4Sha256File -Path $path)-ceq[string]$Artifact.raw_sha256 -and [long](Get-Item -LiteralPath $path).Length-eq[long]$Artifact.bytes) "$Code-local"}
}
function Assert-A05K2ClosureTestArray { param($Actual,[string[]]$Expected,[string]$Code) Assert-A05K2ClosureTest ((@($Actual|ForEach-Object{[string]$_})-join'|')-ceq($Expected-join'|')) $Code }
function Get-A05K2ClosureTestTextSha256 { param([string]$Text)
  $algorithm=[Security.Cryptography.SHA256]::Create()
  try { -join ($algorithm.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text))|ForEach-Object{$_.ToString('X2')}) } finally { $algorithm.Dispose() }
}
$closureRelative='spec/programmes/evidence/synthesis-2026-09-10/a05-k2-materials/k2-materials/MIR4-A05-K2-Materials-ClosureV1.json'
$schemaRelative='spec/schemas/mir4-a05-k2-materials-closure-v1.schema.json'
$closurePath=Resolve-A05K2ClosureTestPath $closureRelative
$snapshotCommit=Get-A05K2ClosureTestSnapshotIntroducer $closureRelative
$snapshotClosureBlob=Get-A05K2ClosureTestGitBlob -Commit $snapshotCommit -Relative $closureRelative -Code '[mir4-a05-k2-materials-test-snapshot-closure]'
$unsafeSnapshotPathRejected=$false
try {[void](Get-A05K2ClosureTestGitBlob -Commit $snapshotCommit -Relative '../unsafe' -Code '[mir4-a05-k2-materials-test-snapshot-negative]')}catch{$unsafeSnapshotPathRejected=$true}
Assert-A05K2ClosureTest $unsafeSnapshotPathRejected '[mir4-a05-k2-materials-test-snapshot-path-negative]'
Assert-A05K2ClosureTest ((Get-MIR4Sha256Bytes -Bytes ([byte[]]$snapshotClosureBlob.bytes))-ceq(Get-MIR4Sha256File -Path $closurePath)) '[mir4-a05-k2-materials-test-snapshot-identity]'
$text=Get-A05K2ClosureTestSnapshotText $snapshotClosureBlob '[mir4-a05-k2-materials-test-snapshot-closure]'
$schemaSnapshot=Get-A05K2ClosureTestSnapshotText (Get-A05K2ClosureTestGitBlob -Commit $snapshotCommit -Relative $schemaRelative -Code '[mir4-a05-k2-materials-test-snapshot-schema]') '[mir4-a05-k2-materials-test-snapshot-schema]'
Assert-A05K2ClosureTest ($text|Test-Json -Schema $schemaSnapshot) '[mir4-a05-k2-materials-test-schema]'
Assert-A05K2ClosureTest ($text-notmatch '(?i)(?:[A-Z]:[\\/]|\\\\)') '[mir4-a05-k2-materials-test-private-record]'
$closure=$text|ConvertFrom-Json -Depth 100 -DateKind String
Assert-A05K2ClosureTest (Test-MIR4BootstrapRecordHash $closure) '[mir4-a05-k2-materials-test-self-hash]'
Assert-A05K2ClosureTest ($closure.kind-eq'MIR4A05K2MaterialsClosureV1' -and $closure.status-eq'bounded-claims-passed' -and $closure.recorded_at-eq'2026-09-10T21:48:47.0654939Z') '[mir4-a05-k2-materials-test-identity]'
Assert-A05K2ClosureTestArray $closure.requests @('K2-02','K2-04','K2-05','K2-06','K2-07') '[mir4-a05-k2-materials-test-requests]'
Assert-A05K2ClosureTestArtifact $closure.runtime_result '[mir4-a05-k2-materials-test-runtime]'
Assert-A05K2ClosureTestArtifact $closure.candidate '[mir4-a05-k2-materials-test-candidate]'
Assert-A05K2ClosureTest ($closure.candidate.raw_sha256-eq'A6D5D264BE0153310BBE1E61ACDAAFE6407AA4D654B13B5251E680A0D3CADDF8' -and $closure.engine.version-eq'2.1.17' -and $closure.engine.executable_sha256-eq'710B0278D3049564B122DAFB3CD3D0338D0BDE1CEC3B7417AE1FC3FB37AB85A8') '[mir4-a05-k2-materials-test-engine-candidate]'
$expectedSources=@('src/mod/families/modern/prototypes/mir/capabilities/recipe_productivity/recipe_matching.lua','src/mod/families/modern/prototypes/mir/index/recipe_facts.lua','src/mod/families/modern/prototypes/mir/index/recipe_risk_facts.lua','src/mod/families/modern/prototypes/mir/index/relationships.lua','src/mod/families/modern/prototypes/mir/index/item_prototype_facts.lua','src/mod/families/modern/prototypes/mir/platform/factorio/prototype_lookup.lua','src/mod/families/modern/prototypes/mir/core/fingerprint.lua','src/mod/common/prototypes/mir/core/deepcopy.lua','src/mod/common/prototypes/mir/domain/facts/recipe_semantics.lua','src/mod/common/prototypes/mir/platform/factorio/data_raw.lua','src/mod/families/modern/prototypes/mir/report/compiler_telemetry.lua','src/mod/families/modern/prototypes/mir/pipeline/compiler_context.lua','src/mod/common/prototypes/mir/settings/automatic_compiler_policy.lua','targets/f210/files/prototypes/mir/platform/factorio/target_profiles.lua','.mir/targets.json','tools/commands/targets/Sync-MIRTargetProfiles.ps1','src/mod/families/modern/prototypes/mir/streams/generated_stream_manifest.json','prototypes/mir/streams/generated_stream_manifest.json','.mir/streams.yml','src/mod/families/modern/prototypes/streams/productivity.lua','tools/mir/application/package/TargetMaterializer.ps1','src/mod/package-source.json','targets/f210/overlay.json','targets/f200/overlay.json','targets/package-authority.json','tests/compiler/material_routes.lua','tests/runtime/Test-MIR4A05K2Materials.ps1','tests/mir4/Test-MIR4A05K2MaterialsClosure.ps1','fixtures/assert-k2-materials/info.json','fixtures/assert-k2-materials/data-final-fixes.lua','fixtures/assert-k2-materials/control.lua','tools/commands/mir4/Write-MIR4A05K2MaterialsClosure.ps1','tools/mir/application/tooling/CommandInventory.ps1','governance/automation/mir4-command-inventory-v1.json','spec/programmes/mir4-4x-operating-programme-v1.json','spec/programmes/community-requests.json','spec/schemas/mir4-a05-k2-materials-closure-v1.schema.json','spec/schemas/mir4-a05-k2-materials-command-inventory-evolution-v1.schema.json','.mir/assurance.json','.mir/fixtures.yml','.mir/modules.yml','.mir/control/paths.yml','validation/tests.yml')
$expectedSources+=@('src/mod/families/modern/prototypes/mir/pipeline/recipe_productivity_permissions.lua','src/mod/families/modern/prototypes/mir/index/productivity_owners.lua','src/mod/families/modern/prototypes/mir/policy/competing_productivity.lua')
Assert-A05K2ClosureTestArray @($closure.source_authorities|ForEach-Object path) $expectedSources '[mir4-a05-k2-materials-test-source-order]'
foreach($source in @($closure.source_authorities)){
  $sourceBlob=Get-A05K2ClosureTestGitBlob -Commit $snapshotCommit -Relative ([string]$source.path) -Code "[mir4-a05-k2-materials-test-source] $($source.path)"
  Assert-A05K2ClosureTest ((Get-A05K2ClosureTestSnapshotCanonicalSha256 $sourceBlob "[mir4-a05-k2-materials-test-source] $($source.path)")-ceq[string]$source.canonical_sha256) "[mir4-a05-k2-materials-test-source] $($source.path)"
}
$packageManifestRelative='src/mod/families/modern/prototypes/mir/streams/generated_stream_manifest.json';$rootManifestRelative='prototypes/mir/streams/generated_stream_manifest.json'
$packageManifestBlob=Get-A05K2ClosureTestGitBlob -Commit $snapshotCommit -Relative $packageManifestRelative -Code '[mir4-a05-k2-materials-test-package-manifest]'
$rootManifestBlob=Get-A05K2ClosureTestGitBlob -Commit $snapshotCommit -Relative $rootManifestRelative -Code '[mir4-a05-k2-materials-test-root-manifest]'
$mirProjectionBlob=Get-A05K2ClosureTestGitBlob -Commit $snapshotCommit -Relative '.mir/streams.yml' -Code '[mir4-a05-k2-materials-test-mir-projection]'
$packageManifest=Get-A05K2ClosureTestSnapshotText $packageManifestBlob '[mir4-a05-k2-materials-test-package-manifest]'|ConvertFrom-Json -Depth 30
$rootManifest=Get-A05K2ClosureTestSnapshotText $rootManifestBlob '[mir4-a05-k2-materials-test-root-manifest]'|ConvertFrom-Json -Depth 30
$rootManifestSource=@($closure.source_authorities|Where-Object{[string]$_.path-ceq$rootManifestRelative})
Assert-A05K2ClosureTest ($rootManifestSource.Count-eq1 -and (Get-MIR4Sha256Bytes -Bytes ([byte[]]$rootManifestBlob.bytes))-ceq[string]$rootManifestSource[0].canonical_sha256) '[mir4-a05-k2-materials-test-root-manifest-exact-blob]'
foreach($technology in @('recipe-prod-research_material_rare_metals-1','recipe-prod-research_material_silicon-1','recipe-prod-research_material_glass-1')){$row=@($packageManifest.streams.PSObject.Properties|Where-Object{[string]$_.Value.generated_technology-ceq$technology});$rootRow=@($rootManifest.streams.PSObject.Properties|Where-Object{[string]$_.Value.generated_technology-ceq$technology});Assert-A05K2ClosureTest ($row.Count-eq1 -and [string]$row[0].Value.policy-ceq'exact-reviewed-forward-material-manufacturing' -and $rootRow.Count-eq0) "[mir4-a05-k2-materials-test-reviewed-forward-manifest] $technology"}
Assert-A05K2ClosureTest ($closure.qualification_boundary.graph_guard-eq'potential-return-paths-withheld-unless-exact-profile-locked-reviewed-forward-certificate-proves-bounded-ordinary-route' -and $closure.qualification_boundary.reviewed_forward_certificate-eq'exact-final-recipe-facts-risk-fingerprint-and-complete-mod-profile-locked' -and $closure.qualification_boundary.current_k2so_material_qualification-eq'bounded-rare-metals-silicon-glass-fresh-and-two-reload-evidence' -and $closure.qualification_boundary.broader_k2so_support-eq'not-proven' -and $closure.qualification_boundary.angel_or_combined_a06_support-eq'not-proven') '[mir4-a05-k2-materials-test-qualification-boundary]'
Assert-A05K2ClosureTest ($closure.projection_gap.status-eq'unresolved-pre-release' -and $closure.projection_gap.blocks_release -and $closure.projection_gap.package_source.path-eq$packageManifestRelative -and [int]$closure.projection_gap.package_source.rows-eq98 -and $closure.projection_gap.package_source.raw_sha256-eq(Get-MIR4Sha256Bytes -Bytes ([byte[]]$packageManifestBlob.bytes)) -and $closure.projection_gap.root_projection.path-eq$rootManifestRelative -and [int]$closure.projection_gap.root_projection.rows-eq76 -and $closure.projection_gap.root_projection.raw_sha256-eq(Get-A05K2ClosureTestSnapshotCrlfSha256 $rootManifestBlob '[mir4-a05-k2-materials-test-root-manifest]') -and $closure.projection_gap.mir_projection_authority.path-eq'.mir/streams.yml' -and $closure.projection_gap.mir_projection_authority.canonical_sha256-eq(Get-A05K2ClosureTestSnapshotCanonicalSha256 $mirProjectionBlob '[mir4-a05-k2-materials-test-mir-projection]') -and $closure.projection_gap.required_disposition-eq'regenerate-whole-projection-or-authoritatively-reconcile-before-release-candidate') '[mir4-a05-k2-materials-test-projection-gap]'
$evolutionRelative='spec/programmes/evidence/synthesis-2026-09-10/a05-k2-materials/k2-materials/MIR4-A05-K2-Materials-Command-Inventory-EvolutionV1.json'
$rootManifestExactBlobSha256=Get-MIR4Sha256Bytes -Bytes ([byte[]]$rootManifestBlob.bytes)
Assert-A05K2ClosureTest ($closure.projection_gap.root_projection.raw_sha256-cne$rootManifestExactBlobSha256 -and $rootManifestSource[0].canonical_sha256-ceq$rootManifestExactBlobSha256) '[mir4-a05-k2-materials-test-root-manifest-worktree-versus-blob]'
$evolutionSchemaRelative='spec/schemas/mir4-a05-k2-materials-command-inventory-evolution-v1.schema.json'
$evolutionBlob=Get-A05K2ClosureTestGitBlob -Commit $snapshotCommit -Relative $evolutionRelative -Code '[mir4-a05-k2-materials-test-evolution]'
$evolutionText=Get-A05K2ClosureTestSnapshotText $evolutionBlob '[mir4-a05-k2-materials-test-evolution]'
$evolutionSchemaText=Get-A05K2ClosureTestSnapshotText (Get-A05K2ClosureTestGitBlob -Commit $snapshotCommit -Relative $evolutionSchemaRelative -Code '[mir4-a05-k2-materials-test-evolution-schema]') '[mir4-a05-k2-materials-test-evolution-schema]'
Assert-A05K2ClosureTest ($evolutionText|Test-Json -Schema $evolutionSchemaText) '[mir4-a05-k2-materials-test-evolution-schema]'
Assert-A05K2ClosureTest ($evolutionText-notmatch '(?i)(?:[A-Z]:[\\/]|\\\\)') '[mir4-a05-k2-materials-test-evolution-private]'
$evolution=$evolutionText|ConvertFrom-Json -Depth 100 -DateKind String
Assert-A05K2ClosureTest (Test-MIR4BootstrapRecordHash $evolution) '[mir4-a05-k2-materials-test-evolution-self-hash]'
Assert-A05K2ClosureTest ($closure.command_inventory_evolution.path-eq$evolutionRelative -and $closure.command_inventory_evolution.raw_sha256-eq(Get-MIR4Sha256Bytes -Bytes ([byte[]]$evolutionBlob.bytes)) -and $closure.command_inventory_evolution.record_sha256-eq$evolution.record_sha256) '[mir4-a05-k2-materials-test-evolution-closure-binding]'
$previousEvolutionRelative='spec/programmes/evidence/synthesis-2026-09-10/a05-k2-materials/k2-03/MIR4-A05-K2-03-Command-Inventory-EvolutionV1.json'
$previousEvolutionBlob=Get-A05K2ClosureTestGitBlob -Commit $snapshotCommit -Relative $previousEvolutionRelative -Code '[mir4-a05-k2-materials-test-previous-evolution]'
$previousEvolutionText=Get-A05K2ClosureTestSnapshotText $previousEvolutionBlob '[mir4-a05-k2-materials-test-previous-evolution]'
$previousEvolutionSchemaText=Get-A05K2ClosureTestSnapshotText (Get-A05K2ClosureTestGitBlob -Commit $snapshotCommit -Relative 'spec/schemas/mir4-a05-k2-03-command-inventory-evolution-v1.schema.json' -Code '[mir4-a05-k2-materials-test-previous-evolution-schema]') '[mir4-a05-k2-materials-test-previous-evolution-schema]'
Assert-A05K2ClosureTest ($previousEvolutionText|Test-Json -Schema $previousEvolutionSchemaText) '[mir4-a05-k2-materials-test-previous-evolution-schema]'
$previousEvolution=$previousEvolutionText|ConvertFrom-Json -Depth 100 -DateKind String
Assert-A05K2ClosureTest (Test-MIR4BootstrapRecordHash $previousEvolution) '[mir4-a05-k2-materials-test-previous-evolution-self-hash]'
Assert-A05K2ClosureTest ($evolution.kind-eq'MIR4A05K2MaterialsCommandInventoryEvolutionV1' -and $evolution.task-eq'A05/K2-materials' -and $evolution.status-eq'append-only-successor-passed' -and $evolution.predecessor.k2_03_evolution.path-eq$previousEvolutionRelative -and $evolution.predecessor.k2_03_evolution.raw_sha256-eq(Get-MIR4Sha256Bytes -Bytes ([byte[]]$previousEvolutionBlob.bytes)) -and $evolution.predecessor.k2_03_evolution.record_sha256-eq$previousEvolution.record_sha256) '[mir4-a05-k2-materials-test-evolution-lineage]'
Assert-A05K2ClosureTest ($previousEvolution.current.raw_sha256-eq'45CE61E163C34A6BE41A02BDB7C2A375F05ED5E1B9E09DE5C36C6564A58B72BC' -and $previousEvolution.current.canonical_sha256-eq'45CE61E163C34A6BE41A02BDB7C2A375F05ED5E1B9E09DE5C36C6564A58B72BC' -and $previousEvolution.current.digest-eq'sha256:5074415336ac8c7b45dde4f8e851071352c33d7bfbf76679882cb891eddcfd9d' -and [int]$previousEvolution.current.command_count-eq85 -and [int]$previousEvolution.current.canonical_internal_count-eq379) '[mir4-a05-k2-materials-test-evolution-predecessor]'
Assert-A05K2ClosureTest ((ConvertTo-MIR4BootstrapCanonicalJson -Value $evolution.predecessor.inventory)-ceq(ConvertTo-MIR4BootstrapCanonicalJson -Value $previousEvolution.current)) '[mir4-a05-k2-materials-test-evolution-predecessor-binding]'
$inventoryRelative='governance/automation/mir4-command-inventory-v1.json'
$snapshotInventoryBlob=Get-A05K2ClosureTestGitBlob -Commit $snapshotCommit -Relative $inventoryRelative -Code '[mir4-a05-k2-materials-test-snapshot-inventory]'
$snapshotInventoryText=Get-A05K2ClosureTestSnapshotText $snapshotInventoryBlob '[mir4-a05-k2-materials-test-snapshot-inventory]'
$inventory=$snapshotInventoryText|ConvertFrom-Json -Depth 100 -DateKind String
$added=@($inventory.implementation_files|Where-Object path -CEQ 'tools/commands/mir4/Write-MIR4A05K2MaterialsClosure.ps1')
Assert-A05K2ClosureTest ($inventory.command_count-eq85 -and $inventory.summary.canonical_public-eq1 -and $inventory.summary.canonical_internal-eq380 -and $inventory.summary.compatibility_wrapper-eq168 -and $inventory.summary.migration_only-eq48 -and $inventory.summary.historical-eq16 -and $inventory.summary.obsolete-eq0 -and $inventory.summary.unknown-eq0 -and $inventory.summary.duplicate_command_keys-eq0 -and $added.Count-eq1 -and $added[0].classification-eq'canonical-internal' -and -not$added[0].package_visible) '[mir4-a05-k2-materials-test-evolution-current-inventory]'
Assert-A05K2ClosureTest ($evolution.current.path-eq$inventoryRelative -and $evolution.current.raw_sha256-eq(Get-MIR4Sha256Bytes -Bytes ([byte[]]$snapshotInventoryBlob.bytes)) -and $evolution.current.canonical_sha256-eq(Get-A05K2ClosureTestSnapshotCanonicalSha256 $snapshotInventoryBlob '[mir4-a05-k2-materials-test-snapshot-inventory]') -and $evolution.current.digest-eq$inventory.digest -and [int]$evolution.current.command_count-eq85 -and [int]$evolution.current.canonical_internal_count-eq380 -and $evolution.transition.added_implementation_files.Count-eq1 -and (ConvertTo-MIR4BootstrapCanonicalJson -Value $evolution.transition.added_implementation_files[0])-ceq(ConvertTo-MIR4BootstrapCanonicalJson -Value $added[0]) -and $evolution.transition.classification-eq'append-only-one-canonical-internal-writer' -and $evolution.transition.public_command_count_unchanged -and $evolution.transition.non_added_summary_counts_unchanged -and $evolution.transition.transition_gates_remain_closed -and @($evolution.authority_flags.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) '[mir4-a05-k2-materials-test-evolution-current-binding]'
$predecessor=[ordered]@{schema=[int]$inventory.schema;kind=[string]$inventory.kind;state=[string]$inventory.state;public_entrypoint=[string]$inventory.public_entrypoint;router=[string]$inventory.router;command_count=[int]$inventory.command_count;commands=@($inventory.commands);implementation_files=@($inventory.implementation_files|Where-Object path -CNE 'tools/commands/mir4/Write-MIR4A05K2MaterialsClosure.ps1');summary=[ordered]@{canonical_public=1;canonical_internal=379;compatibility_wrapper=168;migration_only=48;historical=16;obsolete=0;unknown=0;duplicate_command_keys=0};transition_gate=[ordered]@{version_allocation=$false;tagging=$false;signing=$false;sealing=$false;publication=$false};digest=''}
$digestMaterial=[ordered]@{}
foreach($property in $predecessor.GetEnumerator()){if([string]$property.Key-cne'digest'){$digestMaterial[$property.Key]=$property.Value}}
$predecessor.digest=Get-MIR4CommandInventoryDigestV1 -Value $digestMaterial
$predecessorText=(($predecessor|ConvertTo-Json -Depth 100)+[string][char]10).Replace(([string][char]13+[char]10),[string][char]10).Replace([string][char]13,[string][char]10)
$reconstructedSha=Get-A05K2ClosureTestTextSha256 $predecessorText
Assert-A05K2ClosureTest ($predecessor.digest-eq$previousEvolution.current.digest -and $reconstructedSha-eq$previousEvolution.current.raw_sha256 -and $evolution.transition.reconstructed_predecessor_sha256-eq$reconstructedSha) '[mir4-a05-k2-materials-test-evolution-reconstruction]'
Update-MIR4CommandInventoryV1 -RepoRoot $RepoRoot -Check|Out-Null
$liveInventoryPath=Resolve-A05K2ClosureTestPath $inventoryRelative
$liveInventory=Get-Content -Raw -LiteralPath $liveInventoryPath|ConvertFrom-Json -Depth 100 -DateKind String
$liveWriter=@($liveInventory.implementation_files|Where-Object path -CEQ 'tools/commands/mir4/Write-MIR4A05K2MaterialsClosure.ps1')
Assert-A05K2ClosureTest ([int]$liveInventory.command_count-ge[int]$inventory.command_count -and [int]$liveInventory.summary.canonical_internal-ge[int]$inventory.summary.canonical_internal -and [int]$liveInventory.summary.duplicate_command_keys-eq0 -and $liveWriter.Count-eq1 -and $liveWriter[0].classification-eq'canonical-internal' -and -not$liveWriter[0].package_visible) '[mir4-a05-k2-materials-test-live-inventory-successor]'
foreach($profile in @([pscustomobject]@{case=$closure.cases.locked_2_0_13;version='2.0.13';xy=$true},[pscustomobject]@{case=$closure.cases.current_2_0_17;version='2.0.17';xy=$false})){
  Assert-A05K2ClosureTest (@($liveInventory.transition_gate.PSObject.Properties|Where-Object{[bool]$_.Value}).Count-eq0) '[mir4-a05-k2-materials-test-live-transition-gates-closed]'
  $case=$profile.case;Assert-A05K2ClosureTest ($case.k2so_version-eq$profile.version -and [bool]$case.xy_enabled-eq[bool]$profile.xy) "[mir4-a05-k2-materials-test-profile] $($profile.version)"
  $names=@($case.mod_archives|ForEach-Object{Split-Path -Leaf ([string]$_.path)});$xy=@($names|Where-Object{$_-match'^xy-k2so-enhancements-nulls-fork_0[.]8[.]3[.]zip$'})
  Assert-A05K2ClosureTest (($profile.xy -and $xy.Count-eq1)-or((-not$profile.xy)-and$xy.Count-eq0)) "[mir4-a05-k2-materials-test-xy] $($profile.version)"
  foreach($artifact in @($case.fresh_load.save,$case.fresh_load.stdout,$case.fresh_load.stderr,$case.fresh_load.factorio_log,$case.fixture,$case.candidate,$case.mod_list,$case.mod_settings)+@($case.mod_archives)){Assert-A05K2ClosureTestArtifact $artifact "[mir4-a05-k2-materials-test-case-artifact] $($profile.version)"}
  Assert-A05K2ClosureTest ($case.candidate.raw_sha256-eq$closure.candidate.raw_sha256) "[mir4-a05-k2-materials-test-case-candidate] $($profile.version)"
  Assert-A05K2ClosureTest ($case.reloads.Count-eq2) "[mir4-a05-k2-materials-test-reload-count] $($profile.version)"
  foreach($reload in @($case.reloads|Sort-Object ordinal)){Assert-A05K2ClosureTest ($reload.input_save_sha256-eq$case.fresh_load.save.raw_sha256 -and $reload.save_sha256-eq$case.fresh_load.save.raw_sha256) "[mir4-a05-k2-materials-test-save-identity] $($profile.version)/$($reload.ordinal)";foreach($artifact in @($reload.stdout,$reload.stderr,$reload.factorio_log)){Assert-A05K2ClosureTestArtifact $artifact "[mir4-a05-k2-materials-test-reload-artifact] $($profile.version)/$($reload.ordinal)"}}
}
Assert-A05K2ClosureTestArray $closure.outcomes.K2_02.admitted_routes @('kr-rare-metals','kr-rare-metals-from-enriched-rare-metals') '[mir4-a05-k2-materials-test-rare-routes]'
Assert-A05K2ClosureTest ($closure.outcomes.K2_04.admitted_routes[0]-eq'kr-silicon' -and $closure.outcomes.K2_05.admitted_routes[0]-eq'kr-glass' -and $closure.outcomes.casting.reason-eq'final-dirty-water-ignored-by-productivity-5' -and $closure.outcomes.K2_06.reason-eq'final-productivity-permission-not-true-and-no-owner' -and $closure.outcomes.K2_07.reason-eq'final-productivity-permission-not-true-and-no-owner') '[mir4-a05-k2-materials-test-outcomes]'
$programme=Get-Content -Raw -LiteralPath (Resolve-A05K2ClosureTestPath 'spec/programmes/mir4-4x-operating-programme-v1.json')|ConvertFrom-Json -Depth 100
$a05=@($programme.synthesis.tasks|Where-Object id -eq 'A05');Assert-A05K2ClosureTest ($a05.Count-eq1 -and @($a05[0].evidence|Where-Object{[string]$_-ceq$closureRelative}).Count-eq1) '[mir4-a05-k2-materials-test-a05-evidence-retained]'
$requests=Get-Content -Raw -LiteralPath (Resolve-A05K2ClosureTestPath 'spec/programmes/community-requests.json')|ConvertFrom-Json -Depth 100
foreach($id in @('K2-02','K2-04','K2-05','K2-06','K2-07')){$request=@($requests.requests|Where-Object id -eq $id);Assert-A05K2ClosureTest ($request.Count-eq1 -and @($request[0].qualification|Where-Object{[string]$_.evidence-ceq$closureRelative}).Count-ge1) "[mir4-a05-k2-materials-test-ledger-evidence-retained] $id"}
$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile((Resolve-A05K2ClosureTestPath 'tools/commands/mir4/Write-MIR4A05K2MaterialsClosure.ps1'),[ref]$tokens,[ref]$errors)|Out-Null;Assert-A05K2ClosureTest ($errors.Count-eq0) '[mir4-a05-k2-materials-test-writer-parser]'
'[ok] MIR4 A05 K2 material closure is exact, bounded, immutable, and retained by its programme successors.'
