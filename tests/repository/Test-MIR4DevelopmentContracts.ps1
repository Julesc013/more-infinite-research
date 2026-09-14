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
$commandInventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
# Parse every current tooling and test module, including modules whose original
# decomposition receipt now belongs to the pinned historical source.
$files=@(& git -C $repo ls-files --cached --others --exclude-standard -- 'tools/*.ps1' 'tests/*.ps1')
if($LASTEXITCODE -ne 0 -or $files.Count -eq 0) { throw '[mir4-development-tooling-inventory]' }
foreach($path in @($files | Sort-Object -Unique)) {
  $tokens=$null;$errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $path),[ref]$tokens,[ref]$errors)
  if($errors.Count) { throw "[mir4-development-powershell-syntax] $path : $errors" }
}
$developmentContractsRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build/packages/development-contracts'))
$root=Join-Path $developmentContractsRoot ([guid]::NewGuid().ToString('N'))
$completed=$false
try {
  $results=@()
  foreach($target in @('f210','f200','f110','f100')) {
    $pair=@()
    foreach($run in @('A','B')) {
      $pair+=& (Join-Path $repo 'tools/commands/package/Build-MIRPackage.ps1') -Target $target -SourceVersion '4.2.0' -CandidateId ('DEVELOPMENT-'+$run) -OutputDir $root
    }
    if($pair[0].archive_sha256 -cne $pair[1].archive_sha256 -or $pair[0].content_sha256 -cne $pair[1].content_sha256) { throw "[mir4-development-package-determinism] $target" }
    $results+=[ordered]@{target=$target;archive_sha256=$pair[0].archive_sha256;content_sha256=$pair[0].content_sha256;entry_count=$pair[0].entry_count}
  }
  $packageSourceFingerprint=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
  $receiptId=Get-MIRStringSha256 -Value ("$packageSourceFingerprint`n$($commandInventory.digest)")
  $receiptRoot=Join-Path $repo 'build/results/validation/development-contracts'
  [IO.Directory]::CreateDirectory($receiptRoot)|Out-Null
  $receiptPath=Join-Path $receiptRoot ("$receiptId.json")
  $receipt=[ordered]@{
    schema=1
    kind='MIR4DevelopmentContractsLocalResultV1'
    status='passed'
    scope='current-source-and-four-target-determinism'
    source=[ordered]@{
      commit=(& git -C $repo rev-parse HEAD).Trim()
      tree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
      package_source_sha256=$packageSourceFingerprint
      package_source_dirty=(Test-MIR4CanonicalPackageSourceGitDirty -RepoRoot $repo)
    }
    command_inventory_digest=[string]$commandInventory.digest
    packages=$results
    retained_expanded_packages=$false
    release_authority=$false
  }
  $receiptJson=($receipt|ConvertTo-Json -Depth 10)+"`n"
  $temporaryReceipt="$receiptPath.$([guid]::NewGuid().ToString('N')).tmp"
  [IO.File]::WriteAllText($temporaryReceipt,$receiptJson,[Text.UTF8Encoding]::new($false))
  [IO.File]::Move($temporaryReceipt,$receiptPath,$true)
  $completed=$true
  Write-Host "Current source bindings, tooling syntax, command inventory and four-target package determinism passed. Compact evidence: $receiptPath"
} finally {
  if($completed -and (Test-Path -LiteralPath $root -PathType Container)) {
    $resolvedRoot=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $root).Path)
    $expectedPrefix=$developmentContractsRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    $rootItem=Get-Item -LiteralPath $resolvedRoot -Force
    if(-not $resolvedRoot.StartsWith($expectedPrefix,[StringComparison]::OrdinalIgnoreCase)-or($rootItem.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0) {
      throw "[mir4-development-cleanup-boundary] $resolvedRoot"
    }
    [IO.Directory]::Delete($resolvedRoot,$true)
  }
}
