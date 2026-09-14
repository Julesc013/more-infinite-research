# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
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

function Assert-MIRDevelopmentContractsReparseGuardRegression {
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
}

function ConvertFrom-MIRDevelopmentContractsPorcelainV1Z {
  param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Fields)

  $records=[Collections.Generic.List[object]]::new()
  for($index=0;$index -lt $Fields.Count;) {
    $field=$Fields[$index]
    $index++
    if($field.Length -eq 0 -and $index -eq $Fields.Count) { break }
    if($field.Length -lt 4 -or $field[2] -cne ' ') { throw "[mir4-development-selected-input-git-status-record] $field" }
    $status=$field.Substring(0,2)
    $paths=[Collections.Generic.List[string]]::new()
    $paths.Add($field.Substring(3))
    if($status[0] -in @('R','C') -or $status[1] -in @('R','C')) {
      if($index -ge $Fields.Count) { throw "[mir4-development-selected-input-git-status-rename] $field" }
      $paths.Add($Fields[$index])
      $index++
    }
    $records.Add([pscustomobject]@{status=$status;paths=@($paths)})
  }
  return @($records)
}

function Get-MIRDevelopmentContractsPorcelainV1Z {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $startInfo=[Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName='git'
  $startInfo.Arguments=('-C "{0}" status --porcelain=v1 -z --untracked-files=all' -f $RepoRoot.Replace('"','\"'))
  $startInfo.UseShellExecute=$false
  $startInfo.RedirectStandardOutput=$true
  $startInfo.RedirectStandardError=$true
  $process=[Diagnostics.Process]::new()
  $process.StartInfo=$startInfo
  [void]$process.Start()
  $bytes=[IO.MemoryStream]::new()
  $process.StandardOutput.BaseStream.CopyTo($bytes)
  $standardError=$process.StandardError.ReadToEnd()
  $process.WaitForExit()
  if($process.ExitCode -ne 0) { throw "[mir4-development-selected-input-git-status] $standardError" }
  $fields=[Text.UTF8Encoding]::new($false).GetString($bytes.ToArray()).Split([char]0,[StringSplitOptions]::None)
  return @(ConvertFrom-MIRDevelopmentContractsPorcelainV1Z -Fields $fields)
}

function Assert-MIRDevelopmentContractsPorcelainV1ZRegression {
  $records=@(ConvertFrom-MIRDevelopmentContractsPorcelainV1Z -Fields @(
    ' M tools/commands/package/Build-MIRPackage.ps1',
    'R  targets/f210/old.lua', 'targets/f210/new.lua',
    ' C contracts/repository/mir4-development-contracts-local-result-v1.schema.json', 'contracts/repository/renamed.schema.json',
    '?? validation/tests.yml',
    ''
  ))
  if($records.Count -ne 4 -or $records[1].paths.Count -ne 2 -or $records[2].paths.Count -ne 2) { throw '[mir4-development-selected-input-git-status-two-path]' }
  $allPaths=@($records | ForEach-Object { $_.paths } | ForEach-Object { $_.Replace('\','/') })
  foreach($required in @('tools/commands/package/Build-MIRPackage.ps1','targets/f210/old.lua','targets/f210/new.lua','contracts/repository/mir4-development-contracts-local-result-v1.schema.json','contracts/repository/renamed.schema.json','validation/tests.yml')) {
    if($required -notin $allPaths) { throw "[mir4-development-selected-input-git-status-path] $required" }
  }
}

function Get-MIRDevelopmentContractsSelectedInputFingerprint {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string[]]$SelectedInputPaths,
    [Parameter(Mandatory)][string]$PackageSourceFingerprint,
    [Parameter(Mandatory)][string]$CommandInventoryDigest,
    [hashtable]$IdentityOverrides=@{}
  )

  $rows=@(
    foreach($relative in $SelectedInputPaths) {
      $identity=if($IdentityOverrides.ContainsKey($relative)) { $IdentityOverrides[$relative] } else { Get-MIRFileContentIdentity -Path (Join-Path $RepoRoot $relative) -RelativePath $relative }
      "{0}`t{1}`t{2}" -f $relative,$identity.Length,$identity.Sha256
    }
    "canonical-package-source-sha256`t$PackageSourceFingerprint"
    "command-inventory-digest`t$CommandInventoryDigest"
  )
  return Get-MIRStringSha256 -Value ($rows -join "`n")
}

function Assert-MIRDevelopmentContractsInputFingerprintRegression {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string[]]$SelectedInputPaths,
    [Parameter(Mandatory)][string]$PackageSourceFingerprint,
    [Parameter(Mandatory)][string]$CommandInventoryDigest
  )

  $baseline=Get-MIRDevelopmentContractsSelectedInputFingerprint -RepoRoot $RepoRoot -SelectedInputPaths $SelectedInputPaths -PackageSourceFingerprint $PackageSourceFingerprint -CommandInventoryDigest $CommandInventoryDigest
  foreach($relative in @('tools/commands/package/Build-MIRPackage.ps1','contracts/repository/mir4-development-contracts-local-result-v1.schema.json')) {
    if($relative -notin $SelectedInputPaths) { throw "[mir4-development-selected-input-missing] $relative" }
    $identity=Get-MIRFileContentIdentity -Path (Join-Path $RepoRoot $relative) -RelativePath $relative
    $changed=Get-MIRDevelopmentContractsSelectedInputFingerprint -RepoRoot $RepoRoot -SelectedInputPaths $SelectedInputPaths -PackageSourceFingerprint $PackageSourceFingerprint -CommandInventoryDigest $CommandInventoryDigest -IdentityOverrides @{$relative=[pscustomobject]@{Length=([long]$identity.Length+1);Sha256=('0' * 64)}}
    if($changed -ceq $baseline) { throw "[mir4-development-selected-input-fingerprint] $relative" }
  }
}

