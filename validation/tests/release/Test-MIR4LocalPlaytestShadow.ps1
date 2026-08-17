param([string]$RepoRoot = "")

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../..")).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $RepoRoot "tools/lib/mir4/BootstrapMaterialization.ps1")
. (Join-Path $RepoRoot "tools/lib/validation/PackageIdentity.ps1")

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

function Copy-Record($Record) {
  return ($Record | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String)
}

function Assert-SchemaRejects($Record, [string]$Context) {
  $text = $Record | ConvertTo-Json -Depth 100
  Assert-True (-not ($text | Test-Json -SchemaFile $script:authoritySchema -ErrorAction SilentlyContinue)) "Local-playtest authority schema accepted $Context."
}

if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) {
  throw "Test-Json is required for fail-closed MIR 4 local-playtest tests."
}

$authorityRelative = '.mir/releases/waves/mir4-r0/MIR4-Private-Lane-AuthorizationV2.json'
$authorityPath = Join-Path $RepoRoot $authorityRelative
$authoritySchema = Join-Path $RepoRoot 'spec/schemas/mir4-private-lane-authorization-v2.schema.json'
$manifestSchema = Join-Path $RepoRoot 'spec/schemas/mir4-local-playtest-candidate-manifest.schema.json'
$text = Get-Content -Raw -LiteralPath $authorityPath
$authority = $text | ConvertFrom-Json -Depth 100 -DateKind String

Assert-True ($text | Test-Json -SchemaFile $authoritySchema) 'Local-playtest shadow authorization schema validation failed.'
Assert-True (Test-MIR4BootstrapRecordHash -Record $authority) 'Local-playtest shadow authorization self-hash is stale.'
Assert-True ([string]$authority.authority_family -ceq 'MIRLocalArtifactLaneAuthorizationV1') 'Local artifact authority family drifted.'
Assert-True ([string]$authority.output_root -ceq 'build/mir4/local-playtest-shadow') 'Local-playtest output root drifted.'
Assert-True ((@($authority.authorized_targets.target_key) -join '|') -ceq 'f200|f110|f100') 'Local-playtest target set or order drifted.'
Assert-True (@($authority.authorized_targets | Where-Object { [string]$_.target_key -ceq 'f210' }).Count -eq 0) 'Local-playtest authority inherited f210.'
Assert-True (-not [bool]$authority.package_visible -and
  -not [bool]$authority.semantic_authority -and
  -not [bool]$authority.semantic_difference_authorized -and
  -not [bool]$authority.release_admission_authorized -and
  -not [bool]$authority.public_identity_authorized -and
  -not [bool]$authority.public_output_authorized -and
  -not [bool]$authority.signing_or_sealing_authorized -and
  -not [bool]$authority.publication_authorized -and
  -not [bool]$authority.wildcard_targets_authorized -and
  -not [bool]$authority.gate_waivers_authorized) 'Local-playtest authorization crossed a release-authority boundary.'
Assert-True ([string]$authority.private_transfer.custody -ceq 'maintainer-controlled-private-machines-only' -and
  [bool]$authority.private_transfer.permitted -and
  -not [bool]$authority.private_transfer.public_or_uncontrolled_transfer) 'Private-transfer policy drifted.'

foreach ($import in @($authority.imports.PSObject.Properties.Value)) {
  $importPath = Join-Path $RepoRoot ([string]$import.path)
  Assert-True ((Get-MIR4BootstrapTextSha256 -Path $importPath) -ceq [string]$import.file_sha256) "Local-playtest canonical-text import hash drifted: $($import.path)"
  if ($null -ne $import.PSObject.Properties['record_sha256']) {
    $importRecord = Get-Content -Raw -LiteralPath $importPath | ConvertFrom-Json -Depth 100 -DateKind String
    Assert-True ([string]$importRecord.record_sha256 -ceq [string]$import.record_sha256) "Local-playtest imported record drifted: $($import.path)"
  }
}

