[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path,
  [switch]$Check
)

$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
. (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
$receiptPath='releases/migrations/MIR4-M41-Source-Freeze-Authority-EvolutionV1.json'
$receiptRaw=Get-Content -Raw -LiteralPath (Join-Path $repo $receiptPath)
if(-not($receiptRaw|Test-Json -SchemaFile (Join-Path $repo 'contracts/repository/mir4-m41-source-freeze-authority-evolution-v1.schema.json'))){throw '[mir441-package-presentation-historical-receipt-schema]'}
$receipt=$receiptRaw|ConvertFrom-Json -Depth 100 -DateKind String
if(-not(Test-MIR4BootstrapRecordHash -Record $receipt)-or[string]$receipt.record_sha256-cne'BB674AC17B31E9920BAC80C2D3635F0B01B49E95F50B4B97F6D584F6C0D9637A'){throw '[mir441-package-presentation-historical-receipt]'}
$commit='3562377b520cccb071b97b3968946eae7024c950'
$tree='e094f72aa59ecb994f12bb33c399022f20e94165'
$tagObject=(@(& git -C $repo rev-parse 'v4.1.0^{tag}' 2>$null)-join'').Trim()
$tagCommit=(@(& git -C $repo rev-parse 'v4.1.0^{commit}' 2>$null)-join'').Trim()
$observedTree=(@(& git -C $repo rev-parse "$commit^{tree}" 2>$null)-join'').Trim()
if($LASTEXITCODE-ne0-or$tagObject-cne'9e5e63ef45b9d583d3f463fbfa737eb2c3a6b69f'-or$tagCommit-cne$commit-or$observedTree-cne$tree){throw '[mir441-package-presentation-historical-source]'}
$targets=@('f210','f200','f110','f100')
$paths=@('tools/mir/application/package/MIR441PackagePresentation.ps1','releases/governance/MIR4-Source-Changelog-PlanV1.json')+@($targets|ForEach-Object{"targets/$_/generation/changelog.txt.template"})
$rows=@(foreach($path in $paths){
  $blob=(@(& git -C $repo rev-parse "$commit`:$path" 2>$null)-join'').Trim()
  if($LASTEXITCODE-ne0-or$blob-cnotmatch'^[0-9a-f]{40}$'){throw "[mir441-package-presentation-historical-path] $path"}
  [ordered]@{path=$path;blob_sha1=$blob}
})
[pscustomobject][ordered]@{
  status='MIR-4.1-PACKAGE-PRESENTATION-PINNED-HISTORICAL-SOURCE-VERIFIED'
  source=[ordered]@{tag='v4.1.0';tag_object=$tagObject;commit=$commit;tree=$tree;source_freeze_receipt=$receiptPath}
  inputs=$rows
  current_checkout_rebuild_authorized=$false
  pinned_checkout_required=$true
  check=[bool]$Check
  publication_authorized=$false
}
