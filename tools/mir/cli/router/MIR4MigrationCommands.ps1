function Invoke-MIR4MigrationCommandGroup {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$RepoRoot,
    [Parameter(Mandatory)][string]$ScriptRoot,
    [Parameter(Mandatory)][string]$Verb,
    [AllowEmptyCollection()][string[]]$CommandArguments = @()
  )

  & {
    param(
      $repo,
      [string]$scriptRoot,
      [string]$verb
    )

    switch ($verb) {
          "canonicalization-migration" {
            if ($Args.Count -lt 3) { throw "mir4 canonicalization-migration requires generate, check, or show." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('generate','check','show')) { throw "Unknown mir4 canonicalization-migration command: $subcommand" }
            $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4CanonicalizationMigration.ps1") @migrationArguments
          }
          "diagnostics-migration" {
            if ($Args.Count -lt 3) { throw "mir4 diagnostics-migration requires generate, check, or show." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('generate','check','show')) { throw "Unknown mir4 diagnostics-migration command: $subcommand" }
            $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4DiagnosticsMigration.ps1") @migrationArguments
          }
          "target-key-migration" {
            if ($Args.Count -lt 3) { throw "mir4 target-key-migration requires check or show." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('check','show')) { throw "Unknown mir4 target-key-migration command: $subcommand" }
            $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4TargetKeyMigration.ps1") @migrationArguments
          }
          "whole-platform-migration" {
            if ($Args.Count -lt 3) { throw "mir4 whole-platform-migration requires check or show." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('check','show')) { throw "Unknown mir4 whole-platform-migration command: $subcommand" }
            $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4WholePlatformMigration.ps1") @migrationArguments
          }
          "technology-acceptance-migration" {
            if ($Args.Count -lt 3) { throw "mir4 technology-acceptance-migration requires check or show." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('check','show')) { throw "Unknown mir4 technology-acceptance-migration command: $subcommand" }
            $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4TechnologyAcceptanceMigration.ps1") @migrationArguments
          }
          "target-compiler-migration" {
            if ($Args.Count -lt 3) { throw "mir4 target-compiler-migration requires check or show." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('check','show')) { throw "Unknown mir4 target-compiler-migration command: $subcommand" }
            $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4TargetCompilerMigration.ps1") @migrationArguments
          }
          "semantic-compiler-policy-migration" {
            if ($Args.Count -lt 3) { throw "mir4 semantic-compiler-policy-migration requires check or show." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('check','show')) { throw "Unknown mir4 semantic-compiler-policy-migration command: $subcommand" }
            $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4SemanticCompilerPolicyMigration.ps1") @migrationArguments
          }
          "runtime-continuity-migration" {
            if ($Args.Count -lt 3) { throw "mir4 runtime-continuity-migration requires check or show." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('check','show')) { throw "Unknown mir4 runtime-continuity-migration command: $subcommand" }
            $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4RuntimeContinuityMigration.ps1") @migrationArguments
          }
          "module-sdk-mep-migration" {
            if ($Args.Count -lt 3) { throw "mir4 module-sdk-mep-migration requires check or show." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('check','show')) { throw "Unknown mir4 module-sdk-mep-migration command: $subcommand" }
            $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4ModuleSdkMepMigration.ps1") @migrationArguments
          }
          "processir-exact-migration" {
            if ($Args.Count -lt 3) { throw "mir4 processir-exact-migration requires check or show." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('check','show')) { throw "Unknown mir4 processir-exact-migration command: $subcommand" }
            $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4ProcessIRExactMigration.ps1") @migrationArguments
          }
          "inspector-compatibility-migration" {
            if ($Args.Count -lt 3) { throw "mir4 inspector-compatibility-migration requires check or show." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('check','show')) { throw "Unknown mir4 inspector-compatibility-migration command: $subcommand" }
            $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4InspectorCompatibilityMigration.ps1") @migrationArguments
          }
          "assurance-offline-custody-migration" {
            if ($Args.Count -lt 3) { throw "mir4 assurance-offline-custody-migration requires check or show." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('check','show')) { throw "Unknown mir4 assurance-offline-custody-migration command: $subcommand" }
            $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4AssuranceOfflineCustodyMigration.ps1") @migrationArguments
          }
          "historical-tooling-migration" {
            if ($Args.Count -lt 3) { throw "mir4 historical-tooling-migration requires check or show." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('check','show')) { throw "Unknown mir4 historical-tooling-migration command: $subcommand" }
            $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4HistoricalToolingMigration.ps1") @migrationArguments
          }
          "release-tooling-migration" {
            if ($Args.Count -lt 3) { throw "mir4 release-tooling-migration requires check or show." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('check','show')) { throw "Unknown mir4 release-tooling-migration command: $subcommand" }
            $migrationArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $migrationArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4ReleaseToolingMigration.ps1") @migrationArguments
          }
          "historical-succession" {
            if ($Args.Count -lt 3) { throw "mir4 historical-succession requires export or check." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('export','check')) { throw "Unknown mir4 historical-succession command: $subcommand" }
            $historicalArguments = @{ RepoRoot=$repo.Path; Check=($subcommand -eq 'check') }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $historicalArguments.OutputRoot = $output }
            & (Join-Path $repo "tools/mir/cli/Export-MIR4HistoricalSuccessionRecords.ps1") @historicalArguments
          }
      default { throw '[mir4-router-migration-command]' }
    }
  } $RepoRoot $ScriptRoot $Verb @CommandArguments
}
