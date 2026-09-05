Set-StrictMode -Version Latest

if (-not (Get-Command Invoke-MIR4ReleaseNarrativesV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot '../ReleaseNarratives.ps1')
}

function Write-MIR441Text {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Text)
  $parent=Split-Path -Parent $Path
  if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
  [IO.File]::WriteAllText($Path,$Text.Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
}

function Get-MIR441DirectoryIdentities {
  param([Parameter(Mandatory)][string]$Root,[string[]]$Exclude=@())
  $full=[IO.Path]::GetFullPath($Root)
  foreach($path in [IO.Directory]::EnumerateFiles($full,'*',[IO.SearchOption]::AllDirectories)|Sort-Object){
    $relative=[IO.Path]::GetRelativePath($full,$path).Replace('\','/')
    if($relative-in$Exclude){continue}
    Get-MIR441FileIdentity -Path $path -RelativePath $relative
  }
}

function Get-MIR441PublicEngineIdentity {
  param([Parameter(Mandatory)]$Engine)
  $public=[ordered]@{}
  foreach($property in $Engine.PSObject.Properties){
    if([string]$property.Name-cne'path'){$public[[string]$property.Name]=$property.Value}
  }
  return [pscustomobject]$public
}

function New-MIR441DeterministicDirectoryArchive {
  param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$ArchivePath)
  Add-Type -AssemblyName System.IO.Compression
  $parent=Split-Path -Parent $ArchivePath;if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
  if(Test-Path -LiteralPath $ArchivePath){Remove-Item -LiteralPath $ArchivePath -Force}
  $stream=[IO.File]::Open($ArchivePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try {
    $archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true,[Text.Encoding]::UTF8)
    try {
      foreach($path in [IO.Directory]::EnumerateFiles([IO.Path]::GetFullPath($SourceRoot),'*',[IO.SearchOption]::AllDirectories)|Sort-Object){
        $relative=[IO.Path]::GetRelativePath($SourceRoot,$path).Replace('\','/')
        $entry=$archive.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime=[DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
        $input=[IO.File]::OpenRead($path);$output=$entry.Open()
        try{$input.CopyTo($output)}finally{$output.Dispose();$input.Dispose()}
      }
    } finally {$archive.Dispose()}
  } finally {$stream.Dispose()}
  return Get-MIR441FileIdentity -Path $ArchivePath -RelativePath ([IO.Path]::GetFileName($ArchivePath))
}

function Get-MIR441PrepareTagScriptText {
@'
[CmdletBinding()]
param([string]$RepoRoot='C:\Projects\Factorio\more-infinite-research',[string]$SigningKey='')
$ErrorActionPreference='Stop'
$window=$PSScriptRoot;$seal=Get-Content -Raw (Join-Path $window 'technical-seal.json')|ConvertFrom-Json -Depth 100
$tag=[string]$seal.release.tag;$source=[string]$seal.source.commit
git -C $RepoRoot fetch --prune origin | Out-Null;if($LASTEXITCODE-ne0){throw '[mir441-tag-fetch]'}
$remote=@(git -C $RepoRoot ls-remote --tags origin "refs/tags/$tag");if($LASTEXITCODE-ne0-or$remote.Count-ne0){throw '[mir441-tag-remote-present]'}
if([string]::IsNullOrWhiteSpace($SigningKey)){$SigningKey=[string](git -C $RepoRoot config --get user.signingkey)}
if([string]::IsNullOrWhiteSpace($SigningKey)-or-not(Test-Path -LiteralPath $SigningKey -PathType Leaf)){throw '[mir441-tag-signing-key-required]'}
$public="$SigningKey.pub";if(-not(Test-Path -LiteralPath $public -PathType Leaf)){throw '[mir441-tag-signing-public-key-required]'}
$email=[string](git -C $RepoRoot config --get user.email);if([string]::IsNullOrWhiteSpace($email)){throw '[mir441-tag-email-required]'}
$allowed=Join-Path $window 'allowed-signers';$publicText=[IO.File]::ReadAllText($public).Trim();[IO.File]::WriteAllText($allowed,"$email $publicText`n",[Text.UTF8Encoding]::new($false))
git -C $RepoRoot config gpg.format ssh;git -C $RepoRoot config user.signingkey $SigningKey;git -C $RepoRoot config gpg.ssh.allowedSignersFile $allowed
$existing=@(git -C $RepoRoot for-each-ref --format='%(objectname)' "refs/tags/$tag")
if($existing.Count-eq0){git -C $RepoRoot tag -s $tag $source -F (Join-Path $window 'tag-message.txt');if($LASTEXITCODE-ne0){throw '[mir441-tag-sign]'}}
$type=[string](git -C $RepoRoot cat-file -t "refs/tags/$tag");$peeled=[string](git -C $RepoRoot rev-parse "refs/tags/$tag^{}")
if($type.Trim()-cne'tag'-or$peeled.Trim()-cne$source){throw '[mir441-tag-object-identity]'}
git -C $RepoRoot verify-tag $tag | Out-Null;if($LASTEXITCODE-ne0){throw '[mir441-tag-signature-verification]'}
$receipt=[ordered]@{schema=1;kind='MIR441PreparedSignedTagV1';status='SIGNED-ANNOTATED-TAG-PREPARED-LOCAL-NOT-PUSHED';tag=$tag;tag_object=([string](git -C $RepoRoot rev-parse "refs/tags/$tag")).Trim();source_commit=$source;signature_verified=$true;remote_tag_absent=$true;publication_authorized=$false;prepared_at=[DateTimeOffset]::UtcNow.ToString('o')}
[IO.File]::WriteAllText((Join-Path $window 'prepared-tag.json'),(($receipt|ConvertTo-Json -Depth 20)+"`n"),[Text.UTF8Encoding]::new($false));$receipt
'@
}

function Get-MIR441PlaytestScriptText {
@'
[CmdletBinding()]
param([ValidateSet('f210','f200')][string]$Target='f210')
$ErrorActionPreference='Stop';$window=$PSScriptRoot
$seal=Get-Content -Raw (Join-Path $window 'technical-seal.json')|ConvertFrom-Json -Depth 100
$row=@($seal.targets|Where-Object target -eq $Target);if($row.Count-ne1){throw '[mir441-playtest-target]'}
$asset=Join-Path $window ([string]$row[0].asset.path);if((Get-FileHash $asset -Algorithm SHA256).Hash-cne[string]$row[0].asset.sha256){throw '[mir441-playtest-asset-drift]'}
$engine=[string]$row[0].engine.path;if((Get-FileHash $engine -Algorithm SHA256).Hash-cne[string]$row[0].engine.binary_sha256){throw '[mir441-playtest-engine-drift]'}
$session=Join-Path $window "playtest/$Target";$mods=Join-Path $session 'mods';$data=Join-Path $session 'data'
New-Item -ItemType Directory -Force -Path $mods,$data|Out-Null
Copy-Item -LiteralPath $asset -Destination (Join-Path $mods ([IO.Path]::GetFileName($asset))) -Force
$modList=[ordered]@{mods=@([ordered]@{name='base';enabled=$true},[ordered]@{name='more-infinite-research';enabled=$true})}
[IO.File]::WriteAllText((Join-Path $mods 'mod-list.json'),(($modList|ConvertTo-Json -Depth 10)+"`n"),[Text.UTF8Encoding]::new($false))
$config=Join-Path $session 'config.ini';$lines=@('[path]','read-data=__PATH__executable__/../../data',("write-data="+$data.Replace('\','/')),'[other]','check-updates=false')
[IO.File]::WriteAllText($config,(($lines-join"`n")+"`n"),[Text.UTF8Encoding]::new($false))
Start-Process -FilePath $engine -ArgumentList @('--config',$config,'--no-log-rotation','--mod-directory',$mods)
Write-Host "Launched exact $Target sealed package. Return GO or NO-GO only after the visual/gameplay check."
'@
}

function Get-MIR441FinalizeScriptText {
@'
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('GO','NO-GO')][string]$Decision,[Parameter(Mandatory)][string]$Reviewer,[string]$RepoRoot='C:\Projects\Factorio\more-infinite-research')
$ErrorActionPreference='Stop';if([string]::IsNullOrWhiteSpace($Reviewer)){throw '[mir441-final-reviewer]'}
$window=$PSScriptRoot;$seal=Get-Content -Raw (Join-Path $window 'technical-seal.json')|ConvertFrom-Json -Depth 100
$promotion=Get-Content -Raw (Join-Path $window 'main-promotion.json')|ConvertFrom-Json -Depth 50
$source=[string]$seal.source.commit;$tag=[string]$seal.release.tag
if([string]$promotion.status-cne'MIR41-SEALED-ON-MAIN-AWAITING-HUMAN-PLAYTEST'-or[string]$promotion.main_after-cne$source){throw '[mir441-final-promotion]'}
git -C $RepoRoot fetch --prune origin | Out-Null;if($LASTEXITCODE-ne0){throw '[mir441-final-fetch]'}
foreach($branch in 'dev','main'){$line=@(git -C $RepoRoot ls-remote --heads origin "refs/heads/$branch");if($line.Count-ne1-or-not([string]$line[0]).StartsWith($source,[StringComparison]::Ordinal)){throw "[mir441-final-ref] $branch"}}
foreach($row in @($seal.targets)){$asset=Join-Path $window ([string]$row.asset.path);if((Get-FileHash $asset -Algorithm SHA256).Hash-cne[string]$row.asset.sha256){throw "[mir441-final-asset] $([string]$row.target)"}}
$decisionReceipt=[ordered]@{schema=1;kind='MIR441HumanPlaytestDecisionV1';decision=$Decision;reviewer=$Reviewer;source_commit=$source;technical_seal_sha256=(Get-FileHash (Join-Path $window 'technical-seal.json') -Algorithm SHA256).Hash;decided_at=[DateTimeOffset]::UtcNow.ToString('o');decision_inferred=$false}
[IO.File]::WriteAllText((Join-Path $window 'human-playtest-decision.json'),(($decisionReceipt|ConvertTo-Json -Depth 20)+"`n"),[Text.UTF8Encoding]::new($false))
if($Decision-ceq'NO-GO'){Write-Host 'NO-GO recorded. No tag or release was pushed.';return}
$prepared=Get-Content -Raw (Join-Path $window 'prepared-tag.json')|ConvertFrom-Json -Depth 30
if([string]$prepared.source_commit-cne$source-or-not[bool]$prepared.signature_verified){throw '[mir441-final-prepared-tag]'}
if(([string](git -C $RepoRoot cat-file -t "refs/tags/$tag")).Trim()-cne'tag'-or([string](git -C $RepoRoot rev-parse "refs/tags/$tag^{}")).Trim()-cne$source){throw '[mir441-final-tag-object]'}
git -C $RepoRoot verify-tag $tag|Out-Null;if($LASTEXITCODE-ne0){throw '[mir441-final-tag-signature]'}
if(@(git -C $RepoRoot ls-remote --tags origin "refs/tags/$tag").Count-ne0){throw '[mir441-final-remote-tag-present]'}
git -C $RepoRoot push origin "refs/tags/$tag:refs/tags/$tag";if($LASTEXITCODE-ne0){throw '[mir441-final-tag-push]'}
$manifestPath=Join-Path $window 'mir-4.1.0.release.json';$manifest=Get-Content -Raw $manifestPath|ConvertFrom-Json -Depth 50
$releaseArgs=@('release','create',$tag,'--verify-tag','--draft','--title',[string]$manifest.title,'--notes-file',(Join-Path $window 'release-copy/github-release.md'))
foreach($asset in @($manifest.github_assets)){$releaseArgs+=((Join-Path $window ([string]$asset.path))+'#'+[string]$asset.label)}
$releaseArgs+=($manifestPath+'#'+[string]$manifest.manifest_asset.label)
& gh @releaseArgs;if($LASTEXITCODE-ne0){throw '[mir441-final-release-create]'}
$remote=gh release view $tag --json isDraft,assets,url|ConvertFrom-Json -Depth 30;if(-not[bool]$remote.isDraft-or@($remote.assets).Count-ne(@($manifest.github_assets).Count+1)){throw '[mir441-final-release-inventory]'}
gh release edit $tag --draft=false --latest;if($LASTEXITCODE-ne0){throw '[mir441-final-release-publish]'}
$readback=Join-Path $window 'public-readback';New-Item -ItemType Directory -Force -Path $readback|Out-Null;gh release download $tag --dir $readback --clobber;if($LASTEXITCODE-ne0){throw '[mir441-final-release-download]'}
foreach($asset in @($manifest.github_assets)){$path=Join-Path $readback ([IO.Path]::GetFileName([string]$asset.path));if((Get-FileHash $path -Algorithm SHA256).Hash-cne[string]$asset.sha256){throw "[mir441-final-public-byte] $([string]$asset.path)"}}
$manifestReadback=Join-Path $readback ([IO.Path]::GetFileName([string]$manifest.manifest_asset.path));if((Get-FileHash $manifestReadback -Algorithm SHA256).Hash-cne(Get-FileHash $manifestPath -Algorithm SHA256).Hash){throw '[mir441-final-public-manifest-byte]'}
$manifestIdentity=[ordered]@{path=[string]$manifest.manifest_asset.path;label=[string]$manifest.manifest_asset.label;sha256=(Get-FileHash $manifestPath -Algorithm SHA256).Hash.ToUpperInvariant();bytes=(Get-Item -LiteralPath $manifestPath).Length}
$receipt=[ordered]@{schema=1;kind='MIR441PublicationReceiptV1';status='GITHUB-PUBLISHED-PUBLIC-BYTES-VERIFIED';tag=$tag;source_commit=$source;url=[string]$remote.url;assets=@($manifest.github_assets)+@($manifestIdentity);mod_portal_payloads=@($manifest.mod_portal_payloads);published_at=[DateTimeOffset]::UtcNow.ToString('o')}
[IO.File]::WriteAllText((Join-Path $window 'publication-receipt.json'),(($receipt|ConvertTo-Json -Depth 50)+"`n"),[Text.UTF8Encoding]::new($false));$receipt
'@
}

function New-MIR441TechnicalSeal {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$WorkRoot,[Parameter(Mandatory)][string]$EvidenceRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path;$work=Assert-MIR441ExternalRoot -RepoRoot $repo -Path $WorkRoot -Name WorkRoot;$evidence=Assert-MIR441ExternalRoot -RepoRoot $repo -Path $EvidenceRoot -Name EvidenceRoot
  if(@(& git -C $repo status --porcelain).Count-ne0){throw '[mir441-seal-working-tree-dirty]'}
  $contract=Get-MIR441ReleaseReadinessContract -RepoRoot $repo;$source=Get-MIR441GitIdentity -RepoRoot $repo
  $independent=Get-Content -Raw -LiteralPath (Join-Path $evidence 'independent-verification.json')|ConvertFrom-Json -Depth 100 -DateKind String
  if([string]$independent.status-cne'MIR-4.1.0-FOUR-TARGET-INDEPENDENT-VERIFICATION-PASSED'-or[string]$independent.source.commit-cne[string]$source.commit-or[string]$independent.source.tree-cne[string]$source.tree){throw '[mir441-seal-independent-input]'}
  $window=Join-Path $evidence 'release-window';if(Test-Path -LiteralPath $window){Remove-MIR441ContainedTree -AdmittedRoot $evidence -Path $window};New-Item -ItemType Directory -Force -Path $window|Out-Null
  $copyRoot=Join-Path $window 'release-copy';$narratives=Invoke-MIR4ReleaseNarrativesV1 -RepoRoot $repo -PlanPath 'releases/governance/MIR4-Source-Changelog-PlanV1.json' -OutputRoot $copyRoot -Command render
  $targetRows=[Collections.Generic.List[object]]::new();$candidate=Get-Content -Raw -LiteralPath (Join-Path $evidence 'candidate-manifest.json')|ConvertFrom-Json -Depth 100
  foreach($target in @($independent.targets)){
    $id=[string]$target.target;$candidateRow=@($candidate.targets|Where-Object target -eq $id)[0];$sourceAsset=Join-Path $evidence "assets/$([string]$candidateRow.asset.path)";$relative="assets/$([string]$candidateRow.asset.path)";$destination=Join-Path $window $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)|Out-Null
    try{New-Item -ItemType HardLink -Path $destination -Target $sourceAsset -ErrorAction Stop|Out-Null}catch{Copy-Item -LiteralPath $sourceAsset -Destination $destination}
    $asset=Get-MIR441FileIdentity -Path $destination -RelativePath $relative
    if([string]$asset.sha256-cne[string]$target.archive.archive_sha256){throw "[mir441-seal-asset-copy] $id"}
    $targetRows.Add([pscustomobject][ordered]@{target=$id;distribution_version=[string]$target.distribution_version;asset=$asset;content_sha256=[string]$target.archive.content_sha256;entry_count=[int]$target.archive.entry_count;engine=$target.engine;qualification='passed';independent_verification='passed'})
  }
  $publicTargetRows=@($targetRows|ForEach-Object{[pscustomobject][ordered]@{target=$_.target;distribution_version=$_.distribution_version;asset=$_.asset;content_sha256=$_.content_sha256;entry_count=$_.entry_count;engine=(Get-MIR441PublicEngineIdentity -Engine $_.engine);qualification=$_.qualification;independent_verification=$_.independent_verification}})
  $checksumLines=@($targetRows|Sort-Object target|ForEach-Object{"$([string]$_.asset.sha256)  $([IO.Path]::GetFileName([string]$_.asset.path))"});Write-MIR441Text -Path (Join-Path $window 'SHA256SUMS.txt') -Text (($checksumLines-join"`n")+"`n")
  $qualification=[ordered]@{schema=1;kind='MIR441ReleaseQualificationSummaryV1';status='GO-4TARGET-TECHNICAL';source=$source;targets=@($publicTargetRows);human_playtest='pending';publication_authorized=$false};Write-MIR441Json -Value $qualification -Path (Join-Path $window 'mir-4.1.0.qualification.json')
  $labels=@($targetRows|ForEach-Object{[ordered]@{path=[string]$_.asset.path;label="MIR $([string]$_.distribution_version) for Factorio $([string]$_.engine.version)"}});Write-MIR441Json -Value ([ordered]@{schema=1;kind='MIR441AssetLabelMapV1';assets=$labels}) -Path (Join-Path $window 'asset-labels.json')
  Write-MIR441Json -Value ([ordered]@{schema=1;kind='MIR441KnownIssuesV1';release='4.1.0';issues=@();status='none-declared-at-seal'}) -Path (Join-Path $window 'known-issues.json')
  $upgrade=@('# MIR 4.1.0 upgrade guide','','Back up important saves and install only the package matching the running Factorio line.','','| Target | Upgrade |','| --- | --- |')+@($contract.targets|ForEach-Object{"| $([string]$_.target) | $([string]$_.predecessor) to $([string]$_.distribution_version) |"})+@('','Each direct transition has passed fresh load, migration/configuration reconciliation, first reload, second reload, settings, research state, stable-ID, runtime-state, and target-omission checks.');Write-MIR441Text -Path (Join-Path $window 'upgrade-guide.md') -Text (($upgrade-join"`n")+"`n")
  $provenance=[ordered]@{schema=1;kind='MIR441ReleaseProvenanceV1';source=$source;package_source_sha256=[string]$independent.package_source_sha256;materializer='tools/mir/application/package/TargetMaterializer.ps1';contract=(Get-MIR441FileIdentity -Path (Join-Path $repo 'governance/release/mir4-4.1-release-readiness-v1.json') -RelativePath 'governance/release/mir4-4.1-release-readiness-v1.json');outputs=@($publicTargetRows);builder='MIR441ReleaseReadiness';build_isolation='serial-external-roots-cleaned-after-custody'};Write-MIR441Json -Value $provenance -Path (Join-Path $window 'mir-4.1.0.provenance.json')
  $components=[ordered]@{schema=1;kind='MIR441ComponentInventoryV1';release='4.1.0';source_authorities=@('src/mod','targets','tools/mir/application/package/TargetMaterializer.ps1');player_assets=@($targetRows|ForEach-Object{[ordered]@{target=$_.target;path=$_.asset.path;sha256=$_.asset.sha256;entries=$_.entry_count}});developer_kit=[ordered]@{included=$false;reason='No separately supported SDK distribution is required by this player release; repository developer surfaces remain source-controlled and package-excluded.'}};Write-MIR441Json -Value $components -Path (Join-Path $window 'mir-4.1.0.components.json')
  Write-MIR441Text -Path (Join-Path $window 'tag-message.txt') -Text "MIR 4.1.0`n`nFour-target generated package and repository fixed point.`nSource: $([string]$source.commit)`n"
  Write-MIR441Text -Path (Join-Path $window 'Prepare-MIR410SignedTag.ps1') -Text (Get-MIR441PrepareTagScriptText)
  Write-MIR441Text -Path (Join-Path $window 'Start-MIR410Playtest.ps1') -Text (Get-MIR441PlaytestScriptText)
  Write-MIR441Text -Path (Join-Path $window 'Finalize-MIR410.ps1') -Text (Get-MIR441FinalizeScriptText)
  $githubAssets=@($targetRows|ForEach-Object{[ordered]@{path=$_.asset.path;label=(@($labels|Where-Object path -eq $_.asset.path)[0].label);sha256=$_.asset.sha256;bytes=$_.asset.bytes}})
  foreach($name in 'SHA256SUMS.txt','mir-4.1.0.qualification.json','mir-4.1.0.provenance.json','mir-4.1.0.components.json'){
    $i=Get-MIR441FileIdentity -Path (Join-Path $window $name) -RelativePath $name
    $label=switch($name){'SHA256SUMS.txt'{'SHA-256 checksums'};'mir-4.1.0.qualification.json'{'Four-target qualification summary'};'mir-4.1.0.provenance.json'{'Build provenance'};default{'Component inventory'}}
    $githubAssets+=,[ordered]@{path=$i.path;label=$label;sha256=$i.sha256;bytes=$i.bytes}
  }
  $releaseManifest=[ordered]@{schema=1;kind='MIR441ReleaseManifestV1';status='technically-qualified-unpublished';title='MIR 4.1.0';tag='v4.1.0';source=$source;github_assets=$githubAssets;manifest_asset=[ordered]@{path='mir-4.1.0.release.json';label='Release manifest'};mod_portal_payloads=@($targetRows|ForEach-Object{[ordered]@{target=$_.target;package=$_.asset.path;copy="release-copy/$([string]$_.target)/mod-portal.md"}});human_playtest='pending';tagging_authorized=$false;publication_authorized=$false};Write-MIR441Json -Value $releaseManifest -Path (Join-Path $window 'mir-4.1.0.release.json')
  $core=@(Get-MIR441DirectoryIdentities -Root $window)
  $seal=[ordered]@{schema=1;kind='MIR441TechnicalSealV1';status='MIR41-TECHNICALLY-SEALED-AWAITING-EXACT-MAIN-PROMOTION';release=[ordered]@{source_version='4.1.0';tag='v4.1.0'};source=$source;targets=@($targetRows);package_source_sha256=[string]$independent.package_source_sha256;package_authority=(Get-MIR441FileIdentity -Path (Join-Path $repo 'targets/package-authority.json') -RelativePath 'targets/package-authority.json');narrative_result_digest=[string]$narratives.result_digest;independent_verification=(Get-MIR441FileIdentity -Path (Join-Path $evidence 'independent-verification.json') -RelativePath '../independent-verification.json');sealed_objects=$core;human_playtest='pending';tag_object='pending-local-signing-custody';tagging_authorized=$false;publication_authorized=$false;sealed_at=[DateTimeOffset]::UtcNow.ToString('o');record_sha256=''}
  $seal.record_sha256=Get-MIR4BootstrapRecordSha256 -Record ([pscustomobject]$seal);Write-MIR441Json -Value $seal -Path (Join-Path $window 'technical-seal.json')
  $custody=[ordered]@{schema=1;kind='MIR441ReleaseWindowCustodyV1';status='verified-prepromotion-custody';source=$source;objects=@(Get-MIR441DirectoryIdentities -Root $window);technical_seal_sha256=(Get-FileHash (Join-Path $window 'technical-seal.json') -Algorithm SHA256).Hash.ToUpperInvariant()};Write-MIR441Json -Value $custody -Path (Join-Path $window 'custody-manifest.json')
  $capsule=New-MIR441DeterministicDirectoryArchive -SourceRoot $window -ArchivePath (Join-Path $evidence 'MIR4_4.1.0_RELEASE_WINDOW.zip')
  $restore=Join-Path $work ("restore-"+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Force -Path $restore|Out-Null
  try{[IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $evidence $capsule.path),$restore);foreach($item in @($custody.objects)){if((Get-FileHash -LiteralPath (Join-Path $restore ([string]$item.path)) -Algorithm SHA256).Hash-cne[string]$item.sha256){throw "[mir441-seal-restore] $([string]$item.path)"}}}finally{if(Test-Path -LiteralPath $restore){Remove-MIR441ContainedTree -AdmittedRoot $work -Path $restore}}
  $ready=[ordered]@{schema=1;kind='MIR441ReleaseWindowReadinessV1';status='TECHNICALLY-SEALED-AWAITING-EXACT-MAIN-PROMOTION';source=$source;technical_seal=(Get-MIR441FileIdentity -Path (Join-Path $window 'technical-seal.json') -RelativePath 'release-window/technical-seal.json');custody=(Get-MIR441FileIdentity -Path (Join-Path $window 'custody-manifest.json') -RelativePath 'release-window/custody-manifest.json');capsule=$capsule;offline_restore='passed';human_playtest='pending';publication_authorized=$false};Write-MIR441Json -Value $ready -Path (Join-Path $evidence 'release-window-readiness.json')
  return [pscustomobject]$ready
}
