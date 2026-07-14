param(
  [Parameter(Mandatory)][string]$FactorioBin,
  [Parameter(Mandatory)][string]$CandidateZip,
  [string]$PriorZip,
  [string]$OutputRoot
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$profile = Get-Content -Raw -LiteralPath (Join-Path $repo ".mir\target-reconstruction.json") | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $FactorioBin -Algorithm SHA256).Hash -ne $profile.factorio.binary_sha256) {
  throw "Factorio binary hash does not match the qualified target profile."
}
$candidate = (Resolve-Path -LiteralPath $CandidateZip).Path
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $repo "build\retention\$($profile.release)" }
if (Test-Path -LiteralPath $OutputRoot) { Remove-Item -LiteralPath $OutputRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$factorioRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $FactorioBin))
$dataPath = Join-Path $factorioRoot "data"
if (-not (Test-Path -LiteralPath $dataPath)) { throw "Factorio data directory not found: $dataPath" }

function Invoke-MIRRetentionRun {
  param([string]$Name, [string]$ModZip, [string]$Mode, [string]$MapPath)
  $runRoot = Join-Path $OutputRoot $Name
  $mods = Join-Path $runRoot "mods"
  $user = Join-Path $runRoot "user"
  New-Item -ItemType Directory -Force -Path $mods, $user | Out-Null
  Copy-Item -LiteralPath $ModZip -Destination (Join-Path $mods ([System.IO.Path]::GetFileName($ModZip)))
  $modList = @{ mods = @(@{ name = "base"; enabled = $true }, @{ name = "more-infinite-research"; enabled = $true }) } | ConvertTo-Json -Depth 5
  [System.IO.File]::WriteAllText((Join-Path $mods "mod-list.json"), $modList, [System.Text.UTF8Encoding]::new($false))
  $config = "[path]`nread-data=$($dataPath.Replace('\','/'))`nwrite-data=$($user.Replace('\','/'))`n`n[general]`nlocale=auto`n`n[other]`nenable-steam-networking=false`ndisable-blueprint-storage=true`n"
  $configPath = Join-Path $runRoot "config.ini"
  [System.IO.File]::WriteAllText($configPath, $config, [System.Text.UTF8Encoding]::new($false))
  $log = Join-Path $runRoot "$Name.log"
  $args = @("--config", $configPath, "--no-log-rotation", "--disable-audio", "--mod-directory", $mods)
  if ($Mode -eq "create") { $args += @("--create", $MapPath) }
  else { $args += @("--benchmark", $MapPath, "--benchmark-ticks", "1", "--benchmark-runs", "1") }
  & $FactorioBin @args *> $log
  if ($LASTEXITCODE -ne 0) { throw "Factorio $Name failed; see $log" }
  $text = Get-Content -Raw -LiteralPath $log
  if ($text -notmatch "Loading mod more-infinite-research $([regex]::Escape(([IO.Path]::GetFileNameWithoutExtension($ModZip) -replace '^more-infinite-research_','')))" -or $text -match '(?im)^.*Error ') {
    throw "Factorio $Name did not load the expected MIR archive cleanly; see $log"
  }
  return $log
}

$freshMap = Join-Path $OutputRoot "fresh-$($profile.release).zip"
$logs = @()
$logs += Invoke-MIRRetentionRun -Name "fresh-create" -ModZip $candidate -Mode create -MapPath $freshMap
$logs += Invoke-MIRRetentionRun -Name "fresh-reload" -ModZip $candidate -Mode load -MapPath $freshMap

$priorStatus = "not-applicable-no-prior-artifact"
if (-not [string]::IsNullOrWhiteSpace($PriorZip)) {
  $prior = (Resolve-Path -LiteralPath $PriorZip).Path
  if ($profile.prior_release.sha256 -and (Get-FileHash -LiteralPath $prior -Algorithm SHA256).Hash -ne $profile.prior_release.sha256) {
    throw "Prior archive does not match target profile."
  }
  $upgradeMap = Join-Path $OutputRoot "upgrade-from-$($profile.prior_release.version).zip"
  $logs += Invoke-MIRRetentionRun -Name "upgrade-create-prior" -ModZip $prior -Mode create -MapPath $upgradeMap
  $logs += Invoke-MIRRetentionRun -Name "upgrade-load-candidate" -ModZip $candidate -Mode load -MapPath $upgradeMap
  $priorStatus = "passed"
}

[ordered]@{ schema=1; status="passed"; release=$profile.release; fresh_create="passed"; fresh_reload="passed"; prior_upgrade=$priorStatus; logs=@($logs | ForEach-Object { [IO.Path]::GetRelativePath($repo, $_).Replace('\','/') }) } |
  ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputRoot "retention-summary.json") -Encoding utf8
Write-Host "[ok] exact-candidate create/reload and retention proof passed."
