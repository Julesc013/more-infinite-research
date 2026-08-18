param(
  [string]$RepoRoot='',
  [ValidateSet('all','f018','f017','f016','f015','f014','f013')][string]$Target='all',
  [ValidateRange(3,3)][int]$Repetitions=3,
  [switch]$Check
)
$ErrorActionPreference='Stop'
if(-not $RepoRoot){$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path}else{$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path}
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
$authorityPath=Join-Path $RepoRoot '.mir/releases/waves/mir4-r0/MIR4-Historical-Private-Candidate-AuthorizationV1.json'
$authorityText=Get-Content -Raw -LiteralPath $authorityPath
if(-not($authorityText|Test-Json -SchemaFile (Join-Path $RepoRoot 'spec/schemas/mir4-historical-private-candidate-authorization.schema.json'))){throw '[mir4-historical-authority-schema]'}
$authority=$authorityText|ConvertFrom-Json -Depth 100
if(-not(Test-MIR4BootstrapRecordHash -Record $authority)){throw '[mir4-historical-authority-hash]'}
foreach($flag in @('semantic_authority','public_output_authorized','signing_or_sealing_authorized','publication_authorized')){if([bool]$authority.$flag){throw "[mir4-historical-boundary] $flag"}}
$outputRoot=[IO.Path]::GetFullPath((Join-Path $RepoRoot ([string]$authority.output_root)))
$outputRoot=Assert-MIR4DescendantPath -Root (Join-Path $RepoRoot 'build/mir4') -Path $outputRoot
$targets=@($authority.targets|Where-Object{$Target-eq'all'-or$_.target_key-eq$Target})

function Test-HistoricalProjection($row,[string]$candidatePath){
  $predecessorPath=Join-Path $RepoRoot ([string]$row.predecessor_archive)
  $pre=Get-MIR4ArchiveInventory -Path $predecessorPath;$candidate=Get-MIR4ArchiveInventory -Path $candidatePath
  $preNames=@($pre.entries|ForEach-Object{$_.path});$candidateNames=@($candidate.entries|ForEach-Object{$_.path})
  if(@(Compare-Object -ReferenceObject $preNames -DifferenceObject $candidateNames).Count-ne 0){throw "[mir4-historical-surface] $($row.target_key)"}
  foreach($name in $preNames){if($name-eq'info.json'){continue};$a=$pre.entries|Where-Object path -eq $name;$b=$candidate.entries|Where-Object path -eq $name;if($a.sha256-cne$b.sha256){throw "[mir4-historical-content] $($row.target_key):$name"}}
  $info=Read-MIR4ArchiveText -Path $candidatePath -RelativePath 'info.json'|ConvertFrom-Json
  if([string]$info.version-cne[string]$row.distribution_version){throw "[mir4-historical-version] $($row.target_key)"}
  if([string]$info.factorio_version-cne[string]$row.factorio_line){throw "[mir4-historical-factorio-line] $($row.target_key)"}
  return $candidate
}

foreach($row in $targets){
  $predecessorPath=Join-Path $RepoRoot ([string]$row.predecessor_archive)
  if((Get-FileHash -LiteralPath $predecessorPath -Algorithm SHA256).Hash-cne[string]$row.predecessor_archive_sha256){throw "[mir4-historical-predecessor-hash] $($row.target_key)"}
  $snapshot=Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ([string]$row.predecessor_snapshot))|ConvertFrom-Json
  if([string]$snapshot.record_sha256-cne[string]$row.predecessor_snapshot_record_sha256){throw "[mir4-historical-snapshot] $($row.target_key)"}
  $hashes=@();$inventories=@();$letters=@('A','B','C')
  foreach($letter in $letters){
    $candidatePath=Join-Path $outputRoot "candidates/$($row.target_key)/$letter/more-infinite-research_$($row.distribution_version).zip"
    if(-not $Check){
      $work=Join-Path $outputRoot "work/$($row.target_key)-$letter"
      Expand-MIR4SafeArchive -ArchivePath $predecessorPath -Destination $work -OutputRoot $outputRoot
      $sourceRoot=Join-Path $work "more-infinite-research_$($row.predecessor_release)"
      $infoPath=Join-Path $sourceRoot 'info.json'
      Set-MIR4InfoVersion -InfoPath $infoPath -Version ([string]$row.distribution_version)
      if([string]$row.target_key-eq'f018'){
        $text=[IO.File]::ReadAllText($infoPath).Replace('"factorio_version": "0.17"','"factorio_version": "0.18"').Replace('"base >= 0.17"','"base >= 0.18"')
        [IO.File]::WriteAllText($infoPath,$text,[Text.UTF8Encoding]::new($false))
      }
      Write-MIR4DeterministicArchive -SourceRoot $sourceRoot -EntryRoot "more-infinite-research_$($row.distribution_version)" -OutputPath $candidatePath -ContainmentRoot $outputRoot
      Remove-MIR4BuildTree -OutputRoot $outputRoot -Path $work
    }
    if(-not(Test-Path -LiteralPath $candidatePath -PathType Leaf)){throw "[mir4-historical-candidate-missing] $candidatePath"}
    $inventory=Test-HistoricalProjection $row $candidatePath
    $hash=(Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
    $hashes+=$hash;$inventories+=$inventory
  }
  if(@($hashes|Sort-Object -Unique).Count-ne 1){throw "[mir4-historical-nondeterministic] $($row.target_key)"}
  $distribution=Join-Path $outputRoot "distributions/more-infinite-research_$($row.distribution_version).zip"
  if(-not $Check){New-Item -ItemType Directory -Force -Path (Split-Path $distribution -Parent)|Out-Null;Copy-Item -LiteralPath (Join-Path $outputRoot "candidates/$($row.target_key)/A/more-infinite-research_$($row.distribution_version).zip") -Destination $distribution -Force}
  if((Get-FileHash -LiteralPath $distribution -Algorithm SHA256).Hash-cne$hashes[0]){throw "[mir4-historical-distribution] $($row.target_key)"}
  $manifest=[pscustomobject][ordered]@{schema=1;kind='MIR4HistoricalPrivateCandidateManifestV1';status='built-unqualified-private-experimental';target_key=[string]$row.target_key;factorio_line=[string]$row.factorio_line;source_version='4.0.0';distribution_version=[string]$row.distribution_version;predecessor=[ordered]@{release=[string]$row.predecessor_release;archive=[string]$row.predecessor_archive;sha256=[string]$row.predecessor_archive_sha256};projection=[string]$row.projection;builds=@($letters|ForEach-Object{[ordered]@{id=$_;sha256=$hashes[0]}});distribution=[ordered]@{path=[IO.Path]::GetRelativePath($RepoRoot,$distribution).Replace('\','/');sha256=$hashes[0];bytes=(Get-Item $distribution).Length;entries=@($inventories[0].entries).Count};runtime=[ordered]@{status='not-run';engine=$row.engine};public_claim=$false;record_sha256=''}
  $manifest.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $manifest
  $manifestPath=Join-Path $outputRoot "manifests/$($row.target_key).json"
  if($Check){$existing=Get-Content -Raw -LiteralPath $manifestPath|ConvertFrom-Json -Depth 50;if(-not(Test-MIR4BootstrapRecordHash -Record $existing)-or[string]$existing.distribution.sha256-cne$hashes[0]){throw "[mir4-historical-manifest] $($row.target_key)"}}else{Write-MIR4BootstrapRecord -Path $manifestPath -Record $manifest}
}
Write-Host "MIR 4 historical private candidate $Target $(if($Check){'check'}else{'build'}) passed."
