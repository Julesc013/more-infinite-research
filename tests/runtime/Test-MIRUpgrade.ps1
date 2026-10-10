# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path,
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$FromZip,
  [Parameter(Mandatory)][string]$ToZip,
  [string]$SelectedReleaseManifest = '',
  [string]$SourceMaterializationPath = '',
  [string]$SelectedTarget = '',
  [ValidateSet('4.2.1','4.2.2')][string]$SourceVersion = '4.2.1',
  [switch]$SpaceIsFake,
  [string]$K2ImersiteInputProfile = '',
  [ValidateSet(0,3)][int]$K2ImersiteCap = 3,
  [string]$PublishedMaintenancePredecessorManifestPath = '',
  [string[]]$LocalModLibraryDirs = @(),
  [switch]$PrepareInputsOnly,
  [string]$FromVersion = "3.0.5",
  [string]$ToVersion = "3.1.0",
  [string]$FixtureName = "assert-upgrade-3-0-5-to-3-1-0",
  [ValidateSet("", "base-default", "space-age-native-owner", "automatic-family-creation", "base-continuations", "mod-set-configuration-change", "affected-planet-discovery")]
  [string]$Archetype = "",
  [string[]]$SourceOnlyFixtureNames = @(),
  [string]$OutputPath = "",
  [string]$WorkRoot = "",
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB = 0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB = 120,
  [ValidateSet('OnFailure','Always','Never')][string]$Retention = 'Always'
)
# Canonical validation scripts live three levels below the repository root.
# Keep the former scripts/ base explicit while tooling internals complete L5.
$MirRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "../..")).Path
$MirLegacyScriptRoot = Join-Path $MirRepoRoot "scripts"

$ErrorActionPreference = "Stop"
. (Join-Path $RepoRoot "tools\lib\validation\FactorioProcess.ps1")
. (Join-Path $RepoRoot 'tools/lib/compatibility/FactorioRunner.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/Common.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/release/readiness/ResourceGovernor.ps1')

