# MIR4-CANONICAL-EXECUTABLE-TEST
param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path,
  [Parameter(Mandatory)]
  [ValidateSet('f017', 'f016', 'f015', 'f014', 'f013')]
  [string]$Target,
  [string]$FactorioBin = '',
  [string]$CandidateZip = '',
  [string]$PredecessorZip = '',
  [ValidateRange(0,8192)][int]$ExpectedPeakMemoryMiB = 0,
  [ValidateRange(1,2048)][int]$MaxNewOutputMiB = 120,
  [string]$EvidenceRoot = '',
  [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$inputLeases=@()
# Native execution is retired; the preserved oracle is not current acceptance.
throw '[mir-native-obsolete-runner] This native runner still materializes a mod directory. Use a migrated direct-library consumer; retain this scenario and its historical evidence until conversion. No engine or staging was started.'
$inputLeases=[Collections.Generic.List[object]]::new()
. (Join-Path $RepoRoot 'tools/lib/validation/FactorioProcess.ps1')
. (Join-Path $RepoRoot 'tools/lib/validation/NativeProbeResources.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')

function Get-MIR4ArchiveInfo {
  param([Parameter(Mandatory)][string]$Path)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  try {
    $entries = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') -and $_.FullName -match '^[^/]+/info\.json$' })
    if ($entries.Count -ne 1) { throw "Archive must contain exactly one package-root info.json: $Path" }
    $reader = [IO.StreamReader]::new($entries[0].Open(), [Text.UTF8Encoding]::new($false), $true)
    try { return $reader.ReadToEnd() | ConvertFrom-Json }
    finally { $reader.Dispose() }
  } finally {
    $archive.Dispose()
  }
}

function Assert-MIR4RuntimeLog {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$Phase
  )
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Phase produced no Factorio log: $Path" }
  $text = Get-Content -Raw -LiteralPath $Path
  if ($text -match '(?im)(^|\s)(Error|Failed to load mods|Failed to load mod|Invalid Mod|Couldn.t load|stack traceback)') {
    throw "$Phase log contains a load failure: $Path"
  }
  $displayVersion = (($Version -split '\.') | ForEach-Object { [int]$_ }) -join '.'
  $marker = "Loading mod more-infinite-research $displayVersion"
  if (-not $text.Contains($marker)) { throw "$Phase log lacks exact candidate marker '$marker': $Path" }
  return $text
}

function New-MIR4HistoricalArchiveStage {
  param([Parameter(Mandatory)][string]$Role,[Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$ExpectedSha256,[Parameter(Mandatory)][string]$Version)
  $stageRoot=Join-Path $EvidenceRoot ('inputs/'+$Role)
  $stageMods=Join-Path $stageRoot 'mods'
  $null=New-Item -ItemType Directory -Path $stageRoot,$stageMods -Force
  $input=[ordered]@{source_path=$Source;file_name=[IO.Path]::GetFileName($Source);expected_sha256=$ExpectedSha256;role=$Role;identity=@{target=$Target;version=$Version;authority_record_sha256=$authority.record_sha256};provenance=@{kind='supplied-historical-private-input';public_support_claim=$false};immutable=$true}
  $lease=New-MIRImmutableInputLease -RunRoot $stageRoot -StageDirectory $stageMods -Inputs @($input) -RequireHardLinks
  $inputLeases.Add($lease)
  Add-MIRNativeProbeImmutableLease -Context $resources -Lease $lease
  [ordered]@{mods=@([ordered]@{name='base';enabled=$true},[ordered]@{name='more-infinite-research';enabled=$true})}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $stageMods 'mod-list.json') -Encoding UTF8
  [pscustomobject]@{root=$stageRoot;mods=$stageMods;lease=$lease;role=$Role}
}

