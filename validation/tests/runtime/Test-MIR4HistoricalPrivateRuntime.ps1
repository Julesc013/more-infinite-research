param(
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,
  [Parameter(Mandatory)]
  [ValidateSet('f017', 'f016', 'f015', 'f014', 'f013')]
  [string]$Target,
  [string]$FactorioBin = '',
  [string]$CandidateZip = '',
  [string]$EvidenceRoot = '',
  [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools/lib/validation/FactorioProcess.ps1')

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
  $terminatedAfterProof = $false
  if ($BoundedServer) {
    $processInfo = [Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $Binary
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    foreach ($argument in $Arguments) { [void]$processInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($processInfo)
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    $loaded = $false
    while ((Get-Date) -lt $deadline -and -not $process.HasExited) {
      Start-Sleep -Milliseconds 200
      if (Test-Path -LiteralPath $LiveLog -PathType Leaf) {
        $candidateText = Get-Content -Raw -LiteralPath $LiveLog
        $displayVersion = (($ExpectedVersion -split '\.') | ForEach-Object { [int]$_ }) -join '.'
        if ($candidateText -match '(?im)(^|\s)(Error|Failed to load mods|Failed to load mod|Invalid Mod|Couldn.t load|stack traceback)') {
          try { $process.Kill($true) } catch { $process.Kill() }
          throw "$Name log contains a load failure: $LiveLog"
        }
        if ($candidateText.Contains("Loading mod more-infinite-research $displayVersion") -and
            $candidateText.Contains('Map version ') -and
            ($candidateText.Contains('Hosting game at') -or $candidateText.Contains('changing state from(CreatingGame) to(InGame)'))) {
          $loaded = $true
          break
        }
      }
    }
    if (-not $loaded) {
      if (-not $process.HasExited) { try { $process.Kill($true) } catch { $process.Kill() } }
      throw "$Name did not reach a proven exact-package loaded-map state within $TimeoutMs ms."
    }
    if (-not $process.HasExited) { try { $process.Kill($true) } catch { $process.Kill() } }
    [void]$process.WaitForExit(10000)
    $exitCode = $process.ExitCode
    $terminatedAfterProof = $true
  } else {
    $exitCode = Invoke-FactorioProcess -FilePath $Binary -Arguments $Arguments -TimeoutMs $TimeoutMs
    if ($exitCode -ne 0) { throw "$Name exited with code $exitCode." }
  }
  [void](Assert-MIR4RuntimeLog -Path $LiveLog -Version $ExpectedVersion -Phase $Name)
  $proof = Join-Path $OutputRoot "$Name.log"
  Copy-Item -LiteralPath $LiveLog -Destination $proof -Force
  return [ordered]@{
    phase = $Name
    status = 'passed'
    version = $ExpectedVersion
    duration_seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 3)
    terminated_after_proof = $terminatedAfterProof
    process_exit_code = $exitCode
    log = [IO.Path]::GetRelativePath($OutputRoot, $proof).Replace('\', '/')
    log_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $proof).Hash
  }
}

$authorityPath = Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Historical-Private-Candidate-AuthorizationV1.json'
$authority = Get-Content -Raw -LiteralPath $authorityPath | ConvertFrom-Json
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
  $EvidenceRoot = Join-Path $RepoRoot "build/results/mir4-m4c01/runtime/$Target"
}
if (-not [IO.Path]::IsPathRooted($FactorioBin)) { $FactorioBin = Join-Path $RepoRoot $FactorioBin }
if (-not [IO.Path]::IsPathRooted($CandidateZip)) { $CandidateZip = Join-Path $RepoRoot $CandidateZip }
if (-not [IO.Path]::IsPathRooted($EvidenceRoot)) { $EvidenceRoot = Join-Path $RepoRoot $EvidenceRoot }
$FactorioBin = (Resolve-Path -LiteralPath $FactorioBin).Path
$CandidateZip = (Resolve-Path -LiteralPath $CandidateZip).Path
$predecessorZip = (Resolve-Path -LiteralPath (Join-Path $RepoRoot ([string]$row.predecessor_archive))).Path

$binarySha = (Get-FileHash -Algorithm SHA256 -LiteralPath $FactorioBin).Hash
if ($binarySha -cne [string]$row.engine.sha256) { throw "$Target engine fingerprint mismatch: $binarySha" }
$predecessorSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $predecessorZip).Hash
if ($predecessorSha -cne [string]$row.predecessor_archive_sha256) { throw "$Target predecessor fingerprint mismatch: $predecessorSha" }
$candidateInfo = Get-MIR4ArchiveInfo -Path $CandidateZip
if ([string]$candidateInfo.name -cne 'more-infinite-research' -or
    [string]$candidateInfo.version -cne [string]$row.distribution_version -or
    [string]$candidateInfo.factorio_version -cne [string]$row.factorio_line) {
  throw "$Target candidate metadata does not match its authority row."
}

if (Test-Path -LiteralPath $EvidenceRoot) {
  $resolvedEvidence = (Resolve-Path -LiteralPath $EvidenceRoot).Path
  $allowedRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot 'build/results/mir4-m4c01/runtime')).TrimEnd('\') + '\'
  if (-not ($resolvedEvidence + '\').StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to replace runtime evidence outside the M4C01 result root: $resolvedEvidence"
  }
  Remove-Item -LiteralPath $resolvedEvidence -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$userData = Join-Path $EvidenceRoot 'user'
$mods = Join-Path $userData 'mods'
New-Item -ItemType Directory -Force -Path $mods | Out-Null

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
[ordered]@{ mods = @(
  [ordered]@{ name = 'base'; enabled = $true },
  [ordered]@{ name = 'more-infinite-research'; enabled = $true }
) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $mods 'mod-list.json') -Encoding UTF8

$deployedPredecessor = Join-Path $mods (Split-Path -Leaf $predecessorZip)
Copy-Item -LiteralPath $predecessorZip -Destination $deployedPredecessor
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

Remove-Item -LiteralPath $deployedPredecessor -Force
$deployedCandidate = Join-Path $mods (Split-Path -Leaf $CandidateZip)
Copy-Item -LiteralPath $CandidateZip -Destination $deployedCandidate
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
$recordPath = Join-Path $EvidenceRoot 'runtime-proof.json'
$record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $recordPath -Encoding UTF8
Write-Host "[ok] MIR 4 historical private runtime proof: $Target $recordPath"
$record
