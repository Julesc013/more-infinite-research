function Invoke-MIRRepositoryCommandGroup {
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
      "package" {
        if ($verb -ne "build") { throw "Unknown package command: $verb" }
        $parameters = @{}
        foreach ($option in @(
          @{name='--target';property='Target'},
          @{name='--source-version';property='SourceVersion'},
          @{name='--distribution-version';property='DistributionVersion'},
          @{name='--candidate-id';property='CandidateId'},
          @{name='--output';property='OutputDir'}
        )) {
          $value = Get-MIRArgValue -Items $Args -Name $option.name
          if (-not [string]::IsNullOrWhiteSpace($value)) { $parameters[$option.property] = $value }
        }
        & (Join-Path $repo "tools/commands/package/Build-MIRPackage.ps1") @parameters
      }
      "backport" {
        $manifest = Get-MIRArgValue -Items $Args -Name "--manifest" -Default ".mir/releases/backports/2.5.0.json"
        switch ($verb) {
          "validate" {
            $params = @{RepoRoot=$repo.Path; ManifestPath=$manifest}
            if (Test-MIRArgSwitch -Items $Args -Name "--allow-pending-tags") { $params.AllowPendingTags = $true }
            & (Join-Path $scriptRoot "Test-MIRBackportManifest.ps1") @params
          }
          "materialize" {
            $worktree = Get-MIRArgValue -Items $Args -Name "--worktree"
            if ([string]::IsNullOrWhiteSpace($worktree)) { throw "backport materialize requires --worktree." }
            $params = @{RepoRoot=$repo.Path; ManifestPath=$manifest; Worktree=$worktree}
            foreach ($binding in @(
              @{Option="--source"; Parameter="Source"},
              @{Option="--baseline"; Parameter="Baseline"},
              @{Option="--target"; Parameter="Target"}
            )) {
              $value = Get-MIRArgValue -Items $Args -Name $binding.Option
              if ($value) { $params[$binding.Parameter] = $value }
            }
            $receipt = Get-MIRArgValue -Items $Args -Name "--receipt"
            if ($receipt) { $params.ReceiptPath = $receipt }
            if (Test-MIRArgSwitch -Items $Args -Name "--keep-worktree") { $params.KeepWorktree = $true }
            & (Join-Path $scriptRoot "Materialize-MIRBackport.ps1") @params
          }
          default { throw "Unknown backport command: $verb" }
        }
      }
      "storage" {
        if ($verb -notin @("audit", "clean")) { throw "Unknown storage command: $verb" }
        $olderThanText = Get-MIRArgValue -Items $Args -Name "--older-than-days" -Default "7"
        [int]$olderThanDays = 0
        if (-not [int]::TryParse($olderThanText, [ref]$olderThanDays) -or $olderThanDays -lt 0) {
          throw "--older-than-days must be a non-negative integer."
        }
        $params = @{
          RepoRoot = $repo.Path
          OlderThanDays = $olderThanDays
          AllWorktrees = (Test-MIRArgSwitch -Items $Args -Name "--all-worktrees")
        }
        if ($verb -eq "clean" -and (Test-MIRArgSwitch -Items $Args -Name "--apply")) { $params.Apply = $true }
        & (Join-Path $repo "tools/commands/workspace/Remove-MIRStaleArtifacts.ps1") @params
      }
      "report" {
        switch ($verb) {
          "latest" {
            & (Join-Path $scriptRoot "Show-MIROvernightSummary.ps1") -OutputRoot (Get-MIRLatestRunRoot)
          }
          "missing-deps" {
            $run = Get-MIRArgValue -Items $Args -Name "--run" -Default (Get-MIRLatestRunRoot)
            Get-ChildItem -LiteralPath $run -Recurse -Filter missing-dependencies.csv -File |
              ForEach-Object { Import-Csv -LiteralPath $_.FullName } |
              Group-Object mod |
              Sort-Object Count -Descending |
              Select-Object @{Name='mod';Expression={$_.Name}},Count |
              Format-Table -AutoSize
          }
          "observations" {
            $run = Get-MIRArgValue -Items $Args -Name "--run" -Default (Get-MIRLatestRunRoot)
            Get-ChildItem -LiteralPath $run -Recurse -Filter compat-observations.csv -File |
              ForEach-Object { Import-Csv -LiteralPath $_.FullName } |
              Group-Object kind |
              Sort-Object Count -Descending |
              Select-Object @{Name='kind';Expression={$_.Name}},Count |
              Format-Table -AutoSize
          }
          default { throw "Unknown report command: $verb" }
        }
      }
      "legacy" {
        if ($verb -ne "inventory") { throw "Unknown legacy command: $verb" }
        $output = Get-MIRArgValue -Items $Args -Name "--output" -Default (Join-Path $repo "build\results\legacy-inventory")
        $params = @{ OutputRoot = $output }
        if (Test-MIRArgSwitch -Items $Args -Name "--check") {
          $params.CheckThresholds = $true
        }
        & (Join-Path $repo "tools/commands/workspace/Get-MIRLegacyInventory.ps1") @params
      }
      "profile" {
        if ($verb -ne "stub") { throw "Unknown profile command: $verb" }
        if ($Args.Count -lt 3) { throw "profile stub requires a group id." }
        $groupId = $Args[2]
        $groupedFailures = Get-MIRArgValue -Items $Args -Name "--grouped-failures"
        if ([string]::IsNullOrWhiteSpace($groupedFailures)) { throw "--grouped-failures is required." }
        & (Join-Path $repo "tools/commands/compatibility/New-MIRCompatProfileStub.ps1") -GroupedFailures $groupedFailures -GroupId $groupId
      }
      "run" {
        $profile = Get-MIRArgValue -Items $Args -Name "-Profile"
        if ([string]::IsNullOrWhiteSpace($profile)) { $profile = Get-MIRArgValue -Items $Args -Name "--profile" }
        Invoke-MIRRunProfile -Profile $profile -Overrides (New-MIRProfileOverrides -Items $Args)
      }
      "local-index" {
        if ($verb -ne "build") { throw "Unknown local-index command: $verb" }
        $mods = Get-MIRArgValue -Items $Args -Name "--mods" -Default (Get-MIRDefaultLocalModDir)
        $out = Get-MIRArgValue -Items $Args -Name "--out" -Default (Join-Path $repo "build\cache\local-mod-index\local-mod-index.2.1.json")
        New-MIRLocalModIndex -Dirs @($mods) -OutputPath $out | Out-Null
        Write-MIRSuccess "wrote $out"
      }
      default { throw '[mir4-router-repository-area]' }
    }
  } $RepoRoot $ScriptRoot $Area $Verb @CommandArguments
}
