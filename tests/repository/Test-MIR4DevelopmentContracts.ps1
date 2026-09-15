# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$ExpectedSourceCommit='',
  [string]$ExpectedSourceTree='',
  [string]$ExpectedPackageSourceSha256='',
  [string]$ReceiptPath=''
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
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Fields,
    [ValidateRange(1,1000000)][int]$MaxFields = 100000,
    [ValidateRange(16,1048576)][int]$MaxFieldCharacters = 65536
  )

  if ($Fields.Count -gt $MaxFields) { throw '[mir4-development-selected-input-git-status-bounded-fields]' }
  $records=[Collections.Generic.List[object]]::new()
  for($index=0;$index -lt $Fields.Count;) {
    $field=$Fields[$index]
    $index++
    if($field.Length -eq 0 -and $index -eq $Fields.Count) { break }
    if ($field.Length -gt $MaxFieldCharacters) { throw '[mir4-development-selected-input-git-status-bounded-field]' }
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
    if ($records.Count -gt $MaxFields) { throw '[mir4-development-selected-input-git-status-bounded-records]' }
  }
  return @($records)
}

function Get-MIRDevelopmentContractsPorcelainV1Z {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [ValidateRange(1024,67108864)][int]$MaxOutputBytes = 8388608,
    [ValidateRange(16,1048576)][int]$MaxFieldBytes = 65536,
    [ValidateRange(1,1000000)][int]$MaxFields = 100000
  )

  $startInfo=[Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName='git'
  $startInfo.ArgumentList.Add('-C')
  $startInfo.ArgumentList.Add($RepoRoot)
  $startInfo.ArgumentList.Add('status')
  $startInfo.ArgumentList.Add('--porcelain=v1')
  $startInfo.ArgumentList.Add('-z')
  $startInfo.ArgumentList.Add('--untracked-files=all')
  $startInfo.UseShellExecute=$false
  $startInfo.RedirectStandardOutput=$true
  # Do not buffer an arbitrary diagnostic stream while this bounded reader is
  # waiting on status output.  Git receives the inherited diagnostic handle;
  # nonzero exit remains a fail-closed status error below.
  $startInfo.RedirectStandardError=$false
  $process=[Diagnostics.Process]::new()
  $process.StartInfo=$startInfo
  [void]$process.Start()
  $fields=[Collections.Generic.List[string]]::new()
  $fieldBytes=[Collections.Generic.List[byte]]::new()
  $buffer=New-Object byte[] 4096
  [long]$totalBytes=0
  try {
    while (($read=$process.StandardOutput.BaseStream.Read($buffer,0,$buffer.Length)) -gt 0) {
      $totalBytes += $read
      if ($totalBytes -gt $MaxOutputBytes) { throw '[mir4-development-selected-input-git-status-bounded-output]' }
      for ($offset=0;$offset -lt $read;$offset++) {
        $byte=$buffer[$offset]
        if ($byte -eq 0) {
          if ($fieldBytes.Count -gt $MaxFieldBytes) { throw '[mir4-development-selected-input-git-status-bounded-field]' }
          try { $fields.Add([Text.UTF8Encoding]::new($false,$true).GetString($fieldBytes.ToArray())) }
          catch { throw '[mir4-development-selected-input-git-status-utf8]' }
          if ($fields.Count -gt $MaxFields) { throw '[mir4-development-selected-input-git-status-bounded-fields]' }
          $fieldBytes.Clear()
          continue
        }
        $fieldBytes.Add($byte)
        if ($fieldBytes.Count -gt $MaxFieldBytes) { throw '[mir4-development-selected-input-git-status-bounded-field]' }
      }
    }
    if ($fieldBytes.Count -ne 0) { throw '[mir4-development-selected-input-git-status-truncated]' }
    $process.WaitForExit()
    if($process.ExitCode -ne 0) { throw '[mir4-development-selected-input-git-status]' }
  } catch {
    if (-not $process.HasExited) { $process.Kill($true);$process.WaitForExit() }
    throw
  } finally {
    $process.Dispose()
  }
  return @(ConvertFrom-MIRDevelopmentContractsPorcelainV1Z -Fields @($fields) -MaxFields $MaxFields -MaxFieldCharacters $MaxFieldBytes)
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
  $boundedFieldsCaught=$false
  try { $null=ConvertFrom-MIRDevelopmentContractsPorcelainV1Z -Fields @(' M a',' M b',' M c') -MaxFields 2 } catch { $boundedFieldsCaught=$_.Exception.Message -match 'bounded-fields' }
  if(-not $boundedFieldsCaught) { throw '[mir4-development-selected-input-git-status-bounded-fields-self-test]' }
  $boundedFieldCaught=$false
  try { $null=ConvertFrom-MIRDevelopmentContractsPorcelainV1Z -Fields @(' M '+('x'*128)) -MaxFieldCharacters 64 } catch { $boundedFieldCaught=$_.Exception.Message -match 'bounded-field' }
  if(-not $boundedFieldCaught) { throw '[mir4-development-selected-input-git-status-bounded-field-self-test]' }
}

