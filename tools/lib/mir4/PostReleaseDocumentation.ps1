Set-StrictMode -Version Latest

function Get-MIR4PostReleaseDocumentationPaths {
  @(
    '.mir/assurance.json'
    'governance/automation/mir4-command-inventory-v1.json'
    'AGENTS.md'
    'README.md'
    'docs/reference/generated/runtime-pipeline.md'
    'docs/reference/generated/stream-defaults.md'
    'tests/mir4/Test-MIR4DocumentationCutoverM4105B.ps1'
    'tests/mir4/Test-MIR4RepositoryCharacterizationM4200A.ps1'
    'tests/support/MIR4M4202PackageSuccession.ps1'
    'tests/tooling/Test-MIR4PowerShellCharacterizationM4202.ps1'
    'tools/commands/docs/Update-MIRPipelineDocumentation.ps1'
    'tools/commands/docs/Update-MIRREADMEStreamDefaults.ps1'
    'tools/commands/docs/Update-MIRPostReleaseDocumentation.ps1'
    'tools/lib/mir4/PostReleaseDocumentation.ps1'
    'tools/lib/mir4/pre-freeze-release/AuthorityValidation.ps1'
    'tools/mir/application/repository/RepositoryCharacterization.ps1'
    'contracts/repository/mir4-post-release-documentation-v1.schema.json'
  )
}

function Get-MIR4PostReleaseDocumentation {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $relative='releases/migrations/MIR4-M41-Readme-RestorationV1.json'
  $path=Join-Path $RepoRoot $relative
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return $null}
  $raw=Get-Content -LiteralPath $path -Raw
  if(-not($raw|Test-Json -SchemaFile (Join-Path $RepoRoot 'contracts/repository/mir4-post-release-documentation-v1.schema.json'))){throw '[mir4-post-release-docs-schema]'}
  $record=$raw|ConvertFrom-Json -Depth 100 -DateKind String
  if(-not(Test-MIR4BootstrapRecordHash -Record $record)){throw '[mir4-post-release-docs-record]'}
  $tag=@(& git -C $RepoRoot rev-parse 'refs/tags/v4.1.0^{tag}')
  if($LASTEXITCODE -ne 0 -or [string]$tag[0] -cne [string]$record.tag_object){throw '[mir4-post-release-docs-tag]'}
  $target=@(& git -C $RepoRoot rev-parse 'refs/tags/v4.1.0^{commit}')
  if($LASTEXITCODE -ne 0 -or [string]$target[0] -cne [string]$record.base_commit){throw '[mir4-post-release-docs-source]'}
  $predecessor=Join-Path $RepoRoot ([string]$record.predecessor.path)
  if((Get-FileHash -LiteralPath $predecessor -Algorithm SHA256).Hash -cne [string]$record.predecessor.sha256){throw '[mir4-post-release-docs-predecessor]'}
  if((Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot) -cne [string]$record.package_source_sha256){throw '[mir4-post-release-docs-package-change]'}
  $allowed=@(Get-MIR4PostReleaseDocumentationPaths)
  $seen=@{}
  foreach($binding in @($record.bindings)){
    $name=[string]$binding.path
    if($name -cnotin $allowed -or $seen.ContainsKey($name)){throw "[mir4-post-release-docs-path] $name"}
    $seen[$name]=$true
    if((Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot $name)) -cne [string]$binding.current_sha256){throw "[mir4-post-release-docs-current] $name"}
    $object=([string]$record.base_commit)+':'+$name
    & git -C $RepoRoot cat-file -e $object 2>$null
    if($LASTEXITCODE -eq 0){
      $prior=@(& git -C $RepoRoot show $object)
      if($LASTEXITCODE -ne 0){throw '[mir4-post-release-docs-prior-object]'}
      $priorHash=Get-MIR4Sha256String -Value (($prior -join "`n")+"`n")
      if($priorHash -cne [string]$binding.previous_sha256){throw "[mir4-post-release-docs-prior] $name"}
    }elseif($null -ne $binding.previous_sha256){throw "[mir4-post-release-docs-new-path] $name"}
  }
  $changed=@(& git -C $RepoRoot diff --name-only ([string]$record.base_commit) --)
  if($LASTEXITCODE -ne 0){throw '[mir4-post-release-docs-diff]'}
  $untracked=@(& git -C $RepoRoot ls-files --others --exclude-standard)
  if($LASTEXITCODE -ne 0){throw '[mir4-post-release-docs-untracked]'}
  $actual=@($changed+$untracked|ForEach-Object{([string]$_).Replace('\','/')}|Where-Object{$_ -and $_ -cne $relative}|Sort-Object -Unique)
  if(($actual -join "`n") -cne (@($seen.Keys|Sort-Object)-join "`n")){throw '[mir4-post-release-docs-scope]'}
  return $record
}