function Invoke-MIR4HistoricalPhase {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$ExpectedVersion,
    [Parameter(Mandatory)][string]$LiveLog,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$Binary,
    [Parameter(Mandatory)][int]$TimeoutMs,
    [switch]$BoundedServer
  )
  if (Test-Path -LiteralPath $LiveLog) { Remove-Item -LiteralPath $LiveLog -Force }
  $started = Get-Date
  $completion=$null
  if ($BoundedServer) {
    $displayVersion = (($ExpectedVersion -split '\.') | ForEach-Object { [int]$_ }) -join '.'
    $completion={
      if(-not (Test-Path -LiteralPath $LiveLog -PathType Leaf)){return $false}
      $candidateText=Get-Content -Raw -LiteralPath $LiveLog
      if($candidateText -match '(?im)(^|\s)(Error|Failed to load mods|Failed to load mod|Invalid Mod|Couldn.t load|stack traceback)'){
        throw "$Name log contains a load failure: $LiveLog"
      }
      return $candidateText.Contains("Loading mod more-infinite-research $displayVersion") -and
        $candidateText.Contains('Map version ') -and
        ($candidateText.Contains('Hosting game at') -or $candidateText.Contains('changing state from(CreatingGame) to(InGame)'))
    }.GetNewClosure()
  }
  $actor=Invoke-MIRNativeProbeFactorioProcess -Context $resources -FilePath $Binary -Arguments $Arguments -TimeoutSeconds ([int][Math]::Ceiling($TimeoutMs/1000)) -CompletionPredicate $completion
  if($BoundedServer -and -not $actor.result.completion_predicate_observed){throw "$Name did not reach a proven exact-package loaded-map state within $TimeoutMs ms."}
  [void](Assert-MIR4RuntimeLog -Path $LiveLog -Version $ExpectedVersion -Phase $Name)
  $proof = Join-Path $OutputRoot "$Name.log"
  Copy-Item -LiteralPath $LiveLog -Destination $proof -Force
  return [ordered]@{
    phase = $Name
    status = 'passed'
    version = $ExpectedVersion
    duration_seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 3)
    terminated_after_proof = [bool]$BoundedServer
    process_exit_code = $actor.result.exit_code
    log = [IO.Path]::GetRelativePath($OutputRoot, $proof).Replace('\', '/')
    log_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $proof).Hash
  }
}

$authorityPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Historical-Private-Candidate-AuthorizationV1.json'
$authority = Get-Content -Raw -LiteralPath $authorityPath | ConvertFrom-Json -Depth 100 -DateKind String
if($authority.kind -cne 'MIR4HistoricalPrivateCandidateAuthorizationV1' -or $authority.status -cne 'authorized-private-experimental' -or $authority.public_output_authorized -or $authority.publication_authorized -or -not (Test-MIR4BootstrapRecordHash -Record $authority)){throw 'Historical private authority differs.'}
$row = @($authority.targets | Where-Object { [string]$_.target_key -eq $Target })
if ($row.Count -ne 1) { throw "Historical candidate authority has no unique $Target row." }
$row = $row[0]

if ([string]::IsNullOrWhiteSpace($FactorioBin)) {
  $FactorioBin = "D:\Programs\Factorio\$([string]$row.factorio_line)\bin\x64\factorio.exe"
}
if ([string]::IsNullOrWhiteSpace($CandidateZip)) {
  $CandidateZip = Join-Path $RepoRoot "build/mir4/m4c01-player-candidates/distributions/more-infinite-research_$([string]$row.distribution_version).zip"
}
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
  $EvidenceRoot = Join-Path $RepoRoot "build/tmp/mir4-historical-private/$Target"
}
if (-not [IO.Path]::IsPathRooted($FactorioBin)) { $FactorioBin = Join-Path $RepoRoot $FactorioBin }
if (-not [IO.Path]::IsPathRooted($CandidateZip)) { $CandidateZip = Join-Path $RepoRoot $CandidateZip }
if (-not [IO.Path]::IsPathRooted($EvidenceRoot)) { $EvidenceRoot = Join-Path $RepoRoot $EvidenceRoot }
$FactorioBin = (Resolve-Path -LiteralPath $FactorioBin).Path
$CandidateZip = (Resolve-Path -LiteralPath $CandidateZip).Path
if([string]::IsNullOrWhiteSpace($PredecessorZip)){$PredecessorZip=Join-Path $RepoRoot ([string]$row.predecessor_archive)}
if(-not [IO.Path]::IsPathRooted($PredecessorZip)){$PredecessorZip=Join-Path $RepoRoot $PredecessorZip}
$predecessorZip = (Resolve-Path -LiteralPath $PredecessorZip).Path
if(@(Get-Process -Name factorio -ErrorAction SilentlyContinue).Count){throw 'Historical runtime requires one engine process tree; Factorio is already running.'}
$resources=New-MIRNativeProbeResourceContext -RepoRoot $RepoRoot -OutputRoot $EvidenceRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB
$EvidenceRoot=$resources.root