function Assert-MIRDevelopmentContractsPorcelainStreamingBoundRegression {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $fixture=Join-Path $RepoRoot ('mir4-development-status-bound-' + [guid]::NewGuid().ToString('N'))
  try {
    New-Item -ItemType Directory -Force -Path $fixture | Out-Null
    foreach($index in 1..24) { [IO.File]::WriteAllText((Join-Path $fixture ("status-$index.txt")),('x'*128),[Text.UTF8Encoding]::new($false)) }
    $caught=$false
    try { $null=Get-MIRDevelopmentContractsPorcelainV1Z -RepoRoot $RepoRoot -MaxOutputBytes 1024 -MaxFieldBytes 512 -MaxFields 100 } catch { $caught=$_.Exception.Message -match 'bounded-output' }
    if(-not $caught) { throw '[mir4-development-selected-input-git-status-bounded-output-self-test]' }
  } finally {
    if(Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
  }
}

function Assert-MIRDevelopmentContractsCommittedSource {
  param(
    [Parameter(Mandatory)][string]$ActualCommit,
    [Parameter(Mandatory)][string]$ActualTree,
    [Parameter(Mandatory)][string]$ActualPackageSourceSha256,
    [Parameter(Mandatory)][string]$ExpectedCommit,
    [Parameter(Mandatory)][string]$ExpectedTree,
    [Parameter(Mandatory)][string]$ExpectedPackageSourceSha256,
    [Parameter(Mandatory)][bool]$PackageSourceDirty,
    [Parameter(Mandatory)][bool]$SelectedInputsDirty,
    [Parameter(Mandatory)][bool]$RepositoryDirty
  )

  if ($PackageSourceDirty -or $SelectedInputsDirty -or $RepositoryDirty) {
    throw '[mir4-development-committed-source-dirty]'
  }
  if ($ActualCommit -cne $ExpectedCommit) { throw '[mir4-development-committed-source-commit]' }
  if ($ActualTree -cne $ExpectedTree) { throw '[mir4-development-committed-source-tree]' }
  if ($ActualPackageSourceSha256 -cne $ExpectedPackageSourceSha256) { throw '[mir4-development-committed-source-package-source]' }
}

function Assert-MIRDevelopmentContractsCommittedSourceRegression {
  $arguments = @{
    ActualCommit = ('a' * 40)
    ActualTree = ('b' * 40)
    ActualPackageSourceSha256 = ('C' * 64)
    ExpectedCommit = ('a' * 40)
    ExpectedTree = ('b' * 40)
    ExpectedPackageSourceSha256 = ('C' * 64)
    PackageSourceDirty = $false
    SelectedInputsDirty = $false
    RepositoryDirty = $false
  }
  Assert-MIRDevelopmentContractsCommittedSource @arguments
  foreach ($counterexample in @(
    @{name='dirty'; changes=@{RepositoryDirty=$true}; expected='dirty'},
    @{name='commit'; changes=@{ExpectedCommit=('0' * 40)}; expected='commit'},
    @{name='tree'; changes=@{ExpectedTree=('0' * 40)}; expected='tree'},
    @{name='package-source'; changes=@{ExpectedPackageSourceSha256=('0' * 64)}; expected='package-source'}
  )) {
    $changed = @{}
    foreach ($entry in $arguments.GetEnumerator()) { $changed[$entry.Key] = $entry.Value }
    foreach ($entry in $counterexample.changes.GetEnumerator()) { $changed[$entry.Key] = $entry.Value }
    $caught = $false
    try { Assert-MIRDevelopmentContractsCommittedSource @changed } catch { $caught = $_.Exception.Message -match [regex]::Escape([string]$counterexample.expected) }
    if (-not $caught) { throw "[mir4-development-committed-source-regression] $($counterexample.name)" }
  }
}

function Assert-MIRDevelopmentContractsReceiptSchemaRegression {
  param([Parameter(Mandatory)][string]$SchemaPath)

  $receipt = [ordered]@{
    schema=1;kind='MIR4DevelopmentContractsLocalResultV1';status='passed';scope='current-source-and-four-target-determinism'
    source=[ordered]@{
      commit=('a' * 40);tree=('b' * 40);package_source_sha256=('C' * 64);package_source_dirty=$false
      selected_inputs_sha256=('D' * 64);selected_input_file_count=1;selected_inputs_dirty=$false;repository_dirty=$false
    }
    command_inventory_digest=('sha256:' + ('e' * 64))
    packages=@(foreach ($target in @('f210','f200','f110','f100')) { [ordered]@{target=$target;archive_sha256=('F' * 64);content_sha256=('A' * 64);entry_count=1} })
    retained_expanded_packages=$false;release_authority=$false
  }
  if (-not (($receipt | ConvertTo-Json -Depth 10) | Test-Json -SchemaFile $SchemaPath)) { throw '[mir4-development-receipt-schema-positive]' }
  foreach ($counterexample in @(
    @{name='package-source-dirty'; mutate={ param($value) $value.source.package_source_dirty=$true }},
    @{name='selected-inputs-dirty'; mutate={ param($value) $value.source.selected_inputs_dirty=$true }},
    @{name='repository-dirty'; mutate={ param($value) $value.source.repository_dirty=$true }},
    @{name='missing-f210'; mutate={ param($value) $value.packages[0].target='f200' }},
    @{name='missing-f200'; mutate={ param($value) $value.packages[1].target='f110' }},
    @{name='missing-f110'; mutate={ param($value) $value.packages[2].target='f100' }},
    @{name='missing-f100'; mutate={ param($value) $value.packages[3].target='f210' }}
  )) {
    $changed = ($receipt | ConvertTo-Json -Depth 10) | ConvertFrom-Json -Depth 100
    & $counterexample.mutate $changed
    $accepted = $false
    try { $accepted = [bool](($changed | ConvertTo-Json -Depth 10) | Test-Json -SchemaFile $SchemaPath) }
    catch { $accepted = $false }
    if ($accepted) {
      throw "[mir4-development-receipt-schema-counterexample] $($counterexample.name)"
    }
  }
}

function Assert-MIRDevelopmentContractsCanonicalPackageAuthorityRegression {
  param([Parameter(Mandatory)][string]$RepoRoot)

  $authority=Read-MIR4TargetMaterializerRecord -RepoRoot $RepoRoot -RelativePath 'targets/package-authority.json' -Kind 'MIR4CanonicalPackageAuthorityV2'
  if([int]$authority.schema -ne 2 -or [string]$authority.kind -cne 'MIR4CanonicalPackageAuthorityV2' -or [string]$authority.record_sha256 -notmatch '^[A-F0-9]{64}$') {
    throw '[mir4-development-canonical-package-authority-positive]'
  }
  $wrongKindRejected=$false
  try {
    Read-MIR4TargetMaterializerRecord -RepoRoot $RepoRoot -RelativePath 'targets/package-authority.json' -Kind 'MIR4TargetRegistryV2' | Out-Null
  } catch {
    $wrongKindRejected=$_.Exception.Message -match '\[mir4-target-materializer-record-schema\]'
  }
  if(-not $wrongKindRejected) { throw '[mir4-development-canonical-package-authority-wrong-kind]' }
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
  foreach($relative in @(
    'tools/commands/package/Build-MIRPackage.ps1',
    'tools/commands/workspace/Remove-MIRStaleArtifacts.ps1',
    'scripts/Invoke-MIRAssurance.ps1',
    'contracts/repository/mir4-development-contracts-local-result-v1.schema.json'
  )) {
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
Assert-MIRDevelopmentContractsPorcelainStreamingBoundRegression -RepoRoot $repo
. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
Assert-MIRDevelopmentContractsCanonicalPackageAuthorityRegression -RepoRoot $repo
[void](Update-MIR4CurrentSourceBindings -RepoRoot $repo -Check)
$packageSourceFingerprint=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
$receiptSchema=Join-Path $repo 'contracts/repository/mir4-development-contracts-local-result-v1.schema.json'
Assert-MIRDevelopmentContractsCommittedSourceRegression
Assert-MIRDevelopmentContractsReceiptSchemaRegression -SchemaPath $receiptSchema
. (Join-Path $repo 'tools/mir/application/tooling/CommandInventory.ps1')
$commandInventory=Update-MIR4CommandInventoryV1 -RepoRoot $repo -Check
. (Join-Path $repo 'tools/mir/application/tooling/TestWorkflowCatalogues.ps1')
[void](Update-MIR4ToolingCatalogueV1 -RepoRoot $repo -Catalogue tests -Check)
$testCatalogue=Get-Content -Raw -LiteralPath (Join-Path $repo 'assurance/catalog/tests.json') | ConvertFrom-Json -Depth 100
$catalogueEntry=@($testCatalogue.tests | Where-Object id -ceq 'static.mir4-development-contracts')
if($catalogueEntry.Count -ne 1) { throw '[mir4-development-catalogue-entry]' }
$requiredCatalogueInputs=@(
  'governance/repository/development-epoch-v1.json',
  'source-identity',
  'tests/repository/Test-MIR4DevelopmentContracts.ps1',
  'source/**', 'targets/**', 'tools/mir/**', 'tools/lib/**',
  'tools/mir.ps1', 'tools/commands/**', 'scripts/**',
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
if([string]$catalogueEntry[0].command -cne './tests/repository/Test-MIR4DevelopmentContracts.ps1 -ExpectedSourceCommit <source-commit> -ExpectedSourceTree <source-tree> -ExpectedPackageSourceSha256 <package-source-sha256> -ReceiptPath <test-output>' -or
   $capturedArtifacts.Count -ne 1 -or
   [string]$capturedArtifacts[0].path_pattern -cne '<test-output>' -or
   [string]$capturedArtifacts[0].schema -cne 'contracts/repository/mir4-development-contracts-local-result-v1.schema.json' -or
   [string]$capturedArtifacts[0].kind -cne 'MIR4DevelopmentContractsLocalResultV1') {
  throw '[mir4-development-catalogue-captured-artifact]'
}
# Parse every current tooling and test module, including modules whose original
# decomposition receipt now belongs to the pinned historical source.
$toolingPathspecs=@(
  'tools/mir.ps1', ':(glob)tools/mir/**/*.ps1', ':(glob)tools/commands/**/*.ps1',
  ':(glob)tools/lib/**/*.ps1', ':(glob)scripts/**/*.ps1', ':(glob)tests/**/*.ps1'
)
$files=@(& git -C $repo ls-files --cached --others --exclude-standard -- @toolingPathspecs)
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
$actualCommit=(& git -C $repo rev-parse HEAD).Trim()
$actualTree=(& git -C $repo rev-parse 'HEAD^{tree}').Trim()
if([string]::IsNullOrWhiteSpace($ExpectedSourceCommit)) { $ExpectedSourceCommit=$actualCommit }
if([string]::IsNullOrWhiteSpace($ExpectedSourceTree)) { $ExpectedSourceTree=$actualTree }
if([string]::IsNullOrWhiteSpace($ExpectedPackageSourceSha256)) { $ExpectedPackageSourceSha256=$packageSourceFingerprint }
Assert-MIRDevelopmentContractsCommittedSource `
  -ActualCommit $actualCommit `
  -ActualTree $actualTree `
  -ActualPackageSourceSha256 $packageSourceFingerprint `
  -ExpectedCommit $ExpectedSourceCommit `
  -ExpectedTree $ExpectedSourceTree `
  -ExpectedPackageSourceSha256 $ExpectedPackageSourceSha256 `
  -PackageSourceDirty $packageSourceDirty `
  -SelectedInputsDirty $selectedInputsDirty `
  -RepositoryDirty $repositoryDirty
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
  $receiptPath=if([string]::IsNullOrWhiteSpace($ReceiptPath)) {
    $receiptRoot=Join-Path $repo 'build/results/validation/development-contracts'
    [IO.Directory]::CreateDirectory($receiptRoot)|Out-Null
    Join-Path $receiptRoot ("$receiptId.json")
  } else {
    $candidateReceiptPath=[IO.Path]::GetFullPath($ReceiptPath)
    $repoBoundary=[IO.Path]::GetFullPath($repo).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if(-not $candidateReceiptPath.StartsWith($repoBoundary,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-development-receipt-path-boundary]' }
    $receiptRelative=[IO.Path]::GetRelativePath($repo,$candidateReceiptPath).Replace('\','/')
    if($receiptRelative -notmatch '^build/results/assurance/evidence/static[.]mir4-development-contracts/[0-9A-F]{64}/work/[0-9a-f]{32}/test-output[.]json$') {
      throw '[mir4-development-receipt-path-worker-boundary]'
    }
    $receiptParent=Split-Path -Parent $candidateReceiptPath
    if([string]::IsNullOrWhiteSpace($receiptParent)) { throw '[mir4-development-receipt-path-parent]' }
    [IO.Directory]::CreateDirectory($receiptParent)|Out-Null
    $current=$repo
    foreach($segment in @($receiptRelative.Split('/') | Select-Object -SkipLast 1)) {
      $current=Join-Path $current $segment
      $item=Get-Item -LiteralPath $current -Force
      if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0) { throw '[mir4-development-receipt-path-reparse]' }
    }
    if((Test-Path -LiteralPath $candidateReceiptPath) -and ((Get-Item -LiteralPath $candidateReceiptPath -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0) { throw '[mir4-development-receipt-path-reparse]' }
    $candidateReceiptPath
  }
  $receipt=[ordered]@{
    schema=1
    kind='MIR4DevelopmentContractsLocalResultV1'
    status='passed'
    scope='current-source-and-four-target-determinism'
    source=[ordered]@{
      commit=$actualCommit
      tree=$actualTree
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
