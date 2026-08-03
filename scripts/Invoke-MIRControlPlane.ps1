param(
  [Parameter(Position=0)][ValidateSet("help", "validate", "package-freeze", "baseline", "status", "views", "plan", "registry", "replay", "context", "evidence-index", "aggregate", "calibrate", "calibration-proof", "qualification", "release", "backport", "seal", "promotion")][string]$Command = "help",
  [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path,
  [switch]$AllLocks,
  [switch]$Check,
  [ValidateSet("changed", "qualify-incremental", "calibrate-fresh", "rerun-failure")][string]$Mode = "changed",
  [string]$ChangedSince = "",
  [string[]]$ChangedPath = @(),
  [string[]]$FailedTask = @(),
  [string]$EvidenceIndex = "",
  [string]$TrustClass = "ci",
  [string]$Target = "2.1",
  [string]$Release = "",
  [ValidateSet("verification", "release", "publication", "all")][string]$Stage = "verification",
  [string]$Output = ".work/output/control-plane-v5-plan.json",
  [string]$ContextOutputRoot = ".work/output/verification-context",
  [string]$EvidenceRoot = "",
  [string]$ContextPath = "",
  [string]$AggregateTaskId = "",
  [string]$TaskId = "",
  [string]$CandidatePath = "",
  [string]$SourceRepoRoot = "",
  [string]$FactorioBin = "",
  [string]$PriorRelease = "",
  [string]$LocalModDir = "",
  [string]$LocalModZipDir = "",
  [switch]$Resume
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($module in @("Core", "Records", "Planner", "Scenario", "Observation", "Evidence", "Views", "Context", "Shadow", "Executor", "Release", "Calibration")) {
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
  context                   Materialize one immutable, digest-checked context; seed new candidates with -FactorioBin.
  evidence-index            Rebuild the evidence index from content-addressed objects.
  aggregate                 Resolve one result-only aggregate from exact admitted evidence.
  calibrate                 Run or resume a complete local C24 fresh calibration context.
  calibration-proof         Materialize the compact proof for a completed fresh calibration.
  qualification             Complete protected qualification.full for a release-stage context.
  release                   Execute one named release/publication admission TaskNode.
  backport                  Admit governed dual-parent reconstruction proof for a 2.0 context.
  seal                      Create a protected content-addressed release seal.
  promotion                 Admit promotion only after exact seal and shadow proof closure.
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
    Read-MIRCPJson -Path "validation/baselines/control/3.2.2-v4.json" -RepoRoot $repo | ConvertTo-Json -Depth 20
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
    $plan = New-MIRCPPlan -Mode $Mode -ChangedSince $ChangedSince -ChangedPath $ChangedPath -FailedTask $FailedTask -EvidenceIndex $EvidenceIndex -TrustClass $TrustClass -Target $Target -Release $Release -Stage $Stage -SourceRepoRoot $SourceRepoRoot -RepoRoot $repo
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
    New-MIRCPVerificationContext -Mode $Mode -Target $Target -Release $Release -Stage $Stage -CandidatePath $CandidatePath -SourceRepoRoot $SourceRepoRoot -FactorioBin $FactorioBin -OutputRoot $ContextOutputRoot -RepoRoot $repo | ConvertTo-Json -Depth 10
  }
  "evidence-index" {
    Update-MIRCPEvidenceIndex -RepoRoot $repo -Root $EvidenceRoot | ConvertTo-Json -Depth 10
  }
  "aggregate" {
    Complete-MIRCPAggregateGate -ContextPath $ContextPath -AggregateTaskId $AggregateTaskId -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo | ConvertTo-Json -Depth 12
  }
  "calibrate" {
    Invoke-MIRCPFreshCalibration -ContextPath $ContextPath -FactorioBin $FactorioBin -PriorRelease $PriorRelease `
      -LocalModDir $LocalModDir -LocalModZipDir $LocalModZipDir -SourceRepoRoot $SourceRepoRoot `
      -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -Resume:$Resume -RepoRoot $repo | ConvertTo-Json -Depth 12
  }
  "calibration-proof" {
    New-MIRCPFreshCalibrationProof -ContextPath $ContextPath -EvidenceRoot $EvidenceRoot -Output $Output -RepoRoot $repo | ConvertTo-Json -Depth 12
  }
  "qualification" {
    Complete-MIRCPQualification -ContextPath $ContextPath -EvidenceRoot $EvidenceRoot -RequireFresh:($Mode -eq "calibrate-fresh") -RepoRoot $repo | ConvertTo-Json -Depth 12
  }
  "release" {
    Invoke-MIRCPReleaseTaskAdmission -ContextPath $ContextPath -TaskId $TaskId -SourceRepoRoot $SourceRepoRoot -TrustClass $TrustClass -EvidenceRoot $EvidenceRoot -RepoRoot $repo | ConvertTo-Json -Depth 12
  }
  "backport" {
    Invoke-MIRCPBackportAdmission -ContextPath $ContextPath -EvidenceRoot $EvidenceRoot -RepoRoot $repo | ConvertTo-Json -Depth 12
  }
  "seal" {
    New-MIRCPReleaseSeal -ContextPath $ContextPath -EvidenceRoot $EvidenceRoot -RepoRoot $repo | ConvertTo-Json -Depth 12
  }
  "promotion" {
    Invoke-MIRCPPromotionAdmission -ContextPath $ContextPath -EvidenceRoot $EvidenceRoot -RepoRoot $repo | ConvertTo-Json -Depth 12
  }
}
