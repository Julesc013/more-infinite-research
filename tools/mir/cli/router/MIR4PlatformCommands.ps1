function Invoke-MIR4PlatformCommandGroup {
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
          "targets" {
            if ($Args.Count -lt 3) { throw "mir4 targets requires contracts, laws, build, or check." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('contracts','laws','build','check')) { throw "Unknown mir4 targets command: $subcommand" }
            if ($subcommand -in @('contracts','laws')) {
              . (Join-Path $repo "tools/lib/mir4/PlatformPreview.ps1")
              $record = if ($subcommand -eq 'contracts') { New-MIR4TargetContractSet -RepoRoot $repo.Path } else { Test-MIR4TargetProviderLaws -RepoRoot $repo.Path }
              $record | ConvertTo-Json -Depth 100
            } else {
              $targetInput = Get-MIRArgValue -Items $Args -Name '--target' -Default 'all'
              $target = if ($targetInput -ceq 'all') { 'all' } else { ConvertTo-MIR4LegacyTargetKey -Target $targetInput }
              $targetArguments = @{RepoRoot=$repo.Path;Target=$target;Check=($subcommand -eq 'check')}
              $output = Get-MIRArgValue -Items $Args -Name '--output'
              if (-not [string]::IsNullOrWhiteSpace($output)) { $targetArguments.OutputRoot = $output }
              & (Join-Path $repo "tools/commands/mir4/New-MIR4TargetProductSet.ps1") @targetArguments
            }
          }
          "semantic" {
            if ($Args.Count -lt 3) { throw "mir4 semantic requires export, check, or laws." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('export','check','laws')) { throw "Unknown mir4 semantic command: $subcommand" }
            if ($subcommand -eq 'laws') {
              . (Join-Path $repo "tools/lib/mir4/PlatformPreview.ps1")
              Test-MIR4SemanticMergeLaws -RepoRoot $repo.Path | ConvertTo-Json -Depth 100
            } else {
              $semanticArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
              $output = Get-MIRArgValue -Items $Args -Name '--output'
              if (-not [string]::IsNullOrWhiteSpace($output)) { $semanticArguments.OutputRoot = $output }
              & (Join-Path $repo "tools/mir/cli/Export-MIR4SemanticCompilerRecords.ps1") @semanticArguments
            }
          }
          "runtime-continuity" {
            if ($Args.Count -lt 3) { throw "mir4 runtime-continuity requires export, check, or laws." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('export','check','laws')) { throw "Unknown mir4 runtime-continuity command: $subcommand" }
            if ($subcommand -eq 'laws') {
              . (Join-Path $repo "tools/lib/mir4/PlatformPreview.ps1")
              $runtime = New-MIR4RuntimeStateMatrix -RepoRoot $repo.Path -Providers $null -SourceIdentity $null
              $migration = New-MIR4MigrationGraphMatrix -RepoRoot $repo.Path -Providers $null -SourceIdentity $null
              [ordered]@{runtime=$runtime.registration_plan.law_results;migration=$migration.law_results;passed=([bool]$runtime.registration_plan.law_results.all_passed -and [bool]$migration.law_results.all_passed)} | ConvertTo-Json -Depth 20
            } else {
              $runtimeArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
              $output = Get-MIRArgValue -Items $Args -Name '--output'
              $candidate = Get-MIRArgValue -Items $Args -Name '--candidate'
              if (-not [string]::IsNullOrWhiteSpace($output)) { $runtimeArguments.OutputRoot = $output }
              if (-not [string]::IsNullOrWhiteSpace($candidate)) { $runtimeArguments.CandidateZip = $candidate }
              & (Join-Path $repo "tools/mir/cli/Export-MIR4RuntimeContinuityRecords.ps1") @runtimeArguments
            }
          }
          "module-ecosystem" {
            if ($Args.Count -lt 3) { throw "mir4 module-ecosystem requires export or check." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('export','check')) { throw "Unknown mir4 module-ecosystem command: $subcommand" }
            $moduleArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            $candidate = Get-MIRArgValue -Items $Args -Name '--candidate'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $moduleArguments.OutputRoot = $output }
            if (-not [string]::IsNullOrWhiteSpace($candidate)) { $moduleArguments.CandidateZip = $candidate }
            & (Join-Path $repo "tools/mir/cli/Export-MIR4ModuleEcosystemRecords.ps1") @moduleArguments
          }
          "processir-synthesis" {
            if ($Args.Count -lt 3) { throw "mir4 processir-synthesis requires export or check." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('export','check')) { throw "Unknown mir4 processir-synthesis command: $subcommand" }
            $processArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $processArguments.OutputRoot = $output }
            & (Join-Path $repo "tools/mir/cli/Export-MIR4ProcessIRSynthesisRecords.ps1") @processArguments
          }
          "exact-processir" {
            if ($Args.Count -lt 3) { throw "mir4 exact-processir requires export or check." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('export','check')) { throw "Unknown mir4 exact-processir command: $subcommand" }
            $exactArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
            $captures = @(Get-MIRArgValues -Items $Args -Name '--capture')
            if ($captures.Count) { $exactArguments.CaptureId = $captures }
            $repetitionsText = Get-MIRArgValue -Items $Args -Name '--repetitions' -Default '2'
            $repetitions = 0
            if (-not [int]::TryParse($repetitionsText,[ref]$repetitions) -or $repetitions -lt 1 -or $repetitions -gt 4) { throw "--repetitions must be an integer from 1 through 4." }
            $exactArguments.Repetitions = $repetitions
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            $reference = Get-MIRArgValue -Items $Args -Name '--reference'
            if (-not [string]::IsNullOrWhiteSpace($output)) {
              if ($subcommand -eq 'check') { $exactArguments.ReferenceRoot = $output } else { $exactArguments.OutputRoot = $output }
            }
            if (-not [string]::IsNullOrWhiteSpace($reference)) { $exactArguments.ReferenceRoot = $reference }
            if (Test-MIRArgSwitch -Items $Args -Name '--publish-reference') {
              if ($subcommand -eq 'check') { throw "--publish-reference is valid only for exact-processir export." }
              $exactArguments.PublishReference = $true
            }
            & (Join-Path $repo "tools/mir/cli/Export-MIR4ExactProcessIRRecords.ps1") @exactArguments
          }
          "release-canaries" {
            if ($Args.Count -lt 3) { throw "mir4 release-canaries requires export or check." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('export','check')) { throw "Unknown mir4 release-canaries command: $subcommand" }
            $canaryArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
            foreach($binding in @(
              @{arg='--capture-root';parameter='CaptureRoot'},
              @{arg='--upgrade-root';parameter='UpgradeRoot'},
              @{arg='--output';parameter=$(if($subcommand -eq 'check'){'ReferenceRoot'}else{'OutputRoot'})},
              @{arg='--reference';parameter='ReferenceRoot'}
            )){
              $value=Get-MIRArgValue -Items $Args -Name $binding.arg
              if(-not[string]::IsNullOrWhiteSpace($value)){$canaryArguments[$binding.parameter]=$value}
            }
            if(Test-MIRArgSwitch -Items $Args -Name '--publish-reference'){
              if($subcommand -eq 'check'){throw "--publish-reference is valid only for release-canaries export."}
              $canaryArguments.PublishReference=$true
            }
            & (Join-Path $repo "tools/mir/cli/Export-MIR4CompatibilityCanaryRecords.ps1") @canaryArguments
          }
          "inspector-compatibility" {
            if ($Args.Count -lt 3) { throw "mir4 inspector-compatibility requires export or check." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('export','check')) { throw "Unknown mir4 inspector-compatibility command: $subcommand" }
            $inspectorArguments = @{RepoRoot=$repo.Path;Check=($subcommand -eq 'check')}
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $inspectorArguments.OutputRoot = $output }
            & (Join-Path $repo "tools/mir/cli/Export-MIR4InspectorCompatibilityRecords.ps1") @inspectorArguments
          }
          "whole-platform" {
            if ($Args.Count -lt 3) { throw "mir4 whole-platform requires generate, check, matrix, or target-key." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('generate','check','matrix','target-key')) { throw "Unknown mir4 whole-platform command: $subcommand" }
            $wholeArguments = @{Command=$subcommand;RepoRoot=$repo.Path}
            if ($subcommand -eq 'target-key') {
              $wholeArguments.Target = Get-MIRArgValue -Items $Args -Name '--target'
            }
            & (Join-Path $repo "tools/commands/mir4/Invoke-MIR4WholePlatform.ps1") @wholeArguments
          }
          "acceptance" {
            if ($Args.Count -lt 3 -or [string]$Args[2] -cne 'queue') { throw "mir4 acceptance requires queue." }
            $catalog = Get-MIRArgValue -Items $Args -Name '--catalog'
            $target = Get-MIRArgValue -Items $Args -Name '--target'
            $ecosystem = Get-MIRArgValue -Items $Args -Name '--ecosystem'
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            foreach ($required in @(@{name='--catalog';value=$catalog},@{name='--target';value=$target},@{name='--ecosystem';value=$ecosystem},@{name='--output';value=$output})) {
              if ([string]::IsNullOrWhiteSpace([string]$required.value)) { throw "mir4 acceptance queue requires $($required.name)." }
            }
            & (Join-Path $repo "tools/commands/mir4/New-MIR4TechnologyAcceptanceQueue.ps1") -RepoRoot $repo.Path -CatalogPath $catalog -Target $target -Ecosystem $ecosystem -OutputPath $output
          }
          "extension" {
            if ($Args.Count -lt 3) { throw "mir4 extension requires init, validate, explain, test, package, migrate, doctor, lock, diff, ci-init, or discover." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('init','validate','explain','test','package','migrate','doctor','lock','diff','ci-init','discover')) { throw "Unknown mir4 extension command: $subcommand" }
            $builderArguments = @{Command=$subcommand;RepoRoot=$repo.Path}
            $extension = Get-MIRArgValue -Items $Args -Name '--extension'
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            $id = Get-MIRArgValue -Items $Args -Name '--id'
            $template = Get-MIRArgValue -Items $Args -Name '--template'
            $target = Get-MIRArgValue -Items $Args -Name '--target'
            $base = Get-MIRArgValue -Items $Args -Name '--base'
            $candidate = Get-MIRArgValue -Items $Args -Name '--candidate'
            $discovery = Get-MIRArgValue -Items $Args -Name '--discovery'
            if (-not [string]::IsNullOrWhiteSpace($extension)) { $builderArguments.ExtensionPath = $extension }
            if (-not [string]::IsNullOrWhiteSpace($output)) { $builderArguments.OutputRoot = $output }
            if (-not [string]::IsNullOrWhiteSpace($id)) { $builderArguments.ExtensionId = $id }
            if (-not [string]::IsNullOrWhiteSpace($template)) { $builderArguments.Template = $template }
            if (-not [string]::IsNullOrWhiteSpace($target)) { $builderArguments.Target = $target.ToLowerInvariant() }
            if (-not [string]::IsNullOrWhiteSpace($base)) { $builderArguments.BasePath = $base }
            if (-not [string]::IsNullOrWhiteSpace($candidate)) { $builderArguments.CandidatePath = $candidate }
            if (-not [string]::IsNullOrWhiteSpace($discovery)) { $builderArguments.DiscoveryPath = $discovery }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4Extension.ps1") @builderArguments
          }
          "handoff-m4c01" {
            $output = Get-MIRArgValue -Items $Args -Name "--output" -Default "build/mir4/m4c01-handoff"
            & (Join-Path $repo "tools/commands/mir4/Export-MIR4M4C01Handoff.ps1") -RepoRoot $repo.Path -OutputRoot $output
          }
      default { throw '[mir4-router-platform-command]' }
    }
  } $RepoRoot $ScriptRoot $Verb @CommandArguments
}
