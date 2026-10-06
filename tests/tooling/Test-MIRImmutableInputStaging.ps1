# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot = '',[switch]$NativeProbeOnly,[switch]$MaterialAuditInputsOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

. (Join-Path $RepoRoot 'tools/lib/validation/ImmutableInputStaging.ps1')
if($NativeProbeOnly -and $MaterialAuditInputsOnly){throw 'Select one focused immutable-input test mode.'}
if($NativeProbeOnly) { & (Join-Path $RepoRoot 'tests/tooling/Test-MIRNativeProbeResources.ps1') -RepoRoot $RepoRoot;return }

. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/ResourceGovernor.ps1')
$tempRoot = Resolve-MIR441RecoveryScratchPath -Path (Join-Path $RepoRoot 'build/tmp')
$fixtureRoot = Resolve-MIR441RecoveryScratchPath -Path (Join-Path $tempRoot ("mir-immutable-input-staging-{0}" -f [guid]::NewGuid().ToString('N')))
$expectedFixtureRoot = $fixtureRoot
$firstLease = $null
$secondLease = $null
$materialLease = $null
try {
  New-Item -ItemType Directory -Force -Path $fixtureRoot | Out-Null
  $sourceRoot = Join-Path $fixtureRoot 'verified-inputs'
  $runOne = Join-Path $fixtureRoot 'run-one'
  $runTwo = Join-Path $fixtureRoot 'run-two'
  New-Item -ItemType Directory -Force -Path $sourceRoot, $runOne, $runTwo | Out-Null
  $sourceOne = Join-Path $sourceRoot 'candidate.zip'
  $sourceTwo = Join-Path $sourceRoot 'bobplates_2.1.1.zip'
  [IO.File]::WriteAllText($sourceOne, 'candidate bytes', [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($sourceTwo, 'mod bytes', [Text.UTF8Encoding]::new($false))
  $hashOne = Get-MIRImmutableInputSha256 -Path $sourceOne
  $hashTwo = Get-MIRImmutableInputSha256 -Path $sourceTwo

  . (Join-Path $RepoRoot 'tests/support/MIRMaterialAuditInputs.ps1')
  $auditLibrary=Join-Path $fixtureRoot 'audit-library'
  New-Item -ItemType Directory -Path $auditLibrary | Out-Null
  $expectedArchives=[ordered]@{}
  $archivePaths=[ordered]@{}
  $expectedHashes=[ordered]@{}
  foreach($name in @('boblibrary','bobores','bobplates')){
    $file=$name+'_fixture.zip'
    $path=Join-Path $auditLibrary $file
    [IO.File]::WriteAllText($path,"small immutable $name input",[Text.UTF8Encoding]::new($false))
    $hash=Get-MIRImmutableInputSha256 $path
    $expectedArchives[$name]=[ordered]@{file=$file;sha256=$hash}
    $archivePaths[$name]=$file
    $expectedHashes[$name]=$hash
  }
  $auditConsumers=@(
    'Test-MIRBobTinProductionGain.ps1','Test-MIRBobTinMachineMatrix.ps1',
    'Test-MIRBobTinPersistedState.ps1','Test-MIRBobTinProgressionFrontier.ps1',
    'Test-MIRBobTinQualification.ps1','Test-MIRF200BobTinPersistedState.ps1'
  )
  foreach($consumer in $auditConsumers){
    $harnessPath=Join-Path $RepoRoot ('tests/runtime/'+$consumer)
    $tokens=$null;$parseErrors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($harnessPath,[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count -ne 0){throw "$consumer no longer parses"}
    $source=[IO.File]::ReadAllText($harnessPath)
    if($source -match 'Copy-Item\s+-LiteralPath\s+\$(candidateZip|path)\s+-Destination\s+(\$mods|\(Join-Path\s+\$mods)'){
      throw "$consumer restored archive copies"
    }
    $staging=[regex]::Matches($source,'(?m)^\$inputArchives=\[ordered\]@\{\}\r?\nforeach\([^\r\n]*\r?\n\$inputLease=New-MIRMaterialAuditInputLease[^\r\n]*')
    if($staging.Count -ne 1){throw "$consumer does not expose one consumed shared-input staging block"}
    $run=Join-Path $fixtureRoot ([IO.Path]::GetFileNameWithoutExtension($consumer))
    $mods=Join-Path $run 'mods'
    $candidateZip=$sourceOne;$bobMods=$auditLibrary
    New-Item -ItemType Directory -Path $run,$mods | Out-Null
    . ([scriptblock]::Create($staging[0].Value))
    $materialLease=$inputLease
    if($materialLease.record.inputs.Count -ne 4){throw "$consumer lost candidate or dependency inputs"}
    foreach($input in $materialLease.record.inputs){
      if($input.staging_mode -cne 'hardlink' -or
         (Get-MIRImmutableInputFileIdentity $input.source_path) -cne (Get-MIRImmutableInputFileIdentity $input.stage_path)){
        throw "$consumer duplicated archive data instead of linking the source file"
      }
    }
    [IO.File]::WriteAllText((Join-Path $mods 'mod-settings.dat'),'private writable settings',[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $mods 'mod-list.json'),'{"mods":[]}',[Text.UTF8Encoding]::new($false))
    if(Test-Path -LiteralPath (Join-Path $auditLibrary 'mod-settings.dat')){throw "$consumer wrote settings into the dependency library"}
    $terminal=Complete-MIRImmutableInputLease -Lease $materialLease -Outcome passed
    $null=Assert-MIRImmutableInputTerminalReceipt -Receipt $terminal
    $materialLease=$null
    foreach($input in $terminal.inputs){
      if((Get-MIRImmutableInputSha256 $input.source_path) -cne $input.expected_sha256){throw "$consumer changed an input"}
    }
    # Retire only this completed synthetic run, then prove the shared bytes survive.
    $null=Assert-MIRImmutableInputLeaseReclaimable -RunRoot $run -Context $consumer
    $null=Assert-MIRImmutableInputPathWithin -Path $run -Root $fixtureRoot -Context 'Synthetic completed staging'
    Remove-Item -LiteralPath $run -Recurse
    foreach($input in $terminal.inputs){
      if(-not (Test-Path -LiteralPath $input.source_path -PathType Leaf)){throw "$consumer cleanup removed a source"}
    }
    $completion=[regex]::Match($source,'\$terminalInputStaging=Complete-MIRImmutableInputLease -Lease \$inputLease -Outcome passed')
    $binding=[regex]::Match($source,"\`$receipt\['input_staging'\]=\`$terminalInputStaging")
    if(-not $completion.Success -or -not $binding.Success -or $completion.Index -ge $binding.Index){
      throw "$consumer lost terminal input custody from its result"
    }
  }
  # Execute each consumed block with a real failed hard-link operation. Any copy
  # attempt is a failure, including the general adapter's default path below.
  $copyAttempts=0
  function New-Item {
    [CmdletBinding()]
    param([string]$ItemType,[string[]]$Path,[string]$Target,[switch]$Force)
    if($ItemType -ceq 'HardLink'){throw 'controlled unavailable hardlink'}
    Microsoft.PowerShell.Management\New-Item @PSBoundParameters
  }
  function Copy-Item {
    [CmdletBinding()]
    param([string[]]$LiteralPath,[string]$Destination,[switch]$Force)
    $script:copyAttempts++
    throw 'archive copy fallback attempted'
  }
  try {
    foreach($consumer in $auditConsumers){
      $source=[IO.File]::ReadAllText((Join-Path $RepoRoot ('tests/runtime/'+$consumer)))
      $staging=[regex]::Match($source,'(?m)^\$inputArchives=\[ordered\]@\{\}\r?\nforeach\([^\r\n]*\r?\n\$inputLease=New-MIRMaterialAuditInputLease[^\r\n]*')
      $run=Join-Path $fixtureRoot ('failed-'+[IO.Path]::GetFileNameWithoutExtension($consumer))
      $mods=Join-Path $run 'mods';$candidateZip=$sourceOne;$bobMods=$auditLibrary
      New-Item -ItemType Directory -Path $run,$mods | Out-Null
      $rejected=$false
      try { . ([scriptblock]::Create($staging.Value)) } catch {
        $rejected=$_.Exception.Message -match 'requires a verified hard link.*controlled unavailable hardlink'
      }
      if(-not $rejected){throw "$consumer did not refuse an unavailable hardlink"}
      if(@(Get-ChildItem -LiteralPath $mods -File).Count -ne 0){throw "$consumer left copied payloads after a failed link"}
      $failed=Get-Content -LiteralPath (Join-Path $run 'mir-immutable-input-lease.json') -Raw | ConvertFrom-Json
      if($failed.state -cne 'staging-failed' -or $failed.require_hard_links -ne $true){throw "$consumer lost strict failure custody"}
    }
    $defaultRun=Join-Path $fixtureRoot 'default-no-copy'
    New-Item -ItemType Directory -Path $defaultRun | Out-Null
    $rejected=$false
    try {
      $materialLease=New-MIRImmutableInputLease -RunRoot $defaultRun -StageDirectory (Join-Path $defaultRun 'mods') -Inputs @(
        [ordered]@{source_path=$sourceOne;file_name='candidate.zip';expected_sha256=$hashOne;role='candidate';identity=@{};provenance=@{kind='fixture'};immutable=$true}
      )
    } catch { $rejected=$_.Exception.Message -match 'requires a verified hard link.*controlled unavailable hardlink' }
    if(-not $rejected -or $copyAttempts -ne 0){throw 'Default immutable staging retained an implicit copy fallback'}
  } finally {
    Remove-Item Function:New-Item
    Remove-Item Function:Copy-Item
  }
  Write-Host '[ok] six Bob Tin blocks consume 24 same-file aliases, preserve private controls and retire completed staging; seven unavailable-link cases refuse copies.'
  if($MaterialAuditInputsOnly){return}

  $firstLease = New-MIRImmutableInputLease -RunRoot $runOne -StageDirectory (Join-Path $runOne 'mods') -Inputs @(
    [ordered]@{
      source_path = $sourceOne
      file_name = 'more-infinite-research_4.2.21000.zip'
      expected_sha256 = $hashOne
      role = 'candidate'
      identity = [ordered]@{ target = 'f210'; materializer = 'TargetMaterializer'; sha256 = $hashOne }
      provenance = [ordered]@{ kind = 'fresh-materializer-output'; source = 'fixture' }
      immutable = $true
    },
    [ordered]@{
      source_path = $sourceTwo
      file_name = 'bobplates_2.1.1.zip'
      expected_sha256 = $hashTwo
      role = 'dependency-mod'
      identity = [ordered]@{ name = 'bobplates'; version = '2.1.1'; sha256 = $hashTwo }
      provenance = [ordered]@{ kind = 'verified-mod-archive'; source = 'fixture' }
      immutable = $true
    }
  )
  if ((Get-MIRImmutableInputLeaseLiveness -RunRoot $runOne).active -ne $true) {
    throw 'Immutable input lease did not present as live while its lock was held.'
  }
  if (@($firstLease.record.inputs | Where-Object { $_.staging_mode -ne 'hardlink' }).Count -ne 0) {
    throw 'Same-volume verified inputs did not use a proven hard-link mode.'
  }
  foreach ($input in @($firstLease.record.inputs)) {
    if ($input.hardlink_file_identity.verified -ne $true -or
        $input.hardlink_file_identity.source -cne $input.hardlink_file_identity.staged) {
      throw 'Hard-link staging did not record equal native file identities.'
    }
  }
  $writeBlocked = $false
  try {
    [IO.File]::WriteAllText((Join-Path $runOne 'mods/more-infinite-research_4.2.21000.zip'), 'mutation')
  } catch [IO.IOException] {
    $writeBlocked = $true
  }
  if (-not $writeBlocked) { throw 'The active immutable lease allowed a staged input write.' }
  $capturedReceipt = Get-MIRImmutableInputLeaseReceipt -Lease $firstLease
  if ($capturedReceipt.state -cne 'receipt-captured' -or $capturedReceipt.inputs_sha256_match -ne $true) {
    throw 'Immutable input receipt was not captured while the no-write lease remained active.'
  }
  if (-not (Get-MIRImmutableInputLeaseLiveness -RunRoot $runOne).active) {
    throw 'Immutable input receipt capture released the active lease before the caller completed its receipt.'
  }
  $firstReceipt = Complete-MIRImmutableInputLease -Lease $firstLease
  $firstLease = $null
  if ($firstReceipt.state -cne 'completed' -or $firstReceipt.inputs_sha256_match -ne $true) {
    throw 'Completed immutable input lease did not preserve exact pre/post hashes.'
  }
  $completedLiveness = Get-MIRImmutableInputLeaseLiveness -RunRoot $runOne
  if ($completedLiveness.active -or $completedLiveness.ambiguous -or $completedLiveness.state -cne 'completed' -or $null -ne $completedLiveness.record.owner_pid -or [string]::IsNullOrWhiteSpace([string]$completedLiveness.record.completed_owner_pid)) {
    throw 'Completed immutable input lease did not clear active ownership into an unambiguous terminal record.'
  }
  $completedReclaimable = Assert-MIRImmutableInputLeaseReclaimable -RunRoot $runOne -Context 'completed immutable-input fixture'
  if ($completedReclaimable.present -ne $true -or $completedReclaimable.state -cne 'completed') {
    throw 'Completed immutable input lease was not the sole reclaimable terminal custody state.'
  }

  $secondLease = New-MIRImmutableInputLease -RunRoot $runTwo -StageDirectory (Join-Path $runTwo 'mods') -ForceCopy -Inputs @(
    [ordered]@{
      source_path = $sourceOne
      file_name = 'more-infinite-research_4.2.21000.zip'
      expected_sha256 = $hashOne
      role = 'candidate'
      identity = [ordered]@{ target = 'f210'; materializer = 'TargetMaterializer'; sha256 = $hashOne }
      provenance = [ordered]@{ kind = 'fresh-materializer-output'; source = 'fixture' }
      immutable = $true
    }
  )
  $copyInput = @($secondLease.record.inputs)[0]
  if ($copyInput.staging_mode -cne 'copy' -or $copyInput.hardlink_fallback_reason -cne 'copy mode was explicitly selected') {
    throw 'Forced copy staging did not record its bounded fallback reason.'
  }
  $secondReceipt = Complete-MIRImmutableInputLease -Lease $secondLease
  $secondLease = $null
  if ($secondReceipt.inputs_sha256_match -ne $true) { throw 'Copy fallback did not preserve the exact input hash.' }
  $secondInput = @($secondReceipt.inputs)[0]
  [IO.File]::WriteAllText([string]$secondInput.stage_path, 'mutated only after the terminal receipt released its lease', [Text.UTF8Encoding]::new($false))
  if ((Get-MIRImmutableInputSha256 -Path ([string]$secondInput.stage_path)) -ceq [string]$secondInput.expected_sha256) {
    throw 'Post-completion mutation fixture did not change the unlocked private copy.'
  }
  $receiptArtifact = ConvertTo-MIRImmutableInputArtifact -Receipt $secondReceipt -Input $secondInput -Locator 'run-two/mods/more-infinite-research_4.2.21000.zip'
  if ($receiptArtifact.raw_sha256 -cne $hashOne -or $receiptArtifact.bytes -ne ([Text.UTF8Encoding]::new($false).GetByteCount('candidate bytes'))) {
    throw 'Immutable artifact identity was reread from bytes changed after terminal receipt capture.'
  }

  $mismatchedCandidate = Join-Path $fixtureRoot 'mismatched-f200-candidate.zip'
  [IO.File]::WriteAllText($mismatchedCandidate, 'not the current F200 materialization', [Text.UTF8Encoding]::new($false))
  $f200Harness = Join-Path $RepoRoot 'tests/runtime/Test-MIRF200BobTinProductionGain.ps1'
  $bindingOutput = @(& pwsh -NoProfile -File $f200Harness -RepoRoot $RepoRoot -CandidateZip $mismatchedCandidate -FactorioBin (Join-Path $fixtureRoot 'must-not-resolve-factorio.exe') -BobModsDir (Join-Path $fixtureRoot 'must-not-resolve-bob-mods') -VerifyCandidateBindingOnly 2>&1)
  $bindingExitCode = $LASTEXITCODE
  # The non-zero child exit is the expected negative assertion, not this
  # enclosing test's process result.
  $global:LASTEXITCODE = 0
  if ($bindingExitCode -eq 0) { throw 'F200 production-gain harness accepted a caller candidate whose bytes differ from current materialization.' }
  $bindingText = $bindingOutput | Out-String
  if ($bindingText -notmatch 'supplied[.]candidate[.]sha256 differs') { throw "F200 production-gain mismatch was not rejected by its candidate binding: $bindingText" }
  if ($bindingText -match 'must-not-resolve-factorio|must-not-resolve-bob-mods') { throw "F200 candidate-binding-only path reached an engine or dependency lookup: $bindingText" }

  $aluminiumHarness = Join-Path $RepoRoot 'tests/runtime/Test-MIRA06BobAluminiumQualification.ps1'
  $aluminiumBindingOutput = @(& pwsh -NoProfile -File $aluminiumHarness -RepoRoot $RepoRoot -CandidateZip $mismatchedCandidate -FactorioBin (Join-Path $fixtureRoot 'must-not-resolve-factorio.exe') -BobModsDir (Join-Path $fixtureRoot 'must-not-resolve-bob-mods') -VerifyCandidateBindingOnly 2>&1)
  $aluminiumBindingExitCode = $LASTEXITCODE
  $global:LASTEXITCODE = 0
  if ($aluminiumBindingExitCode -eq 0) { throw 'A06 Aluminium harness accepted supplied bytes that differ from current F210 materialization.' }
  $aluminiumBindingText = $aluminiumBindingOutput | Out-String
  if ($aluminiumBindingText -notmatch 'supplied candidate bytes differ') { throw "A06 Aluminium mismatch was not rejected by its candidate binding: $aluminiumBindingText" }
  if ($aluminiumBindingText -match 'must-not-resolve-factorio|must-not-resolve-bob-mods') { throw "A06 Aluminium candidate-binding-only path reached an engine or dependency lookup: $aluminiumBindingText" }

  $materialsHarness = Join-Path $RepoRoot 'tests/runtime/Test-MIR4A05K2Materials.ps1'
  $materialsBindingOutput = @(& pwsh -NoProfile -File $materialsHarness -RepoRoot $RepoRoot -CandidateZip $mismatchedCandidate -FactorioBin (Join-Path $fixtureRoot 'must-not-resolve-factorio.exe') -VerifyCandidateBindingOnly 2>&1)
  $materialsBindingExitCode = $LASTEXITCODE
  $global:LASTEXITCODE = 0
  if ($materialsBindingExitCode -eq 0) { throw 'A05 K2 Materials harness accepted supplied bytes that differ from current F210 materialization.' }
  $materialsBindingText = $materialsBindingOutput | Out-String
  if ($materialsBindingText -notmatch 'supplied candidate bytes differ') { throw "A05 K2 Materials mismatch was not rejected by its candidate binding: $materialsBindingText" }
  if ($materialsBindingText -match 'must-not-resolve-factorio') { throw "A05 K2 Materials candidate-binding-only path reached an engine lookup: $materialsBindingText" }

  $adoptedA06Harnesses = @(
    'tests/runtime/Test-MIRA06BobLeadQualification.ps1',
    'tests/runtime/Test-MIRA06BobGoldQualification.ps1',
    'tests/runtime/Test-MIRA06BobAluminiumQualification.ps1'
  )
  foreach ($relativeHarness in $adoptedA06Harnesses) {
    $harnessPath = Join-Path $RepoRoot $relativeHarness
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($harnessPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if (@($parseErrors).Count -ne 0) {
      throw "$relativeHarness no longer parses after immutable-input adoption: $(@($parseErrors)[0].Message)"
    }
    $harnessSource = [IO.File]::ReadAllText($harnessPath)
    foreach ($requiredText in @(
      'New-MIRImmutableInputLease',
      'Get-MIRImmutableInputLeaseReceipt',
      'Complete-MIRImmutableInputLease',
      'input_staging=$inputStaging'
    )) {
      if (-not $harnessSource.Contains($requiredText, [StringComparison]::Ordinal)) {
        throw "$relativeHarness omitted required immutable-input contract text: $requiredText"
      }
    }
    if ($harnessSource -match 'Copy-Item\s+-LiteralPath\s+\$candidateZip\s+-Destination\s+\$mods' -or
        $harnessSource -match 'Copy-Item\s+-LiteralPath\s+\$source\s+-Destination\s+\$mods') {
      throw "$relativeHarness restored private copies of an immutable candidate or dependency archive."
    }
  }

  $adoptedK2Harnesses = @(
    'tests/runtime/Test-MIR4A03K2K2SOIntake.ps1',
    'tests/runtime/Test-MIR4A05K2Materials.ps1',
    'tests/runtime/Test-MIR4A05K203Imersite.ps1'
  )
  foreach ($relativeHarness in $adoptedK2Harnesses) {
    $harnessPath = Join-Path $RepoRoot $relativeHarness
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($harnessPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if (@($parseErrors).Count -ne 0) {
      throw "$relativeHarness no longer parses after immutable-input adoption: $(@($parseErrors)[0].Message)"
    }
    $harnessSource = [IO.File]::ReadAllText($harnessPath)
    foreach ($requiredText in @(
      'ImmutableInputStaging.ps1',
      'New-MIRImmutableInputLease',
      'Complete-MIRImmutableInputLease',
      'ConvertTo-MIRImmutableInputArtifact',
      'input_staging=$terminalInputStaging',
      'Outcome failed'
    )) {
      if (-not $harnessSource.Contains($requiredText, [StringComparison]::Ordinal)) {
        throw "$relativeHarness omitted required immutable-input contract text: $requiredText"
      }
    }
    if ($harnessSource -match 'Copy-Item\s+-LiteralPath\s+\$candidate\s+-Destination\s+\$mods' -or
        $harnessSource -match 'Copy-Item\s+-LiteralPath\s+\$source\s+-Destination\s+\$mods') {
      throw "$relativeHarness restored private copies of an immutable candidate or dependency archive."
    }
    if ($harnessSource -match 'New-Item\s+-ItemType\s+(?:SymbolicLink|Junction)') {
      throw "$relativeHarness introduced a whole-directory link instead of immutable archive staging."
    }
    $terminalCompletion = [regex]::Match($harnessSource, '\$terminalInputStaging\s*=\s*Complete-MIRImmutableInputLease\s+-Lease\s+\$inputLease')
    $terminalBinding = [regex]::Match($harnessSource, 'input_staging\s*=\s*\$terminalInputStaging')
    if (-not $terminalCompletion.Success -or -not $terminalBinding.Success -or $terminalCompletion.Index -gt $terminalBinding.Index) {
      throw "$relativeHarness did not persist the terminal immutable-input lease receipt in its result."
    }
    if ($harnessSource -match 'input_staging\s*=\s*\$inputStaging') {
      throw "$relativeHarness persisted an earlier receipt-captured lease state instead of the terminal receipt."
    }
    if ($relativeHarness -ne 'tests/runtime/Test-MIR4A03K2K2SOIntake.ps1' -and -not $harnessSource.Contains('Assert-MIRImmutableInputLeaseReclaimable', [StringComparison]::Ordinal)) {
      throw "$relativeHarness deletes a fixed K2 case root without checking immutable-input lease liveness."
    }
    $settingsCopy = if ($relativeHarness -ceq 'tests/runtime/Test-MIR4A03K2K2SOIntake.ps1') {
      'Copy-Item -LiteralPath $settingsSourcePath -Destination (Join-Path $mods $settingsSourceItem.Name)'
    } else {
      "Copy-Item -LiteralPath `$settings -Destination (Join-Path `$mods 'mod-settings.dat')"
    }
    if (-not $harnessSource.Contains($settingsCopy, [StringComparison]::Ordinal)) {
      throw "$relativeHarness must retain a private copy of mutable mod-settings.dat."
    }
  }

  $stagingLibraryRelative = 'tools/lib/validation/ImmutableInputStaging.ps1'
  $governedK2Tests = @(
    'runtime.k2-k2so-f210-intake',
    'static.mir4-a05-k2-03-imersite-closure',
    'static.mir4-a05-k2-materials-closure'
  )
  $testRegistry = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'validation/tests.yml') | ConvertFrom-Json -Depth 100
  $stagingDefinition = @($testRegistry.tests | Where-Object { [string]$_.id -ceq 'static.immutable-input-staging' })
  $stagingDirectInputs = @(
    'tests/runtime/Test-MIR4A05K2Materials.ps1',
    'targets/f210/composition.json'
  )
  if ($stagingDefinition.Count -ne 1 -or @($stagingDirectInputs | Where-Object { $_ -cnotin @($stagingDefinition[0].inputs | ForEach-Object { [string]$_ }) }).Count -ne 0) {
    throw 'Immutable-input staging proof does not fingerprint its F210 Materials binding-negative inputs.'
  }
  foreach ($testId in $governedK2Tests) {
    $definition = @($testRegistry.tests | Where-Object { [string]$_.id -ceq $testId })
    if ($definition.Count -ne 1 -or $stagingLibraryRelative -cnotin @($definition[0].inputs | ForEach-Object { [string]$_ })) {
      throw "$testId does not fingerprint the immutable-input staging implementation."
    }
  }
  $assurancePolicy = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot '.mir/assurance.json') | ConvertFrom-Json -Depth 100
  $stagingImpact = @($assurancePolicy.classes | Where-Object { [string]$_.id -ceq 'k2-immutable-input-staging' })
  $expectedImpactTests = @('runtime.k2-k2so-f210-intake', 'static.immutable-input-staging', 'static.mir4-a05-k2-03-imersite-closure', 'static.mir4-a05-k2-materials-closure')
  if ($stagingImpact.Count -ne 1 -or
      '^tools/lib/validation/ImmutableInputStaging[.]ps1$' -cnotin @($stagingImpact[0].patterns | ForEach-Object { [string]$_ }) -or
      (@($stagingImpact[0].tests | ForEach-Object { [string]$_ } | Sort-Object) -join "`n") -cne (($expectedImpactTests | Sort-Object) -join "`n")) {
    throw 'Immutable-input staging changes do not select the complete governed K2 proof set.'
  }

  $failedRun = Join-Path $fixtureRoot 'failed-run'
  New-Item -ItemType Directory -Force -Path $failedRun | Out-Null
  $rejected = $false
  try {
    New-MIRImmutableInputLease -RunRoot $failedRun -StageDirectory (Join-Path $failedRun 'mods') -Inputs @(
      [ordered]@{
        source_path = $sourceOne
        file_name = 'candidate.zip'
        expected_sha256 = ('0' * 64)
        role = 'candidate'
        identity = [ordered]@{ target = 'f210' }
        provenance = [ordered]@{ kind = 'fixture' }
        immutable = $true
      }
    ) | Out-Null
  } catch {
    $rejected = $true
  }
  if (-not $rejected) { throw 'Immutable input staging accepted an incorrect source hash.' }
  $failedRecord = Get-Content -Raw -LiteralPath (Join-Path $failedRun 'mir-immutable-input-lease.json') | ConvertFrom-Json
  if ($failedRecord.state -cne 'staging-failed') { throw 'Failed staging did not leave a recovery record.' }
  $failedReclaimRejected = $false
  try {
    Assert-MIRImmutableInputLeaseReclaimable -RunRoot $failedRun -Context 'failed immutable-input fixture' | Out-Null
  } catch {
    $failedReclaimRejected = $_.Exception.Message -match 'retains immutable-input custody'
  }
  if (-not $failedReclaimRejected) { throw 'Failed immutable input custody was considered reclaimable.' }

  $forgedRun = Join-Path $fixtureRoot 'forged-completed-run'
  New-Item -ItemType Directory -Force -Path $forgedRun | Out-Null
  $forgedLease = New-MIRImmutableInputLease -RunRoot $forgedRun -StageDirectory (Join-Path $forgedRun 'mods') -ForceCopy -Inputs @(
    [ordered]@{
      source_path = $sourceOne
      file_name = 'candidate.zip'
      expected_sha256 = $hashOne
      role = 'candidate'
      identity = [ordered]@{ target = 'f210'; sha256 = $hashOne }
      provenance = [ordered]@{ kind = 'fixture' }
      immutable = $true
    }
  )
  $null = Complete-MIRImmutableInputLease -Lease $forgedLease -Outcome failed
  $forgedRecordPath = Join-Path $forgedRun 'mir-immutable-input-lease.json'
  $forgedRecord = Get-Content -Raw -LiteralPath $forgedRecordPath | ConvertFrom-Json -Depth 20
  $forgedRecord.state = 'completed'
  $forgedRecord.outcome = 'passed'
  $forgedRecord.inputs_sha256_match = $true
  [IO.File]::WriteAllText($forgedRecordPath, (($forgedRecord | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
  $forgedReclaimRejected = $false
  try {
    Assert-MIRImmutableInputLeaseReclaimable -RunRoot $forgedRun -Context 'forged completed immutable-input fixture' | Out-Null
  } catch {
    $forgedReclaimRejected = $_.Exception.Message -match 'retains immutable-input custody'
  }
  if (-not $forgedReclaimRejected) { throw 'A forged completed receipt was considered reclaimable.' }

  $orphanLockRun = Join-Path $fixtureRoot 'orphan-lock-run'
  New-Item -ItemType Directory -Force -Path $orphanLockRun | Out-Null
  $orphanLock = [IO.File]::Open((Join-Path $orphanLockRun 'mir-immutable-input-lease.lock'), [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  try {
    $orphanLive = Get-MIRImmutableInputLeaseLiveness -RunRoot $orphanLockRun
    if (-not $orphanLive.present -or -not $orphanLive.active -or $orphanLive.state -cne 'missing-record') {
      throw 'A lease lock without a record was not treated as active and unsafe.'
    }
  } finally {
    $orphanLock.Dispose()
  }
  $orphanRecovered = Get-MIRImmutableInputLeaseLiveness -RunRoot $orphanLockRun
  if (-not $orphanRecovered.present -or $orphanRecovered.active -or $orphanRecovered.state -cne 'missing-record') {
    throw 'An interrupted lease lock was not retained for recovery classification.'
  }
  $orphanReclaimRejected = $false
  try {
    Assert-MIRImmutableInputLeaseReclaimable -RunRoot $orphanLockRun -Context 'orphaned immutable-input fixture' | Out-Null
  } catch {
    $orphanReclaimRejected = $_.Exception.Message -match 'retains immutable-input custody'
  }
  if (-not $orphanReclaimRejected) { throw 'Orphaned immutable input custody was considered reclaimable.' }
} finally {
  if($null -ne $materialLease -and -not $materialLease.closed){
    try { Complete-MIRImmutableInputLease -Lease $materialLease -Outcome failed | Out-Null } catch {}
  }
  if ($null -ne $firstLease -and -not $firstLease.closed) {
    try { Complete-MIRImmutableInputLease -Lease $firstLease -Outcome failed | Out-Null } catch {}
  }
  if ($null -ne $secondLease -and -not $secondLease.closed) {
    try { Complete-MIRImmutableInputLease -Lease $secondLease -Outcome failed | Out-Null } catch {}
  }
  if (Test-Path -LiteralPath $fixtureRoot) {
    $resolved = Resolve-MIR441RecoveryScratchPath -Path $fixtureRoot
    if (-not $resolved.Equals($expectedFixtureRoot, [StringComparison]::OrdinalIgnoreCase) -or
      -not (Split-Path -Parent $resolved).Equals($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
      (Split-Path -Leaf $resolved) -cnotmatch '^mir-immutable-input-staging-[0-9a-f]{32}$') {
      throw "Immutable input fixture does not match its allocated project scratch path: $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}

Write-Host '[ok] immutable input staging proves hard-link identity, no-write lease liveness, copy fallback, exact hashes, and failure retention.'
& (Join-Path $RepoRoot 'tests/tooling/Test-MIRNativeProbeResources.ps1') -RepoRoot $RepoRoot
