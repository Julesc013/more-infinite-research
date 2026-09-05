# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$epoch=Get-Content -Raw (Join-Path $repo 'governance/repository/development-epoch-v1.json') | ConvertFrom-Json
if($epoch.schema -ne 1 -or $epoch.current_profile -cne 'mir4-development' -or $epoch.release_authority -or $epoch.protection_mutation_authority -or $epoch.historical_receipt_rewrite_authority) { throw '[mir4-development-authority]' }
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
[void](Update-MIR4CurrentSourceBindings -RepoRoot $repo -Check)
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')
[void](Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check)
# Parse every current tooling and test module, including modules whose original
# decomposition receipt now belongs to the pinned historical source.
$files=@(& git -C $repo ls-files --cached --others --exclude-standard -- 'tools/*.ps1' 'tests/*.ps1')
if($LASTEXITCODE -ne 0 -or $files.Count -eq 0) { throw '[mir4-development-tooling-inventory]' }
foreach($path in @($files | Sort-Object -Unique)) {
  $tokens=$null;$errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $path),[ref]$tokens,[ref]$errors)
  if($errors.Count) { throw "[mir4-development-powershell-syntax] $path : $errors" }
}
$root=Join-Path $repo ('build/packages/development-contracts/'+[guid]::NewGuid().ToString('N'))
$results=@()
foreach($target in @('f210','f200','f110','f100')) {
  $pair=@()
  foreach($run in @('A','B')) {
    $pair+=& (Join-Path $repo 'tools/commands/package/Build-MIRPackage.ps1') -Target $target -SourceVersion '4.2.0' -CandidateId ('DEVELOPMENT-'+$run) -OutputDir $root
  }
  if($pair[0].archive_sha256 -cne $pair[1].archive_sha256 -or $pair[0].content_sha256 -cne $pair[1].content_sha256) { throw "[mir4-development-package-determinism] $target" }
  $results+=@{target=$target;archive=$pair[0].archive_path;content_sha256=$pair[0].content_sha256;entry_count=$pair[0].entry_count}
}
[ordered]@{status='passed';scope='current-source-and-four-target-determinism';packages=$results;release_authority=$false} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'receipt.json')
Write-Host "Current source bindings, tooling syntax, command inventory and four-target package determinism passed. Evidence: $root"
