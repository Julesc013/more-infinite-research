. (Join-Path $PSScriptRoot "Checkpoint.ps1")

function New-MIRRunContext {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RunKind,
    [string]$OutputRoot = "",
    [string]$FactorioBin = "",
    [string[]]$Tiers = @(),
    [string[]]$LocalModDirs = @(),
    [int]$ScenarioTimeoutSeconds = 900,
    [bool]$Offline = $false
  )

  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $runId = "{0}-{1}" -f $RunKind, $stamp
  if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RepoRoot "artifacts\runs\$runId"
  } elseif (-not [System.IO.Path]::IsPathRooted($OutputRoot)) {
    $OutputRoot = Join-Path $RepoRoot $OutputRoot
  }

  New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
  $resolvedOutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path

  $gitBranch = (& git -C $RepoRoot rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1)
  $gitCommit = (& git -C $RepoRoot rev-parse HEAD 2>$null | Select-Object -First 1)
  $mirVersion = ""
  $infoPath = Join-Path $RepoRoot "info.json"
  if (Test-Path -LiteralPath $infoPath) {
    try {
      $mirVersion = [string]((Get-Content -Raw -LiteralPath $infoPath | ConvertFrom-Json).version)
    } catch {
      $mirVersion = ""
    }
  }
  $factorioVersion = ""
  if (-not [string]::IsNullOrWhiteSpace($FactorioBin) -and (Test-Path -LiteralPath $FactorioBin)) {
    try {
      $factorioVersion = [string](& $FactorioBin --version 2>$null | Select-Object -First 1)
    } catch {
      $factorioVersion = ""
    }
  }

  $context = [ordered]@{
    schema = 1
    run_id = $runId
    run_kind = $RunKind
    started_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
    repo_root = $RepoRoot
    output_root = $resolvedOutputRoot
    git_branch = [string]$gitBranch
    git_commit = [string]$gitCommit
    factorio_bin = $FactorioBin
    factorio_version = $factorioVersion
    mir_version = $mirVersion
    tiers = @($Tiers)
    local_mod_dirs = @($LocalModDirs)
    scenario_timeout_seconds = $ScenarioTimeoutSeconds
    offline = $Offline
    manifest_path = (Join-Path $resolvedOutputRoot "run-manifest.json")
    events_path = (Join-Path $resolvedOutputRoot "events.jsonl")
    artifact_index_path = (Join-Path $resolvedOutputRoot "artifact-index.json")
  }

  Write-MIRJsonAtomic -Path $context.manifest_path -Data $context
  return [pscustomobject]$context
}