$plan = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ([string]$authority.imports.candidate_plan.path)) | ConvertFrom-Json -Depth 100 -DateKind String
$terminalImport = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ([string]$authority.imports.terminal_import.path)) | ConvertFrom-Json -Depth 100 -DateKind String
$rootSet = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ([string]$authority.imports.bootstrap_root_set.path)) | ConvertFrom-Json -Depth 100 -DateKind String
foreach ($target in @($authority.authorized_targets)) {
  $planRows = @($plan.targets | Where-Object { [string]$_.target_key -ceq [string]$target.target_key })
  $importRows = @($terminalImport.releases | Where-Object { [string]$_.release -ceq [string]$target.predecessor_release })
  $rootRows = @($rootSet.targets | Where-Object { [string]$_.target_id -ceq [string]$target.target_key })
  Assert-True ($planRows.Count -eq 1 -and $importRows.Count -eq 1 -and $rootRows.Count -eq 1) "Local-playtest target is not uniquely imported: $($target.target_key)"
  $planRow = $planRows[0]
  Assert-True ([string]$planRow.admission -ceq 'non-authoritative-shadow-blocked-by-eol' -and
    [string]$planRow.source.candidate_commit -ceq [string]$target.source_commit -and
    [string]$planRow.source.source_tree -ceq [string]$target.source_tree -and
    [string]$planRow.predecessor.archive_sha256 -ceq [string]$target.predecessor_archive_sha256 -and
    [string]$planRow.engine_lock.executable_sha256 -ceq [string]$target.engine_sha256) "Local-playtest target binding drifted: $($target.target_key)"
  Assert-True ([string]$importRows[0].distribution.archive_sha256 -ceq [string]$target.predecessor_archive_sha256 -and
    [string]$rootRows[0].predecessor_release -ceq [string]$target.predecessor_release) "Current terminal import or bootstrap root drifted: $($target.target_key)"
}
Assert-True ([string]$authority.authorized_targets[0].predecessor_release -ceq '2.5.10') 'The f200 private lane did not advance to the immutable 2.5.10 predecessor.'

$packageFiles = @(Get-MIRPackageSourceFiles -RepoRoot $RepoRoot)
foreach ($relative in @($authorityRelative, 'spec/schemas/mir4-private-lane-authorization-v2.schema.json', 'spec/schemas/mir4-local-playtest-candidate-manifest.schema.json')) {
  Assert-True ($relative -cnotin $packageFiles) "Package-excluded local-playtest path became package-visible: $relative"
}
Assert-True (Test-Path -LiteralPath $manifestSchema -PathType Leaf) 'Local-playtest candidate manifest schema is absent.'

$bad = Copy-Record $authority; $bad.authorized_targets[0].target_key = 'f210'; Assert-SchemaRejects $bad 'f210 target inheritance'
$bad = Copy-Record $authority; $bad | Add-Member -NotePropertyName wildcard_target -NotePropertyValue '*'; Assert-SchemaRejects $bad 'a wildcard target field'
$bad = Copy-Record $authority; $bad.output_root = 'dist'; Assert-SchemaRejects $bad 'a dist output root'
$bad = Copy-Record $authority; $bad.public_output_authorized = $true; Assert-SchemaRejects $bad 'public output'
$bad = Copy-Record $authority; $bad.signing_or_sealing_authorized = $true; Assert-SchemaRejects $bad 'production sealing'
$bad = Copy-Record $authority; $bad.publication_authorized = $true; Assert-SchemaRejects $bad 'publication'
$bad = Copy-Record $authority; $bad.authorized_targets[0].source_commit = '0000000000000000000000000000000000000000'; Assert-SchemaRejects $bad 'source drift'
$bad = Copy-Record $authority; $bad.imports.candidate_plan.file_sha256 = ('0' * 64); Assert-True (($bad | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $authoritySchema) 'Plan-drift negative fixture should remain structurally valid.'; Assert-True (-not (Test-MIR4BootstrapRecordHash -Record $bad)) 'Plan-drift mutation retained the authority self-hash.'
$bad = Copy-Record $authority; $bad.expiry = @('never'); Assert-SchemaRejects $bad 'an unbounded expiry'

Write-Host '[ok] MIR 4 private local-playtest shadow authority is exact, package-excluded, and release-orthogonal'
