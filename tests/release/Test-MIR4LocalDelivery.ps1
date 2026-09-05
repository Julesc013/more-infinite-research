# MIR4-CANONICAL-EXECUTABLE-TEST
param([string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $RepoRoot 'tools/mir/application/release/LocalDelivery.ps1')
$root=Join-Path $RepoRoot ('build/tests/local-delivery/'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $root 'source';$repo=Join-Path $root 'repo'
New-Item -ItemType Directory -Force -Path $source,$repo | Out-Null
[IO.File]::WriteAllText((Join-Path $source 'package.zip'),'exact accepted package')
[IO.File]::WriteAllText((Join-Path $source 'notes.md'),'matching release notes')
$files=@(
 [pscustomobject]@{source_path='package.zip';destination_path='package.zip';sha256=(Get-FileHash (Join-Path $source 'package.zip')).Hash},
 [pscustomobject]@{source_path='notes.md';destination_path='release/notes.md';sha256=(Get-FileHash (Join-Path $source 'notes.md')).Hash}
)
function Expect-Blocked([scriptblock]$Action,[string]$Code) {
 try { & $Action | Out-Null } catch { if($_.Exception.Message.Contains($Code)) { return }; throw }
 throw "Expected rejection: $Code"
}
Expect-Blocked { Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files $files -ReleaseId 'probe' -AfterCopy { throw 'simulated-process-loss' } } 'simulated-process-loss'
if(-not(Test-Path (Join-Path $repo 'build/delivery/probe/intent.json')) -or (Test-Path (Join-Path $repo 'build/delivery/probe/receipt.json'))) { throw 'Intent must precede effects and completion must await all files.' }
$result=Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files $files -ReleaseId 'probe'
if($result.status -cne 'delivered-and-verified' -or $result.files.Count -ne 2) { throw 'Resume did not complete exact files.' }
[void](Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files $files -ReleaseId 'probe')
$conflict=Join-Path $repo 'dist/release/notes.md'
[IO.File]::WriteAllText($conflict,'user material')
Expect-Blocked { Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files $files -ReleaseId 'probe' } 'destination-conflict'
if([IO.File]::ReadAllText($conflict) -cne 'user material') { throw 'Conflict was overwritten.' }
$bad=[pscustomobject]@{source_path='package.zip';destination_path='../escape.zip';sha256=$files[0].sha256}
Expect-Blocked { Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files @($bad) -ReleaseId 'unsafe' } 'delivery-path'
$bad.destination_path='new.zip';$bad.sha256='0'*64
Expect-Blocked { Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files @($bad) -ReleaseId 'unsafe' } 'source-identity'
Expect-Blocked { Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files @($files[0],$files[0]) -ReleaseId 'duplicate' } 'duplicate-destination'
Expect-Blocked { Invoke-MIR4LocalDelivery -RepoRoot $repo -SourceRoot $source -Files @($files[0]) -ReleaseId 'probe' } 'intent-conflict'
Write-Output 'Local delivery passed interruption/resume, idempotence, identity, conflict preservation, duplicate, traversal, and intent binding tests.'
