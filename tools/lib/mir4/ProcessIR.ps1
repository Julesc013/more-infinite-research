function New-MIR4ProcessIRInventory {
  param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)]$PlatformSpec)
  $repo = Get-MIR4PlatformRepoRoot $RepoRoot
  $luaFiles = @(Get-ChildItem -LiteralPath (Join-Path $repo 'prototypes') -Recurse -Filter '*.lua' -File | Sort-Object FullName)
  $channels = @(foreach ($channel in $PlatformSpec.effect_channels) {
    $needle = ([string]$channel).Replace('-','[_ -]?')
    $matches = @($luaFiles | Select-String -Pattern $needle -CaseSensitive:$false)
    $evidencePaths = @($matches | ForEach-Object { [IO.Path]::GetRelativePath($repo,$_.Path).Replace('\','/') } | Sort-Object -Unique | Select-Object -First 16)
    [ordered]@{
      id=[string]$channel; inputs=@('technology-effect','target-capability'); outputs=@("effect-channel:$channel")
      owners=$evidencePaths; invariants=@('owner-preserved-unless-certified','target-capability-required')
      loop_risks=@('positive-cycle-requires-bounded-proof'); evidence_count=$matches.Count; evidence_paths=$evidencePaths
      parity='shadow-observed'; loop_policy='diagnose-only'
    }
  })
  $record = [pscustomobject][ordered]@{
    kind='MIR4ProcessIRInventoryV0'; schema=0; maturity='shadow'; authoritative=$false
    model=@('subject','inputs','outputs','effects','owners','invariants','loop-risks','evidence'); channels=$channels
    hard_safety=@('no-unbounded-positive-cycle','no-opaque-owner-rewrite','no-confidence-based-safety-override'); digest=''
  }
  return Add-MIR4PlatformDigest $record
}

function New-MIR4OpportunityCatalogue {
  param([Parameter(Mandatory)]$PlatformSpec,[Parameter(Mandatory)]$ProcessIR)
  $rows = @(foreach ($channel in @($ProcessIR.channels)) {
    $disposition = if ([int]$channel.evidence_count -gt 0) { 'request-review' } else { 'request-extension' }
    [ordered]@{
      id=('opportunity-effect-channel-' + [string]$channel.id)
      subject=('effect-channel:' + [string]$channel.id)
      disposition=$disposition
      execution='diagnose-only'
      observed_evidence_count=[int]$channel.evidence_count
      evidence_paths=@($channel.evidence_paths)
      mutation_allowed=$false
      authoritative=$false
      required_evidence=@('subject-identity','target-capability','effect-channel','safety-witness','fixture-or-named-load-check')
    }
  })
  $record = [pscustomobject][ordered]@{ kind='MIR4AutonomousOpportunityCatalogueV0'; schema=0; maturity='shadow'; authoritative=$false; grammar=@($PlatformSpec.synthesis_dispositions); candidates=$rows; digest='' }
  return Add-MIR4PlatformDigest $record
}
