function Invoke-MIRProductCommandGroup {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$RepoRoot,
    [Parameter(Mandatory)][string]$ScriptRoot,
    [Parameter(Mandatory)][string]$Area,
    [Parameter(Mandatory)][string]$Verb,
    [AllowEmptyCollection()][string[]]$CommandArguments = @()
  )

  & {
    param(
      $repo,
      [string]$scriptRoot,
      [string]$area,
      [string]$verb
    )

    switch ($area) {
      "technology" {
        $catalog = Get-MIRArgValue -Items $Args -Name "--catalog"
        $candidateId = Get-MIRArgValue -Items $Args -Name "--candidate"
        $output = Get-MIRArgValue -Items $Args -Name "--output"
        if ([string]::IsNullOrWhiteSpace($catalog) -or [string]::IsNullOrWhiteSpace($output)) {
          throw "technology commands require --catalog and --output."
        }
        switch ($verb) {
          "quality-assessment" {
            $profilePath = Get-MIRArgValue -Items $Args -Name "--profile"
            if ([string]::IsNullOrWhiteSpace($candidateId) -or [string]::IsNullOrWhiteSpace($profilePath)) {
              throw "technology quality-assessment requires --candidate and --profile."
            }
            $params = @{CatalogPath=$catalog; CandidateId=$candidateId; ProfilePath=$profilePath; OutputPath=$output}
            $metrics = Get-MIRArgValue -Items $Args -Name "--metrics"
            if ($metrics) { $params.MetricsPath = $metrics }
            & (Join-Path $repo "tools/commands/technology/New-MIRTechnologyQualityAssessment.ps1") @params
          }
          "review-dossier" {
            if ([string]::IsNullOrWhiteSpace($candidateId)) { throw "technology review-dossier requires --candidate." }
            $params = @{CatalogPath=$catalog; CandidateId=$candidateId; OutputPath=$output}
            $assessment = Get-MIRArgValue -Items $Args -Name "--assessment"
            if ($assessment) { $params.AssessmentPath = $assessment }
            & (Join-Path $repo "tools/commands/technology/New-MIRTechnologyReviewDossier.ps1") @params
          }
          "promotion-gate" {
            $assessment = Get-MIRArgValue -Items $Args -Name "--assessment"
            $approval = Get-MIRArgValue -Items $Args -Name "--approval"
            $promotion = Get-MIRArgValue -Items $Args -Name "--promotion"
            $profilePath = Get-MIRArgValue -Items $Args -Name "--profile"
            foreach ($value in @($assessment, $approval, $promotion, $profilePath)) {
              if ([string]::IsNullOrWhiteSpace($value)) { throw "technology promotion-gate requires --assessment, --approval, --promotion, and --profile." }
            }
            $params = @{
              CatalogPath=$catalog; AssessmentPath=$assessment; ApprovalPath=$approval
              PromotionPath=$promotion; ProfilePath=$profilePath; OutputPath=$output
            }
            $migration = Get-MIRArgValue -Items $Args -Name "--migration"
            if ($migration) { $params.MigrationPath = $migration }
            & (Join-Path $scriptRoot "Test-MIRTechnologyPromotionAdmission.ps1") @params
          }
          default { throw "Unknown technology command: $verb" }
        }
      }
      "release" {
        switch ($verb) {
          "doctor" {
            $parameters = @{
              Command='release-doctor';RepoRoot=$repo.Path
              Json=(Test-MIRArgSwitch -Items $Args -Name '--json')
              DryRun=(Test-MIRArgSwitch -Items $Args -Name '--dry-run')
              Explain=(Test-MIRArgSwitch -Items $Args -Name '--explain')
            }
            $output = Get-MIRArgValue -Items $Args -Name '--output'
            if (-not [string]::IsNullOrWhiteSpace($output)) { $parameters.OutputPath = $output }
            & (Join-Path $repo 'tools/commands/mir4/Invoke-MIR4PreFreeze.ps1') @parameters
          }
          "gate" {
            $profile = Get-MIRCommandProfile -Items $Args -Default "release-targeted"
            Invoke-MIRRunProfile -Profile $profile -Overrides (New-MIRProfileOverrides -Items $Args)
          }
          "docs-only" {
            Invoke-MIRDocsOnlyReleaseCheck
          }
          "docs-refresh" {
            Invoke-MIRDocsOnlyReleaseCheck
          }
          default { throw "Unknown release command: $verb" }
        }
      }
      "playtest" {
        if ($verb -notin @('prepare','capture','finalize')) { throw "Unknown playtest command: $verb" }
        $parameters = @{
          Command=("playtest-" + $verb);RepoRoot=$repo.Path
          Json=(Test-MIRArgSwitch -Items $Args -Name '--json')
          DryRun=(Test-MIRArgSwitch -Items $Args -Name '--dry-run')
        }
        if ($verb -eq 'prepare') {
          $target = (Get-MIRArgValue -Items $Args -Name '--target' -Default 'F210').ToUpperInvariant()
          if ($target -notin @('F210','F200')) { throw 'playtest prepare --target must be F210 or F200.' }
          $parameters.Target = $target
          foreach ($binding in @(
            @{option='--candidate';parameter='CandidatePath'},
            @{option='--predecessor';parameter='PredecessorPath'},
            @{option='--factorio';parameter='FactorioBin'},
            @{option='--settings';parameter='SettingsPath'},
            @{option='--save';parameter='SavePath'},
            @{option='--output';parameter='SessionOutputRoot'}
          )) {
            $value = Get-MIRArgValue -Items $Args -Name $binding.option
            if (-not [string]::IsNullOrWhiteSpace($value)) { $parameters[$binding.parameter] = $value }
          }
        } else {
          $session = Get-MIRArgValue -Items $Args -Name '--session'
          if ([string]::IsNullOrWhiteSpace($session)) { throw "playtest $verb requires --session." }
          $parameters.SessionRoot = $session
          if ($verb -eq 'capture') {
            $parameters.CapturePath = @(Get-MIRArgValues -Items $Args -Name '--capture')
            $observations = Get-MIRArgValue -Items $Args -Name '--observations'
            if (-not [string]::IsNullOrWhiteSpace($observations)) { $parameters.ObservationsPath = $observations }
          } else {
            $decision = (Get-MIRArgValue -Items $Args -Name '--decision').ToUpperInvariant()
            $reviewer = Get-MIRArgValue -Items $Args -Name '--reviewer'
            if ($decision -notin @('ACCEPTED','CHANGES-REQUESTED','REJECTED') -or [string]::IsNullOrWhiteSpace($reviewer)) {
              throw 'playtest finalize requires an explicit --decision and --reviewer.'
            }
            $parameters.Decision = $decision
            $parameters.Reviewer = $reviewer
            $parameters.Notes = Get-MIRArgValue -Items $Args -Name '--notes'
          }
        }
        & (Join-Path $repo 'tools/commands/mir4/Invoke-MIR4PreFreeze.ps1') @parameters
      }
      "rulesets" {
        if ($verb -ne 'audit') { throw "Unknown rulesets command: $verb" }
        $parameters = @{Command='rulesets-audit';RepoRoot=$repo.Path;Json=(Test-MIRArgSwitch -Items $Args -Name '--json')}
        $output = Get-MIRArgValue -Items $Args -Name '--output'
        if (-not [string]::IsNullOrWhiteSpace($output)) { $parameters.OutputPath = $output }
        & (Join-Path $repo 'tools/commands/mir4/Invoke-MIR4PreFreeze.ps1') @parameters
      }
      "overnight" {
        if ($verb -ne "local") { throw "Unknown overnight command: $verb" }
        $profile = Get-MIRCommandProfile -Items $Args -Default "overnight-local-2.1"
        Invoke-MIRRunProfile -Profile $profile -Overrides (New-MIRProfileOverrides -Items $Args)
      }
      "audit" {
        switch ($verb) {
          "local" {
            $profile = Get-MIRCommandProfile -Items $Args -Default "local-audit-2.1"
            Invoke-MIRRunProfile -Profile $profile -Overrides (New-MIRProfileOverrides -Items $Args)
          }
          "top25" {
            $includeSpaceAge = Test-MIRArgSwitch -Items $Args -Name "--space-age"
            $tier = if ($includeSpaceAge) { "Top25SpaceAge" } else { "Top25Base" }
            & (Join-Path $scriptRoot "Invoke-MIRExtendedTests.ps1") -Tier $tier -CollectAll
          }
          default { throw "Unknown audit command: $verb" }
        }
      }
      default { throw '[mir4-router-product-area]' }
    }
  } $RepoRoot $ScriptRoot $Area $Verb @CommandArguments
}
