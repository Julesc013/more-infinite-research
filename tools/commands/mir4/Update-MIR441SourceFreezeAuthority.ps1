[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [string]$RecordedAt='',
  [switch]$Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')

$outputRelative='releases/migrations/MIR4-M41-Source-Freeze-Authority-EvolutionV1.json'
$schemaRelative='contracts/repository/mir4-m41-source-freeze-authority-evolution-v1.schema.json'
$predecessorRelative='releases/migrations/MIR4-M41-Current-Product-Bridge-RetirementV1.json'
$contractRelative='governance/release/mir4-4.1-release-readiness-v1.json'
$baseCommit='65bb11c1226a8160c27ab074ddb503c20df98c69'
$baseTree='bebfd455f7f13d724eabb43c3ed48362d8d7901e'
$expectedPaths=@(
  '.mir/docs.yml',
  '.mir/fixtures.yml',
  'CHANGELOG.md',
  'README.md',
  'RELEASE-RUNBOOK.md',
  'assurance/catalog/tests.json',
  'changes/unreleased/MIR4-CHG-2026-0032.json',
  'changes/unreleased/MIR4-CHG-2026-0033.json',
  'changes/unreleased/MIR4-CHG-2026-0034.json',
  'changes/unreleased/MIR4-CHG-2026-0035.json',
  'changes/unreleased/MIR4-CHG-2026-0036.json',
  'changes/unreleased/MIR4-CHG-2026-0037.json',
  'changes/unreleased/MIR4-CHG-2026-0038.json',
  'changes/unreleased/MIR4-CHG-2026-0039.json',
  'changes/unreleased/MIR4-CHG-2026-0040.json',
  'changes/unreleased/MIR4-CHG-2026-0041.json',
  'changes/unreleased/MIR4-CHG-2026-0042.json',
  'changes/unreleased/MIR4-CHG-2026-0043.json',
  'changes/unreleased/MIR4-CHG-2026-0044.json',
  'contracts/release/mir4-release-narrative-plan-v1.schema.json',
  'contracts/repository/mir4-4.1-release-readiness-v1.schema.json',
  'contracts/repository/mir4-m41-source-freeze-authority-evolution-v1.schema.json',
  'docs/maintainer/mir4-4.1-release-readiness.md',
  'docs/maintainer/mir4-release-operations.md',
  'docs/reference/generated/documentation-index.md',
  'docs/reference/generated/documentation-navigation.md',
  'docs/reference/generated/documentation-owner-dashboard.md',
  'docs/reference/generated/documentation-reference-matrix.md',
  'docs/reference/generated/documentation-review-age.md',
  'docs/releases/mir4-post-4.0-roadmap.md',
  'fixtures/assert-upgrade-4-0-10000-to-4-1-10000/control.lua',
  'fixtures/assert-upgrade-4-0-10000-to-4-1-10000/data.lua',
  'fixtures/assert-upgrade-4-0-10000-to-4-1-10000/info.json',
  'fixtures/assert-upgrade-4-0-10000-to-4-1-10000/settings.lua',
  'fixtures/assert-upgrade-4-0-11000-to-4-1-11000/control.lua',
  'fixtures/assert-upgrade-4-0-11000-to-4-1-11000/data.lua',
  'fixtures/assert-upgrade-4-0-11000-to-4-1-11000/info.json',
  'fixtures/assert-upgrade-4-0-11000-to-4-1-11000/settings.lua',
  'fixtures/assert-upgrade-4-0-20000-to-4-1-20000/control.lua',
  'fixtures/assert-upgrade-4-0-20000-to-4-1-20000/data.lua',
  'fixtures/assert-upgrade-4-0-20000-to-4-1-20000/info.json',
  'fixtures/assert-upgrade-4-0-20000-to-4-1-20000/settings.lua',
  'fixtures/assert-upgrade-4-0-21000-to-4-1-21000/control.lua',
  'fixtures/assert-upgrade-4-0-21000-to-4-1-21000/data.lua',
  'fixtures/assert-upgrade-4-0-21000-to-4-1-21000/info.json',
  'fixtures/assert-upgrade-4-0-21000-to-4-1-21000/settings-updates.lua',
  'fixtures/assert-upgrade-4-0-21000-to-4-1-21000/settings.lua',
  'fixtures/assert-compiler-contracts/data-final-fixes.lua',
  'governance/automation/mir4-command-inventory-v1.json',
  'governance/release/mir4-4.1-release-readiness-v1.json',
  'releases/governance/MIR4-Source-Changelog-PlanV1.json',
  'spec/programmes/mir4-4x-operating-programme-v1.json',
  'tests/mir4/Test-MIR4ReleaseNarrativesM4103.ps1',
  'tests/mir4/Test-MIR4RepositoryCharacterizationM4200A.ps1',
  'tests/release/Test-MIR441ReleaseReadiness.ps1',
  'tests/release/Test-MIRReleaseAuthority.ps1',
  'tests/repository/Test-MIR4RepositoryFixedPoint.ps1',
  'tests/runtime/Test-MIRUpgrade.ps1',
  'tests/runtime/Test-MIRUpgradeMatrix.ps1',
  'tests/support/MIR4M4202PackageSuccession.ps1',
  'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1',
  'tests/tooling/Test-MIR4PowerShellCommandRouterDecompositionM4202.ps1',
  'tests/tooling/Test-MIR4CliReleaseConvergence.ps1',
  'tests/tooling/Test-MIR4TestWorkflowConvergence.ps1',
  'tools/commands/mir4/Update-MIR441PackagePresentationAuthority.ps1',
  'tools/commands/mir4/Update-MIR441SourceFreezeAuthority.ps1',
  'tools/commands/mir4/Update-MIR441UpgradeFixtures.ps1',
  'tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1',
  'tools/lib/mir4/pre-freeze-release/Common.ps1',
  'tools/lib/control/PackageSourceAtCommit.ps1',
  'tools/lib/control/Records.ps1',
  'tools/mir/application/package/MIR441PackagePresentation.ps1',
  'tools/mir/application/package/TargetMaterializer.ps1',
  'tools/mir/application/release/GitHubReleaseRenderer.ps1',
  'tools/mir/application/release/MIR441ReleaseReadiness.ps1',
  'tools/mir/application/release/ReleaseNarrativeModel.ps1',
  'tools/mir/application/release/ReleaseNarratives.ps1',
  'tools/mir/application/release/SourceChangelogRenderer.ps1',
  'tools/mir/application/release/readiness/CandidateBuild.ps1',
  'tools/mir/application/release/readiness/Common.ps1',
  'tools/mir/application/release/readiness/Contract.ps1',
  'tools/mir/application/release/readiness/IndependentVerification.ps1',
  'tools/mir/application/release/readiness/Promotion.ps1',
  'tools/mir/application/release/readiness/Qualification.ps1',
  'tools/mir/application/release/readiness/QualificationResume.ps1',
  'tools/mir/application/release/readiness/ResourceGovernor.ps1',
  'tools/mir/application/release/readiness/TechnicalSeal.ps1',
  'tools/mir/application/repository/RepositoryCharacterization.ps1',
  'tools/mir/cli/Invoke-MIR4ReleaseEngine.ps1',
  'tools/mir/cli/Invoke-MIRCommandRouter.ps1',
  'tools/mir/cli/router/MIR4ApplicationCommands.ps1',
  'validation/tests.yml'
) | Sort-Object -Unique

$predecessor=Get-Content -Raw -LiteralPath (Join-Path $repo $predecessorRelative)|ConvertFrom-Json -Depth 100 -DateKind String
$contract=Get-Content -Raw -LiteralPath (Join-Path $repo $contractRelative)|ConvertFrom-Json -Depth 100 -DateKind String
$package=Get-Content -Raw -LiteralPath (Join-Path $repo 'targets/package-authority.json')|ConvertFrom-Json -Depth 100 -DateKind String
$actualBaseTree=(& git -C $repo rev-parse "$baseCommit^{tree}").Trim()
if($LASTEXITCODE-ne0-or$actualBaseTree-cne$baseTree){throw '[mir441-source-freeze-base]'}
$tracked=@(& git -C $repo diff --name-only $baseCommit --)
if($LASTEXITCODE-ne0){throw '[mir441-source-freeze-diff]'}
$untracked=@(& git -C $repo ls-files --others --exclude-standard)
if($LASTEXITCODE-ne0){throw '[mir441-source-freeze-untracked]'}
$changed=@($tracked+$untracked|ForEach-Object{([string]$_).Replace('\','/')}|Where-Object{$_-and$_-cne$outputRelative}|Sort-Object -Unique)
if(($changed-join"`n")-cne($expectedPaths-join"`n")){
  $missing=@($expectedPaths|Where-Object{$_-cnotin$changed});$unexpected=@($changed|Where-Object{$_-cnotin$expectedPaths})
  throw "[mir441-source-freeze-path-set] missing=$($missing-join',') unexpected=$($unexpected-join',')"
}

function Get-MIR441ReadinessRole([string]$Path){
  if($Path-ceq$contractRelative){return 'Private release intent and transition authority.'}
  if($Path-like'targets/*'-or$Path-like'src/mod/*'){return 'Canonical generated-package source or target authority.'}
  if($Path-like'fixtures/*'-or$Path-like'tests/*'-or$Path-ceq'validation/tests.yml'-or$Path-ceq'assurance/catalog/tests.json'){return 'Executable release-readiness proof or fixture authority.'}
  if($Path-like'tools/*'){return 'Bounded release-readiness application, generator, or validator.'}
  if($Path-like'docs/*'-or$Path-in@('README.md','RELEASE-RUNBOOK.md','CHANGELOG.md')){return 'Repository or generated release documentation authority.'}
  return 'MIR 4.1 release-readiness governance or generated projection.'
}

$evolved=[Collections.Generic.List[object]]::new();$current=[Collections.Generic.List[object]]::new()
foreach($path in $changed){
  $full=Join-Path $repo $path
  $isText=(Test-MIRTextFingerprintPath -RelativePath $path)-or$path.EndsWith('.template',[StringComparison]::Ordinal)
  if(-not(Test-Path -LiteralPath $full -PathType Leaf)-or-not$isText){throw "[mir441-source-freeze-text-path] $path"}
  $text=[IO.File]::ReadAllText($full).Normalize([Text.NormalizationForm]::FormC)
  $sha=(Get-MIRNormalizedTextIdentity -Text $text).Sha256
  $releaseAuthority=$path-ceq$contractRelative
  & git -C $repo cat-file -e ($baseCommit+':'+$path) 2>$null
  if($LASTEXITCODE-eq0){
    $evolved.Add([ordered]@{path=$path;previous_sha256=(Get-MIRGitTextAtCommitSha256 -RepoRoot $repo -Commit $baseCommit -RelativePath $path);current_sha256=$sha;hash_mode='canonical-text-v1';scope='mir4-4.1-release-readiness';package_visible=$false;release_authority=$releaseAuthority;role=(Get-MIR441ReadinessRole $path)})
  }else{
    $current.Add([ordered]@{path=$path;sha256=$sha;hash_mode='canonical-text-v1';scope='mir4-4.1-release-readiness';package_visible=$false;release_authority=$releaseAuthority;role=(Get-MIR441ReadinessRole $path)})
  }
}
if($evolved.Count-lt1-or$current.Count-lt1-or(@($evolved+$current|Where-Object release_authority).Count)-ne1){throw '[mir441-source-freeze-authority-bindings]'}

$output=Join-Path $repo $outputRelative
if($Check){
  if(-not(Test-Path -LiteralPath $output -PathType Leaf)){throw '[mir441-source-freeze-receipt-missing]'}
  $RecordedAt=[string](Get-Content -Raw -LiteralPath $output|ConvertFrom-Json -Depth 100 -DateKind String).recorded_at
}elseif([string]::IsNullOrWhiteSpace($RecordedAt)){$RecordedAt=[DateTimeOffset]::Now.ToString('o')}

$record=[ordered]@{
  schema=1;kind='MIR4M41SourceFreezeAuthorityEvolutionV1';recorded_at=$RecordedAt;status='MIR41-RELEASE-READINESS-AUTHORITY-EVOLVED-SOURCE-FREEZE-PENDING'
  programme_id='MIR4-4.1-RELEASE-READINESS';change_id='MIR4-M41-SOURCE-FREEZE-AUTHORITY-2026-09-05'
  predecessor=[ordered]@{path=$predecessorRelative;sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $predecessorRelative));record_sha256=[string]$predecessor.record_sha256}
  base=[ordered]@{branch='dev';commit=$baseCommit;tree=$baseTree}
  readiness_contract=[ordered]@{path=$contractRelative;sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $repo $contractRelative))}
  package_source=[ordered]@{predecessor_sha256=[string]$predecessor.package_source.current_sha256;current_sha256=(Get-MIRPackageSourceFingerprint -RepoRoot $repo);authority_record_sha256=[string]$package.record_sha256;writer=[string]$package.writer.implementation}
  changed_path_count=[int]$changed.Count;evolved_bindings=@($evolved);current_authorities=@($current)
  package_visible_delta=@(@('f210','f200','f110','f100')|ForEach-Object{[ordered]@{target=$_;outputs=@('README.md','changelog.txt','info.json')}})
  invariants=[ordered]@{exact_changed_path_set=$true;canonical_text_hashes=$true;single_package_writer=$true;baseline_info_template_preserved=$true;candidate_version_materialized_from_release_intent=$true;gameplay_semantics_added=$false;tagging_authorized=$false;publication_authorized=$false}
  transition_gate=[ordered]@{version_allocation=$true;private_build=$true;qualification=$true;source_freeze=$false;production_signing=$false;technical_seal=$false;promotion_to_main=$false;tagging=$false;publication=$false}
  record_sha256=''
}
$object=[pscustomobject]$record;$record.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $object
$json=(($record|ConvertTo-Json -Depth 100).Replace("`r`n","`n")+"`n")
if($Check){if([IO.File]::ReadAllText($output).Replace("`r`n","`n")-cne$json){throw '[mir441-source-freeze-receipt-stale]'}}else{[void](New-Item -ItemType Directory -Force -Path(Split-Path -Parent $output));[IO.File]::WriteAllText($output,$json,[Text.UTF8Encoding]::new($false))}
if(-not((Get-Content -Raw -LiteralPath $output)|Test-Json -SchemaFile(Join-Path $repo $schemaRelative))){throw '[mir441-source-freeze-receipt-schema]'}
[pscustomobject][ordered]@{status=$(if($Check){'current'}else{'generated'});path=$outputRelative;record_sha256=[string]$record.record_sha256;changed_paths=$changed.Count;evolved=$evolved.Count;current=$current.Count;package_source_sha256=[string]$record.package_source.current_sha256}
