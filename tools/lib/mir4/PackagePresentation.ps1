function Assert-MIR4PackagePresentationV1 {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$PackageSourceSha256
  )
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $preT14='9EFA2BBF5D399CCB6CE78BC907C5051D48E2CDB3DE652BA423FAF95FCE67A24C'
  $t14='F9E3F19201B5D660B24883168BBC43B0F06760FA272E33F1380AB6967D42EB0E'
  if($PackageSourceSha256-cne$preT14-and$PackageSourceSha256-cne$t14){
    throw "[mir4-package-presentation-unknown] $PackageSourceSha256"
  }
  if($PackageSourceSha256-ceq$t14){
    & {
      param([string]$ScopedRepoRoot)
      . (Join-Path $ScopedRepoRoot 'tools/lib/mir4/PreFreezeRelease.ps1')
      Test-MIR4PreFreezeAuthorities -RepoRoot $ScopedRepoRoot|Out-Null
    } $repo
    $authorityText=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/releases/waves/mir4-r0/MIR4-Documentation-Continuity-T14V1.json')
    if(-not($authorityText|Test-Json -SchemaFile (Join-Path $repo 'spec/schemas/mir4-documentation-continuity-t14-v1.schema.json'))){
      throw '[mir4-package-presentation-t14-schema]'
    }
    $authority=$authorityText|ConvertFrom-Json -Depth 100
    if((@($authority.package_visible_delta)-join'|')-cne'README.md'-or
      -not[bool]$authority.player_executable_sources_unchanged-or-not[bool]$authority.one_emitter_preserved-or
      [bool]$authority.source_freeze_authorized-or[bool]$authority.signing_or_sealing_authorized-or
      [bool]$authority.promotion_authorized-or[bool]$authority.publication_authorized){
      throw '[mir4-package-presentation-t14-boundary]'
    }
    return [pscustomobject][ordered]@{maturity='t14-readme-presentation';package_source_sha256=$PackageSourceSha256;package_visible_delta=@('README.md');player_executable_sources_unchanged=$true;one_emitter_preserved=$true}
  }
  return [pscustomobject][ordered]@{maturity='pre-t14';package_source_sha256=$PackageSourceSha256;package_visible_delta=@();player_executable_sources_unchanged=$true;one_emitter_preserved=$true}
}
