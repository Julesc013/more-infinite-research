[CmdletBinding()]
param([string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path,[switch]$Check)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $RepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
. (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
. (Join-Path $RepoRoot 'tools/lib/mir4/PostReleaseDocumentation.ps1')
if($Check){$existing=Get-MIR4PostReleaseDocumentation -RepoRoot $RepoRoot;if($null -eq $existing){throw 'No documentation successor is recorded'};Write-Host '[ok] post-release documentation record verified';return}
$relative='releases/migrations/MIR4-M41-Readme-RestorationV1.json'
$recordPath=Join-Path $RepoRoot $relative
# Once a receipt is committed, preserve it. A later change needs a successor.
& git -C $RepoRoot cat-file -e ('HEAD:'+$relative) 2>$null
if($LASTEXITCODE -eq 0){throw 'The committed documentation receipt is immutable; create a successor for later work.'}
. (Join-Path $RepoRoot 'tools/mir/application/tooling/CommandInventory.ps1')
$null=Update-MIR4CommandInventoryV1 -RepoRoot $RepoRoot
$base='3562377b520cccb071b97b3968946eae7024c950'
$changed=@(& git -C $RepoRoot diff --name-only $base --)
if($LASTEXITCODE -ne 0){throw 'Cannot inspect documentation changes'}
$untracked=@(& git -C $RepoRoot ls-files --others --exclude-standard)
if($LASTEXITCODE -ne 0){throw 'Cannot inspect untracked files'}
$paths=@($changed+$untracked|ForEach-Object{([string]$_).Replace('\','/')}|Where-Object{$_ -and $_ -cne $relative}|Sort-Object -Unique)
$allowed=@(Get-MIR4PostReleaseDocumentationPaths)
$rows=@(foreach($name in $paths){
 if($name -cnotin $allowed){throw "Not in the authorized documentation correction: $name"}
 $object=$base+':'+$name
 & git -C $RepoRoot cat-file -e $object 2>$null
 $previous=$null
 if($LASTEXITCODE -eq 0){$lines=@(& git -C $RepoRoot show $object);if($LASTEXITCODE -ne 0){throw 'Cannot read predecessor'};$previous=Get-MIR4Sha256String -Value (($lines -join "`n")+"`n")}
 [pscustomobject][ordered]@{path=$name;previous_sha256=$previous;current_sha256=(Get-MIR4BootstrapTextSha256 -Path (Join-Path $RepoRoot $name))}
})
$predecessor='releases/migrations/MIR4-M41-Source-Freeze-Authority-EvolutionV1.json'
$record=[pscustomobject][ordered]@{
 schema=1;kind='MIR4PostReleaseDocumentationV1';recorded_at=[DateTimeOffset]::UtcNow.ToString('o')
 authorization='Maintainer requested restoration of the existing README detail and delivery into the primary checkout on 2026-09-05.'
 base_commit=$base;tag_object='9e5e63ef45b9d583d3f463fbfa737eb2c3a6b69f'
 predecessor=[pscustomobject][ordered]@{path=$predecessor;sha256=(Get-FileHash -LiteralPath (Join-Path $RepoRoot $predecessor) -Algorithm SHA256).Hash}
 package_source_sha256=(Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot)
 package_visible_delta=@();release_transition_authority=$false;bindings=$rows;record_sha256=''
}
$record.record_sha256=Get-MIR4BootstrapRecordSha256 -Record $record
[IO.File]::WriteAllText($recordPath,($record|ConvertTo-Json -Depth 10)+"`n",[Text.UTF8Encoding]::new($false))
$null=Get-MIR4PostReleaseDocumentation -RepoRoot $RepoRoot
Write-Host "[ok] documentation successor binds $($rows.Count) package-excluded paths"
