param(
  [Parameter(Position=0)][ValidateSet("help", "validate", "package-freeze", "baseline", "status", "views", "plan", "registry", "replay", "context", "evidence-index")][string]$Command = "help",
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [switch]$AllLocks,
  [switch]$Check,
  [ValidateSet("changed", "qualify-incremental", "calibrate-fresh", "rerun-failure")][string]$Mode = "changed",
  [string]$ChangedSince = "",
  [string[]]$ChangedPath = @(),
  [string[]]$FailedTask = @(),
  [string]$EvidenceIndex = "",
  [string]$TrustClass = "",
  [string]$Target = "2.1",
  [string]$Release = "",
  [string]$Output = "out/control-plane-v5-plan.json",
  [string]$ContextOutputRoot = "out/verification-context",
  [string]$EvidenceRoot = "",
  [string]$CandidatePath = "",
  [string]$SourceRepoRoot = ""
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context", "Shadow")) {
  . (Join-Path $PSScriptRoot "MIRControlPlane/$module.ps1")
}

switch ($Command) {
  "help" {
    @"
MIR Control Plane v5

  validate                  Validate typed records and package freeze.
  package-freeze            Verify the current target package roots and locked archive.
  package-freeze -AllLocks  Reconstruct every locked commit package identity.
  baseline                  Print the immutable 3.2.2 v4 baseline.
  status                    Print current release roles and shadow status.
  views                     Generate release, branch, publication, backport, TODO, and dashboard views.
  views -Check              Fail when any generated control-plane view is stale.
  plan                      Build an explainable semantic-impact TaskNode plan.
  plan -Mode calibrate-fresh  Select every atomic task for independent calibration.
  registry                  Generate the exact-environment scenario execution registry.
  registry -Check           Fail when the execution registry is stale.
  replay                    Replay historical v4 evidence through the pure v5 evaluator.
  replay -Check             Fail when the deterministic replay report is stale.
  context                   Materialize one immutable, digest-checked verification context.
  evidence-index            Rebuild the evidence index from content-addressed objects.
"@ | Write-Host
  }
  "validate" {
    $records = Assert-MIRCPRecords -RepoRoot $repo
    $freeze = Assert-MIRCPPackageFreeze -RepoRoot $repo -AllLocks:$AllLocks
    [pscustomobject][ordered]@{status="passed"; records=$records; package_freeze=$freeze} | ConvertTo-Json -Depth 10
  }
  "package-freeze" {
    Assert-MIRCPPackageFreeze -RepoRoot $repo -AllLocks:$AllLocks | ConvertTo-Json -Depth 10
  }
  "baseline" {
    Read-MIRCPJson -Path ".mir/control-plane/baselines/3.2.2-v4.json" -RepoRoot $repo | ConvertTo-Json -Depth 20
  }
  "status" {
    [pscustomobject][ordered]@{
      canonical = Get-MIRCPCurrentRelease -Role canonical -RepoRoot $repo
      backport = Get-MIRCPCurrentRelease -Role backport_calibration -RepoRoot $repo
      shadow = Get-MIRCPShadowStatus -RepoRoot $repo
    } | ConvertTo-Json -Depth 20
  }
  "views" {
    Update-MIRCPViews -RepoRoot $repo -Check:$Check | ConvertTo-Json -Depth 10
  }
  "plan" {
    $plan = New-MIRCPPlan -Mode $Mode -ChangedSince $ChangedSince -ChangedPath $ChangedPath -FailedTask $FailedTask -EvidenceIndex $EvidenceIndex -TrustClass $TrustClass -Target $Target -Release $Release -RepoRoot $repo
    Write-MIRCPJson -Path $Output -Value $plan -RepoRoot $repo
    $plan | ConvertTo-Json -Depth 30
  }
  "registry" {
    Update-MIRCPExecutionRegistry -Target $Target -RepoRoot $repo -Check:$Check | ConvertTo-Json -Depth 30
  }
  "replay" {
    Update-MIRCPV4ReplayReport -RepoRoot $repo -Check:$Check | ConvertTo-Json -Depth 20
  }
  "context" {
    New-MIRCPVerificationContext -Mode $Mode -Target $Target -Release $Release -CandidatePath $CandidatePath -SourceRepoRoot $SourceRepoRoot -OutputRoot $ContextOutputRoot -RepoRoot $repo | ConvertTo-Json -Depth 10
  }
  "evidence-index" {
    Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $EvidenceRoot | ConvertTo-Json -Depth 10
  }
}
