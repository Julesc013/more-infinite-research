# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [switch]$SelfTestReparseGuard
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $RepoRoot).Path

function Assert-MIRDevelopmentContractsNoReparsePoint {
  param([Parameter(Mandatory)][string]$Root)

  $rootItem=Get-Item -LiteralPath $Root -Force
  $pending=[Collections.Generic.Stack[System.IO.FileSystemInfo]]::new()
  $pending.Push($rootItem)
  while($pending.Count -gt 0) {
    $item=$pending.Pop()
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0) {
      throw "[mir4-development-cleanup-reparse] $($item.FullName)"
    }
    if(-not $item.PSIsContainer) { continue }
    try {
      foreach($path in [IO.Directory]::EnumerateFileSystemEntries($item.FullName)) {
        $pending.Push((Get-Item -LiteralPath $path -Force))
      }
    } catch {
      throw "[mir4-development-cleanup-inspection] $($item.FullName): $($_.Exception.Message)"
    }
  }
}

if($SelfTestReparseGuard) {
  $fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ("mir4-development-contracts-reparse-{0}" -f [guid]::NewGuid().ToString('N'))
  try {
    $outside=Join-Path $fixtureRoot 'outside'
    $candidate=Join-Path $fixtureRoot 'candidate'
    New-Item -ItemType Directory -Path $outside,$candidate -Force|Out-Null
    New-Item -ItemType Junction -Path (Join-Path $candidate 'nested-link') -Target $outside|Out-Null
    $caught=$false
    try { Assert-MIRDevelopmentContractsNoReparsePoint -Root $candidate } catch { $caught=$_.Exception.Message -match '\[mir4-development-cleanup-reparse\]' }
    if(-not $caught) { throw '[mir4-development-cleanup-reparse-self-test]' }
  } finally {
    if(Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
  }
  Write-Host 'Development-contract output cleanup rejects nested reparse points.'
  return
}

$epoch=Get-Content -Raw (Join-Path $repo 'governance/repository/development-epoch-v1.json') | ConvertFrom-Json
if($epoch.schema -ne 1 -or $epoch.current_profile -cne 'mir4-development' -or $epoch.release_authority -or $epoch.protection_mutation_authority -or $epoch.historical_receipt_rewrite_authority) { throw '[mir4-development-authority]' }
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
[void](Update-MIR4CurrentSourceBindings -RepoRoot $repo -Check)
$packageSourceFingerprint=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
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
$selectedInputPaths=@(
  $files
  'governance/repository/development-epoch-v1.json'
  'governance/automation/mir4-command-inventory-v1.json'
) | Sort-Object -Unique
$selectedInputRows=@(
  foreach($relative in $selectedInputPaths) {
    $identity=Get-MIRFileContentIdentity -Path (Join-Path $repo $relative) -RelativePath $relative
    "{0}`t{1}`t{2}" -f $relative,$identity.Length,$identity.Sha256
  }
  "canonical-package-source-sha256`t$packageSourceFingerprint"
  "command-inventory-digest`t$($commandInventory.digest)"
)
$selectedInputFingerprint=Get-MIRStringSha256 -Value ($selectedInputRows -join "`n")
# Query Git once: passing the complete tooling/test file set as native command
# arguments can exceed Windows process-command limits.  The selected-input set
# is still checked exactly, and package source has its own canonical dirty bit.
$repositoryStatus=@(& git -C $repo status --porcelain --untracked-files=all 2>$null)
if($LASTEXITCODE -ne 0) { throw '[mir4-development-selected-input-git-status]' }
$selectedInputSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($relative in $selectedInputPaths) { [void]$selectedInputSet.Add($relative.Replace('\','/')) }
$selectedInputStatus=@($repositoryStatus | Where-Object {
  $relative=([string]$_).Substring(3).Replace('\','/')
  $selectedInputSet.Contains($relative)
})
$packageSourceDirty=Test-MIR4CanonicalPackageSourceGitDirty -RepoRoot $repo
$selectedInputsDirty=$packageSourceDirty -or $selectedInputStatus.Count -gt 0
$repositoryDirty=$repositoryStatus.Count -gt 0
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
  $receiptId=Get-MIRStringSha256 -Value ("$packageSourceFingerprint`n$($commandInventory.digest)`n$selectedInputFingerprint")
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
      package_source_dirty=$packageSourceDirty
      selected_inputs_sha256=$selectedInputFingerprint
      selected_input_file_count=$selectedInputPaths.Count
      selected_inputs_dirty=$selectedInputsDirty
      repository_dirty=$repositoryDirty
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
    Assert-MIRDevelopmentContractsNoReparsePoint -Root $resolvedRoot
    [IO.Directory]::Delete($resolvedRoot,$true)
  }
}