$epoch=Get-Content -Raw (Join-Path $repo 'governance/repository/development-epoch-v1.json') | ConvertFrom-Json
if($epoch.schema -ne 1 -or $epoch.current_profile -cne 'mir4-development' -or $epoch.release_authority -or $epoch.protection_mutation_authority -or $epoch.historical_receipt_rewrite_authority) { throw '[mir4-development-authority]' }
Assert-MIRDevelopmentContractsReparseGuardRegression
Assert-MIRDevelopmentContractsPorcelainV1ZRegression
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
[void](Update-MIR4CurrentSourceBindings -RepoRoot $repo -Check)
$packageSourceFingerprint=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')
$commandInventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
. (Join-Path $repo 'tools/mir/application/tooling/TestWorkflowCatalogues.ps1')
[void](Update-MIR4ToolingCatalogueV1 -RepoRoot $repo -Catalogue tests -Check)
$testCatalogue=Get-Content -Raw -LiteralPath (Join-Path $repo 'assurance/catalog/tests.json') | ConvertFrom-Json -Depth 100
$catalogueEntry=@($testCatalogue.tests | Where-Object id -ceq 'static.mir4-development-contracts')
if($catalogueEntry.Count -ne 1) { throw '[mir4-development-catalogue-entry]' }
$requiredCatalogueInputs=@(
  'governance/repository/development-epoch-v1.json',
  'tests/repository/Test-MIR4DevelopmentContracts.ps1',
  'src/mod/**', 'targets/**', 'tools/mir/**', 'tools/lib/**',
  'tools/commands/package/Build-MIRPackage.ps1', 'tests/**',
  'governance/automation/mir4-command-inventory-v1.json',
  'contracts/repository/mir4-command-inventory-v1.schema.json',
  'contracts/repository/mir4-development-contracts-local-result-v1.schema.json',
  'contracts/repository/mir4-test-proof-catalogue-v1.schema.json',
  'validation/tests.yml', 'assurance/catalog/tests.json'
)
foreach($required in $requiredCatalogueInputs) {
  if($required -notin @($catalogueEntry[0].inputs)) { throw "[mir4-development-catalogue-input] $required" }
}
$capturedArtifacts=@($catalogueEntry[0].captured_artifacts)
if($capturedArtifacts.Count -ne 1 -or
   [string]$capturedArtifacts[0].path_pattern -cne 'build/results/validation/development-contracts/*.json' -or
   [string]$capturedArtifacts[0].schema -cne 'contracts/repository/mir4-development-contracts-local-result-v1.schema.json' -or
   [string]$capturedArtifacts[0].kind -cne 'MIR4DevelopmentContractsLocalResultV1') {
  throw '[mir4-development-catalogue-captured-artifact]'
}
# Parse every current tooling and test module, including modules whose original
# decomposition receipt now belongs to the pinned historical source.
$files=@(& git -C $repo ls-files --cached --others --exclude-standard -- ':(glob)tools/**/*.ps1' ':(glob)tests/**/*.ps1')
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
  'contracts/repository/mir4-command-inventory-v1.schema.json'
  'contracts/repository/mir4-development-contracts-local-result-v1.schema.json'
  'contracts/repository/mir4-test-proof-catalogue-v1.schema.json'
  'validation/tests.yml'
  'assurance/catalog/tests.json'
  'tools/commands/package/Build-MIRPackage.ps1'
) | Sort-Object -Unique
$selectedInputFingerprint=Get-MIRDevelopmentContractsSelectedInputFingerprint -RepoRoot $repo -SelectedInputPaths $selectedInputPaths -PackageSourceFingerprint $packageSourceFingerprint -CommandInventoryDigest $commandInventory.digest
Assert-MIRDevelopmentContractsInputFingerprintRegression -RepoRoot $repo -SelectedInputPaths $selectedInputPaths -PackageSourceFingerprint $packageSourceFingerprint -CommandInventoryDigest $commandInventory.digest
# Query Git once: passing the complete tooling/test file set as native command
# arguments can exceed Windows process-command limits. Parse porcelain v1 -z
# records so both rename/copy paths remain dirty inputs.
$selectedInputSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($relative in $selectedInputPaths) { [void]$selectedInputSet.Add($relative.Replace('\','/')) }
$repositoryStatus=@(Get-MIRDevelopmentContractsPorcelainV1Z -RepoRoot $repo)
$selectedInputStatus=@($repositoryStatus | Where-Object {
  @($_.paths | ForEach-Object { $selectedInputSet.Contains(([string]$_).Replace('\','/')) }) -contains $true
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
  $receiptSchema=Join-Path $repo 'contracts/repository/mir4-development-contracts-local-result-v1.schema.json'
  if(-not ($receiptJson | Test-Json -SchemaFile $receiptSchema)) { throw '[mir4-development-receipt-schema]' }
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