function Resolve-MIRUpgradeManifestVersion {
  param([Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$CandidatePath,[string]$Target='')
  $manifest=Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json -Depth 100
  if ($manifest.kind -cin @('MIR42FourTargetDeterministicCandidateManifestV1','MIR42FourTargetDeterministicCandidateManifestV2','MIR42FourTargetDeterministicCandidateManifestV3')) {
    . (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
    $candidate=Get-MIR42ExactFourTargetCandidate -RepoRoot $RepoRoot -CandidateManifestPath $ManifestPath
    $rows=@($candidate.targets | Where-Object {
      [IO.Path]::GetFullPath([string]$_.archive_path) -ceq [IO.Path]::GetFullPath($CandidatePath) -and
      (-not $Target -or $_.target -ceq $Target)
    })
    if ($rows.Count -ne 1) { throw '[mir-upgrade-manifest-target] Candidate must match exactly one frozen construction target.' }
    return [string]$rows[0].distribution_version
  }
  . (Join-Path $RepoRoot 'tools/lib/validation/MIR4DistributionIdentity.ps1')
  $sourceVersion=Get-MIR4FinalManifestSourceVersion -Manifest $manifest
  $parts=$sourceVersion.Split('.');$minor=[int]$parts[1];$patch=[int]$parts[2]
  $filename=Split-Path -Leaf $CandidatePath
  $rows=@($manifest.targets | Where-Object { $_.filename -ceq $filename -and (-not $Target -or $_.target -ceq $Target) })
  if ($rows.Count -ne 1) { throw '[mir-upgrade-manifest-target] Candidate must match exactly one selected target.' }
  $row=$rows[0]
  if ($row.target -notmatch '^f(?<code>210|200|110|100|017|016|015|014|013)$') { throw '[mir-upgrade-manifest-target]' }
  $code=[string]$Matches.code
  $identity=New-MIR4DistributionIdentityProjection -DistributionTargetCode $code -SourceMinor $minor -SourcePatch $patch -DistributionVersion ([string]$row.distribution_version)
  if ($identity.package_name -cne $filename -or (Get-FileHash -LiteralPath $CandidatePath -Algorithm SHA256).Hash -cne $row.sha256) {
    throw '[mir-upgrade-manifest-package-hash] Candidate identity or hash differs from the selected manifest.'
  }
  $archive=[IO.Compression.ZipFile]::OpenRead($CandidatePath)
  try {
    $expectedRoot='more-infinite-research_'+$identity.distribution_version+'/'
    $entries=@($archive.Entries | Where-Object FullName -ceq ($expectedRoot+'info.json'))
    if ($entries.Count -ne 1) { throw '[mir-upgrade-manifest-package-info]' }
    $reader=[IO.StreamReader]::new($entries[0].Open())
    try { $info=$reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    $lines=@{'210'='2.1';'200'='2.0';'110'='1.1';'100'='1.0';'017'='0.17';'016'='0.16';'015'='0.15';'014'='0.14';'013'='0.13'}
    if ($info.name -cne 'more-infinite-research' -or $info.version -cne $identity.distribution_version -or $info.factorio_version -cne $lines[$code]) { throw '[mir-upgrade-manifest-package-info]' }
  } finally { $archive.Dispose() }
  return [string]$identity.distribution_version
}

function Resolve-MIR42UpgradePredecessorReaderVersion {
  param([Parameter(Mandatory)][string]$Target,[Parameter(Mandatory)][string]$FromVersion,
    [ValidateSet('4.2.1','4.2.2')][string]$SourceVersion='4.2.1')
  if($Target-cnotmatch '^f(?<code>210|200|110|100|017|016|015|014|013)$'){throw '[mir42-upgrade-predecessor-target]'}
  $code=$Matches.code
  if($FromVersion-cnotmatch ('^4[.]2[.]'+$code+'(?<patch>00|01)$')){throw '[mir42-upgrade-predecessor-version]'}
  $patch=[int]$Matches.patch
  if($patch-ge([version]$SourceVersion).Build){throw '[mir42-upgrade-predecessor-version]'}
  # Reuse the existing exact published-custody reader for that predecessor.
  # This selects its frozen release contract; the actual candidate retains
  # SourceVersion, its current materialization and its CCC02 identity.
  return '4.2.'+($patch+1)
}

function Assert-MIR421CurrentUpgradeInputMode {
  param([string]$Target,[string]$FromVersion,[string]$ToVersion,[string]$FixtureName,
    [string]$Archetype,[bool]$SpaceIsFake,[string[]]$SourceOnlyFixtureNames=@(),
    [string]$SelectedReleaseManifest,[string]$PublishedPredecessorManifest,[string]$Retention,
    [string]$K2ImersiteInputProfile='',
    [ValidateSet('4.2.1','4.2.2')][string]$SourceVersion='4.2.1')
  if ($Target -cnotin @('f210','f200') -or $SelectedReleaseManifest -or
      -not $PublishedPredecessorManifest -or $Retention -cne 'Always') {
    throw '[mir421-current-upgrade-input-mode]'
  }
  $code=$Target.Substring(1)
  $toPatch=([version]$SourceVersion).Build
  $fromPatches=if($SourceVersion-ceq'4.2.2'){@(0,1)}else{@(0)}
  $allowedFrom=@($fromPatches|ForEach-Object {'4.2.'+$code+$_.ToString('00')})
  if ($FromVersion -cnotin $allowedFrom -or $ToVersion -cne ('4.2.'+$code+$toPatch.ToString('00')) -or $SourceOnlyFixtureNames.Count) {
    throw '[mir421-current-upgrade-transition]'
  }
  if ($K2ImersiteInputProfile -or $FixtureName -cin @('assert-upgrade-k2-imersite-4-2-21000-to-4-2-21001','assert-upgrade-k2-imersite-4-2-21001-to-4-2-21002')) {
    if (-not $K2ImersiteInputProfile) { throw '[mir421-k2-upgrade-inputs-required]' }
    Assert-MIR421K2UpgradeTransition -Target $Target -FromVersion $FromVersion -ToVersion $ToVersion -FixtureName $FixtureName -Archetype $Archetype -SpaceIsFake $SpaceIsFake -SourceOnlyFixtureNames $SourceOnlyFixtureNames -SourceVersion $SourceVersion
  } elseif ($SpaceIsFake) {
    $null=Get-MIR421SpaceFakeUpgradeDescriptor -Target $Target -FromVersion $FromVersion -ToVersion $ToVersion -FixtureName $FixtureName -Archetype $Archetype -SourceVersion $SourceVersion
  } elseif ($Archetype-ceq'space-age-native-owner') {
    if($Target-cne'f210'-or$SourceVersion-cne'4.2.2'-or$FixtureName-cne'assert-upgrade-4-0-21000-to-4-1-21000'){
      throw '[mir421-current-upgrade-scenario]'
    }
  } elseif ($FixtureName -cne "assert-upgrade-4-0-${code}00-to-4-1-${code}00" -or $Archetype -cnotin @('','base-default')) {
    throw '[mir421-current-upgrade-scenario]'
  }
}

function Resolve-MIRHistoricalUpgradeTransition {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$FromVersion,
    [Parameter(Mandatory)][string]$ToVersion
  )
  $targets = @{
    '017' = [ordered]@{ line='0.17'; terminal='1.7.9'; infinite_technology='mining-productivity-4' }
    '016' = [ordered]@{ line='0.16'; terminal='1.6.9'; infinite_technology='mining-productivity-16' }
    '015' = [ordered]@{ line='0.15'; terminal='1.5.9'; infinite_technology='mining-productivity-16' }
    '014' = [ordered]@{ line='0.14'; terminal='1.4.9'; infinite_technology='' }
    '013' = [ordered]@{ line='0.13'; terminal='1.3.9'; infinite_technology='' }
  }
  $failure = 'MIR historical upgrade specialization requires an exact terminal predecessor or an earlier same-target maintenance version and matching 4.2 target version.'
  if ($ToVersion -cnotmatch '^4[.]2[.](?<target>017|016|015|014|013)(?<patch>[0-9]{2})$') { throw $failure }
  $code = [string]$Matches.target
  $toPatch = [int]$Matches.patch
  $target = $targets[$code]
  . (Join-Path $RepoRoot 'tools/lib/validation/MIR4DistributionIdentity.ps1')
  $null = New-MIR4DistributionIdentityProjection -DistributionTargetCode $code -SourceMinor 2 -SourcePatch $toPatch -DistributionVersion $ToVersion
  $predecessorKind = 'historical-terminal'
  if ($FromVersion -cne [string]$target.terminal) {
    if ($FromVersion -cnotmatch ('^4[.]2[.]' + $code + '(?<patch>[0-9]{2})$')) { throw $failure }
    $fromPatch = [int]$Matches.patch
    if ($fromPatch -ge $toPatch) { throw $failure }
    $null = New-MIR4DistributionIdentityProjection -DistributionTargetCode $code -SourceMinor 2 -SourcePatch $fromPatch -DistributionVersion $FromVersion
    $predecessorKind = 'same-target-maintenance'
  }
  # Fixture specialization selects an engine line and continuity oracle. The
  # caller still authenticates actual archives and published predecessor custody.
  return [ordered]@{
    line = [string]$target.line
    target = $ToVersion
    infinite_technology = [string]$target.infinite_technology
    predecessor_kind = $predecessorKind
  }
}

function Invoke-MIRUpgradeMonitoredProcess {
  param([string]$FilePath,[string[]]$Arguments,[int]$TimeoutMs=300000,[scriptblock]$CompletionPredicate=$null)
  Assert-MIRLibraryLaunch -Activation $script:upgradeActivation -FactorioBin $FilePath -Arguments $Arguments
  $script:upgradeProcessIndex++
  $prefix=Join-Path $root ('process-'+$script:upgradeProcessIndex)
  $remaining=Get-MIRNativeProbeRemainingOutputBytes -Context $script:upgradeResourceContext
  $run=Invoke-MIR441MonitoredProcess -FilePath $FilePath -Arguments $Arguments -WorkRoot $root `
    -LedgerPath ($prefix+'.resources.jsonl') -Policy $upgradePolicy -EstimatedPeakBytes $remaining `
    -ExpectedPeakMemoryBytes $upgradePeakBytes -TimeoutSeconds ([int][Math]::Ceiling($TimeoutMs/1000)) `
    -StdoutPath ($prefix+'.stdout.txt') -StderrPath ($prefix+'.stderr.txt') -AllowNonZeroExit `
    -CompletionPredicate $CompletionPredicate
  $script:upgradeResourceRuns+=@([ordered]@{index=$script:upgradeProcessIndex;ledger=($prefix+'.resources.jsonl');exit_code=$run.exit_code;completion_predicate_observed=$run.completion_predicate_observed;peak_working_set_bytes=$run.peak_working_set_bytes;duration_seconds=$run.duration_seconds})
  # --no-log-rotation accumulates launches, while benchmark stdout omits mod
  # loading. Verify the native log from its latest engine-start boundary.
  $observer=if($k2Scenario){$fixtureModName}else{''}
  $null=Assert-MIRLibraryLoadedSelection -Activation $script:upgradeActivation -LogPath (Join-Path $root 'userdata/factorio-current.log') -LatestInvocation -ActiveModsObserver $observer
  return $run
}

function Invoke-MIRUpgradeFactorioProcess {
  param([string]$FilePath,[string[]]$Arguments,[int]$TimeoutMs=300000)
  return (Invoke-MIRUpgradeMonitoredProcess -FilePath $FilePath -Arguments $Arguments -TimeoutMs $TimeoutMs).exit_code
}

function Invoke-MIRUpgradeServerUntilSaved {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$LogPath,
    [Parameter(Mandatory)][string]$Marker,
    [Parameter(Mandatory)][string]$SavedMapPath,
    [switch]$HistoricalSaveLog,
    [switch]$ReloadOnly,
    [int]$TimeoutMs = 30000
  )

  # Keep the native save oracle; the shared runner owns admission, deadline,
  # resource sampling, child cancellation and isolated temporary output.
  $completion = {
    if ((Test-Path -LiteralPath $LogPath) -and (Test-Path -LiteralPath $SavedMapPath -PathType Leaf)) {
      $text = [string](Get-Content -Raw -LiteralPath $LogPath)
      if ($ReloadOnly -and $text.Contains($Marker) -and $text.Contains("Hosting game")) {
        return $true
      }
      $saveComplete = $text.Contains("Saving finished")
      if (-not $saveComplete -and $HistoricalSaveLog) {
        # 0.13 through 0.15 log the save request without Saving finished. A
        # readable ZIP central directory with map data closes that save gate;
        # both subsequent native reloads still have to verify its saved state.
        $archive = $null
        try {
          $archive = [IO.Compression.ZipFile]::OpenRead($SavedMapPath)
          $saveComplete = @($archive.Entries | Where-Object {
            $_.FullName.EndsWith('/level.dat',[StringComparison]::Ordinal) -and $_.Length -gt 0
          }).Count -eq 1
        } catch { $saveComplete = $false }
        finally { if ($null -ne $archive) { $archive.Dispose() } }
      }
      if ($text.Contains($Marker) -and $text.Contains("Hosting game") -and $saveComplete) {
        return $true
      }
    }
    return $false
  }.GetNewClosure()
  $run=Invoke-MIRUpgradeMonitoredProcess -FilePath $FilePath -Arguments $Arguments -TimeoutMs $TimeoutMs -CompletionPredicate $completion
  if (-not $run.completion_predicate_observed) {
    throw "Factorio exited before the governed upgraded save/reload completed (exit $($run.exit_code))."
  }
  return 0
}

function Resolve-MIRUpgradePath {
  param([Parameter(Mandatory)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return (Resolve-Path -LiteralPath $Path).Path }
  return (Resolve-Path -LiteralPath (Join-Path $RepoRoot $Path)).Path
}

function Copy-MIRUpgradeLogEvidence {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination,
    [string]$FactorioBinaryPath = "",
    [string]$ExpandedWorkPath = "",
    [string]$RepositoryRootPath = ""
  )
  $factorioPaths = if ([string]::IsNullOrWhiteSpace($FactorioBinaryPath)) {
    @()
  } else {
    @($FactorioBinaryPath, $FactorioBinaryPath.Replace('\', '/')) | Sort-Object -Unique
  }
  $factorioInstallPaths = if ([string]::IsNullOrWhiteSpace($FactorioBinaryPath)) {
    @()
  } else {
    $factorioInstallRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $FactorioBinaryPath))
    @($factorioInstallRoot, $factorioInstallRoot.Replace('\', '/')) | Sort-Object -Unique
  }
  $normalized = @(
    Get-Content -LiteralPath $Source |
      Where-Object { $_ -notmatch 'System info:|Memory info:|\s\[[0-9]+\]:\s' } |
      ForEach-Object {
        $line = $_.TrimEnd()
        foreach ($factorioPath in $factorioPaths) {
          $line = $line -replace [regex]::Escape($factorioPath), '<factorio-binary>'
        }
        foreach ($factorioInstallPath in $factorioInstallPaths) {
          $line = $line -replace [regex]::Escape($factorioInstallPath), '<factorio-install>'
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpandedWorkPath)) {
          foreach ($workPath in @($ExpandedWorkPath, $ExpandedWorkPath.Replace('\', '/'))) {
            $line = $line -replace [regex]::Escape($workPath), '<upgrade-root>'
          }
        }
        if (-not [string]::IsNullOrWhiteSpace($RepositoryRootPath)) {
          foreach ($repoPath in @($RepositoryRootPath, $RepositoryRootPath.Replace('\', '/'))) {
            $line = $line -replace [regex]::Escape($repoPath), '<repository-root>'
          }
        }
        $line `
          -replace '(?i)[A-Z]:\\Program Files\\Steam\\steamapps\\common\\Factorio', '<factorio-install>' `
          -replace '(?i)[A-Z]:/Program Files/Steam/steamapps/common/Factorio', '<factorio-install>' `
          -replace '(?i)[A-Z]:\\[^\s"]*\\build\\validation-upgrades\\u-[0-9a-f]+', '<upgrade-root>' `
          -replace '(?i)[A-Z]:/[^\s"]*/build/validation-upgrades/u-[0-9a-f]+', '<upgrade-root>' `
          -replace '(?i)[A-Z]:\\Users\\[^\\]+\\AppData\\Local\\Temp\\mir-upgrade-[^\\\s"]+', '<upgrade-root>' `
          -replace '(?i)[A-Z]:/Users/[^/]+/AppData/Local/Temp/mir-upgrade-[^/\s"]+', '<upgrade-root>'
      }
  )
  $normalized | Set-Content -LiteralPath $Destination -Encoding UTF8
}

function Write-MIRUpgradeModList {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$FixtureModName,
    [Parameter(Mandatory)][bool]$EnableDlc,
    [string[]]$AdditionalModNames = @()
  )
  $rows = @(
    @{ name = "base"; enabled = $true }
    @{ name = "elevated-rails"; enabled = $EnableDlc }
    @{ name = "quality"; enabled = $EnableDlc }
    @{ name = "recycler"; enabled = $EnableDlc }
    @{ name = "space-age"; enabled = $EnableDlc }
    @{ name = "more-infinite-research"; enabled = $true }
    @{ name = $FixtureModName; enabled = $true }
  )
  foreach ($name in $AdditionalModNames) { $rows += @{ name = $name; enabled = $true } }
  [ordered]@{ mods = $rows } | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $Path -Encoding UTF8
}

$generatedUpgradeRoot = if ([string]::IsNullOrWhiteSpace($WorkRoot)) {
  Join-Path $RepoRoot 'build/p/validation-upgrades'
} else {
  if (-not [IO.Path]::IsPathRooted($WorkRoot)) { throw 'Upgrade -WorkRoot must be an absolute controlled path.' }
  [IO.Path]::GetFullPath($WorkRoot)
}
$resolvedUpgradeRoot=Resolve-MIR441RecoveryScratchPath -Path $generatedUpgradeRoot
if (-not $PrepareInputsOnly -and $LocalModLibraryDirs.Count -ne 1) { throw '[mir-upgrade-library-required] Supply exactly one flat archive library; retired profile staging is unsupported.' }
if (-not $PrepareInputsOnly -and $ExpectedPeakMemoryMiB -le 0) { throw '[mir441-resource-peak-budget-required] Declare the upgrade peak memory budget.' }
$upgradePolicy=[pscustomobject]@{minimum_free_ram_gib=4}
$upgradePeakBytes=[int64]$ExpectedPeakMemoryMiB*1MB
$upgradeWriteBytes=[int64]$MaxNewOutputMiB*1MB
# Refuse before source resolution, staging, evidence allocation or any engine.
if (-not $PrepareInputsOnly) {
  $null=Assert-MIR441ResourceAdmission -Policy $upgradePolicy -WorkRoot $resolvedUpgradeRoot -EstimatedPeakBytes $upgradeWriteBytes -ExpectedPeakMemoryBytes $upgradePeakBytes
} elseif ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($resolvedUpgradeRoot)).AvailableFreeSpace -lt 544MB) {
  throw '[mir-upgrade-preparation-capacity] Small fixture preparation requires 32 MiB output allowance plus 512 MiB headroom; this does not admit a native run.'
}
$script:upgradeProcessIndex=0
$script:upgradeResourceRuns=@()
$script:upgradeActivation=$null
$script:upgradeActivations=@()
. (Join-Path $RepoRoot 'tests/support/MIR421SpaceFakeUpgrade.ps1')
. (Join-Path $RepoRoot 'tests/support/MIR421K2Upgrade.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/NativeProbeResources.ps1')
$k2Scenario=$FixtureName -cin @('assert-upgrade-k2-imersite-4-2-21000-to-4-2-21001','assert-upgrade-k2-imersite-4-2-21001-to-4-2-21002')
if($k2Scenario -or $K2ImersiteInputProfile){
  Assert-MIR421K2UpgradeTransition -Target $SelectedTarget -FromVersion $FromVersion -ToVersion $ToVersion -FixtureName $FixtureName -Archetype $Archetype -SpaceIsFake ([bool]$SpaceIsFake) -SourceOnlyFixtureNames $SourceOnlyFixtureNames -SourceVersion $SourceVersion
  if(-not$K2ImersiteInputProfile-or(-not$SelectedReleaseManifest-and-not$SourceMaterializationPath)-or-not$PublishedMaintenancePredecessorManifestPath-or$Retention-cne'Always'){throw '[mir421-k2-upgrade-inputs-required]'}
}
if($PSBoundParameters.ContainsKey('K2ImersiteCap')-and-not$k2Scenario){throw '[mir421-k2-upgrade-input-mode]'}
if($SourceMaterializationPath){
  Assert-MIR421CurrentUpgradeInputMode -Target $SelectedTarget -FromVersion $FromVersion -ToVersion $ToVersion -FixtureName $FixtureName -Archetype $Archetype -SpaceIsFake ([bool]$SpaceIsFake) -SourceOnlyFixtureNames $SourceOnlyFixtureNames -SelectedReleaseManifest $SelectedReleaseManifest -PublishedPredecessorManifest $PublishedMaintenancePredecessorManifestPath -Retention $Retention -K2ImersiteInputProfile $K2ImersiteInputProfile -SourceVersion $SourceVersion
  if (-not $SpaceIsFake -and -not $k2Scenario -and -not $Archetype) { $Archetype='base-default' }
}
$factorio = Resolve-MIRUpgradePath -Path $FactorioBin
$engineData=Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $factorio))) 'data'
$from = Resolve-MIRUpgradePath -Path $FromZip
$to = Resolve-MIRUpgradePath -Path $ToZip
$currentMaterialization=$null
if($SourceMaterializationPath){
  . (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
  . (Join-Path $RepoRoot 'tools/mir/application/package/TargetMaterializer.ps1')
  # Harness-only corrections need not rebuild identical player archives. The
  # existing native reader checks current bindings and supplied archive bytes;
  # this mode does not relax the separate frozen-source release-seal reader.
  $currentMaterialization=Read-MIRNativeProbeCurrentCandidate -Repository $RepoRoot -Archive $to -ReceiptPath (Resolve-MIRUpgradePath $SourceMaterializationPath) -Target $SelectedTarget -SourceVersion $SourceVersion
  if($ToVersion-cne$currentMaterialization.receipt.distribution_version){throw '[mir-upgrade-manifest-explicit-version]'}
} elseif ($SelectedReleaseManifest -and -not $SpaceIsFake) {
  $selectedVersion=Resolve-MIRUpgradeManifestVersion -ManifestPath (Resolve-MIRUpgradePath -Path $SelectedReleaseManifest) -CandidatePath $to -Target $SelectedTarget
  if ($PSBoundParameters.ContainsKey('ToVersion') -and $ToVersion -cne $selectedVersion) { throw '[mir-upgrade-manifest-explicit-version] ToVersion disagrees with the selected package.' }
  $ToVersion=$selectedVersion
} elseif ($SelectedTarget -and -not $SpaceIsFake) { throw '[mir-upgrade-manifest-required] SelectedTarget requires its release manifest.' }
$sifDescriptor=$null
$sifInputs=@()
$publishedInputs=$null
if ($SpaceIsFake -or $k2Scenario -or $currentMaterialization -or $PublishedMaintenancePredecessorManifestPath) {
  . (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1')
  $predecessorReaderVersion=Resolve-MIR42UpgradePredecessorReaderVersion -Target $SelectedTarget -FromVersion $FromVersion -SourceVersion $SourceVersion
  $predecessorContract=Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion $predecessorReaderVersion
  $metadataText=(& gh api ('repos/Julesc013/more-infinite-research/releases/tags/'+$predecessorContract.source_tag) | Out-String)
  if ($LASTEXITCODE -ne 0) { throw '[mir421-upgrade-release-metadata]' }
  $publishedInputs=Get-MIR42PublishedMaintenancePredecessorInputs -RepoRoot $RepoRoot -ManifestPath $PublishedMaintenancePredecessorManifestPath -ReleaseMetadata ($metadataText | ConvertFrom-Json -Depth 100 -DateKind String) -CandidateSourceVersion $predecessorReaderVersion -SelectedTarget $SelectedTarget -SelectedArchivePath $from
  $predecessor=@($publishedInputs.targets | Where-Object target -CEQ $SelectedTarget)
  if ($predecessor.Count -ne 1 -or [string]$predecessor[0].path -cne $from -or
      [string]$predecessor[0].version -cne $FromVersion -or
      (Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash -cne $predecessor[0].sha256) { throw '[mir421-upgrade-published-predecessor]' }
  $expectedTo=New-MIR4DistributionIdentityProjection -DistributionTargetCode $SelectedTarget.Substring(1) -SourceMinor 2 -SourcePatch ([version]$SourceVersion).Build
  if ($ToVersion -cne $expectedTo.distribution_version) { throw '[mir-upgrade-manifest-explicit-version]' }
}
if ($SpaceIsFake) {
  if ((-not $SelectedReleaseManifest -and -not $currentMaterialization) -or -not $PublishedMaintenancePredecessorManifestPath) { throw '[mir421-sif-manifests-required]' }
  if (-not $OutputPath -or (Test-Path -LiteralPath $OutputPath) -or $Retention -cne 'Always') { throw '[mir421-sif-fresh-retained-output-required]' }
  $null=Resolve-MIR441RecoveryScratchPath -Path $(if([IO.Path]::IsPathRooted($OutputPath)){$OutputPath}else{Join-Path $RepoRoot $OutputPath})
  $sifDescriptor=Get-MIR421SpaceFakeUpgradeDescriptor -Target $SelectedTarget -FromVersion $FromVersion -ToVersion $ToVersion -FixtureName $FixtureName -Archetype $Archetype -SourceVersion $SourceVersion
  $engineBaseInfo=Get-Content -LiteralPath (Join-Path $engineData 'base/info.json') -Raw|ConvertFrom-Json
  if(([version]$engineBaseInfo.version).ToString(2)-cne$sifDescriptor.line){throw '[mir421-sif-engine-authority] Configured engine does not match the selected target.'}
  if (-not $currentMaterialization) {
    $sifCandidate=Get-MIR42ExactFourTargetCandidate -RepoRoot $RepoRoot -CandidateManifestPath $SelectedReleaseManifest
    $null=Get-MIR42TechnicalSealInputContract -Candidate $sifCandidate -PublishedMaintenance
    $sifTarget=@($sifCandidate.targets | Where-Object target -CEQ $SelectedTarget)
    if ($sifTarget.Count -ne 1 -or [string]$sifTarget[0].distribution_version -cne $ToVersion -or [IO.Path]::GetFullPath([string]$sifTarget[0].archive_path) -cne [IO.Path]::GetFullPath($to)) { throw '[mir421-sif-candidate-path]' }
  }
  if (-not $PrepareInputsOnly) { $sifInputs=Resolve-MIR421SpaceFakeUpgradeInputs -RepoRoot $RepoRoot -Descriptor $sifDescriptor -LocalModLibraryDirs $LocalModLibraryDirs }
}
$k2Inputs=$null
if($k2Scenario){
  $k2Inputs=Read-MIR421K2UpgradeProfile -Path (Resolve-MIRUpgradePath $K2ImersiteInputProfile) -SourceVersion $SourceVersion
  if((Get-FileHash -LiteralPath $factorio).Hash-cne$k2Inputs.profile.engine_sha256-or
     (Get-FileHash -LiteralPath (Join-Path (Split-Path -Parent $engineData) 'doc-html/runtime-api.json')).Hash-cne$k2Inputs.profile.runtime_api_sha256){throw '[mir421-k2-upgrade-engine-identity]'}
  $sifInputs=@($k2Inputs.inputs)
  if(-not$PrepareInputsOnly){
    $hashes=[ordered]@{};foreach($row in $sifInputs){$hashes[$row.file_name]=$row.expected_sha256}
    $null=Resolve-MIRNativeProbeDependencyInputs -ExpectedArchives $hashes -LocalModLibraryDirs $LocalModLibraryDirs
  }
}
$factorioVersionInfo = (Get-Item -LiteralPath $factorio).VersionInfo
$isHistoricalTerminalFixture = $FixtureName -eq 'assert-upgrade-historical-terminal-to-mir42'
$isLegacyFactorio = $isHistoricalTerminalFixture -or ([string]$factorioVersionInfo.ProductVersion -match '^(?:0|1)[.]')
$fixture = Resolve-MIRUpgradePath -Path (Join-Path $RepoRoot "fixtures\$FixtureName")
$fixtureInfo = Get-Content -Raw -LiteralPath (Join-Path $fixture "info.json") | ConvertFrom-Json
$fixtureModName = [string]$fixtureInfo.name
$proofSuffix = if ($FixtureName -like "*-automatic-compiler") { " automatic compiler" } else { "" }
$archetypeSuffix = if ($Archetype) { " archetype=$Archetype" } else { "" }
$artifactSlug = if ($Archetype) { $Archetype } else { "default" }
if ($SpaceIsFake) { $artifactSlug='sif-'+$artifactSlug }
if ($k2Scenario) { $artifactSlug='k2-imersite-maintenance-cap-'+$K2ImersiteCap }
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = "build/p/validation-upgrades/$ToVersion-upgrade-$artifactSlug-proof.json"
}
$output = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $RepoRoot $OutputPath }
$output=Resolve-MIR441RecoveryScratchPath -Path $output
if(Test-Path -LiteralPath $output){throw '[mir-upgrade-fresh-output-required] Preserve the previous result and select a fresh output path.'}
$outputParent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $outputParent)) { New-Item -ItemType Directory -Force -Path $outputParent | Out-Null }