$binarySha = (Get-FileHash -Algorithm SHA256 -LiteralPath $FactorioBin).Hash
if ($binarySha -cne [string]$row.engine.sha256) { throw "$Target engine fingerprint mismatch: $binarySha" }
$predecessorSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $predecessorZip).Hash
if ($predecessorSha -cne [string]$row.predecessor_archive_sha256) { throw "$Target predecessor fingerprint mismatch: $predecessorSha" }
$candidateSha=(Get-FileHash -Algorithm SHA256 -LiteralPath $CandidateZip).Hash
$candidateInfo = Get-MIR4ArchiveInfo -Path $CandidateZip
if ([string]$candidateInfo.name -cne 'more-infinite-research' -or
    [string]$candidateInfo.version -cne [string]$row.distribution_version -or
    [string]$candidateInfo.factorio_version -cne [string]$row.factorio_line) {
  throw "$Target candidate metadata does not match its authority row."
}

trap {
  $failure=$_
  foreach($lease in $inputLeases){if(-not $lease.closed){try{$null=Complete-MIRImmutableInputLease -Lease $lease -Outcome failed}catch{}}}
  throw $failure
}
New-Item -ItemType Directory -Path $EvidenceRoot | Out-Null
$userData = Join-Path $EvidenceRoot 'user'
New-Item -ItemType Directory -Path $userData | Out-Null
$predecessorStage=New-MIR4HistoricalArchiveStage -Role predecessor -Source $predecessorZip -ExpectedSha256 $predecessorSha -Version ([string]$row.predecessor_release)
$candidateStage=New-MIR4HistoricalArchiveStage -Role candidate -Source $CandidateZip -ExpectedSha256 $candidateSha -Version ([string]$row.distribution_version)
$mods=$predecessorStage.mods

$factorioRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $FactorioBin))
$readData = Join-Path $factorioRoot 'data'
if (-not (Test-Path -LiteralPath (Join-Path $readData 'base') -PathType Container)) { throw "Missing exact-engine base data: $readData" }
$config = Join-Path $EvidenceRoot 'config.ini'
@(
  '[path]',
  "read-data=$($readData.Replace('\', '/'))",
  "write-data=$($userData.Replace('\', '/'))",
  '[other]',
  'check-updates=false'
) | Set-Content -LiteralPath $config -Encoding UTF8
$save = Join-Path $EvidenceRoot "mir-$Target-direct-upgrade.zip"
$liveLog = Join-Path $userData 'factorio-current.log'
$common = @('--config', $config, '--no-log-rotation')
if ([string]$row.factorio_line -notin @('0.13', '0.14')) { $common += '--disable-audio' }
$common += @('--mod-directory', $mods)

