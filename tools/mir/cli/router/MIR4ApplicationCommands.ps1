function Invoke-MIR4ApplicationCommandGroup {
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
          "environment-evidence" {
            if ($Args.Count -lt 3) { throw "mir4 environment-evidence requires lock, diff, bundle, minimize, verify, or reference." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('lock','diff','bundle','minimize','verify','reference')) { throw "Unknown mir4 environment-evidence command: $subcommand" }
            $environmentArguments = @{Mode=$subcommand;RepoRoot=$repo.Path}
            $inputValue = Get-MIRArgValue -Items $Args -Name '--input'
            $otherValue = Get-MIRArgValue -Items $Args -Name '--other'
            $outputValue = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($inputValue)) { $environmentArguments.InputPath = $inputValue }
            if (-not [string]::IsNullOrWhiteSpace($otherValue)) { $environmentArguments.OtherPath = $otherValue }
            if (-not [string]::IsNullOrWhiteSpace($outputValue)) { $environmentArguments.OutputPath = $outputValue }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4EnvironmentEvidence.ps1") @environmentArguments
          }
          "assurance-scale" {
            if ($Args.Count -lt 3) { throw "mir4 assurance-scale requires export or check." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('export','check')) { throw "Unknown mir4 assurance-scale command: $subcommand" }
            $assuranceArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $assuranceArguments.OutputRoot = $output }
            & (Join-Path $repo "tools/mir/cli/Export-MIR4AssuranceScaleRecords.ps1") @assuranceArguments
          }
          "release-governance" {
            if ($Args.Count -lt 3) { throw "mir4 release-governance requires check or initialize." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('check','initialize')) { throw "Unknown mir4 release-governance command: $subcommand" }
            $governanceArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $governanceArguments.OutputPath = $output }
            & (Join-Path $repo "tools/commands/mir4/Invoke-MIR4ReleaseGovernance.ps1") @governanceArguments
          }
          "release-engine" {
            if ($Args.Count -lt 3) { throw "mir4 release-engine requires show, check, or phase." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('show','check','phase')) { throw "Unknown mir4 release-engine command: $subcommand" }
            $releaseArguments = @{Command=$subcommand;RepoRoot=$repo.Path}
            foreach ($binding in @(
              @{option='--phase';parameter='Phase'},
              @{option='--source-release-record';parameter='SourceReleaseRecord'},
              @{option='--candidate-id';parameter='CandidateId'},
              @{option='--source-commit';parameter='SourceCommit'},
              @{option='--source-tree';parameter='SourceTree'},
              @{option='--target-record-set';parameter='TargetDistributionRecordSet'},
              @{option='--release-plan-digest';parameter='ReleasePlanDigest'},
              @{option='--proof-root';parameter='ProofRoot'},
              @{option='--seal-root';parameter='SealRoot'},
              @{option='--operation';parameter='Operation'},
              @{option='--output-root';parameter='OutputRoot'},
              @{option='--output';parameter='OutputPath'}
            )) {
              $value = Get-MIRArgValue -Items $Args -Name $binding.option
              if (-not [string]::IsNullOrWhiteSpace($value)) { $releaseArguments[$binding.parameter] = $value }
            }
            & (Join-Path $repo 'tools/mir/cli/Invoke-MIR4ReleaseEngine.ps1') @releaseArguments
          }
          "tooling" {
            if ($Args.Count -lt 3) { throw "mir4 tooling requires inventory, inventory-check, test-authority, test-authority-check, tests, tests-check, workflows, or workflows-check." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('inventory','inventory-check','test-authority','test-authority-check','tests','tests-check','workflows','workflows-check')) { throw "Unknown mir4 tooling command: $subcommand" }
            & (Join-Path $repo 'tools/mir/cli/Invoke-MIR4ToolingConvergence.ps1') -Command $subcommand -RepoRoot $repo.Path
          }
          "patch-rehearsal" {
            if ($Args.Count -lt 3) { throw "mir4 patch-rehearsal requires run or check." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('run','check')) { throw "Unknown mir4 patch-rehearsal command: $subcommand" }
            $rehearsalArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $rehearsalArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4PatchLaneRehearsal.ps1") @rehearsalArguments
          }
          "release-narratives" {
            if ($Args.Count -lt 3) { throw "mir4 release-narratives requires render, check, source-render, or source-check." }
            $subcommand = $Args[2]
            if ($subcommand -notin @('render','check','source-render','source-check')) { throw "Unknown mir4 release-narratives command: $subcommand" }
            $planIndex = [Array]::IndexOf($Args, '--plan')
            $outputIndex = [Array]::IndexOf($Args, '--output')
            if ($planIndex -lt 0 -or $planIndex + 1 -ge $Args.Count) { throw 'mir4 release-narratives requires --plan.' }
            if ($subcommand -in @('render','check') -and ($outputIndex -lt 0 -or $outputIndex + 1 -ge $Args.Count)) { throw 'mir4 release-narratives render and check require --output.' }
            $narrativeArguments = @{Command=$subcommand;Plan=$Args[$planIndex + 1];RepoRoot=$repo.Path}
            if ($outputIndex -ge 0 -and $outputIndex + 1 -lt $Args.Count) { $narrativeArguments.Output = $Args[$outputIndex + 1] }
            & (Join-Path $repo 'tools/mir/cli/Invoke-MIR4ReleaseNarratives.ps1') @narrativeArguments
            return
          }
          "repository" {
            if ($Args.Count -lt 3) { throw "mir4 repository requires generate, check, inventory, initialize, characterize, or characterization-check." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('generate','check','inventory','initialize','characterize','characterization-check')) { throw "Unknown mir4 repository command: $subcommand" }
            $repositoryArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $repositoryArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4RepositoryFixedPoint.ps1") @repositoryArguments
          }
          "factorio-2.1-channel" {
            if ($Args.Count -lt 3) { throw "mir4 factorio-2.1-channel requires inspect or check." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('inspect','check')) { throw "Unknown mir4 factorio-2.1-channel command: $subcommand" }
            $channelArguments = @{Command=$subcommand;RepoRoot=$repo.Path}
            $factorio = Get-MIRArgValue -Items $Args -Name '--factorio'
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($factorio)) { $channelArguments.FactorioBin = $factorio }
            if (-not [string]::IsNullOrWhiteSpace($output)) { $channelArguments.OutputPath = $output }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4Factorio21Channel.ps1") @channelArguments
          }
          "package-source" {
            if ($Args.Count -lt 3) { throw "mir4 package-source requires baseline, baseline-check, shadow, shadow-check, model, model-check, materialize, materialize-check, runtime-replay, or runtime-replay-check." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('baseline','baseline-check','shadow','shadow-check','model','model-check','materialize','materialize-check','runtime-replay','runtime-replay-check')) { throw "Unknown mir4 package-source command: $subcommand" }
            $packageSourceArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $packageSourceArguments.OutputPath = $output }
            $target = Get-MIRArgValue -Items $Args -Name '--target'
            if (-not [string]::IsNullOrWhiteSpace($target)) { $packageSourceArguments.Target = $target }
            $candidateId = Get-MIRArgValue -Items $Args -Name '--candidate-id'
            if (-not [string]::IsNullOrWhiteSpace($candidateId)) { $packageSourceArguments.CandidateId = $candidateId }
            foreach ($option in @(@{name='--source-version';property='SourceVersion'},@{name='--distribution-version';property='DistributionVersion'})) {
              $value = Get-MIRArgValue -Items $Args -Name $option.name
              if (-not [string]::IsNullOrWhiteSpace($value)) { $packageSourceArguments[$option.property] = $value }
            }
            foreach ($option in @(@{name='--factorio';property='FactorioBin'},@{name='--work-root';property='WorkRoot'},@{name='--evidence-root';property='EvidenceRoot'},@{name='--retention';property='Retention'})) {
              $value = Get-MIRArgValue -Items $Args -Name $option.name
              if (-not [string]::IsNullOrWhiteSpace($value)) { $packageSourceArguments[$option.property] = $value }
            }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4PackageSource.ps1") @packageSourceArguments
          }
      default { throw '[mir4-router-application-command]' }
    }
  } $RepoRoot $ScriptRoot $Verb @CommandArguments
}