$root = Join-Path $resolvedUpgradeRoot ("u-" + [guid]::NewGuid().ToString("N").Substring(0, 16))
$resolvedRoot = [IO.Path]::GetFullPath($root)
$containmentPrefix = $resolvedUpgradeRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not $resolvedRoot.StartsWith($containmentPrefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Upgrade row root escapes the admitted work root: $resolvedRoot"
}
$runSucceeded = $false
$factorioProcesses = 0
try {
Assert-MIRFactorioPathBudget -Path (Join-Path $root "userdata\factorio-current.log") -Context "Upgrade Factorio log path"
$fixtureSources = Join-Path $root 'fixture-sources'
$userdata = Join-Path $root "userdata"
$saves = Join-Path $userdata "saves"
New-Item -ItemType Directory -Force -Path $fixtureSources, $userdata, $saves | Out-Null
$upgradeRequest=if($SpaceIsFake){'SIF-01'}else{'native-upgrade'}
$sourceHash=if($publishedInputs){$predecessor[0].sha256}else{(Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash}
$script:upgradeResourceContext=[pscustomobject]@{root=$root;aliases=@();shared_alias_bytes=0L;max_new_output_bytes=$upgradeWriteBytes;result_reserve_bytes=64KB}
$config = Join-Path $root "config.ini"
@(
  "[path]",
  "read-data=$($engineData.Replace('\', '/'))",
  "write-data=$($userdata.Replace('\', '/'))",
  "[other]",
  "check-updates=false",
  "enable-new-mods=false"
) | Set-Content -LiteralPath $config -Encoding UTF8
$serverSettings = Join-Path $root "server-settings.json"
[ordered]@{
  name = "MIR governed upgrade reload proof"
  description = "Private ephemeral upgrade validation server"
  visibility = [ordered]@{ public = $false; lan = $false }
  require_user_verification = $false
  auto_pause = $false
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $serverSettings -Encoding UTF8

$enableDlc = -not $isLegacyFactorio
if ($Archetype) { $enableDlc = $Archetype -in @("space-age-native-owner", "affected-planet-discovery") }
if ($SpaceIsFake) { $enableDlc=$true }
$persistentModNames=if ($SpaceIsFake) { @($sifDescriptor.mod_names) } else { @() }
$sourceOnlyModNames = @()
$sourceOnlyDirectories=@()
foreach ($sourceFixtureName in $SourceOnlyFixtureNames) {
  $sourceFixture = Resolve-MIRUpgradePath -Path (Join-Path $RepoRoot "fixtures\$sourceFixtureName")
  $sourceInfo = Get-Content -Raw -LiteralPath (Join-Path $sourceFixture "info.json") | ConvertFrom-Json
  $sourceModName = [string]$sourceInfo.name
  if ([string]::IsNullOrWhiteSpace($sourceModName)) { throw "Source-only fixture $sourceFixtureName has no mod name." }
  $sourceOnlyDirectories+=$sourceFixture
  $sourceOnlyModNames += $sourceModName
}

$fixtureDirectoryName = if ($isHistoricalTerminalFixture) {
  $fixtureModName + '_' + [string]$fixtureInfo.version
} else { $fixtureModName }
$stagedFixture = Join-Path $fixtureSources $fixtureDirectoryName
$fixtureFiles=@(Get-ChildItem -LiteralPath $fixture -Recurse -File)
if($fixtureFiles.Count-gt2048-or($fixtureFiles|Measure-Object Length -Sum).Sum-gt4MB){throw '[mir-upgrade-fixture-preparation-size]'}
foreach($file in $fixtureFiles){Assert-MIRLibraryPath $file.FullName}
Copy-Item -LiteralPath $fixture -Destination $stagedFixture -Recurse
if ($SpaceIsFake) { Copy-Item -LiteralPath (Join-Path $RepoRoot 'tests/support/MIR421SpaceFakeUpgrade.lua') -Destination (Join-Path $stagedFixture 'mir421_space_fake_upgrade.lua') }
$mir42UpgradeSpecialized=$false
if ($FixtureName -in @('assert-upgrade-4-0-21000-to-4-1-21000', 'assert-upgrade-4-0-20000-to-4-1-20000', 'assert-upgrade-4-0-11000-to-4-1-11000', 'assert-upgrade-4-0-10000-to-4-1-10000') -and
    $ToVersion -match '^4[.]2[.](?<target>210|200|110|100)(?<patch>[0-9]{2})$') {
  $targetCode=[string]$Matches.target
  $toPatch=[int]$Matches.patch
  $code = $targetCode+'00'
  $expectedFrom = "4.1.$code"
  $maintenancePredecessor=$FromVersion -match ('^4[.]2[.]'+$targetCode+'(?<patch>[0-9]{2})$')
  $earlierPatch=$maintenancePredecessor -and [int]$Matches.patch -lt $toPatch
  if ($FromVersion -cne $expectedFrom -and -not $earlierPatch) { throw 'MIR 4.2 upgrade specialization requires its exact baseline or an earlier same-target maintenance version.' }
  $mir42UpgradeSpecialized=$true
  $fixtureFrom = "4.0.$code"
  $fixtureTo = "4.1.$code"
  $stagedControlPath = Join-Path $stagedFixture 'control.lua'
  $stagedControl = Get-Content -Raw -LiteralPath $stagedControlPath
  $oldSaveName = 'mir-' + $fixtureTo.Replace('.', '') + '-upgraded'
  $newSaveName = 'mir-' + $ToVersion.Replace('.', '') + '-upgraded'
  if (-not $stagedControl.Contains($fixtureFrom) -or -not $stagedControl.Contains($fixtureTo) -or
      -not $stagedControl.Contains($oldSaveName)) {
    throw 'MIR 4.2 upgrade fixture version or save anchors changed.'
  }
  $stagedControl = $stagedControl.Replace($fixtureFrom, '__MIR_UPGRADE_FROM_VERSION__').Replace($fixtureTo, '__MIR_UPGRADE_TO_VERSION__')
  $stagedControl = $stagedControl.Replace('__MIR_UPGRADE_FROM_VERSION__', $FromVersion).Replace('__MIR_UPGRADE_TO_VERSION__', $ToVersion).Replace($oldSaveName, $newSaveName)
  [IO.File]::WriteAllText($stagedControlPath, $stagedControl, [Text.UTF8Encoding]::new($false))
  $stagedInfoPath = Join-Path $stagedFixture 'info.json'
  $stagedInfo = Get-Content -Raw -LiteralPath $stagedInfoPath
  $dependencyFrom = "more-infinite-research >= $fixtureFrom"
  if (-not $stagedInfo.Contains($dependencyFrom)) { throw 'MIR 4.2 upgrade fixture dependency anchor changed.' }
  [IO.File]::WriteAllText($stagedInfoPath, $stagedInfo.Replace($dependencyFrom, "more-infinite-research >= $FromVersion"), [Text.UTF8Encoding]::new($false))
  if ($targetCode -cin @('210','200','110','100') -and
      (($FromVersion -ceq "4.2.${targetCode}00" -and $ToVersion -ceq "4.2.${targetCode}01" -and $SourceVersion -ceq '4.2.1') -or
       ($FromVersion -cin @("4.2.${targetCode}00","4.2.${targetCode}01") -and $ToVersion -ceq "4.2.${targetCode}02" -and $SourceVersion -ceq '4.2.2')) -and
      ($SpaceIsFake -or $Archetype -cin @('','base-default') -or ($targetCode-ceq'210' -and $Archetype-ceq'space-age-native-owner'))) {
    Set-MIR421ModernBaseUpgradeFixtureIdentity -FixtureDirectory $stagedFixture -Target ('f'+$targetCode) -SourceVersion $SourceVersion -FromVersion $FromVersion -SpaceIsFake:$SpaceIsFake -SpaceAge:($Archetype-ceq'space-age-native-owner')
  }
}
if ($isHistoricalTerminalFixture) {
  $historical = Resolve-MIRHistoricalUpgradeTransition -RepoRoot $RepoRoot -FromVersion $FromVersion -ToVersion $ToVersion
  if ($Archetype -and $Archetype -cne 'base-default') {
    throw 'MIR historical terminal upgrade fixture only supports the base-default archetype.'
  }
  $stagedInfoPath = Join-Path $stagedFixture 'info.json'
  $stagedInfo = Get-Content -Raw -LiteralPath $stagedInfoPath
  if (-not $stagedInfo.Contains('@@FACTORIO_LINE@@') -or -not $stagedInfo.Contains('@@MIR_UPGRADE_FROM_VERSION@@')) {
    throw 'MIR historical upgrade fixture metadata anchors changed.'
  }
  $stagedInfo = $stagedInfo.Replace('@@FACTORIO_LINE@@',[string]$historical.line).Replace('@@MIR_UPGRADE_FROM_VERSION@@',$FromVersion)
  [IO.File]::WriteAllText($stagedInfoPath, $stagedInfo, [Text.UTF8Encoding]::new($false))
  $stagedControlPath = Join-Path $stagedFixture 'control.lua'
  $stagedControl = Get-Content -Raw -LiteralPath $stagedControlPath
  $controlAnchors = @('__MIR_UPGRADE_FROM_VERSION__','__MIR_UPGRADE_TO_VERSION__','__MIR_FACTORIO_LINE__','__MIR_INFINITE_TECHNOLOGY__','__MIR_UPGRADE_SAVE_NAME__')
  if (@($controlAnchors | Where-Object { -not $stagedControl.Contains($_) }).Count -ne 0) {
    throw 'MIR historical upgrade fixture control anchors changed.'
  }
  $saveName = 'mir-' + $ToVersion.Replace('.','') + '-upgraded'
  $stagedControl = $stagedControl.Replace('__MIR_UPGRADE_FROM_VERSION__',$FromVersion).Replace('__MIR_UPGRADE_TO_VERSION__',$ToVersion).
    Replace('__MIR_FACTORIO_LINE__',[string]$historical.line).Replace('__MIR_INFINITE_TECHNOLOGY__',[string]$historical.infinite_technology).
    Replace('__MIR_UPGRADE_SAVE_NAME__',$saveName)
  [IO.File]::WriteAllText($stagedControlPath, $stagedControl, [Text.UTF8Encoding]::new($false))
  $targetCode=([string]$historical.line).Replace('.','').PadLeft(3,'0')
  if (($FromVersion -ceq "4.2.${targetCode}00" -and $ToVersion -ceq "4.2.${targetCode}01" -and $SourceVersion -ceq '4.2.1') -or
      ($FromVersion -cin @("4.2.${targetCode}00","4.2.${targetCode}01") -and $ToVersion -ceq "4.2.${targetCode}02" -and $SourceVersion -ceq '4.2.2')) {
    Set-MIR42HistoricalMaintenanceUpgradeFixtureIdentity -FixtureDirectory $stagedFixture -Target ('f'+$targetCode) -SourceVersion $SourceVersion -FromVersion $FromVersion
  }
}
if ($FixtureName -eq "assert-upgrade-3-2-9-to-3-2-10") {
  # The emergency programme governs three predecessor lanes through one
  # contract fixture. Specialize only the disposable staged copy so the
  # checked-in fixture remains the exact primary 3.2.9 -> 3.2.10 proof.
  $stagedInfoPath = Join-Path $stagedFixture "info.json"
  $stagedInfoText = Get-Content -Raw -LiteralPath $stagedInfoPath
  $stagedInfoText = $stagedInfoText -replace 'more-infinite-research >= 3\.2\.9', ("more-infinite-research >= " + $FromVersion)
  Set-Content -LiteralPath $stagedInfoPath -Value $stagedInfoText -Encoding UTF8

  $stagedControlPath = Join-Path $stagedFixture "control.lua"
  $stagedControlText = Get-Content -Raw -LiteralPath $stagedControlPath
  # Use collision-proof placeholders because the requested predecessor may be
  # the template's target (for example 3.2.10 -> 4.0.21000).
  $fromPlaceholder = "__MIR_UPGRADE_FROM_VERSION__"
  $toPlaceholder = "__MIR_UPGRADE_TO_VERSION__"
  $stagedControlText = $stagedControlText.Replace("3.2.9", $fromPlaceholder).Replace("3.2.10", $toPlaceholder)
  $stagedControlText = $stagedControlText.Replace($fromPlaceholder, $FromVersion).Replace($toPlaceholder, $ToVersion)
  $stagedControlText = $stagedControlText.Replace("mir-3210-upgraded", "mir-$($ToVersion.Replace('.', ''))-upgraded")
  Set-Content -LiteralPath $stagedControlPath -Value $stagedControlText -Encoding UTF8
}
if ($SpaceIsFake) {
  if (-not $mir42UpgradeSpecialized) { throw '[mir421-sif-fixture-specialization]' }
  $sifControlPath=Join-Path $stagedFixture 'control.lua'
  $sifControl=Add-MIR421SpaceFakeUpgradeOracle -ControlText (Get-Content -Raw -LiteralPath $sifControlPath)
  [IO.File]::WriteAllText($sifControlPath,$sifControl,[Text.UTF8Encoding]::new($false))
}
if ($Archetype -and -not $isHistoricalTerminalFixture) {
  $settingsPath = Join-Path $stagedFixture "settings.lua"
  if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
    throw "Upgrade archetype selection requires fixture settings.lua: $settingsPath"
  }
  $settingsText = Get-Content -Raw -LiteralPath $settingsPath
  $updatedSettingsText = $settingsText -replace 'default_value\s*=\s*"[^"]+"', ('default_value = "' + $Archetype + '"')
  if ($updatedSettingsText -eq $settingsText -and $settingsText -notmatch ('default_value\s*=\s*"' + [regex]::Escape($Archetype) + '"')) {
    throw "Could not select upgrade archetype $Archetype in $settingsPath"
  }
  Set-Content -LiteralPath $settingsPath -Value $updatedSettingsText -Encoding UTF8
}

$persistentFixtureDirectories=@($stagedFixture)
if($k2Scenario){
  . (Join-Path $RepoRoot 'tools/lib/validation/SettingsOverrides.ps1')
  $capOverride=New-MIR421K2CapOverride -Root (Join-Path $root 'cap-settings') -Cap $K2ImersiteCap
  if($capOverride){$persistentFixtureDirectories+=,$capOverride}
}
if ($PrepareInputsOnly) {
  $preparedRoot=Join-Path $root 'prepared-fixtures';[IO.Directory]::CreateDirectory($preparedRoot)|Out-Null
  $prepared=@(foreach($directory in $persistentFixtureDirectories+$sourceOnlyDirectories){
    $info=Get-Content -LiteralPath (Join-Path $directory 'info.json') -Raw|ConvertFrom-Json
    $archive=Publish-MIRModDirectoryArchive -Source $directory -Name $info.name -Version $info.version -ModsDir $preparedRoot
    [ordered]@{name=$info.name;version=$info.version;path=$archive;sha256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash}
  })
  [ordered]@{schema=1;kind='MIRUpgradePreparedInputsV1';status='prepared-not-native-tested';from_version=$FromVersion;to_version=$ToVersion;archetype=$Archetype;fixtures=$prepared;dependency_inputs=if($SpaceIsFake){$sifDescriptor.inputs}elseif($k2Scenario){$k2Inputs.inputs}else{@()};factorio_processes=0}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $output -Encoding utf8
  Write-Host "[ok] Upgrade assertion fixtures prepared without archive-library writes or native execution: $output"
  return
}
$mods=(Resolve-Path -LiteralPath $LocalModLibraryDirs[0]).Path
$sourceSelection=Get-MIRUpgradeLibrarySelection -Library $mods -EngineDataDirectory $engineData -Archive $from -Version $FromVersion -ExpectedSha256 $sourceHash -Dependencies $sifInputs -FixtureDirectories @($persistentFixtureDirectories+$sourceOnlyDirectories) -EnableDlc $enableDlc
$sourceProfile=Join-Path $root 'source-selection.json';$sourceSelection.mod_list|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $sourceProfile -Encoding utf8
$script:upgradeActivation=Start-MIRLibraryActivation -LibraryDirectory $mods -EngineDataDirectory $engineData -ProfilePath $sourceProfile -ArchiveHashes $sourceSelection.archive_hashes
$script:upgradeActivations+=,$script:upgradeActivation
Add-MIRNativeProbeLibraryActivation -Context $script:upgradeResourceContext -Activation $script:upgradeActivation
$save = Join-Path $root "source.zip"
Assert-MIRFactorioPathBudget -Path $save -Context "Upgrade source-save path"
$log = Join-Path $userdata "factorio-current.log"
$historicalLine = if ($isHistoricalTerminalFixture) { [string]$historical.line } else { '' }
$nativeBaseArgs = @("--config", $config, "--no-log-rotation", "--mod-directory", $mods)
if ($historicalLine -notin @('0.13','0.14')) { $nativeBaseArgs += '--disable-audio' }
$createArgs = $nativeBaseArgs + @("--create", $save)
$factorioProcesses++
$createExitCode = Invoke-MIRUpgradeFactorioProcess -FilePath $factorio -Arguments $createArgs
if (-not (Test-Path -LiteralPath $save) -or ($createExitCode -ne 0 -and -not $isLegacyFactorio)) {
  throw "MIR $FromVersion upgrade source save creation failed with exit code $createExitCode. Temporary root: $root"
}
$createText = Get-Content -Raw -LiteralPath $log
if ($SpaceIsFake) { Assert-MIR421SpaceFakeUpgradeMarker -Text $createText -Stage source }
if ($k2Scenario) { Assert-MIR421K2UpgradeMarker -Text $createText -Stage source -Cap $K2ImersiteCap -SourceVersion $SourceVersion }
if ($isLegacyFactorio -and -not $createText.Contains("[mir-fixture] $FromVersion$proofSuffix upgrade source proof complete$archetypeSuffix")) {
  $sourceInitArgs = $nativeBaseArgs + @(
    "--start-server", $save, "--until-tick", "1"
  )
  $factorioProcesses++
  $sourceInitExitCode = Invoke-MIRUpgradeFactorioProcess -FilePath $factorio -Arguments $sourceInitArgs
  if ($sourceInitExitCode -ne 0) {
    throw "MIR $FromVersion legacy source-save initialization failed with exit code $sourceInitExitCode. Temporary root: $root"
  }
  $createText = Get-Content -Raw -LiteralPath $log
}
$sourceMarker = "[mir-fixture] $FromVersion$proofSuffix upgrade source proof complete$archetypeSuffix"
if (-not $createText.Contains($sourceMarker)) {
  throw "MIR $FromVersion upgrade source proof marker is missing: $sourceMarker. Temporary root: $root"
}
$createEvidence = Join-Path $outputParent "$ToVersion-upgrade-$artifactSlug-from-$FromVersion-create.txt"
Copy-MIRUpgradeLogEvidence -Source $log -Destination $createEvidence -FactorioBinaryPath $factorio -ExpandedWorkPath $root -RepositoryRootPath $RepoRoot

# Retain the engine's source settings privately, then restore the prior library
# controls before selecting the candidate. Dependency archives never move.
$sourceSettings=Read-MIRLibraryControl -Path (Join-Path $mods 'mod-settings.dat')
$sourceSettingsPath=Join-Path $root 'source-mod-settings.dat'
if($sourceSettings.exists){[IO.File]::WriteAllBytes($sourceSettingsPath,[Convert]::FromBase64String($sourceSettings.bytes))}
$sifSourceTerminal=Complete-MIRLibraryActivation -Activation $script:upgradeActivation
$candidateHash=if($currentMaterialization){$currentMaterialization.receipt.archive_sha256}elseif($SpaceIsFake){$sifTarget[0].archive_sha256}else{(Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash}
$candidateSelection=Get-MIRUpgradeLibrarySelection -Library $mods -EngineDataDirectory $engineData -Archive $to -Version $ToVersion -ExpectedSha256 $candidateHash -Dependencies $sifInputs -FixtureDirectories $persistentFixtureDirectories -EnableDlc $enableDlc
$candidateProfile=Join-Path $root 'candidate-selection.json';$candidateSelection.mod_list|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $candidateProfile -Encoding utf8
$settingsArgs=if($sourceSettings.exists){@{SettingsMode='File';SettingsPath=$sourceSettingsPath;SettingsSha256=$sourceSettings.sha256}}else{@{SettingsMode='Defaults'}}
$script:upgradeActivation=Start-MIRLibraryActivation -LibraryDirectory $mods -EngineDataDirectory $engineData -ProfilePath $candidateProfile -ArchiveHashes $candidateSelection.archive_hashes @settingsArgs
$script:upgradeActivations+=,$script:upgradeActivation
Add-MIRNativeProbeLibraryActivation -Context $script:upgradeResourceContext -Activation $script:upgradeActivation
$nativeBaseArgs=@('--config',$config,'--no-log-rotation','--mod-directory',$mods)

$requiresReloadProof = $FixtureName -in @(
  'assert-upgrade-k2-imersite-4-2-21000-to-4-2-21001',
  'assert-upgrade-k2-imersite-4-2-21001-to-4-2-21002',
  "assert-upgrade-3-2-11-to-4-0-21000",
  "assert-upgrade-2-5-11-to-4-0-20000",
  "assert-upgrade-3-2-2-to-3-2-3",
  "assert-upgrade-3-2-3-to-3-2-4",
  "assert-upgrade-3-2-3-to-3-2-5",
  "assert-upgrade-3-2-3-to-3-2-9",
  "assert-upgrade-3-2-5-to-3-2-9",
  "assert-upgrade-3-2-9-to-3-2-10",
  "assert-upgrade-2-5-10-to-4-0-20000",
  "assert-upgrade-2-5-9-to-4-0-20000",
  "assert-upgrade-1-9-9-to-4-0-11000",
  "assert-upgrade-1-8-9-to-4-0-10000",
    "assert-upgrade-4-0-21000-to-4-1-21000",
    "assert-upgrade-4-0-20000-to-4-1-20000",
    "assert-upgrade-4-0-11000-to-4-1-11000",
    "assert-upgrade-4-0-10000-to-4-1-10000",
    "assert-upgrade-historical-terminal-to-mir42"
  )
$governedSaveName = "mir-$($ToVersion.Replace('.', ''))-upgraded.zip"
$governedUpgradedSave = Join-Path $userdata "saves\$governedSaveName"
Assert-MIRFactorioPathBudget -Path $governedUpgradedSave -Context "Upgrade governed-save path"
$governedUpgradeMarker = "[mir-fixture] $FromVersion to $ToVersion$proofSuffix upgrade proof complete$archetypeSuffix"
$loadArgs = if ($requiresReloadProof -and $historicalLine -eq '0.13') {
  # 0.13 exposes empty-server pause through this CLI option, not the modern
  # auto_pause server-settings property. Keep the same named save checks.
  $nativeBaseArgs + @('--start-server', $save, '--no-auto-pause')
} elseif ($requiresReloadProof) {
  $nativeBaseArgs + @(
    "--server-settings", $serverSettings, "--start-server", $save
  )
} else {
  $nativeBaseArgs + @(
    "--benchmark", $save, "--benchmark-ticks", "1", "--benchmark-runs", "1", "--benchmark-sanitize"
  )
}
$loadExitCode = if ($requiresReloadProof) {
  $factorioProcesses++
  # The retained exact K2 create/reload actors take about 48-51 seconds.
  # Keep ordinary scenarios' 30-second server deadline; bound this load at 120.
  $upgradeLoadTimeoutMs=if($k2Scenario){120000}else{30000}
  Invoke-MIRUpgradeServerUntilSaved -FilePath $factorio -Arguments $loadArgs -LogPath $log `
    -Marker $governedUpgradeMarker -SavedMapPath $governedUpgradedSave -HistoricalSaveLog:($historicalLine -in @('0.13','0.14','0.15')) -TimeoutMs $upgradeLoadTimeoutMs
} else {
  $factorioProcesses++
  Invoke-MIRUpgradeFactorioProcess -FilePath $factorio -Arguments $loadArgs
}
if ($loadExitCode -ne 0) { throw "MIR $ToVersion upgrade load failed with exit code $loadExitCode. Temporary root: $root" }
$loadText = Get-Content -Raw -LiteralPath $log
if ($mir42UpgradeSpecialized -and $SelectedTarget-ceq'f210' -and $Archetype-ceq'space-age-native-owner') { Assert-MIR42CompleteCatalogueUpgradeMarker -Text $loadText }
if ($SpaceIsFake) { Assert-MIR421SpaceFakeUpgradeMarker -Text $loadText -Stage upgrade }
if ($k2Scenario) { Assert-MIR421K2UpgradeMarker -Text $loadText -Stage upgrade -Cap $K2ImersiteCap -SourceVersion $SourceVersion }
$loadMarker = "[mir-fixture] $FromVersion to $ToVersion$proofSuffix upgrade proof complete$archetypeSuffix"
if (-not $loadText.Contains($loadMarker)) {
  throw "MIR $ToVersion upgrade proof marker is missing: $loadMarker. Temporary root: $root"
}
$loadEvidence = Join-Path $outputParent "$ToVersion-upgrade-$artifactSlug-from-$FromVersion-load.txt"
Copy-MIRUpgradeLogEvidence -Source $log -Destination $loadEvidence -FactorioBinaryPath $factorio -ExpandedWorkPath $root -RepositoryRootPath $RepoRoot

$reloadEvidence = ""
$secondReloadEvidence = ""
if ($requiresReloadProof) {
  $upgradedSave = $governedUpgradedSave
  # Keep the finite-era save/CLI contract already proved by candidate retention.
  $benchmarkMap = if ($historicalLine -eq '0.13') { [IO.Path]::GetFileNameWithoutExtension($upgradedSave) } else { $upgradedSave }
  $serverReload = $isHistoricalTerminalFixture -and $historicalLine -in @('0.15','0.16')
  $reloadArgs = if ($serverReload) {
    # The 0.15 and 0.16 graphical benchmark paths reject the saved equipment-grid
    # table before fixture assertions. Load each save through the normal server path.
    $nativeBaseArgs + @('--server-settings',$serverSettings,'--start-server',$upgradedSave)
  } else {
    $benchmarkArgs = $nativeBaseArgs + @("--benchmark", $benchmarkMap, "--benchmark-ticks", "1")
    if (-not $isHistoricalTerminalFixture -or $historicalLine -eq '0.17') { $benchmarkArgs += @('--benchmark-runs','1') }
    if (-not $isHistoricalTerminalFixture) { $benchmarkArgs += '--benchmark-sanitize' }
    $benchmarkArgs
  }
  $reloadMarker = "[mir-fixture] $ToVersion upgraded save reload proof complete archetype=$Archetype"
  # The log belongs to this disposable run. Clear it so the marker below proves this reload,
  # rather than a prior load or reload recorded by the same no-rotation log.
  [IO.File]::WriteAllText($log, '', [Text.UTF8Encoding]::new($false))
  $factorioProcesses++
  $reloadExitCode = if ($serverReload) {
    Invoke-MIRUpgradeServerUntilSaved -FilePath $factorio -Arguments $reloadArgs -LogPath $log `
      -Marker $reloadMarker -SavedMapPath $upgradedSave -ReloadOnly
  } else { Invoke-MIRUpgradeFactorioProcess -FilePath $factorio -Arguments $reloadArgs }
  if ($reloadExitCode -ne 0) { throw "MIR $ToVersion upgraded-save reload failed with exit code $reloadExitCode. Temporary root: $root" }
  $reloadText = Get-Content -Raw -LiteralPath $log
  if ($mir42UpgradeSpecialized -and $SelectedTarget-ceq'f210' -and $Archetype-ceq'space-age-native-owner') { Assert-MIR42CompleteCatalogueUpgradeMarker -Text $reloadText }
  if ($SpaceIsFake) { Assert-MIR421SpaceFakeUpgradeMarker -Text $reloadText -Stage reload }
  if ($k2Scenario) { Assert-MIR421K2UpgradeMarker -Text $reloadText -Stage reload -Cap $K2ImersiteCap -SourceVersion $SourceVersion }
  if (-not $reloadText.Contains($reloadMarker)) {
    throw "MIR $ToVersion upgraded-save reload proof marker is missing: $reloadMarker. Temporary root: $root"
  }
  $reloadEvidence = Join-Path $outputParent "$ToVersion-upgrade-$artifactSlug-from-$FromVersion-reload.txt"
  Copy-MIRUpgradeLogEvidence -Source $log -Destination $reloadEvidence -FactorioBinaryPath $factorio -ExpandedWorkPath $root -RepositoryRootPath $RepoRoot

  # Clear the same owned log again; the second reload receipt must be process-specific.
  [IO.File]::WriteAllText($log, '', [Text.UTF8Encoding]::new($false))
  $factorioProcesses++
  $secondReloadExitCode = if ($serverReload) {
    Invoke-MIRUpgradeServerUntilSaved -FilePath $factorio -Arguments $reloadArgs -LogPath $log `
      -Marker $reloadMarker -SavedMapPath $upgradedSave -ReloadOnly
  } else { Invoke-MIRUpgradeFactorioProcess -FilePath $factorio -Arguments $reloadArgs }
  if ($secondReloadExitCode -ne 0) {
    throw "MIR $ToVersion upgraded-save second reload failed with exit code $secondReloadExitCode. Temporary root: $root"
  }
  $secondReloadText = Get-Content -Raw -LiteralPath $log
  if ($mir42UpgradeSpecialized -and $SelectedTarget-ceq'f210' -and $Archetype-ceq'space-age-native-owner') { Assert-MIR42CompleteCatalogueUpgradeMarker -Text $secondReloadText }
  if ($SpaceIsFake) { Assert-MIR421SpaceFakeUpgradeMarker -Text $secondReloadText -Stage reload }
  if ($k2Scenario) { Assert-MIR421K2UpgradeMarker -Text $secondReloadText -Stage reload -Cap $K2ImersiteCap -SourceVersion $SourceVersion }
  if (-not $secondReloadText.Contains($reloadMarker)) {
    throw "MIR $ToVersion upgraded-save second-reload proof marker is missing: $reloadMarker. Temporary root: $root"
  }
  $secondReloadEvidence = Join-Path $outputParent "$ToVersion-upgrade-$artifactSlug-from-$FromVersion-second-reload.txt"
  Copy-MIRUpgradeLogEvidence -Source $log -Destination $secondReloadEvidence -FactorioBinaryPath $factorio -ExpandedWorkPath $root -RepositoryRootPath $RepoRoot
}

$assertions = if ($isHistoricalTerminalFixture) {
  @(
    'historical-terminal-source-state-retained',
    'historical-terminal-researched-level-retained',
    'historical-terminal-current-research-retained',
    'historical-terminal-fractional-progress-retained',
    'historical-terminal-infinite-bonus-retained-where-supported',
    'historical-terminal-global-state-retained',
    'exact-candidate-normal-mod-directory-load',
    'upgraded-save-reload-passed',
    'upgraded-save-second-reload-passed'
  )
} elseif ($Archetype) {
  $common = @(
    "startup-profile-retained",
    "technology-level-retained",
    "current-research-retained",
    "fractional-research-progress-retained",
    "fixture-storage-retained",
    "exact-candidate-normal-mod-directory-load"
  )
  if ($requiresReloadProof) {
    $common += @("upgraded-save-reload-passed", "upgraded-save-second-reload-passed")
  }
  switch ($Archetype) {
    "base-default" { $common + @("base-only-mod-set-retained") }
    "space-age-native-owner" {
      if ($FixtureName -eq "assert-upgrade-3-2-2-to-3-2-3") {
        $common + @(
          "landfill-level-retained", "ice-level-retained", "current-ice-research-retained",
          "fractional-ice-progress-retained", "platform-starts-unresearched",
          "landfill-platform-effects-removed", "platform-owner-transfer-exact",
          "duplicate-owner-forbidden", "startup-settings-retained"
        )
      } elseif ($mir42UpgradeSpecialized -and $FixtureName -ceq 'assert-upgrade-4-0-21000-to-4-1-21000') {
        $common + @('space-age-native-owner-retained','all-existing-technology-state-retained',
          'all-existing-recipe-research-bonuses-retained','full-research-queue-retained',
          'reported-missing-technologies-retained')
      } elseif ($requiresReloadProof) {
        $common + @("space-age-native-owner-retained")
      } else {
        $common + @("space-age-native-owner-retained")
      }
    }
    "automatic-family-creation" { $common + @("automatic-generated-family-retained", "automatic-recipe-target-retained") }
    "base-continuations" { $common + @("base-continuation-retained") }
    "mod-set-configuration-change" { $common + @("source-only-mod-removed", "removed-recipe-target-sanitized") }
    "affected-planet-discovery" { $common + @("affected-locked-location-reproduced", "planet-discovery-research-retained", "researched-space-location-restored") }
  }
} elseif ($isLegacyFactorio) {
  @(
    "startup-setting-retained",
    "generated-technology-level-retained",
    "current-research-retained",
    "fractional-research-progress-retained",
    "global-runtime-state-retained",
    "exact-candidate-normal-mod-directory-load"
  )
} elseif ($FixtureName -in @("assert-upgrade-3-1-5-to-3-1-9", "assert-upgrade-3-1-9-to-3-2-0")) {
  @(
    "startup-settings-retained",
    "native-owner-technology-level-retained",
    "native-owner-current-research-retained",
    "native-owner-fractional-progress-retained",
    "fixture-storage-retained",
    "exact-candidate-normal-mod-directory-load"
  )
} else {
  @(
    "startup-setting-retained",
    "effect-setting-retained",
    "technology-level-retained",
    "fixture-storage-retained",
    "scripted-runtime-effect-retained",
    "exact-candidate-normal-mod-directory-load"
  )
}

$resourceEvidence=@(foreach ($resourceRun in $script:upgradeResourceRuns) {
  $resourcePath=Join-Path $outputParent "$ToVersion-upgrade-$artifactSlug-from-$FromVersion-process-$($resourceRun.index).resources.jsonl"
  Copy-Item -LiteralPath $resourceRun.ledger -Destination $resourcePath
  [ordered]@{filename=(Split-Path -Leaf $resourcePath);sha256=(Get-FileHash -LiteralPath $resourcePath -Algorithm SHA256).Hash;exit_code=$resourceRun.exit_code;completion_predicate_observed=$resourceRun.completion_predicate_observed;peak_working_set_bytes=$resourceRun.peak_working_set_bytes;duration_seconds=$resourceRun.duration_seconds}
})
if ($SpaceIsFake) {
  if (-not $requiresReloadProof -or -not $reloadEvidence -or -not $secondReloadEvidence) { throw '[mir421-sif-two-reloads-required]' }
  $assertions=@($assertions | Where-Object { $_ -cne 'base-only-mod-set-retained' }) + @('space-is-fake-mod-set-retained','SIF-01-final-level-seven-science-and-finite-anchors','SIF-01-earned-levels-and-native-rewards-retained')
}
if($k2Scenario){
  if(-not$reloadEvidence-or-not$secondReloadEvidence){throw '[mir421-k2-upgrade-two-reloads-required]'}
  if($SourceVersion-ceq'4.2.2'){
    $assertions=@('published-4.2.1-k2-finite-earned-domain-retained','independent-crystal-ten-percent-retained',
      'existing-queue-level-and-completed-work-retained','configured-imersite-cap-and-fixture-storage-retained',
      'exact-archive-selection-and-library-controls-restored','upgraded-save-reload-passed','upgraded-save-second-reload-passed')
    $assertions+=if($K2ImersiteCap-eq0){@('existing-powder-level-five-and-eight-percent-retained')}else{@('default-cap-three-withholds-continuation-and-preserves-six-percent-powder')}
  }else{
  $assertions=@('published-4.2.0-k2-earned-levels-one-through-three-retained','powder-six-percent-and-native-crystal-ten-percent-retained',
    'copper-queue-level-three-and-completed-work-retained-before-progression',
    'configured-imersite-cap-and-fixture-storage-retained','exact-archive-selection-and-library-controls-restored',
    'upgraded-save-reload-passed','upgraded-save-second-reload-passed')
  $assertions+=if($K2ImersiteCap-eq0){@('new-powder-continuation-completes-level-four',
    'powder-eight-percent-and-independent-crystal-ten-percent-after-completion','queued-next-level-five-and-42-percent-progress-through-two-reloads')
  }else{@('published-default-cap-three-retained','cap-three-continuation-withheld','copper-queue-and-completed-work-through-two-reloads')}
  }
}
$sifTerminal=Complete-MIRLibraryActivation -Activation $script:upgradeActivation
$result = [ordered]@{
  schema = 3
  status = "passed"
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  git_commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
  archetype = if ($Archetype) { $Archetype } else { "default" }
  factorio_binary_version = $factorioVersionInfo.FileVersion
  factorio_binary_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $factorio).Hash
  factorio_processes = $factorioProcesses
  resource_policy = [ordered]@{declared_peak_memory_mib=$ExpectedPeakMemoryMiB;max_new_output_mib=$MaxNewOutputMiB;memory_enforcement='sampled-watchdog-not-hard-cap'}
  resource_ledgers = $resourceEvidence
  from = [ordered]@{ version = $FromVersion; path = (Split-Path -Leaf $from); sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $from).Hash }
  to = [ordered]@{ version = $ToVersion; path = (Split-Path -Leaf $to); sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $to).Hash }
  source_only_fixtures = @($SourceOnlyFixtureNames)
  assertions = $assertions
  create_log = (Split-Path -Leaf $createEvidence)
  create_log_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $createEvidence).Hash
  load_log = (Split-Path -Leaf $loadEvidence)
  load_log_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $loadEvidence).Hash
}
if ($reloadEvidence) {
  $result.reload_log = (Split-Path -Leaf $reloadEvidence)
  $result.reload_log_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $reloadEvidence).Hash
}
if ($secondReloadEvidence) {
  $result.second_reload_log = (Split-Path -Leaf $secondReloadEvidence)
  $result.second_reload_log_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $secondReloadEvidence).Hash
}
if ($SpaceIsFake) {
  $result.native_scenario=$sifDescriptor.scenario
  $result.dependency_inputs=$sifTerminal.selected
  $result.native_oracle_sha256=(Get-FileHash -LiteralPath (Join-Path $RepoRoot 'tests/support/MIR421SpaceFakeUpgrade.lua') -Algorithm SHA256).Hash
}
if($k2Scenario){
  $result.native_scenario='K2-'+$SourceVersion.Replace('.','')+'-published-4.2.'+(([version]$SourceVersion).Build-1)+'-to-'+$SourceVersion
  $result.input_profile_sha256=$k2Inputs.sha256
  $result.dependency_inputs=$sifTerminal.selected
  $result.native_oracle_sha256=(Get-FileHash -LiteralPath (Join-Path $fixture 'control.lua')).Hash
  $result.harness_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
  $result.harness_helper_sha256=(Get-FileHash -LiteralPath (Join-Path $RepoRoot 'tests/support/MIR421K2Upgrade.ps1')).Hash
  $result.harness_worktree_dirty=[bool](@(& git -C $RepoRoot status --porcelain).Count)
  $result.imersite_cap=$K2ImersiteCap
  $result.cap_input=if($K2ImersiteCap-eq3){'published-default-no-override'}else{'explicit-shared-settings-override-fixture'}
}
if($publishedInputs){$result.published_maintenance_predecessor=$publishedInputs}
if($currentMaterialization){
  $result.candidate_materialization=[ordered]@{path=$SourceMaterializationPath;sha256=(Get-FileHash -LiteralPath (Resolve-MIRUpgradePath $SourceMaterializationPath)).Hash;record_sha256=$currentMaterialization.receipt.record_sha256;package_source_sha256=$currentMaterialization.receipt.package_source_sha256}
  $result.harness_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
  $result.harness_worktree_dirty=[bool](@(& git -C $RepoRoot status --porcelain).Count)
}
$result.library_activation=$sifTerminal
$result.source_library_activation=$sifSourceTerminal
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $output -Encoding UTF8

$runSucceeded = $true
Write-Host "[ok] MIR $FromVersion to $ToVersion upgrade proof ($artifactSlug): $output"
} finally {
  foreach ($activation in $script:upgradeActivations) {
    if (-not $activation.closed) {
      $null=Complete-MIRLibraryActivation -Activation $activation
    }
  }
  $retained = $Retention -eq 'Always' -or (-not $runSucceeded -and $Retention -eq 'OnFailure')
  $fileCount = 0
  [int64]$bytes = 0
  if (Test-Path -LiteralPath $resolvedRoot -PathType Container) {
    foreach ($file in @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Force -ErrorAction SilentlyContinue)) {
      $fileCount++
      $bytes += [int64]$file.Length
    }
    if (-not $retained) {
      $verifiedRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $resolvedRoot).Path)
      if (-not $verifiedRoot.StartsWith($containmentPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing upgrade cleanup outside admitted work root: $verifiedRoot"
      }
      Remove-Item -LiteralPath $verifiedRoot -Recurse -Force
    }
  }
  $cleanupReceipt = [ordered]@{
    schema = 1
    kind = 'MIRUpgradeExpandedRootCleanupV1'
    status = if ($retained) { 'retained' } else { 'removed' }
    retention = $Retention
    run_status = if ($PrepareInputsOnly -and (Test-Path -LiteralPath $output)) { 'prepared-not-native-tested' } elseif ($runSucceeded) { 'passed' } else { 'failed' }
    admitted_work_root_sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($resolvedUpgradeRoot.ToLowerInvariant())))
    expanded_root = Split-Path -Leaf $resolvedRoot
    file_count = $fileCount
    bytes = $bytes
    contained = $true
  }
  $cleanupPath = Join-Path $outputParent "$ToVersion-upgrade-$artifactSlug-cleanup.json"
  [IO.File]::WriteAllText($cleanupPath, (($cleanupReceipt | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
}