$create = Invoke-MIR4HistoricalPhase -Name 'predecessor-create' `
  -Arguments (@($common) + @('--create', $save)) `
  -ExpectedVersion ([string]$row.predecessor_release) -LiveLog $liveLog -OutputRoot $EvidenceRoot `
  -Binary $FactorioBin -TimeoutMs ($TimeoutSeconds * 1000)
if (-not (Test-Path -LiteralPath $save -PathType Leaf)) {
  $fallback = @($common) + @('--start-server-load-scenario', 'base/freeplay', '--until-tick', '1')
  $create = Invoke-MIR4HistoricalPhase -Name 'predecessor-create-fallback' -Arguments $fallback `
    -ExpectedVersion ([string]$row.predecessor_release) -LiveLog $liveLog -OutputRoot $EvidenceRoot `
    -Binary $FactorioBin -TimeoutMs ($TimeoutSeconds * 1000)
  $fallbackSave = Join-Path $userData "saves/mir-$Target-direct-upgrade.zip"
  if (-not (Test-Path -LiteralPath $fallbackSave -PathType Leaf)) { throw "$Target predecessor did not create the expected save." }
  Copy-Item -LiteralPath $fallbackSave -Destination $save
}

$null=Complete-MIRImmutableInputLease -Lease $predecessorStage.lease -Outcome passed
# Carry only the mutable startup settings, never an archive or directory alias.
$startupSettings=Join-Path $mods 'mod-settings.dat'
if(Test-Path -LiteralPath $startupSettings -PathType Leaf){
  if((Get-Item -LiteralPath $startupSettings).Length -gt 4MB){throw 'Historical mutable settings exceed their bounded allowance.'}
  Copy-Item -LiteralPath $startupSettings -Destination (Join-Path $candidateStage.mods 'mod-settings.dat')
}
$mods=$candidateStage.mods
$common[$common.Count-1]=$mods
$candidateArgs = @($common) + @('--start-server', $save)
$upgrade = Invoke-MIR4HistoricalPhase -Name 'candidate-upgrade-load' -Arguments $candidateArgs `
  -ExpectedVersion ([string]$row.distribution_version) -LiveLog $liveLog -OutputRoot $EvidenceRoot `
  -Binary $FactorioBin -TimeoutMs ($TimeoutSeconds * 1000) -BoundedServer
$reload1 = Invoke-MIR4HistoricalPhase -Name 'candidate-repeat-load-1' -Arguments $candidateArgs `
  -ExpectedVersion ([string]$row.distribution_version) -LiveLog $liveLog -OutputRoot $EvidenceRoot `
  -Binary $FactorioBin -TimeoutMs ($TimeoutSeconds * 1000) -BoundedServer
$reload2 = Invoke-MIR4HistoricalPhase -Name 'candidate-repeat-load-2' -Arguments $candidateArgs `
  -ExpectedVersion ([string]$row.distribution_version) -LiveLog $liveLog -OutputRoot $EvidenceRoot `
  -Binary $FactorioBin -TimeoutMs ($TimeoutSeconds * 1000) -BoundedServer

$record = [ordered]@{
  schema = 1
  kind = 'mir4-historical-private-runtime-proof'
  status = 'passed'
  maturity = 'experimental-private'
  target = $Target
  factorio_line = [string]$row.factorio_line
  exact_engine = [ordered]@{ path = $FactorioBin; sha256 = $binarySha; authority_version = [string]$row.engine.version }
  predecessor = [ordered]@{ version = [string]$row.predecessor_release; archive = $predecessorZip; sha256 = $predecessorSha }
  candidate = [ordered]@{ version = [string]$row.distribution_version; archive = $CandidateZip; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $CandidateZip).Hash }
  assertions = @('exact-engine-fingerprint', 'exact-predecessor-fingerprint', 'fresh-predecessor-save', 'direct-candidate-upgrade-load', 'candidate-repeat-load-1', 'candidate-repeat-load-2', 'healthy-load-logs')
  phases = @($create, $upgrade, $reload1, $reload2)
  public_support_claim = $false
  admission_status = 'private-proof-only-repeat-loads-do-not-satisfy-admission-reload-gate'
}
$record['input_staging']=@($inputLeases|ForEach-Object {Complete-MIRImmutableInputLease -Lease $_ -Outcome passed})
$record['resource_context']=[ordered]@{expected_peak_memory_bytes=$resources.peak_memory_bytes;max_new_output_bytes=$resources.max_new_output_bytes;shared_alias_bytes=$resources.shared_alias_bytes;memory_enforcement='sampled-watchdog-not-hard-cap'}
$record['process_inventory']=@($resources.runs)
$record['authority_record_sha256']=$authority.record_sha256
$recordPath = Join-Path $EvidenceRoot 'runtime-proof.json'
$json=($record|ConvertTo-Json -Depth 25)+"`n"
if([Text.Encoding]::UTF8.GetByteCount($json) -ge (Get-MIRNativeProbeRemainingOutputBytes -Context $resources -IncludeResultReserve)){throw '[mir441-resource-output-budget]'}
[IO.File]::WriteAllText($recordPath,$json,[Text.UTF8Encoding]::new($false))
Write-Host "[ok] MIR 4 historical private runtime proof: $Target $recordPath"
$record
