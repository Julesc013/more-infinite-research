function Invoke-MIR4BootstrapCommandGroup {
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
          "capture-terminal-baselines" {
            $params = @{
              RepoRoot = $repo.Path
              Check = (Test-MIRArgSwitch -Items $Args -Name "--check")
              BuildBundles = (Test-MIRArgSwitch -Items $Args -Name "--build-bundles")
            }
            & (Join-Path $repo "tools/commands/release/New-MIR3Dot9TerminalBaselines.ps1") @params
          }
          "import-terminal-baselines" {
            $output = Get-MIRArgValue -Items $Args -Name "--output"
            $params = @{ RepoRoot = $repo.Path; Check = (Test-MIRArgSwitch -Items $Args -Name "--check") }
            if (-not [string]::IsNullOrWhiteSpace($output)) { $params.OutputPath = $output }
            & (Join-Path $repo "tools/commands/release/Import-MIR3TerminalBaselines.ps1") @params
          }
          "check" {
            & (Join-Path $repo "tools/commands/release/Test-MIR4R0Bootstrap.ps1") `
              -RepoRoot $repo.Path `
              -Update:(Test-MIRArgSwitch -Items $Args -Name "--update") `
              -BuildBundles:(Test-MIRArgSwitch -Items $Args -Name "--build-bundles")
          }
          { $_ -in @("build-local-beta", "check-local-beta") } {
            $targetInput = Get-MIRArgValue -Items $Args -Name "--target" -Default "F210"
            $target = if ($targetInput -ceq 'all') { 'all' } else { ConvertTo-MIR4LegacyTargetKey -Target $targetInput }
            $output = Get-MIRArgValue -Items $Args -Name "--output" -Default "build/mir4/emergency-lane"
            $repetitionsText = Get-MIRArgValue -Items $Args -Name "--repetitions" -Default "3"
            $repetitions = 0
            if (-not [int]::TryParse($repetitionsText, [ref]$repetitions) -or $repetitions -ne 3) {
              throw "--repetitions must be exactly 3 for the A/B/C bootstrap profile."
            }
            & (Join-Path $repo "tools/commands/release/New-MIR4BootstrapLocalCandidate.ps1") `
              -RepoRoot $repo.Path `
              -Target $target `
              -Lane emergency `
              -OutputRoot $output `
              -Repetitions $repetitions `
              -Check:($verb -eq "check-local-beta")
          }
          { $_ -in @("build-local-playtest", "check-local-playtest") } {
            $targetInput = Get-MIRArgValue -Items $Args -Name "--target" -Default "all"
            $target = if ($targetInput -ceq 'all') { 'all' } else { ConvertTo-MIR4LegacyTargetKey -Target $targetInput }
            if ($target -notin @('all', 'f200', 'f110', 'f100')) {
              throw "--target must be one of all, F200, F110, or F100 for the private local-playtest lane."
            }
            $explicitOutput = Get-MIRArgValue -Items $Args -Name "--output"
            if (-not [string]::IsNullOrWhiteSpace($explicitOutput) -and
                [string]$explicitOutput -cne 'build/mir4/local-playtest-shadow') {
              throw "The private local-playtest lane has the fixed output root build/mir4/local-playtest-shadow."
            }
            $repetitionsText = Get-MIRArgValue -Items $Args -Name "--repetitions" -Default "3"
            $repetitions = 0
            if (-not [int]::TryParse($repetitionsText, [ref]$repetitions) -or $repetitions -ne 3) {
              throw "--repetitions must be exactly 3 for the A/B/C bootstrap profile."
            }
            & (Join-Path $repo "tools/commands/release/New-MIR4BootstrapLocalCandidate.ps1") `
              -RepoRoot $repo.Path `
              -Target $target `
              -Lane local-playtest-shadow `
              -OutputRoot 'build/mir4/local-playtest-shadow' `
              -Repetitions $repetitions `
              -Check:($verb -eq "check-local-playtest")
          }
          { $_ -in @("build-historical-private", "check-historical-private") } {
            $targetInput = Get-MIRArgValue -Items $Args -Name "--target" -Default "all"
            $target = if ($targetInput -ceq 'all') { 'all' } else { ConvertTo-MIR4LegacyTargetKey -Target $targetInput }
            if ($target -notin @('all','f018','f017','f016','f015','f014','f013')) {
              throw "--target must be one of all, F018, F017, F016, F015, F014, or F013."
            }
            & (Join-Path $repo "tools/commands/release/New-MIR4HistoricalPrivateCandidate.ps1") `
              -RepoRoot $repo.Path -Target $target -Repetitions 3 -Check:($verb -eq "check-historical-private")
          }
          { $_ -in @("build-m4c01-player-set", "check-m4c01-player-set") } {
            & (Join-Path $repo "tools/commands/release/New-MIR4M4C01PlayerCandidateSet.ps1") `
              -RepoRoot $repo.Path -Check:($verb -eq "check-m4c01-player-set")
          }
          "runtime-historical-private" {
            $target = ConvertTo-MIR4LegacyTargetKey -Target (Get-MIRArgValue -Items $Args -Name "--target")
            if ($target -notin @('f017','f016','f015','f014','f013')) {
              throw "--target must be one of F017, F016, F015, F014, or F013. F018 requires an explicitly admitted exact engine."
            }
            $runtimeArguments = @{ RepoRoot = $repo.Path; Target = $target }
            $factorioBin = Get-MIRArgValue -Items $Args -Name "--factorio-bin"
            $candidate = Get-MIRArgValue -Items $Args -Name "--candidate"
            $evidence = Get-MIRArgValue -Items $Args -Name "--evidence"
            if (-not [string]::IsNullOrWhiteSpace($factorioBin)) { $runtimeArguments.FactorioBin = $factorioBin }
            if (-not [string]::IsNullOrWhiteSpace($candidate)) { $runtimeArguments.CandidateZip = $candidate }
            if (-not [string]::IsNullOrWhiteSpace($evidence)) { $runtimeArguments.EvidenceRoot = $evidence }
            & (Join-Path $repo "tests/runtime/Test-MIR4HistoricalPrivateRuntime.ps1") @runtimeArguments
          }
          { $_ -in @("api", "sdk") } {
            if ($Args.Count -lt 3) { throw "mir4 $verb requires a subcommand." }
            $subcommand = [string]$Args[2]
            $allowed = if ($verb -eq "api") { @("check", "conformance") } else { @("generate", "check") }
            if ($subcommand -notin $allowed) { throw "Unknown mir4 $verb command: $subcommand" }
            & (Join-Path $repo "tools/mir/cli/Invoke-MIR4ExperimentalApi.ps1") -Command "$verb-$subcommand" -RepoRoot $repo.Path
          }
          "platform" {
            if ($Args.Count -lt 3) { throw "mir4 platform requires a subcommand." }
            $subcommand = [string]$Args[2]
            if ($subcommand -notin @('generate','check','conformance','package','compile')) {
              throw "Unknown mir4 platform command: $subcommand"
            }
            $platformArguments = @{ Command=$subcommand; RepoRoot=$repo.Path }
            if ($subcommand -eq 'compile') {
              $platformArguments.Target = ConvertTo-MIR4LegacyTargetKey -Target (Get-MIRArgValue -Items $Args -Name '--target')
              $platformArguments.ExtensionPath = Get-MIRArgValue -Items $Args -Name '--extension'
              $platformArguments.OutputPath = Get-MIRArgValue -Items $Args -Name '--output'
            }
            & (Join-Path $repo "tools/commands/mir4/Invoke-MIR4PlatformPreview.ps1") @platformArguments
          }
      default { throw '[mir4-router-bootstrap-command]' }
    }
  } $RepoRoot $ScriptRoot $Verb @CommandArguments
}
