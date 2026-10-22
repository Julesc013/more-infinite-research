Set-StrictMode -Version Latest

# A narrow native consumer for the current performance patch. It uses the
# repository's direct-library transaction and creates only selection, config,
# log, save, and result files under the caller-owned output root.
. (Join-Path $PSScriptRoot '../compatibility/LibraryActivation.ps1')
. (Join-Path $PSScriptRoot 'NativeProbeResources.ps1')
. (Join-Path $PSScriptRoot 'ResponsiveMenuRecord.ps1')

function Assert-MIRDirectLibraryStartupMeasurement {
  param([bool]$Condition,[string]$Code)
  if(-not $Condition){throw "[mir-direct-startup-$Code]"}
}

# Admission remains the ResourceGovernor's responsibility. This bounded
# pre-launch wait only gives transient RAM/commit headroom a chance to recover;
# it neither changes reserves nor retries a sample after governed launch begins.
function Wait-MIRDirectLibraryStartupAdmission {
  param(
    [Parameter(Mandatory)]$Policy,
    [Parameter(Mandatory)][string]$WorkRoot,
    [Parameter(Mandatory)][int64]$EstimatedPeakBytes,
    [Parameter(Mandatory)][int64]$ExpectedPeakMemoryBytes,
    [ValidateRange(0,300)][int]$AdmissionWaitSeconds=0,
    [Parameter(Mandatory)][string]$Phase
  )
  $record=New-MIR441PreStartAdmissionWait -AdmissionWaitSeconds $AdmissionWaitSeconds -Phase $Phase
  Wait-MIR441PreStartResourceAdmission -Policy $Policy -WorkRoot $WorkRoot -EstimatedPeakBytes $EstimatedPeakBytes -ExpectedPeakMemoryBytes $ExpectedPeakMemoryBytes -State $record
}

function Get-MIRDirectLibraryStartupArchive {
  param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$LibraryDirectory)
  $library=(Resolve-Path -LiteralPath $LibraryDirectory).Path
  $path=(Resolve-Path -LiteralPath $Archive).Path
  Assert-MIRLibraryPath $path
  Assert-MIRDirectLibraryStartupMeasurement ([IO.Path]::GetDirectoryName($path) -ceq $library) 'archive-not-in-selected-library'
  $zip=[IO.Compression.ZipFile]::OpenRead($path)
  try {
    $entries=@($zip.Entries|Where-Object {$_.FullName -match '^[^/]+/info[.]json$'})
    Assert-MIRDirectLibraryStartupMeasurement ($entries.Count -eq 1 -and $entries[0].Length -le 64KB) 'archive-metadata'
    $reader=[IO.StreamReader]::new($entries[0].Open())
    try {$info=$reader.ReadToEnd()|ConvertFrom-Json -AsHashtable} finally {$reader.Dispose()}
  } finally {$zip.Dispose()}
  Assert-MIRDirectLibraryStartupMeasurement ([string]$info.name -ceq 'more-infinite-research') 'archive-name'
  Assert-MIRDirectLibraryStartupMeasurement ([string]$info.version -match '^4[.][0-9]{1,5}[.]\d{5}$') 'archive-version'
  Assert-MIRDirectLibraryStartupMeasurement ([IO.Path]::GetFileName($path) -ceq ('more-infinite-research_'+[string]$info.version+'.zip')) 'archive-filename'
  $root=$entries[0].FullName.Substring(0,$entries[0].FullName.Length-'/info.json'.Length)
  Assert-MIRDirectLibraryStartupMeasurement ($root -ceq ([string]$info.name+'_'+[string]$info.version)) 'archive-root'
  [pscustomobject][ordered]@{path=$path;name=[string]$info.name;version=[string]$info.version;root=$root;factorio_version=[string]$info.factorio_version;sha256=Get-MIRImmutableInputSha256 -Path $path}
}

function Get-MIRDirectLibraryPlayerReadyObserverArchive {
  param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][ValidateSet('f200','f210')][string]$Target)
  $library=(Resolve-Path -LiteralPath $LibraryDirectory).Path
  $path=(Resolve-Path -LiteralPath $Archive).Path
  Assert-MIRLibraryPath $path
  Assert-MIRDirectLibraryStartupMeasurement ([IO.Path]::GetDirectoryName($path) -ceq $library) 'player-ready-observer-not-in-selected-library'
  $zip=[IO.Compression.ZipFile]::OpenRead($path)
  try {
    $infoEntries=@($zip.Entries|Where-Object {$_.FullName -match '^[^/]+/info[.]json$'})
    Assert-MIRDirectLibraryStartupMeasurement ($infoEntries.Count -eq 1 -and $infoEntries[0].Length -le 64KB) 'player-ready-observer-metadata'
    $root=$infoEntries[0].FullName.Substring(0,$infoEntries[0].FullName.Length-'info.json'.Length).TrimEnd('/')
    $reader=[IO.StreamReader]::new($infoEntries[0].Open())
    try {$info=$reader.ReadToEnd()|ConvertFrom-Json -AsHashtable} finally {$reader.Dispose()}
    Assert-MIRDirectLibraryStartupMeasurement (Test-MIRLibraryModName ([string]$info.name)) 'player-ready-observer-name'
    Assert-MIRDirectLibraryStartupMeasurement ([string]$info.version -match '^\d+[.]\d+[.]\d+$') 'player-ready-observer-version'
    Assert-MIRDirectLibraryStartupMeasurement ($root -ceq ([string]$info.name+'_'+[string]$info.version)) 'player-ready-observer-root'
    Assert-MIRDirectLibraryStartupMeasurement ([IO.Path]::GetFileName($path) -ceq ($root+'.zip')) 'player-ready-observer-filename'
    $line=if($Target-ceq'f200'){'2.0'}else{'2.1'}
    Assert-MIRDirectLibraryStartupMeasurement ([string]$info.factorio_version -ceq $line) 'player-ready-observer-target'
    $dependencies=@($info.dependencies)
    Assert-MIRDirectLibraryStartupMeasurement ($dependencies.Count -eq 1 -and [string]$dependencies[0] -ceq 'base') 'player-ready-observer-dependencies'
    $files=@($zip.Entries|Where-Object {-not $_.FullName.EndsWith('/')})
    $expected=@(
      ($root+'/control.lua')
      ($root+'/info.json')
    )|Sort-Object
    Assert-MIRDirectLibraryStartupMeasurement ($files.Count -eq 2 -and ((@($files.FullName|Sort-Object) -join "`n") -ceq ($expected -join "`n"))) 'player-ready-observer-surface'
    $control=@($files|Where-Object {$_.FullName -ceq ($root+'/control.lua')})
    Assert-MIRDirectLibraryStartupMeasurement ($control.Count -eq 1 -and $control[0].Length -gt 0 -and $control[0].Length -le 64KB) 'player-ready-observer-control'
    $controlReader=[IO.StreamReader]::new($control[0].Open())
    try {$controlText=$controlReader.ReadToEnd()} finally {$controlReader.Dispose()}
    Assert-MIRDirectLibraryStartupMeasurement ($controlText.Contains('[MIR_ACTIVE_MODS]')-and$controlText.Contains('[MIR_PLAYER_READY]')) 'player-ready-observer-markers'
  } finally {$zip.Dispose()}
  [pscustomobject][ordered]@{path=$path;name=[string]$info.name;version=[string]$info.version;sha256=Get-MIRImmutableInputSha256 -Path $path;target=$Target;marker='MIR_PLAYER_READY';marker_file='factorio-current.log';scenario='base-only-player-ready-observer-v1'}
}

function Assert-MIRDirectLibraryBaselineManifest {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string]$ExpectedSha256,
    [Parameter(Mandatory)]$PublishedArchive,
    [Parameter(Mandatory)][ValidateSet('f200','f210')][string]$Target,
    [Parameter(Mandatory)][string]$SourceVersion
  )
  . (Join-Path $RepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
  $identity=Resolve-MIR4CanonicalPackageIdentity -RepoRoot $RepoRoot -Target $Target -SourceVersion $SourceVersion
  Assert-MIRDirectLibraryStartupMeasurement ($identity.source_version -ceq $SourceVersion) 'published-source-canonical'
  Assert-MIRDirectLibraryStartupMeasurement ($ExpectedSha256 -match '^[A-Fa-f0-9]{64}$') 'published-manifest-expected-hash'
  $path=(Resolve-Path -LiteralPath $ManifestPath).Path;$actual=Get-MIRImmutableInputSha256 -Path $path
  Assert-MIRDirectLibraryStartupMeasurement ($actual -ceq $ExpectedSha256.ToUpperInvariant()) 'published-manifest-hash'
  $manifest=Get-Content -Raw -LiteralPath $path|ConvertFrom-Json -Depth 100 -DateKind String
  Assert-MIRDirectLibraryStartupMeasurement ($manifest.PSObject.Properties['schema'] -and ($manifest.schema -is [int] -or $manifest.schema -is [long]) -and $manifest.schema -in @(1,13)) 'published-manifest-schema'
  $manifestSourceVersion=''
  if($manifest.PSObject.Properties['release']){$manifestSourceVersion=[string]$manifest.release.source_version}
  elseif($manifest.PSObject.Properties['source_version']){$manifestSourceVersion=[string]$manifest.source_version}
  elseif($manifest.schema -eq 13 -and $manifest.PSObject.Properties['target_authority']){
    $authorities=@($manifest.target_authority|Where-Object {[string]$_.target -ceq $Target})
    Assert-MIRDirectLibraryStartupMeasurement ($authorities.Count -eq 1) 'published-manifest-target-authority'
    Assert-MIRDirectLibraryStartupMeasurement ([string]$authorities[0].distribution_version -ceq [string]$identity.distribution_version) 'published-manifest-target-authority'
    $manifestSourceVersion=[string]$authorities[0].source_version
  }
  Assert-MIRDirectLibraryStartupMeasurement ($manifestSourceVersion -ceq $SourceVersion) 'published-manifest-release'
  $surfaces=@('package_assets','targets','assets'|Where-Object {$manifest.PSObject.Properties[$_]})
  Assert-MIRDirectLibraryStartupMeasurement ($surfaces.Count -eq 1) 'published-manifest-surface'
  $rows=@($manifest.($surfaces[0])|Where-Object {[string]$_.target -ceq $Target})
  Assert-MIRDirectLibraryStartupMeasurement ($rows.Count -eq 1) 'published-manifest-target'
  $row=$rows[0]
  Assert-MIRDirectLibraryStartupMeasurement (($manifest.schema -eq 1 -and -not $row.PSObject.Properties['asset']) -or ($manifest.schema -eq 13 -and $row.PSObject.Properties['asset'] -and [string]$manifest.kind -ceq 'MIR42FourTargetDeterministicCandidateManifestV13')) 'published-manifest-schema'
  $asset=if($row.PSObject.Properties['asset']){$row.asset}else{$row}
  Assert-MIRDirectLibraryStartupMeasurement ([string]$row.distribution_version -ceq [string]$identity.distribution_version -and [string]$PublishedArchive.version -ceq [string]$identity.distribution_version -and [string]$asset.sha256 -ceq [string]$PublishedArchive.sha256) 'published-manifest-archive'
  if($asset.PSObject.Properties['filename']){Assert-MIRDirectLibraryStartupMeasurement ([string]$asset.filename -ceq [IO.Path]::GetFileName([string]$PublishedArchive.path)) 'published-manifest-filename'}
  if($asset.PSObject.Properties['path']){Assert-MIRDirectLibraryStartupMeasurement ([IO.Path]::GetFileName([string]$asset.path) -ceq [IO.Path]::GetFileName([string]$PublishedArchive.path)) 'published-manifest-filename'}
  Assert-MIRDirectLibraryStartupMeasurement ([string]$PublishedArchive.root -ceq [string]$identity.distribution_root -and [string]$PublishedArchive.factorio_version -ceq $(if($Target -ceq 'f200'){'2.0'}else{'2.1'})) 'published-archive-root-target'
  return [pscustomobject][ordered]@{path=$path;sha256=$actual;source_version=$manifestSourceVersion;source_commit=$(if($manifest.PSObject.Properties['source']){[string]$manifest.source.commit}else{''});source_tree=$(if($manifest.PSObject.Properties['source']){[string]$manifest.source.tree}else{''});target=$Target;archive_sha256=[string]$asset.sha256}
}

# Retain the old named caller with its original 4.2.2 contract. New callers
# use the same canonical reader with an explicitly selected baseline.
function Assert-MIRDirectLibraryPublished422Manifest {
  param([Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$ExpectedSha256,[Parameter(Mandatory)]$PublishedArchive,[Parameter(Mandatory)][string]$Target,[string]$RepoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path)
  Assert-MIRDirectLibraryBaselineManifest -RepoRoot $RepoRoot -ManifestPath $ManifestPath -ExpectedSha256 $ExpectedSha256 -PublishedArchive $PublishedArchive -Target $Target -SourceVersion '4.2.2'
}

function Get-MIRDirectLibraryStartupEngineIdentity {
  param([Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$EngineDataDirectory)
  $base=Get-Content -Raw -LiteralPath (Join-Path $EngineDataDirectory 'base/info.json')|ConvertFrom-Json -Depth 20
  $file=Get-Item -LiteralPath $FactorioBin
  [pscustomobject][ordered]@{path=$file.FullName;sha256=Get-MIRImmutableInputSha256 -Path $file.FullName;file_version=[string]$file.VersionInfo.FileVersion;product_version=[string]$file.VersionInfo.ProductVersion;base_version=[string]$base.version}
}

function Read-MIRDirectLibraryStartupProfile {
  param([Parameter(Mandatory)][string]$Path)
  $value=(Get-Content -Raw -LiteralPath $Path).TrimStart([char]0xFEFF)|ConvertFrom-Json -AsHashtable
  Assert-MIRDirectLibraryStartupMeasurement ($value.ContainsKey('mods') -and $value.mods -is [array]) 'profile-shape'
  $rows=@($value.mods)
  Assert-MIRDirectLibraryStartupMeasurement ($rows.Count -gt 0 -and @($rows|Group-Object name|Where-Object Count -gt 1).Count -eq 0) 'profile-rows'
  foreach($row in $rows){
    Assert-MIRDirectLibraryStartupMeasurement ($row.enabled -is [bool] -and (Test-MIRLibraryModName ([string]$row.name))) 'profile-row'
    if($row.enabled){Assert-MIRDirectLibraryStartupMeasurement ([string]$row.version -match '^\d+[.]\d+[.]\d+$') 'profile-version'}
  }
  Assert-MIRDirectLibraryStartupMeasurement (@($rows|Where-Object {$_.enabled -and $_.name -ceq 'base'}).Count -eq 1) 'profile-base'
  return @($rows|Where-Object {$_.name -cne 'more-infinite-research'})
}

function Write-MIRDirectLibraryStartupProfile {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][object[]]$BaseRows,[AllowNull()]$MirArchive)
  $rows=[Collections.Generic.List[object]]::new()
  foreach($row in $BaseRows){$rows.Add([ordered]@{name=[string]$row.name;version=[string]$row.version;enabled=[bool]$row.enabled})}
  if($null -ne $MirArchive){$rows.Add([ordered]@{name='more-infinite-research';version=[string]$MirArchive.version;enabled=$true})}
  [IO.File]::WriteAllText($Path,([ordered]@{mods=@($rows)}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}

function Add-MIRDirectLibraryPlayerReadyObserverSelection {
  param([Parameter(Mandatory)][object[]]$BaseRows,[Parameter(Mandatory)]$Observer)
  $rows=[Collections.Generic.List[object]]::new()
  foreach($row in $BaseRows){$rows.Add([pscustomobject]@{name=[string]$row.name;version=[string]$row.version;enabled=[bool]$row.enabled})}
  $matches=@($rows|Where-Object {$_.name -ceq [string]$Observer.name})
  Assert-MIRDirectLibraryStartupMeasurement ($matches.Count -le 1) 'player-ready-observer-profile-duplicate'
  if($matches.Count -eq 1){
    Assert-MIRDirectLibraryStartupMeasurement ([bool]$matches[0].enabled -and [string]$matches[0].version -ceq [string]$Observer.version) 'player-ready-observer-profile'
  } else {
    $rows.Add([pscustomobject]@{name=[string]$Observer.name;version=[string]$Observer.version;enabled=$true})
  }
  return @($rows)
}

function Get-MIRDirectLibraryStartupArchiveHashes {
  param([Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$EngineDataDirectory,[Parameter(Mandatory)][object[]]$BaseRows,[AllowNull()]$MirArchive)
  $inventory=@(Get-MIRLibraryInventory -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory)
  $wanted=@($BaseRows|Where-Object enabled)
  if($null -ne $MirArchive){$wanted+=,[pscustomobject]@{name='more-infinite-research';version=[string]$MirArchive.version;enabled=$true}}
  $hashes=@{}
  foreach($row in $wanted){
    $matches=@($inventory|Where-Object {$_.name -ceq [string]$row.name -and $_.version -ceq [string]$row.version})
    Assert-MIRDirectLibraryStartupMeasurement ($matches.Count -eq 1) 'selected-archive-missing'
    if(-not $matches[0].builtin){$hashes[[IO.Path]::GetFileName([string]$matches[0].path)]=Get-MIRImmutableInputSha256 -Path ([string]$matches[0].path)}
  }
  return $hashes
}

function New-MIRDirectLibraryStartupConfig {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$EngineDataDirectory,[Parameter(Mandatory)][string]$WriteDataDirectory,[switch]$Graphics)
  $text="[path]`nread-data=$EngineDataDirectory`nwrite-data=$WriteDataDirectory`n`n[general]`nlocale=en`n`n[other]`nenable-new-mods=false`nenable-steam-networking=false`ndisable-blueprint-storage=true`n"
  if($Graphics){$text+="`n[graphics]`nfull-screen=false`ncache-sprite-atlas=false`n"}
  [IO.File]::WriteAllText($Path,$text,[Text.UTF8Encoding]::new($false))
}

function Get-MIRDirectLibraryStartupTextSha256 {
  param([Parameter(Mandatory)][string]$Text)
  return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.UTF8Encoding]::new($false).GetBytes($Text)))
}

function Get-MIRDirectLibraryOrdinaryPlayerConfigInput {
  param([Parameter(Mandatory)][string]$Path)
  $resolved=(Resolve-Path -LiteralPath $Path).Path
  Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $resolved -PathType Leaf) 'ordinary-player-config-file'
  $item=Get-Item -LiteralPath $resolved
  Assert-MIRDirectLibraryStartupMeasurement ($item.Length -gt 0 -and $item.Length -le 1MB) 'ordinary-player-config-size'
  [pscustomobject][ordered]@{path=$resolved;sha256=Get-MIRImmutableInputSha256 -Path $resolved;bytes=[int64]$item.Length}
}

# An ordinary menu sample may encounter Factorio's first-run version notice.
# The selected player-data is a separately captured engine input, copied once
# into the shared write-data cache before timing.  It is not a user profile,
# and the runner refuses credentials in it rather than quietly carrying them
# into a performance artifact.
function Get-MIRDirectLibraryOrdinaryMenuPlayerDataInput {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedEngineVersion)
  $resolved=(Resolve-Path -LiteralPath $Path).Path
  Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $resolved -PathType Leaf) 'ordinary-menu-player-data-file'
  $item=Get-Item -LiteralPath $resolved
  Assert-MIRDirectLibraryStartupMeasurement ($item.Length -gt 0 -and $item.Length -le 1MB) 'ordinary-menu-player-data-size'
  try{$value=[IO.File]::ReadAllText($resolved,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json -AsHashtable}catch{throw '[mir-direct-startup-ordinary-menu-player-data-json]'}
  Assert-MIRDirectLibraryStartupMeasurement ($value.ContainsKey('last-played-version') -and $value['last-played-version'] -is [Collections.IDictionary]) 'ordinary-menu-player-data-last-played'
  Assert-MIRDirectLibraryStartupMeasurement ([string]$value['last-played-version']['game_version'] -ceq $ExpectedEngineVersion) 'ordinary-menu-player-data-engine-version'
  foreach($key in @('service-username','service-token')){
    if($value.ContainsKey($key)){Assert-MIRDirectLibraryStartupMeasurement ([string]$value[$key] -ceq '') 'ordinary-menu-player-data-credentials'}
  }
  [pscustomobject][ordered]@{path=$resolved;sha256=Get-MIRImmutableInputSha256 -Path $resolved;bytes=[int64]$item.Length;engine_version=$ExpectedEngineVersion;kind='actual-engine-prepared-player-data'}
}

function Initialize-MIRDirectLibraryOrdinaryMenuSharedWriteData {
  param([Parameter(Mandatory)][string]$WriteDataRoot,[Parameter(Mandatory)]$PlayerData)
  Assert-MIRDirectLibraryStartupMeasurement (-not(Test-Path -LiteralPath $WriteDataRoot)) 'ordinary-menu-shared-write-data-preexisting'
  [IO.Directory]::CreateDirectory($WriteDataRoot)|Out-Null
  $destination=Join-Path $WriteDataRoot 'player-data.json'
  [IO.File]::Copy([string]$PlayerData.path,$destination,$false)
  Assert-MIRDirectLibraryStartupMeasurement ((Get-MIRImmutableInputSha256 -Path $destination) -ceq [string]$PlayerData.sha256) 'ordinary-menu-player-data-copy'
  [pscustomobject][ordered]@{
    kind=[string]$PlayerData.kind;source=[ordered]@{path=[string]$PlayerData.path;sha256=[string]$PlayerData.sha256;bytes=[int64]$PlayerData.bytes;engine_version=[string]$PlayerData.engine_version}
    destination=[ordered]@{path=$destination;sha256=Get-MIRImmutableInputSha256 -Path $destination;bytes=[int64](Get-Item -LiteralPath $destination).Length}
    primary_measurement=$false;scope='untimed preparation; one copied engine-prepared player-data seed for the shared ordinary-menu cache across all arms'
  }
}

function Get-MIRDirectLibraryResponsiveMenuActor {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $root=Join-Path $RepoRoot 'tools/lib/validation/responsive-menu'
  $actor=Join-Path $root 'Invoke-MIRResponsiveMenuActor.ps1'
  $observation=Join-Path $root 'MenuObservation.ps1'
  $window=Join-Path $root 'OwnedMenuWindow.ps1'
  foreach($path in @($actor,$observation,$window)){
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $path -PathType Leaf) 'ordinary-menu-actor-files'
    Assert-MIRDirectLibraryStartupMeasurement ((Get-Item -LiteralPath $path).Length -gt 0 -and (Get-Item -LiteralPath $path).Length -le 128KB) 'ordinary-menu-actor-size'
  }
  $desktop=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
  Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $desktop -PathType Leaf) 'ordinary-menu-desktop-powershell'
  [pscustomobject][ordered]@{
    path=(Resolve-Path -LiteralPath $actor).Path;sha256=Get-MIRImmutableInputSha256 -Path $actor
    observation_sha256=Get-MIRImmutableInputSha256 -Path $observation;window_sha256=Get-MIRImmutableInputSha256 -Path $window
    host=(Resolve-Path -LiteralPath $desktop).Path
  }
}

function Get-MIRDirectLibraryOrdinaryConfigProtectedText {
  param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines)
  $section='';$protected=[Collections.Generic.List[string]]::new()
  foreach($line in $Lines){
    $header=[regex]::Match($line,'^\s*\[(?<section>[^\]]+)\]\s*(?:;.*)?$')
    if($header.Success){$section=$header.Groups['section'].Value.Trim().ToLowerInvariant();$protected.Add($line);continue}
    $setting=[regex]::Match($line,'^(?<prefix>\s*)(?<key>[A-Za-z0-9_-]+)\s*=')
    $key=if($setting.Success){$setting.Groups['key'].Value.ToLowerInvariant()}else{''}
    if($setting.Success-and(($section-ceq'path'-and$key-ceq'read-data')-or($section-ceq'path'-and$key-ceq'write-data')-or($section-ceq'other'-and$key-ceq'enable-new-mods'))){continue}
    $protected.Add($line)
  }
  return ($protected -join "`n")
}

function New-MIRDirectLibraryOrdinaryPlayerConfig {
  param(
    [Parameter(Mandatory)]$PlayerConfigInput,[Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$EngineDataDirectory,[Parameter(Mandatory)][string]$WriteDataDirectory
  )
  $source=(Resolve-Path -LiteralPath ([string]$PlayerConfigInput.path)).Path
  Assert-MIRDirectLibraryStartupMeasurement ((Get-MIRImmutableInputSha256 -Path $source) -ceq [string]$PlayerConfigInput.sha256) 'ordinary-player-config-drift'
  $encoding=[Text.UTF8Encoding]::new($false,$true)
  try{$text=[IO.File]::ReadAllText($source,$encoding)}catch{throw '[mir-direct-startup-ordinary-player-config-encoding]'}
  $newline=if($text.Contains("`r`n")){"`r`n"}else{"`n"};$lines=[Collections.Generic.List[string]]::new([regex]::Split($text,"`r?`n"))
  $sections=@{path=0;other=0};$settings=@{read_data=@();write_data=@();enable_new_mods=@()};$section=''
  for($index=0;$index-lt$lines.Count;$index++){
    $header=[regex]::Match($lines[$index],'^\s*\[(?<section>[^\]]+)\]\s*(?:;.*)?$')
    if($header.Success){$section=$header.Groups['section'].Value.Trim().ToLowerInvariant();if($sections.ContainsKey($section)){$sections[$section]++};continue}
    $setting=[regex]::Match($lines[$index],'^(?<prefix>\s*)(?<key>[A-Za-z0-9_-]+)(?<equals>\s*=\s*)(?<value>.*)$')
    if(-not$setting.Success){continue}
    $key=$setting.Groups['key'].Value.ToLowerInvariant()
    if($section-ceq'path'-and$key-ceq'read-data'){$settings.read_data+=,$index}
    elseif($section-ceq'path'-and$key-ceq'write-data'){$settings.write_data+=,$index}
    elseif($section-ceq'other'-and$key-ceq'enable-new-mods'){$settings.enable_new_mods+=,$index}
  }
  Assert-MIRDirectLibraryStartupMeasurement ($sections.path-eq1-and$sections.other-eq1) 'ordinary-player-config-sections'
  Assert-MIRDirectLibraryStartupMeasurement ($settings.read_data.Count-eq1-and$settings.write_data.Count-eq1-and$settings.enable_new_mods.Count-le1) 'ordinary-player-config-keys'
  $pathValues=@{read_data=$EngineDataDirectory;write_data=$WriteDataDirectory}
  foreach($pair in @(@('read_data','read-data'),@('write_data','write-data'))){
    $index=[int]$settings[$pair[0]][0];$setting=[regex]::Match($lines[$index],'^(?<prefix>\s*)(?<key>[A-Za-z0-9_-]+)(?<equals>\s*=\s*)(?<value>.*)$')
    $lines[$index]=$setting.Groups['prefix'].Value+$pair[1]+$setting.Groups['equals'].Value+$pathValues[$pair[0]]
  }
  if($settings.enable_new_mods.Count-eq1){
    $index=[int]$settings.enable_new_mods[0];$setting=[regex]::Match($lines[$index],'^(?<prefix>\s*)(?<key>[A-Za-z0-9_-]+)(?<equals>\s*=\s*)(?<value>.*)$')
    $lines[$index]=$setting.Groups['prefix'].Value+'enable-new-mods'+$setting.Groups['equals'].Value+'false'
  }else{
    $insertAt=$lines.Count
    for($index=0;$index-lt$lines.Count;$index++){
      $header=[regex]::Match($lines[$index],'^\s*\[(?<section>[^\]]+)\]\s*(?:;.*)?$')
      if($header.Success-and$header.Groups['section'].Value.Trim().ToLowerInvariant()-ceq'other'){$insertAt=$index+1;break}
    }
    $lines.Insert($insertAt,'enable-new-mods=false')
  }
  $privateText=$lines -join $newline
  $sourceLines=[regex]::Split($text,"`r?`n")
  Assert-MIRDirectLibraryStartupMeasurement ((Get-MIRDirectLibraryOrdinaryConfigProtectedText -Lines $sourceLines) -ceq (Get-MIRDirectLibraryOrdinaryConfigProtectedText -Lines $lines.ToArray())) 'ordinary-player-config-preservation'
  [IO.File]::WriteAllText($Path,$privateText,[Text.UTF8Encoding]::new($false))
  [pscustomobject][ordered]@{
    source=[pscustomobject][ordered]@{path=$source;sha256=[string]$PlayerConfigInput.sha256;bytes=[int64]$PlayerConfigInput.bytes}
    private_config=[pscustomobject][ordered]@{path=$Path;sha256=Get-MIRImmutableInputSha256 -Path $Path;bytes=[int64](Get-Item -LiteralPath $Path).Length}
    preserved_settings_sha256=Get-MIRDirectLibraryStartupTextSha256 -Text (Get-MIRDirectLibraryOrdinaryConfigProtectedText -Lines $lines.ToArray())
    overrides=[ordered]@{read_data=$EngineDataDirectory;write_data=$WriteDataDirectory;enable_new_mods=$false}
  }
}

function Initialize-MIRDirectLibraryWindowObservationInterop {
  if($null-ne('MIRDirectLibraryWindowObservationNative' -as [type])){return}
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MIRDirectLibraryWindowObservationNative {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll", SetLastError=true)] public static extern bool IsWindowVisible(IntPtr handle);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool IsIconic(IntPtr handle);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool GetWindowRect(IntPtr handle, out RECT rect);
  [DllImport("user32.dll", SetLastError=true)] public static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr GetForegroundWindow();
}
'@
}

function Get-MIRDirectLibraryOrdinaryWindowObservation {
  param([Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][datetime]$LaunchNotBefore)
  Initialize-MIRDirectLibraryWindowObservationInterop
  $binary=(Resolve-Path -LiteralPath $FactorioBin).Path
  $candidates=@(Get-Process -Name factorio -ErrorAction SilentlyContinue|Where-Object {
    try{([IO.Path]::GetFullPath($_.Path)-ceq$binary)-and$_.StartTime.ToUniversalTime()-ge$LaunchNotBefore.ToUniversalTime()}catch{$false}
  })
  if($candidates.Count-eq0){return $null}
  Assert-MIRDirectLibraryStartupMeasurement ($candidates.Count-eq1) 'ordinary-window-owned-process'
  $process=$candidates[0]
  try{
    $process.Refresh();$handle=$process.MainWindowHandle
    if($process.HasExited -or $handle -eq [IntPtr]::Zero -or -not [MIRDirectLibraryWindowObservationNative]::IsWindowVisible($handle) -or [MIRDirectLibraryWindowObservationNative]::IsIconic($handle)){return $null}
    [uint32]$windowPid=0;$null=[MIRDirectLibraryWindowObservationNative]::GetWindowThreadProcessId($handle,[ref]$windowPid)
    Assert-MIRDirectLibraryStartupMeasurement ($windowPid-eq[uint32]$process.Id) 'ordinary-window-owned-handle'
    $rect=New-Object MIRDirectLibraryWindowObservationNative+RECT;$rectKnown=[MIRDirectLibraryWindowObservationNative]::GetWindowRect($handle,[ref]$rect)
    $width=if($rectKnown){[int]$rect.Right-[int]$rect.Left}else{0};$height=if($rectKnown){[int]$rect.Bottom-[int]$rect.Top}else{0}
    $observed=[DateTimeOffset]::UtcNow;$started=[DateTimeOffset]$process.StartTime.ToUniversalTime()
    $capture=[pscustomobject][ordered]@{attempted=$false;succeeded=$false;print_window_returned=$false;complete='not-observable';unoccluded='not-observable';path='';sha256='';bytes=0;bounds=[ordered]@{left=$(if($rectKnown){[int]$rect.Left}else{$null});top=$(if($rectKnown){[int]$rect.Top}else{$null});width=$width;height=$height};error='automatic-window-image-not-attempted'}
    return [pscustomobject][ordered]@{pid=$process.Id;process_started_utc=$started.ToString('o');observed_utc=$observed.ToString('o');observed_seconds_since_process_start=[Math]::Round(($observed-$started).TotalSeconds,6);window_handle=$handle.ToInt64();window_visible=$true;window_minimized=$false;window_foreground=([MIRDirectLibraryWindowObservationNative]::GetForegroundWindow() -eq $handle);capture=$capture}
  }finally{$process.Dispose()}
}

function Invoke-MIRDirectLibraryStartupSample {
  param(
    [Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$EngineDataDirectory,
    [Parameter(Mandatory)][object[]]$BaseRows,[Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$WriteDataRoot,[Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)]$Resources,[AllowNull()]$MirArchive,[ValidateRange(1,3600)][int]$TimeoutSeconds=300,[string]$ActiveModsObserver='',
    [uint32]$MapGenerationSeed=400200
  )
  [IO.Directory]::CreateDirectory($RunRoot)|Out-Null
  [IO.Directory]::CreateDirectory($WriteDataRoot)|Out-Null
  $profile=Join-Path $RunRoot 'selection.json';$config=Join-Path $RunRoot 'config.ini';$log=Join-Path $RunRoot 'factorio.log';$saveDirectory=Join-Path $RunRoot 'saves';$save=Join-Path $saveDirectory 'startup-ready.zip';$engineLog=Join-Path $WriteDataRoot 'factorio-current.log'
  [IO.Directory]::CreateDirectory($saveDirectory)|Out-Null
  # Map creation is a separate diagnostic endpoint. Bind its random input so
  # map allocation and saving do not add uncontrolled variation between arms.
  $mapGenerationPath=Join-Path $RunRoot 'map-gen-settings.json'
  [IO.File]::WriteAllText($mapGenerationPath,(@{seed=$MapGenerationSeed}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
  $mapGenerationSha=Get-MIRImmutableInputSha256 -Path $mapGenerationPath
  Write-MIRDirectLibraryStartupProfile -Path $profile -BaseRows $BaseRows -MirArchive $MirArchive
  # The first sample and immediate warm-repeat samples for one selected
  # configuration share this private write-data root. Per-sample logs and
  # saves remain isolated in RunRoot, so a prior ready endpoint cannot be
  # mistaken for the successor's result.
  New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $EngineDataDirectory -WriteDataDirectory $WriteDataRoot
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -BaseRows $BaseRows -MirArchive $MirArchive
  $activation=$null
  try {
    $activation=Start-MIRLibraryActivation -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -ProfilePath $profile -ArchiveHashes $hashes -SettingsMode Defaults
    Add-MIRNativeProbeLibraryActivation -Context $Resources -Activation $activation
    Assert-MIRDirectLibraryStartupMeasurement (-not(Test-Path -LiteralPath $save)) 'ready-save-preexisting'
    # write-data is intentionally retained for this configuration's warm
    # repeat. The engine log is not: remove only this owned previous log so
    # every snapshot has a native invocation boundary from this run.
    if(Test-Path -LiteralPath $engineLog){Remove-Item -LiteralPath $engineLog -Force}
    $arguments=@('--config',$config,'--mod-directory',$activation.library,'--no-log-rotation','--disable-audio','--map-gen-settings',$mapGenerationPath,'--create',$save)
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $FactorioBin -Arguments $arguments
    $liveSettings=Read-MIRLibraryControl -Path (Join-Path $activation.library 'mod-settings.dat')
    Assert-MIRDirectLibraryStartupMeasurement (-not[bool]$liveSettings.exists) 'headless-default-settings'
    $executionControls=[ordered]@{
      engine_sha256=Get-MIRImmutableInputSha256 -Path $FactorioBin
      arguments_sha256=Get-MIRDirectLibraryStartupTextSha256 -Text (ConvertTo-Json -InputObject $arguments -Compress)
      config=[ordered]@{path=[IO.Path]::GetRelativePath($RunRoot,$config).Replace('\','/');sha256=Get-MIRImmutableInputSha256 -Path $config}
      selection=[ordered]@{path=[IO.Path]::GetRelativePath($RunRoot,$profile).Replace('\','/');sha256=Get-MIRImmutableInputSha256 -Path $profile}
      mod_settings=[ordered]@{kind='canonical-absent-default';present=[bool]$liveSettings.exists}
      library_directory=[string]$activation.library
    }
    $native=Invoke-MIRNativeProbeFactorioProcess -Context $Resources -FilePath $FactorioBin -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
    Assert-MIRDirectLibraryStartupMeasurement ($native.result.passed -and -not $native.result.timed_out -and $native.result.exit_code -eq 0) 'process-exit'
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $save -PathType Leaf) 'ready-save'
    Assert-MIRDirectLibraryStartupMeasurement ((Get-MIRImmutableInputSha256 -Path $mapGenerationPath)-ceq$mapGenerationSha) 'map-generation-input-changed'
    # Factorio 2.0 writes its actual current log beneath write-data. Snapshot
    # it after process exit so the per-sample evidence survives the warm run.
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $engineLog -PathType Leaf) 'engine-current-log'
    [IO.File]::Copy($engineLog,$log,$true)
    $logText=Get-Content -Raw -LiteralPath $log
    Assert-MIRDirectLibraryStartupMeasurement ($logText -match '(?m)^\s*\d+[.]\d+ Factorio initialised\s*$') 'ready-initialised'
    Assert-MIRDirectLibraryStartupMeasurement ($logText -match ('(?m)^\s*\d+[.]\d+ Info Create[.]cpp:\d+: Creating new map '+[regex]::Escape($save)+'\s*$')) 'ready-create'
    $zip=[IO.Compression.ZipFile]::OpenRead($save)
    try {$mapEntries=@($zip.Entries|Where-Object {$_.FullName -match '(^|/)level(?:-init)?[.]dat$'});Assert-MIRDirectLibraryStartupMeasurement ($mapEntries.Count -eq 1) 'ready-save-map-data';$mapEntry=[string]$mapEntries[0].FullName} finally {$zip.Dispose()}
    $observerIdentity=$null
    if(-not [string]::IsNullOrWhiteSpace($ActiveModsObserver)){
      $observerRows=@($activation.selected|Where-Object {$_.name -ceq $ActiveModsObserver})
      Assert-MIRDirectLibraryStartupMeasurement ($observerRows.Count -eq 1) 'active-mods-observer-selection'
      $observer=$observerRows[0]
      Assert-MIRDirectLibraryStartupMeasurement (-not [bool]$observer.builtin -and [string]$observer.sha256 -match '^[A-Fa-f0-9]{64}$') 'active-mods-observer-identity'
      $observerIdentity=[ordered]@{name=[string]$observer.name;version=[string]$observer.version;archive=[IO.Path]::GetFileName([string]$observer.path);sha256=[string]$observer.sha256}
    }
    $loaded=@(Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -LatestInvocation -ActiveModsObserver $ActiveModsObserver)
    $loadedArchives=@($activation.selected | Sort-Object name | ForEach-Object {
      [pscustomobject][ordered]@{name=[string]$_.name;version=[string]$_.version;sha256=[string]$_.sha256;builtin=[bool]$_.builtin;bytes=[int64]$_.bytes}
    })
    Assert-MIRDirectLibraryStartupMeasurement ((Get-MIRImmutableInputSha256 -Path $FactorioBin)-ceq$executionControls.engine_sha256-and(Get-MIRImmutableInputSha256 -Path $config)-ceq$executionControls.config.sha256-and(Get-MIRImmutableInputSha256 -Path $profile)-ceq$executionControls.selection.sha256) 'headless-execution-controls-drift'
    $initialised=[regex]::Matches($logText,'(?m)^\s*(?<seconds>\d+[.]\d+) Factorio initialised\s*$')|Select-Object -Last 1
    [pscustomobject][ordered]@{label=$Label;run_relative_path=[IO.Path]::GetRelativePath($Resources.root,$RunRoot).Replace('\','/');elapsed_seconds=[double]$native.result.duration_seconds;engine_log_initialised_seconds=[double]::Parse($initialised.Groups['seconds'].Value,[Globalization.CultureInfo]::InvariantCulture);exit_code=$native.result.exit_code;endpoint_class='headless-create-diagnostic';ready_endpoint='Factorio --create exits successfully after the actual current log records initialisation and map creation, with one initial map-data entry in the new save ZIP';ready_save=[IO.Path]::GetRelativePath($RunRoot,$save).Replace('\','/');ready_save_map_entry=$mapEntry;map_generation=[ordered]@{seed=$MapGenerationSeed;path=[IO.Path]::GetRelativePath($Resources.root,$mapGenerationPath).Replace('\','/');sha256=$mapGenerationSha};loaded_selection=$loaded;loaded_archives=$loadedArchives;execution_controls=$executionControls;active_mods_observer=$observerIdentity;process_memory=[ordered]@{peak_working_set_bytes=[int64]$native.result.peak_working_set_bytes;peak_sampled_private_bytes=[int64]$native.result.peak_sampled_private_bytes;measurement='NativeProbeResources monitored process tree; values are not whole-system memory'};resource_ledger=[IO.Path]::GetRelativePath($Resources.root,$native.ledger).Replace('\','/');log=[IO.Path]::GetRelativePath($RunRoot,$log).Replace('\','/');engine_current_log=[IO.Path]::GetRelativePath($Resources.root,$engineLog).Replace('\','/')}
  } finally {
    if($null -ne $activation -and -not $activation.closed){Complete-MIRLibraryActivation -Activation $activation|Out-Null}
  }
}

function Invoke-MIRDirectLibraryPlayerReadyPreparation {
  param(
    [Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$EngineDataDirectory,
    [Parameter(Mandatory)][object[]]$BaseRows,[Parameter(Mandatory)][string]$PreparationRoot,[Parameter(Mandatory)][string]$WriteDataRoot,[Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)]$Resources,[AllowNull()]$MirArchive,[ValidateRange(1,3600)][int]$TimeoutSeconds=300,[Parameter(Mandatory)][string]$ActiveModsObserver,[Parameter(Mandatory)]$PlayerReadyObserver,
    [uint32]$MapGenerationSeed=400200
  )
  [IO.Directory]::CreateDirectory($PreparationRoot)|Out-Null
  [IO.Directory]::CreateDirectory($WriteDataRoot)|Out-Null
  $profile=Join-Path $PreparationRoot 'selection.json';$config=Join-Path $PreparationRoot 'config.ini';$saveDirectory=Join-Path $PreparationRoot 'saves';$save=Join-Path $saveDirectory 'neutral-player-ready.zip';$engineLog=Join-Path $WriteDataRoot 'factorio-current.log';$log=Join-Path $PreparationRoot 'factorio.log'
  [IO.Directory]::CreateDirectory($saveDirectory)|Out-Null
  $mapGenerationPath=Join-Path $PreparationRoot 'map-gen-settings.json'
  [IO.File]::WriteAllText($mapGenerationPath,(@{seed=$MapGenerationSeed}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
  $mapGenerationSha=Get-MIRImmutableInputSha256 -Path $mapGenerationPath
  Write-MIRDirectLibraryStartupProfile -Path $profile -BaseRows $BaseRows -MirArchive $MirArchive
  New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $EngineDataDirectory -WriteDataDirectory $WriteDataRoot
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -BaseRows $BaseRows -MirArchive $MirArchive
  $activation=$null
  try {
    $activation=Start-MIRLibraryActivation -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -ProfilePath $profile -ArchiveHashes $hashes -SettingsMode Defaults
    Add-MIRNativeProbeLibraryActivation -Context $Resources -Activation $activation
    Assert-MIRDirectLibraryStartupMeasurement (-not(Test-Path -LiteralPath $save)) 'player-ready-preparation-save-preexisting'
    if(Test-Path -LiteralPath $engineLog){Remove-Item -LiteralPath $engineLog -Force}
    $arguments=@('--config',$config,'--mod-directory',$activation.library,'--no-log-rotation','--disable-audio','--map-gen-settings',$mapGenerationPath,'--create',$save)
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $FactorioBin -Arguments $arguments
    $native=Invoke-MIRNativeProbeFactorioProcess -Context $Resources -FilePath $FactorioBin -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
    Assert-MIRDirectLibraryStartupMeasurement ($native.result.passed -and -not $native.result.timed_out -and $native.result.exit_code -eq 0) 'player-ready-preparation-process-exit'
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $save -PathType Leaf) 'player-ready-preparation-save'
    Assert-MIRDirectLibraryStartupMeasurement ((Get-MIRImmutableInputSha256 -Path $mapGenerationPath)-ceq$mapGenerationSha) 'player-ready-map-generation-input-changed'
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $engineLog -PathType Leaf) 'player-ready-preparation-log'
    [IO.File]::Copy($engineLog,$log,$true)
    $logText=Get-Content -Raw -LiteralPath $log
    Assert-MIRDirectLibraryStartupMeasurement ($logText-match'(?m)^\s*\d+[.]\d+ Factorio initialised\s*$') 'player-ready-preparation-initialised'
    $null=Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -LatestInvocation -ActiveModsObserver $ActiveModsObserver -ActiveModsObserverScript control.lua
    $zip=[IO.Compression.ZipFile]::OpenRead($save)
    try {$entries=@($zip.Entries|Where-Object {$_.FullName -match '(^|/)level(?:-init)?[.]dat$'});Assert-MIRDirectLibraryStartupMeasurement ($entries.Count -eq 1) 'player-ready-preparation-map-data'}finally{$zip.Dispose()}
    [pscustomobject][ordered]@{label=$Label;scenario=[string]$PlayerReadyObserver.scenario;prepared_save=[IO.Path]::GetRelativePath($Resources.root,$save).Replace('\','/');prepared_save_sha256=Get-MIRImmutableInputSha256 -Path $save;map_generation=[ordered]@{seed=$MapGenerationSeed;path=[IO.Path]::GetRelativePath($Resources.root,$mapGenerationPath).Replace('\','/');sha256=$mapGenerationSha};preparation_log=[IO.Path]::GetRelativePath($Resources.root,$log).Replace('\','/');resource_ledger=[IO.Path]::GetRelativePath($Resources.root,$native.ledger).Replace('\','/');measurement='preparation only; the native --create process is not a startup sample and contributes no elapsed value to comparison samples'}
  } finally {
    if($null -ne $activation -and -not $activation.closed){Complete-MIRLibraryActivation -Activation $activation|Out-Null}
  }
}

function Read-MIRDirectLibraryPlayerReadyMarker {
  param([Parameter(Mandatory)][string]$LogPath)
  $text=Get-Content -Raw -LiteralPath $LogPath
  $matches=@([regex]::Matches($text,'(?m)^\s*(?<seconds>\d+[.]\d+)\s+.*\[MIR_PLAYER_READY\]\s+(?<json>\{[^\r\n]+\})\s*$'))
  Assert-MIRDirectLibraryStartupMeasurement ($matches.Count -eq 1) 'player-ready-marker-count'
  try{$marker=$matches[0].Groups['json'].Value|ConvertFrom-Json -AsHashtable -Depth 16}catch{throw '[mir-direct-startup-player-ready-marker-json]'}
  $isInteger={param($value) $value -is [byte] -or $value -is [sbyte] -or $value -is [int16] -or $value -is [uint16] -or $value -is [int32] -or $value -is [uint32] -or $value -is [int64] -or $value -is [uint64]}
  Assert-MIRDirectLibraryStartupMeasurement ($marker.ContainsKey('schema') -and (& $isInteger $marker['schema']) -and [long]$marker['schema'] -eq 1 -and [string]$marker['kind'] -ceq 'mir423-player-ready-observer' -and [string]$marker['status'] -ceq 'passed') 'player-ready-marker-shape'
  Assert-MIRDirectLibraryStartupMeasurement ($marker.ContainsKey('connected_players') -and (& $isInteger $marker['connected_players']) -and [long]$marker['connected_players'] -ge 1 -and $marker.ContainsKey('native_players') -and (& $isInteger $marker['native_players']) -and [long]$marker['native_players'] -ge 1) 'player-ready-marker-player'
  Assert-MIRDirectLibraryStartupMeasurement ($marker.ContainsKey('gui_root_valid') -and $marker['gui_root_valid'] -is [bool] -and $marker['gui_root_valid'] -and $marker.ContainsKey('first_usable_tick') -and (& $isInteger $marker['first_usable_tick']) -and [long]$marker['first_usable_tick'] -eq 1) 'player-ready-marker-gui-root'
  [pscustomobject][ordered]@{engine_log_seconds=[double]::Parse($matches[0].Groups['seconds'].Value,[Globalization.CultureInfo]::InvariantCulture);marker=$marker}
}

function Invoke-MIRDirectLibraryGraphicalPlayerReadySample {
  param(
    [Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$EngineDataDirectory,
    [Parameter(Mandatory)][object[]]$BaseRows,[Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$WriteDataRoot,[Parameter(Mandatory)][string]$PreparedSave,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$PreparedSaveSha256,[Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)]$Resources,[AllowNull()]$MirArchive,[ValidateRange(1,3600)][int]$TimeoutSeconds=300,[Parameter(Mandatory)][ValidateRange(1,720)][int]$PlayerReadyBenchmarkTicks,[Parameter(Mandatory)][string]$ActiveModsObserver
  )
  [IO.Directory]::CreateDirectory($RunRoot)|Out-Null
  [IO.Directory]::CreateDirectory($WriteDataRoot)|Out-Null
  $profile=Join-Path $RunRoot 'selection.json';$config=Join-Path $RunRoot 'config.ini';$log=Join-Path $RunRoot 'factorio.log';$engineLog=Join-Path $WriteDataRoot 'factorio-current.log';$save=(Resolve-Path -LiteralPath $PreparedSave).Path
  Write-MIRDirectLibraryStartupProfile -Path $profile -BaseRows $BaseRows -MirArchive $MirArchive
  New-MIRDirectLibraryStartupConfig -Path $config -EngineDataDirectory $EngineDataDirectory -WriteDataDirectory $WriteDataRoot -Graphics
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -BaseRows $BaseRows -MirArchive $MirArchive
  $activation=$null
  try {
    $preparedSaveBeforeSha256=Get-MIRImmutableInputSha256 -Path $save
    Assert-MIRDirectLibraryStartupMeasurement ($preparedSaveBeforeSha256 -ceq $PreparedSaveSha256) 'player-ready-prepared-save-before'
    $activation=Start-MIRLibraryActivation -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -ProfilePath $profile -ArchiveHashes $hashes -SettingsMode Defaults
    Add-MIRNativeProbeLibraryActivation -Context $Resources -Activation $activation
    if(Test-Path -LiteralPath $engineLog){Remove-Item -LiteralPath $engineLog -Force}
    $arguments=@('--config',$config,'--mod-directory',$activation.library,'--no-log-rotation','--force-graphics-preset','low','--video-memory-usage','low','--single-thread-loading','--benchmark-graphics',$save,'--benchmark-ticks',[string]$PlayerReadyBenchmarkTicks,'--disable-audio','--window-size','1024x768')
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $FactorioBin -Arguments $arguments
    $native=Invoke-MIRNativeProbeFactorioProcess -Context $Resources -FilePath $FactorioBin -Arguments $arguments -TimeoutSeconds $TimeoutSeconds
    Assert-MIRDirectLibraryStartupMeasurement ($native.result.passed -and -not $native.result.timed_out -and $native.result.exit_code -eq 0) 'player-ready-process-exit'
    $preparedSaveAfterSha256=Get-MIRImmutableInputSha256 -Path $save
    Assert-MIRDirectLibraryStartupMeasurement ($preparedSaveAfterSha256 -ceq $PreparedSaveSha256) 'player-ready-prepared-save-after'
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $engineLog -PathType Leaf) 'player-ready-engine-current-log'
    [IO.File]::Copy($engineLog,$log,$true)
    $observerRows=@($activation.selected|Where-Object {$_.name -ceq $ActiveModsObserver})
    Assert-MIRDirectLibraryStartupMeasurement ($observerRows.Count -eq 1) 'player-ready-observer-selection'
    $observer=$observerRows[0]
    Assert-MIRDirectLibraryStartupMeasurement (-not [bool]$observer.builtin -and [string]$observer.sha256 -match '^[A-Fa-f0-9]{64}$') 'player-ready-observer-identity'
    $observerIdentity=[ordered]@{name=[string]$observer.name;version=[string]$observer.version;archive=[IO.Path]::GetFileName([string]$observer.path);sha256=[string]$observer.sha256}
    $loaded=@(Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -LatestInvocation -ActiveModsObserver $ActiveModsObserver -ActiveModsObserverScript control.lua)
    $ready=Read-MIRDirectLibraryPlayerReadyMarker -LogPath $log
    [pscustomobject][ordered]@{label=$Label;run_relative_path=[IO.Path]::GetRelativePath($Resources.root,$RunRoot).Replace('\','/');elapsed_seconds=[double]$native.result.duration_seconds;engine_log_player_ready_seconds=[double]$ready.engine_log_seconds;exit_code=$native.result.exit_code;endpoint_class='graphical-player-ready-diagnostic';ready_endpoint='A prepared neutral save reached a real connected player with a valid screen GUI-root marker at tick one during --benchmark-graphics. This is not a main-menu readiness or a full-startup claim.';prepared_save=[IO.Path]::GetRelativePath($Resources.root,$save).Replace('\','/');prepared_save_sha256=$PreparedSaveSha256;prepared_save_sha256_before=$preparedSaveBeforeSha256;prepared_save_sha256_after=$preparedSaveAfterSha256;benchmark_ticks=$PlayerReadyBenchmarkTicks;player_ready_marker=$ready.marker;loaded_selection=$loaded;active_mods_observer=$observerIdentity;process_memory=[ordered]@{peak_working_set_bytes=[int64]$native.result.peak_working_set_bytes;peak_sampled_private_bytes=[int64]$native.result.peak_sampled_private_bytes;measurement='NativeProbeResources monitored process tree; values are not whole-system memory'};resource_ledger=[IO.Path]::GetRelativePath($Resources.root,$native.ledger).Replace('\','/');log=[IO.Path]::GetRelativePath($RunRoot,$log).Replace('\','/');engine_current_log=[IO.Path]::GetRelativePath($Resources.root,$engineLog).Replace('\','/')}
  } finally {
    if($null -ne $activation -and -not $activation.closed){Complete-MIRLibraryActivation -Activation $activation|Out-Null}
  }
}

function Invoke-MIRDirectLibraryOrdinaryWindowSample {
  param(
    [Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$EngineDataDirectory,
    [Parameter(Mandatory)][object[]]$BaseRows,[Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$WriteDataRoot,[Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)]$Resources,[AllowNull()]$MirArchive,[ValidateRange(1,3600)][int]$TimeoutSeconds=300,[Parameter(Mandatory)]$OrdinaryPlayerConfig,[string]$ActiveModsObserver=''
  )
  [IO.Directory]::CreateDirectory($RunRoot)|Out-Null
  [IO.Directory]::CreateDirectory($WriteDataRoot)|Out-Null
  $profile=Join-Path $RunRoot 'selection.json';$config=Join-Path $RunRoot 'config.ini';$log=Join-Path $RunRoot 'factorio.log';$engineLog=Join-Path $WriteDataRoot 'factorio-current.log'
  Write-MIRDirectLibraryStartupProfile -Path $profile -BaseRows $BaseRows -MirArchive $MirArchive
  $configIdentity=New-MIRDirectLibraryOrdinaryPlayerConfig -PlayerConfigInput $OrdinaryPlayerConfig -Path $config -EngineDataDirectory $EngineDataDirectory -WriteDataDirectory $WriteDataRoot
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -BaseRows $BaseRows -MirArchive $MirArchive
  $activation=$null
  try {
    $activation=Start-MIRLibraryActivation -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -ProfilePath $profile -ArchiveHashes $hashes -SettingsMode Defaults
    Add-MIRNativeProbeLibraryActivation -Context $Resources -Activation $activation
    if(Test-Path -LiteralPath $engineLog){Remove-Item -LiteralPath $engineLog -Force}
    # Compile/load the tiny Win32 interop before the timed native process so
    # its first-use cost cannot be recorded as Factorio startup work.
    Initialize-MIRDirectLibraryWindowObservationInterop
    $windowObservations=[Collections.Generic.List[object]]::new();$launchNotBefore=[DateTime]::UtcNow
    # The governed process invokes this completion predicate from its own
    # dynamic scope. Bind the selected observer before closing over it so a
    # host-controlled observer remains available there as well.
    $observeOrdinaryWindow=${function:Get-MIRDirectLibraryOrdinaryWindowObservation}
    $completion={
      if($windowObservations.Count){return $true}
      # A visible splash/loading window is not the selected observation
      # endpoint. Wait until this owned invocation has written Factorio's
      # initialisation boundary before inspecting its native window.
      if(-not(Test-Path -LiteralPath $engineLog -PathType Leaf)){return $false}
      try{$currentLog=[IO.File]::ReadAllText($engineLog)}catch{return $false}
      if($currentLog -notmatch '(?m)^\s*\d+[.]\d+ Factorio initialised\s*$'){return $false}
      $window=& $observeOrdinaryWindow -FactorioBin $FactorioBin -LaunchNotBefore $launchNotBefore
      if($null-eq$window){return $false}
      $windowObservations.Add($window);return $true
    }.GetNewClosure()
    # The copied player configuration retains graphics, sound, and threaded
    # loading choices. These custody arguments select only the isolated config,
    # master archive library, and a new log invocation boundary.
    $arguments=@('--config',$config,'--mod-directory',$activation.library,'--no-log-rotation')
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $FactorioBin -Arguments $arguments
    $native=Invoke-MIRNativeProbeFactorioProcess -Context $Resources -FilePath $FactorioBin -Arguments $arguments -TimeoutSeconds $TimeoutSeconds -CompletionPredicate $completion
    Assert-MIRDirectLibraryStartupMeasurement ($native.result.passed -and -not $native.result.timed_out -and $native.result.completion_predicate_observed) 'ordinary-window-process'
    Assert-MIRDirectLibraryStartupMeasurement ($windowObservations.Count-eq1) 'ordinary-window-observation'
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $engineLog -PathType Leaf) 'ordinary-window-engine-current-log'
    [IO.File]::Copy($engineLog,$log,$true)
    $logText=Get-Content -Raw -LiteralPath $log
    Assert-MIRDirectLibraryStartupMeasurement ($logText -match '(?m)^\s*\d+[.]\d+ Factorio initialised\s*$') 'ordinary-window-initialised'
    $observerIdentity=$null
    if(-not [string]::IsNullOrWhiteSpace($ActiveModsObserver)){
      $observerRows=@($activation.selected|Where-Object {$_.name -ceq $ActiveModsObserver})
      Assert-MIRDirectLibraryStartupMeasurement ($observerRows.Count-eq1) 'ordinary-window-active-mods-observer-selection'
      $observer=$observerRows[0]
      Assert-MIRDirectLibraryStartupMeasurement (-not [bool]$observer.builtin -and [string]$observer.sha256 -match '^[A-Fa-f0-9]{64}$') 'ordinary-window-active-mods-observer-identity'
      $observerIdentity=[ordered]@{name=[string]$observer.name;version=[string]$observer.version;archive=[IO.Path]::GetFileName([string]$observer.path);sha256=[string]$observer.sha256}
    }
    $loaded=@(Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -LatestInvocation -ActiveModsObserver $ActiveModsObserver -ActiveModsObserverScript data-final-fixes.lua)
    $initialised=[regex]::Matches($logText,'(?m)^\s*(?<seconds>\d+[.]\d+) Factorio initialised\s*$')|Select-Object -Last 1
    $window=$windowObservations[0];$capture=$window.capture
    $captureRecord=[ordered]@{attempted=[bool]$capture.attempted;succeeded=[bool]$capture.succeeded;print_window_returned=[bool]$capture.print_window_returned;complete=[string]$capture.complete;unoccluded=[string]$capture.unoccluded;path=$(if([string]::IsNullOrWhiteSpace([string]$capture.path)){''}else{[IO.Path]::GetRelativePath($Resources.root,[string]$capture.path).Replace('\','/')});sha256=[string]$capture.sha256;bytes=[int64]$capture.bytes;bounds=$capture.bounds;error=[string]$capture.error}
    [pscustomobject][ordered]@{label=$Label;run_relative_path=[IO.Path]::GetRelativePath($Resources.root,$RunRoot).Replace('\','/');elapsed_seconds=[double]$native.result.duration_seconds;engine_log_initialised_seconds=[double]::Parse($initialised.Groups['seconds'].Value,[Globalization.CultureInfo]::InvariantCulture);exit_code=$native.result.exit_code;endpoint_class='ordinary-native-window-diagnostic';ready_endpoint='An ordinary Factorio launch using the copied player configuration exposed a visible, non-minimized native window after Factorio initialised. No automatic window image is taken because its synchronous rendering call is not safely bounded here; this is not proof that the main menu was rendered, responsive, or interactable.';menu_ready_confirmation='unavailable-from-engine-log-window-observation';ordinary_player_config=[ordered]@{source=$configIdentity.source;private_config=[ordered]@{path=[IO.Path]::GetRelativePath($Resources.root,[string]$configIdentity.private_config.path).Replace('\','/');sha256=$configIdentity.private_config.sha256;bytes=$configIdentity.private_config.bytes};preserved_settings_sha256=$configIdentity.preserved_settings_sha256;overrides=$configIdentity.overrides};window=[ordered]@{pid=[int]$window.pid;process_started_utc=[string]$window.process_started_utc;observed_utc=[string]$window.observed_utc;observed_seconds_since_process_start=[double]$window.observed_seconds_since_process_start;window_handle=[int64]$window.window_handle;visible=[bool]$window.window_visible;minimized=[bool]$window.window_minimized;foreground=[bool]$window.window_foreground;capture=$captureRecord};loaded_selection=$loaded;active_mods_observer=$observerIdentity;process_memory=[ordered]@{peak_working_set_bytes=[int64]$native.result.peak_working_set_bytes;peak_sampled_private_bytes=[int64]$native.result.peak_sampled_private_bytes;measurement='NativeProbeResources monitored process tree; values are not whole-system memory'};resource_ledger=[IO.Path]::GetRelativePath($Resources.root,$native.ledger).Replace('\','/');log=[IO.Path]::GetRelativePath($RunRoot,$log).Replace('\','/');engine_current_log=[IO.Path]::GetRelativePath($Resources.root,$engineLog).Replace('\','/')}
  } finally {
    if($null-ne$activation -and -not $activation.closed){Complete-MIRLibraryActivation -Activation $activation|Out-Null}
  }
}

# The former ordinary-window helper remains available only as a bounded
# diagnostic.  OrdinaryMenu below selects the stronger owned main-menu
# response endpoint; a visible HWND is not accepted as a primary sample.
function Invoke-MIRDirectLibraryResponsiveMenuSample {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$EngineDataDirectory,
    [Parameter(Mandatory)][object[]]$BaseRows,[Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$WriteDataRoot,[Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)]$Resources,[AllowNull()]$MirArchive,[ValidateRange(1,300)][int]$TimeoutSeconds=300,[Parameter(Mandatory)]$OrdinaryPlayerConfig,[Parameter(Mandatory)]$OrdinaryMenuPreparation,[string]$ActiveModsObserver=''
  )
  [IO.Directory]::CreateDirectory($RunRoot)|Out-Null
  Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $WriteDataRoot -PathType Container) 'ordinary-menu-shared-write-data-missing'
  $profile=Join-Path $RunRoot 'selection.json';$config=Join-Path $RunRoot 'config.ini';$log=Join-Path $RunRoot 'factorio.log';$engineLog=Join-Path $WriteDataRoot 'factorio-current.log';$actorRoot=Join-Path $RunRoot 'responsive-menu-actor';$specPath=Join-Path $RunRoot 'responsive-menu-launch.json'
  $playerData=Join-Path $WriteDataRoot 'player-data.json'
  Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $playerData -PathType Leaf) 'ordinary-menu-player-data-missing'
  $playerDataBefore=Get-MIRImmutableInputSha256 -Path $playerData
  Write-MIRDirectLibraryStartupProfile -Path $profile -BaseRows $BaseRows -MirArchive $MirArchive
  $configIdentity=New-MIRDirectLibraryOrdinaryPlayerConfig -PlayerConfigInput $OrdinaryPlayerConfig -Path $config -EngineDataDirectory $EngineDataDirectory -WriteDataDirectory $WriteDataRoot
  $hashes=Get-MIRDirectLibraryStartupArchiveHashes -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -BaseRows $BaseRows -MirArchive $MirArchive
  $actor=Get-MIRDirectLibraryResponsiveMenuActor -RepoRoot $RepoRoot
  $activation=$null
  try {
    $activation=Start-MIRLibraryActivation -LibraryDirectory $LibraryDirectory -EngineDataDirectory $EngineDataDirectory -ProfilePath $profile -ArchiveHashes $hashes -SettingsMode Defaults
    Add-MIRNativeProbeLibraryActivation -Context $Resources -Activation $activation
    if(Test-Path -LiteralPath $engineLog){Remove-Item -LiteralPath $engineLog -Force}
    Assert-MIRDirectLibraryStartupMeasurement (-not(Test-Path -LiteralPath $actorRoot)) 'ordinary-menu-actor-root-preexisting'
    $arguments=@('--config',$config,'--mod-directory',$activation.library,'--no-log-rotation')
    Assert-MIRLibraryLaunch -Activation $activation -FactorioBin $FactorioBin -Arguments $arguments
    $executionControls=[ordered]@{
      engine_sha256=Get-MIRImmutableInputSha256 -Path $FactorioBin
      arguments_sha256=Get-MIRDirectLibraryStartupTextSha256 -Text (ConvertTo-Json -InputObject $arguments -Compress)
      config=[ordered]@{path=[IO.Path]::GetRelativePath($RunRoot,$config).Replace('\','/');sha256=Get-MIRImmutableInputSha256 -Path $config}
      selection=[ordered]@{path=[IO.Path]::GetRelativePath($RunRoot,$profile).Replace('\','/');sha256=Get-MIRImmutableInputSha256 -Path $profile}
      player_data=[ordered]@{path=[IO.Path]::GetRelativePath($Resources.root,$playerData).Replace('\','/');sha256_before=$playerDataBefore;preparation_sha256=[string]$OrdinaryMenuPreparation.source.sha256}
      library_directory=[string]$activation.library
    }
    $spec=[ordered]@{kind='MIRDirectLibraryOwnedMenuLaunchV1';factorio_path=(Resolve-Path -LiteralPath $FactorioBin).Path;factorio_sha256=$executionControls.engine_sha256;arguments=$arguments;engine_current_log=$engineLog;timeout_seconds=$TimeoutSeconds}
    [IO.File]::WriteAllText($specPath,($spec|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $specSha=Get-MIRImmutableInputSha256 -Path $specPath
    $native=Invoke-MIRNativeProbeProcess -Context $Resources -FilePath $actor.host -Arguments @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$actor.path,'-LaunchSpecPath',$specPath,'-LaunchSpecSha256',$specSha,'-OutputRoot',$actorRoot) -TimeoutSeconds ($TimeoutSeconds+20)
    Assert-MIRDirectLibraryStartupMeasurement ($native.result.passed -and -not $native.result.timed_out -and $native.result.exit_code -eq 0) 'ordinary-menu-actor-process'
    $actorRecordPath=Join-Path $actorRoot 'actor-result.json'
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $actorRecordPath -PathType Leaf) 'ordinary-menu-actor-result'
    $actorItem=Get-Item -LiteralPath $actorRecordPath
    Assert-MIRDirectLibraryStartupMeasurement ($actorItem.Length -gt 0 -and $actorItem.Length -le 2MB -and -not($actorItem.Attributes-band[IO.FileAttributes]::ReparsePoint)) 'ordinary-menu-actor-result-size'
    $actorRecord=Get-Content -Raw -LiteralPath $actorRecordPath|ConvertFrom-Json -Depth 30 -DateKind String
    Assert-MIRDirectLibraryStartupMeasurement ([string]$actorRecord.kind -ceq 'MIRDirectLibraryOwnedMenuObservationV1' -and [string]$actorRecord.status -ceq 'observed-response-awaiting-parent-selection-validation') 'ordinary-menu-actor-status'
    Assert-MIRDirectLibraryStartupMeasurement ([string]$actorRecord.launch_spec_sha256 -ceq $specSha -and [string]$actorRecord.factorio_sha256 -ceq $executionControls.engine_sha256) 'ordinary-menu-actor-inputs'
    Assert-MIRDirectLibraryStartupMeasurement (-not[bool]$actorRecord.claims_library_selection_validation -and -not[bool]$actorRecord.claims_final_acceptance -and -not[bool]$actorRecord.observation.claims_factorio_acceptance) 'ordinary-menu-actor-claims'
    $menu=Read-MIRDirectLibraryResponsiveMenuRecord -Observation $actorRecord.observation -OwnedProcessId ([int]$actorRecord.process_id) -OwnedProcessStartUtc ([datetime]$actorRecord.process_start_utc) -LaunchBeforeQpc ([long]$actorRecord.launch_before_qpc) -LaunchAfterQpc ([long]$actorRecord.launch_after_qpc) -ClockFrequency ([long]$actorRecord.clock_frequency) -ArtifactRoot $actorRoot -TimeoutSeconds $TimeoutSeconds
    Assert-MIRDirectLibraryStartupMeasurement ((Get-MIRImmutableInputSha256 -Path $actor.path)-ceq$actor.sha256-and(Get-MIRImmutableInputSha256 -Path (Join-Path $RepoRoot 'tools/lib/validation/responsive-menu/MenuObservation.ps1'))-ceq$actor.observation_sha256-and(Get-MIRImmutableInputSha256 -Path (Join-Path $RepoRoot 'tools/lib/validation/responsive-menu/OwnedMenuWindow.ps1'))-ceq$actor.window_sha256) 'ordinary-menu-actor-drift'
    Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $engineLog -PathType Leaf) 'ordinary-menu-engine-current-log'
    [IO.File]::Copy($engineLog,$log,$true)
    $logText=Get-Content -Raw -LiteralPath $log
    Assert-MIRDirectLibraryStartupMeasurement ($logText -match '(?m)^\s*\d+[.]\d+ Factorio initialised\s*$') 'ordinary-menu-initialised'
    $observerIdentity=$null
    if(-not [string]::IsNullOrWhiteSpace($ActiveModsObserver)){
      $observerRows=@($activation.selected|Where-Object {$_.name -ceq $ActiveModsObserver})
      Assert-MIRDirectLibraryStartupMeasurement ($observerRows.Count-eq1) 'ordinary-menu-active-mods-observer-selection'
      $observer=$observerRows[0]
      Assert-MIRDirectLibraryStartupMeasurement (-not [bool]$observer.builtin -and [string]$observer.sha256 -match '^[A-Fa-f0-9]{64}$') 'ordinary-menu-active-mods-observer-identity'
      $observerIdentity=[ordered]@{name=[string]$observer.name;version=[string]$observer.version;archive=[IO.Path]::GetFileName([string]$observer.path);sha256=[string]$observer.sha256}
    }
    $loaded=@(Assert-MIRLibraryLoadedSelection -Activation $activation -LogPath $log -LatestInvocation -ActiveModsObserver $ActiveModsObserver -ActiveModsObserverScript data-final-fixes.lua)
    Assert-MIRDirectLibraryStartupMeasurement ((Get-MIRImmutableInputSha256 -Path $FactorioBin)-ceq$executionControls.engine_sha256-and(Get-MIRImmutableInputSha256 -Path $config)-ceq$executionControls.config.sha256-and(Get-MIRImmutableInputSha256 -Path $profile)-ceq$executionControls.selection.sha256) 'ordinary-menu-execution-controls-drift'
    $playerDataAfter=Get-MIRImmutableInputSha256 -Path $playerData
    [pscustomobject][ordered]@{
      label=$Label;run_relative_path=[IO.Path]::GetRelativePath($Resources.root,$RunRoot).Replace('\','/');elapsed_seconds=[double]$menu.elapsed_seconds;endpoint_class='ordinary-responsive-menu'
      ready_endpoint='A Factorio process reached a captured owned main menu and completed a harmless owned Settings action whose distinct Settings screen was captured and OCR-confirmed. The elapsed interval is the actor QPC launch bracket to that confirmed response; actor preheat and shutdown/cleanup are excluded.'
      menu_response=$menu;ordinary_player_config=[ordered]@{source=$configIdentity.source;private_config=[ordered]@{path=[IO.Path]::GetRelativePath($Resources.root,[string]$configIdentity.private_config.path).Replace('\','/');sha256=$configIdentity.private_config.sha256;bytes=$configIdentity.private_config.bytes};preserved_settings_sha256=$configIdentity.preserved_settings_sha256;overrides=$configIdentity.overrides}
      ordinary_menu_preparation=[ordered]@{source=$OrdinaryMenuPreparation.source;destination=$OrdinaryMenuPreparation.destination;primary_measurement=$false;player_data_sha256_before=$playerDataBefore;player_data_sha256_after=$playerDataAfter}
      cache_context=[ordered]@{write_data_root=[IO.Path]::GetRelativePath($Resources.root,$WriteDataRoot).Replace('\','/');configuration_sha256=$executionControls.config.sha256;selection_sha256=$executionControls.selection.sha256;player_data_sha256_before=$playerDataBefore;player_data_sha256_after=$playerDataAfter;shared_across_arms=$true}
      responsive_menu_actor=[ordered]@{path=[IO.Path]::GetRelativePath($Resources.root,$actorRecordPath).Replace('\','/');sha256=Get-MIRImmutableInputSha256 -Path $actorRecordPath;script_sha256=$actor.sha256;observation_sha256=$actor.observation_sha256;window_sha256=$actor.window_sha256;launch_spec=[ordered]@{path=[IO.Path]::GetRelativePath($Resources.root,$specPath).Replace('\','/');sha256=$specSha};actor_process_duration_seconds=[double]$native.result.duration_seconds;shutdown_cleanup_seconds=[double]$actorRecord.shutdown_cleanup_seconds;full_engine_cycle_seconds=[double]$actorRecord.full_engine_cycle_seconds;resource_ledger=[IO.Path]::GetRelativePath($Resources.root,$native.ledger).Replace('\','/')}
      loaded_selection=$loaded;active_mods_observer=$observerIdentity;execution_controls=$executionControls;process_memory=[ordered]@{peak_working_set_bytes=[int64]$native.result.peak_working_set_bytes;peak_sampled_private_bytes=[int64]$native.result.peak_sampled_private_bytes;measurement='NativeProbeResources monitored the governed actor and its owned Factorio child; values are not whole-system memory'}
      log=[IO.Path]::GetRelativePath($RunRoot,$log).Replace('\','/');engine_current_log=[IO.Path]::GetRelativePath($Resources.root,$engineLog).Replace('\','/')
    }
  } finally {
    if($null-ne$activation -and -not$activation.closed){Complete-MIRLibraryActivation -Activation $activation|Out-Null}
  }
}

function Invoke-MIRDirectLibraryStartupMeasurement {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$FactorioBin,[Parameter(Mandatory)][string]$LibraryDirectory,[Parameter(Mandatory)][string]$ProfileTemplatePath,
    [Alias('Published422Archive')][string]$BaselineArchive='',[Alias('Published422ManifestPath')][string]$BaselineManifestPath='',[Alias('Published422ManifestSha256')][string]$BaselineManifestSha256='',
  [ValidatePattern('^4[.](?:0|[1-9][0-9]{0,4})[.](?:0|[1-9][0-9]?)$')][string]$BaselineSourceVersion='4.2.2',
    [string]$CandidateArchive='',[string]$CandidateMaterializationArchive='',[string]$CandidateMaterializationReceiptPath='',
    [ValidatePattern('^4[.](?:0|[1-9][0-9]{0,4})[.](?:0|[1-9][0-9]?)$')][string]$StartupCandidateSourceVersion='4.2.3',
    [switch]$Preliminary,[switch]$CandidateOnly,[Parameter(Mandatory)][string]$OutputRoot,
    [ValidateSet('f200','f210')][string]$Target='f200',[ValidateRange(0,5)][int]$WarmupRuns=1,[ValidateRange(1,25)][int]$MeasuredRuns=3,[ValidateRange(1,3600)][int]$TimeoutSeconds=300,
    [Parameter(Mandatory)][ValidateRange(1,8192)][int]$ExpectedPeakMemoryMiB,[ValidateRange(1,2048)][int]$MaxNewOutputMiB=120,[ValidateRange(0,300)][int]$AdmissionWaitSeconds=0,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{40}$')][string]$SourceCommit,[string]$ActiveModsObserver='',
    [switch]$GraphicalPlayerReady,[string]$PlayerReadyObserverArchive='',[ValidateRange(1,720)][int]$PlayerReadyBenchmarkTicks=60,
    [switch]$OrdinaryMenu,[string]$OrdinaryPlayerConfigPath='',[string]$OrdinaryMenuPlayerDataPath=''
  )
  $repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
  $observedCommit=(& git -C $repo rev-parse HEAD).Trim().ToLowerInvariant()
  Assert-MIRDirectLibraryStartupMeasurement ($observedCommit -ceq $SourceCommit.ToLowerInvariant()) 'source-commit'
  $dirty=@(& git -C $repo status --porcelain).Count -gt 0
  $sourceObservation=[ordered]@{requested_commit=$SourceCommit.ToLowerInvariant();head_commit=$observedCommit;working_tree_dirty=$dirty}
  $engine=(Resolve-Path -LiteralPath $FactorioBin).Path;$library=(Resolve-Path -LiteralPath $LibraryDirectory).Path;$template=(Resolve-Path -LiteralPath $ProfileTemplatePath).Path
  $engineRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $engine));$data=Join-Path $engineRoot 'data'
  Assert-MIRDirectLibraryStartupMeasurement (Test-Path -LiteralPath $data -PathType Container) 'engine-data'
  Assert-MIRDirectLibraryStartupMeasurement (-not(Test-Path -LiteralPath $OutputRoot)) 'output-exists'
  $engineIdentity=Get-MIRDirectLibraryStartupEngineIdentity -FactorioBin $engine -EngineDataDirectory $data
  Assert-MIRDirectLibraryStartupMeasurement (-not($CandidateOnly-and($Preliminary-or$GraphicalPlayerReady-or$OrdinaryMenu))) 'candidate-only-mode'
  $published=$null;$publishedManifest=$null
  if($CandidateOnly){
    Assert-MIRDirectLibraryStartupMeasurement ([string]::IsNullOrWhiteSpace($BaselineArchive)-and[string]::IsNullOrWhiteSpace($BaselineManifestPath)-and[string]::IsNullOrWhiteSpace($BaselineManifestSha256)) 'candidate-only-no-comparison'
  }else{
    Assert-MIRDirectLibraryStartupMeasurement (-not[string]::IsNullOrWhiteSpace($BaselineArchive)-and-not[string]::IsNullOrWhiteSpace($BaselineManifestPath)-and-not[string]::IsNullOrWhiteSpace($BaselineManifestSha256)) 'published-inputs'
    $published=Get-MIRDirectLibraryStartupArchive -Archive $BaselineArchive -LibraryDirectory $library
    $publishedManifest=Assert-MIRDirectLibraryBaselineManifest -RepoRoot $repo -ManifestPath $BaselineManifestPath -ExpectedSha256 $BaselineManifestSha256 -PublishedArchive $published -Target $Target -SourceVersion $BaselineSourceVersion
  }
  $seedTarget=if($Target-ceq'f200'){'2.0'}else{'2.1'}
  $seedProfile=Get-Content -LiteralPath (Join-Path $repo ('validation/profiles/factorio-'+$seedTarget+'.json')) -Raw|ConvertFrom-Json
  $mapGenerationSeed=[uint32]$seedProfile.deterministic_seed
  $hasCandidate=-not [string]::IsNullOrWhiteSpace($CandidateArchive)
  Assert-MIRDirectLibraryStartupMeasurement (-not$CandidateOnly-or$hasCandidate) 'candidate-only-candidate-required'
  Assert-MIRDirectLibraryStartupMeasurement (($hasCandidate -and -not $Preliminary) -or (-not $hasCandidate -and $Preliminary)) 'candidate-mode'
  Assert-MIRDirectLibraryStartupMeasurement (-not($GraphicalPlayerReady-and$OrdinaryMenu)) 'endpoint-mode-conflict'
  Assert-MIRDirectLibraryStartupMeasurement ((-not$OrdinaryMenu)-or-not[string]::IsNullOrWhiteSpace($OrdinaryPlayerConfigPath)) 'ordinary-player-config-required'
  Assert-MIRDirectLibraryStartupMeasurement ((-not$OrdinaryMenu)-or-not[string]::IsNullOrWhiteSpace($OrdinaryMenuPlayerDataPath)) 'ordinary-menu-player-data-required'
  Assert-MIRDirectLibraryStartupMeasurement ((-not$OrdinaryMenu)-or$WarmupRuns-ge1) 'ordinary-menu-warmup-required'
  $candidate=$null;$candidateMaterialization=$null
  if($hasCandidate){
    Assert-MIRDirectLibraryStartupMeasurement (-not [string]::IsNullOrWhiteSpace($CandidateMaterializationArchive) -and -not [string]::IsNullOrWhiteSpace($CandidateMaterializationReceiptPath)) 'candidate-materialization-inputs'
    # NativeProbeResources owns receipt validation but deliberately does not
    # load package identity authority at module import time. Load both the
    # canonical identity reader and the materializer before resolving the
    # selected candidate, so a preloaded partial package API cannot omit the
    # identity resolver used by this caller.
    . (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
    . (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
    $candidateIdentity=Resolve-MIR4CanonicalPackageIdentity -RepoRoot $repo -Target $Target -SourceVersion $StartupCandidateSourceVersion
    $candidate=Get-MIRDirectLibraryStartupArchive -Archive $CandidateArchive -LibraryDirectory $library
    Assert-MIRDirectLibraryStartupMeasurement ($candidate.version -ceq [string]$candidateIdentity.distribution_version) 'candidate-identity'
    $candidateMaterialization=Read-MIRNativeProbeCurrentCandidate -Repository $repo -Archive $CandidateMaterializationArchive -ReceiptPath $CandidateMaterializationReceiptPath -Target $Target -SourceVersion $StartupCandidateSourceVersion
    Assert-MIRDirectLibraryStartupMeasurement ([string]$candidateMaterialization.receipt.archive_sha256 -ceq [string]$candidate.sha256) 'candidate-materialization-archive'
  }
  $base=Read-MIRDirectLibraryStartupProfile -Path $template
  $ordinaryPlayerConfig=$null;$ordinaryMenuPlayerData=$null
  if($OrdinaryMenu){
    Assert-MIRDirectLibraryStartupMeasurement ($TimeoutSeconds -le 300) 'ordinary-menu-timeout'
    $ordinaryPlayerConfig=Get-MIRDirectLibraryOrdinaryPlayerConfigInput -Path $OrdinaryPlayerConfigPath
    $ordinaryMenuPlayerData=Get-MIRDirectLibraryOrdinaryMenuPlayerDataInput -Path $OrdinaryMenuPlayerDataPath -ExpectedEngineVersion ([string]$engineIdentity.base_version)
  }
  $playerReadyObserver=$null;$selectedActiveModsObserver=$ActiveModsObserver
  if($GraphicalPlayerReady){
    Assert-MIRDirectLibraryStartupMeasurement (-not [string]::IsNullOrWhiteSpace($PlayerReadyObserverArchive)) 'player-ready-observer-required'
    $playerReadyObserver=Get-MIRDirectLibraryPlayerReadyObserverArchive -Archive $PlayerReadyObserverArchive -LibraryDirectory $library -Target $Target
    if(-not [string]::IsNullOrWhiteSpace($ActiveModsObserver)){Assert-MIRDirectLibraryStartupMeasurement ($ActiveModsObserver -ceq [string]$playerReadyObserver.name) 'player-ready-observer-active-mods-name'}
    $selectedActiveModsObserver=[string]$playerReadyObserver.name
    $base=Add-MIRDirectLibraryPlayerReadyObserverSelection -BaseRows $base -Observer $playerReadyObserver
  }
  if(-not [string]::IsNullOrWhiteSpace($selectedActiveModsObserver)){
    Assert-MIRDirectLibraryStartupMeasurement (Test-MIRLibraryModName $selectedActiveModsObserver) 'active-mods-observer-name'
    Assert-MIRDirectLibraryStartupMeasurement (@($base|Where-Object {$_.enabled -and $_.name -ceq $selectedActiveModsObserver}).Count -eq 1) 'active-mods-observer-profile'
  }
  $templateSha=Get-MIRImmutableInputSha256 -Path $template
  $resources=$null;$records=$null;$currentLabel='';$preparations=$null;$preparedSaves=@{};$admissionWaits=[Collections.Generic.List[object]]::new();$ordinaryMenuPreparation=$null;$ordinaryMenuWriteDataRoot=''
  $durationMeasurement=if($OrdinaryMenu){
    [ordered]@{
      scope='same-QPC Factorio launch bracket-to-confirmed owned Settings response'
      excludes=@('actor OCR/Win32 preheat','shutdown','cleanup')
      process_governance='NativeProbeResources governs the Desktop PowerShell actor and its owned Factorio child process tree'
      primary_measurement=$false
      endpoint_status='implemented measurement endpoint; no native sample, performance result, or acceptance campaign is established by this integration alone'
      comparable_to_process_start_to_exit=$false
    }
  }else{
    [ordered]@{scope='direct-native-executable-start-to-exit';historical_scope='governed-powershell-wrapper-tree-start-to-exit';comparable_to_historical_wrapper_elapsed=$false}
  }
  try {
    $admissionPolicy=[pscustomobject]@{minimum_free_ram_gib=4}
    $admissionWaits.Add((Wait-MIRDirectLibraryStartupAdmission -Policy $admissionPolicy -WorkRoot $OutputRoot -EstimatedPeakBytes ([int64]$MaxNewOutputMiB*1MB) -ExpectedPeakMemoryBytes ([int64]$ExpectedPeakMemoryMiB*1MB) -AdmissionWaitSeconds $AdmissionWaitSeconds -Phase 'resource-context'))
    $resources=New-MIRNativeProbeResourceContext -RepoRoot $repo -OutputRoot $OutputRoot -ExpectedPeakMemoryMiB $ExpectedPeakMemoryMiB -MaxNewOutputMiB $MaxNewOutputMiB -UseExactOutputRoot
    [IO.Directory]::CreateDirectory($resources.root)|Out-Null;$records=[Collections.Generic.List[object]]::new();$preparations=[Collections.Generic.List[object]]::new()
    if($OrdinaryMenu){
      $ordinaryMenuWriteDataRoot=Join-Path $resources.root 'write-data/ordinary-menu-shared'
      $ordinaryMenuPreparation=Initialize-MIRDirectLibraryOrdinaryMenuSharedWriteData -WriteDataRoot $ordinaryMenuWriteDataRoot -PlayerData $ordinaryMenuPlayerData
    }
    $kinds=@([pscustomobject]@{label='without-mir';archive=$null},[pscustomobject]@{label=('released-'+$BaselineSourceVersion);archive=$published})
    if($hasCandidate){$kinds+=,[pscustomobject]@{label=('candidate-'+$StartupCandidateSourceVersion);archive=$candidate}}
    # Absolute work qualification must not wait for a known pathological
    # predecessor. This mode records no baseline or relative speedup.
    if($CandidateOnly){$kinds=@([pscustomobject]@{label=('candidate-'+$StartupCandidateSourceVersion);archive=$candidate})}
    if($GraphicalPlayerReady){
      foreach($kind in $kinds){
        $currentLabel=[string]$kind.label
        $admissionWaits.Add((Wait-MIRDirectLibraryStartupAdmission -Policy $resources.policy -WorkRoot $resources.root -EstimatedPeakBytes (Get-MIRNativeProbeRemainingOutputBytes -Context $resources) -ExpectedPeakMemoryBytes $resources.peak_memory_bytes -AdmissionWaitSeconds $AdmissionWaitSeconds -Phase ('preparation:'+[string]$kind.label)))
        $preparation=Invoke-MIRDirectLibraryPlayerReadyPreparation -FactorioBin $engine -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $base -PreparationRoot (Join-Path $resources.root ('preparations/'+$kind.label)) -WriteDataRoot (Join-Path $resources.root ('write-data/'+$kind.label)) -Label $kind.label -Resources $resources -MirArchive $kind.archive -TimeoutSeconds $TimeoutSeconds -ActiveModsObserver $selectedActiveModsObserver -MapGenerationSeed $mapGenerationSeed -PlayerReadyObserver $playerReadyObserver
        $preparations.Add($preparation);$preparedSaves[[string]$kind.label]=Join-Path $resources.root ([string]$preparation.prepared_save)
      }
    }
    $ordinals=@{};foreach($kind in $kinds){$ordinals[$kind.label]=0}
    # Rotate configurations by block and record the actual predecessor for
    # every first sample. A rotation can bring the same selection to the start
    # of the next block; do not call that a changed configuration.
    $previousSelection=if($GraphicalPlayerReady){[string]$kinds[$kinds.Count-1].label}else{$null}
    for($block=1;$block-le($WarmupRuns+$MeasuredRuns);$block++){
    $offset=($block-1)%$kinds.Count
    for($position=0;$position-lt$kinds.Count;$position++){
      $kind=$kinds[($offset+$position)%$kinds.Count]
      $changed=if($null-eq$previousSelection){$null}else{[bool]($previousSelection-cne$kind.label)}
      $firstState=if($null-eq$previousSelection){'initial-selection'}elseif($changed){'changed-configuration'}else{'same-selection'}
      $samplePlan=@(
        [pscustomobject]@{cache_state=$firstState;prior_selection_label=$previousSelection;selection_changed=$changed},
        [pscustomobject]@{cache_state='warm-repeat';prior_selection_label=$kind.label;selection_changed=$false}
      )
      foreach($samplePlanRow in $samplePlan){
        $ordinals[$kind.label]++;$ordinal=$ordinals[$kind.label]
        $runRoot=Join-Path $resources.root ('runs/'+$kind.label+'/'+$ordinal+'/'+[string]$samplePlanRow.cache_state)
        # Ordinary menu measurements deliberately share one real write-data/cache
        # root across arms. The recorded predecessor selection and immediate warm
        # repeat therefore describe the cache transition that actually occurred.
        $writeDataRoot=if($OrdinaryMenu){$ordinaryMenuWriteDataRoot}else{Join-Path $resources.root ('write-data/'+$kind.label)}
        $currentLabel=[string]$kind.label
        $admissionWait=Wait-MIRDirectLibraryStartupAdmission -Policy $resources.policy -WorkRoot $resources.root -EstimatedPeakBytes (Get-MIRNativeProbeRemainingOutputBytes -Context $resources) -ExpectedPeakMemoryBytes $resources.peak_memory_bytes -AdmissionWaitSeconds $AdmissionWaitSeconds -Phase ('sample:'+[string]$kind.label+':'+$ordinal+':'+[string]$samplePlanRow.cache_state)
        $admissionWaits.Add($admissionWait)
        if($GraphicalPlayerReady){
          $preparation=@($preparations|Where-Object {$_.label -ceq [string]$kind.label})
          Assert-MIRDirectLibraryStartupMeasurement ($preparation.Count -eq 1) 'player-ready-preparation-selection'
          $record=Invoke-MIRDirectLibraryGraphicalPlayerReadySample -FactorioBin $engine -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $base -RunRoot $runRoot -WriteDataRoot $writeDataRoot -PreparedSave $preparedSaves[[string]$kind.label] -PreparedSaveSha256 ([string]$preparation[0].prepared_save_sha256) -Label $kind.label -Resources $resources -MirArchive $kind.archive -TimeoutSeconds $TimeoutSeconds -PlayerReadyBenchmarkTicks $PlayerReadyBenchmarkTicks -ActiveModsObserver $selectedActiveModsObserver
        } elseif($OrdinaryMenu) {
          $record=Invoke-MIRDirectLibraryResponsiveMenuSample -RepoRoot $repo -FactorioBin $engine -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $base -RunRoot $runRoot -WriteDataRoot $writeDataRoot -Label $kind.label -Resources $resources -MirArchive $kind.archive -TimeoutSeconds $TimeoutSeconds -OrdinaryPlayerConfig $ordinaryPlayerConfig -OrdinaryMenuPreparation $ordinaryMenuPreparation -ActiveModsObserver $selectedActiveModsObserver
        } else {
          $record=Invoke-MIRDirectLibraryStartupSample -FactorioBin $engine -LibraryDirectory $library -EngineDataDirectory $data -BaseRows $base -RunRoot $runRoot -WriteDataRoot $writeDataRoot -Label $kind.label -Resources $resources -MirArchive $kind.archive -TimeoutSeconds $TimeoutSeconds -ActiveModsObserver $selectedActiveModsObserver -MapGenerationSeed $mapGenerationSeed
        }
        $record|Add-Member -NotePropertyName sample -NotePropertyValue $ordinal
        $record|Add-Member -NotePropertyName measurement_block -NotePropertyValue $block
        $record|Add-Member -NotePropertyName configuration_order -NotePropertyValue ($position+1)
        $record|Add-Member -NotePropertyName cache_state -NotePropertyValue ([string]$samplePlanRow.cache_state)
        $record|Add-Member -NotePropertyName prior_selection_label -NotePropertyValue $samplePlanRow.prior_selection_label
        $record|Add-Member -NotePropertyName selection_changed -NotePropertyValue $samplePlanRow.selection_changed
        $record|Add-Member -NotePropertyName warmup -NotePropertyValue ($block -le $WarmupRuns)
        $record|Add-Member -NotePropertyName prelaunch_admission_wait -NotePropertyValue $admissionWait
        $records.Add($record)
      }
      $previousSelection=[string]$kind.label
    }
    }
    $inputs=[ordered]@{active_mods_observer=$(if([string]::IsNullOrWhiteSpace($selectedActiveModsObserver)){$null}else{[string]$selectedActiveModsObserver});player_ready_observer=$playerReadyObserver;ordinary_player_config=$(if($null-eq$ordinaryPlayerConfig){$null}else{[ordered]@{path=$ordinaryPlayerConfig.path;sha256=$ordinaryPlayerConfig.sha256;bytes=$ordinaryPlayerConfig.bytes}});ordinary_menu_player_data=$(if($null-eq$ordinaryMenuPlayerData){$null}else{[ordered]@{path=$ordinaryMenuPlayerData.path;sha256=$ordinaryMenuPlayerData.sha256;bytes=$ordinaryMenuPlayerData.bytes;engine_version=$ordinaryMenuPlayerData.engine_version;kind=$ordinaryMenuPlayerData.kind}});published_422=$(if($CandidateOnly-or$BaselineSourceVersion-cne'4.2.2'){$null}else{[ordered]@{archive=$published;authenticated_manifest=$publishedManifest}});baseline=$(if($CandidateOnly){$null}else{[ordered]@{archive=$published;authenticated_manifest=$publishedManifest}});candidate=$(if($hasCandidate){[ordered]@{source_version=$StartupCandidateSourceVersion;archive=$candidate;materialization=[ordered]@{archive_path=$candidateMaterialization.path;archive_sha256=$candidateMaterialization.receipt.archive_sha256;receipt_path=$CandidateMaterializationReceiptPath;receipt_sha256=Get-MIRImmutableInputSha256 -Path $CandidateMaterializationReceiptPath;source_version=$candidateMaterialization.receipt.source_version;package_source_sha256=$candidateMaterialization.receipt.package_source_sha256;source_manifest_sha256=$candidateMaterialization.receipt.source_manifest_sha256}}}else{$null})}
    $endpointClass=if($GraphicalPlayerReady){'graphical-player-ready-diagnostic'}elseif($OrdinaryMenu){'ordinary-responsive-menu'}else{'headless-create-diagnostic'}
    $notes=@('Elapsed time is native process start-to-exit time recorded by NativeProbeResources except where the selected endpoint records a narrower documented interval.','Peak process values are monitored process-tree samples, not whole-system memory.','Each selected configuration retains one private write-data root across blocks unless the ordinary-menu endpoint explicitly records its shared cache root; per-sample logs and saves stay isolated.','Each first sample records its actual prior selection and whether it changed; immediate repeats are marked warm-repeat.','All configurations use the same selected archive library serially; controls are restored after every sample.','Optional pre-launch admission waiting is recorded separately from every native startup elapsed time. It repeats only the existing physical-memory or commit admission check, retains only bounded first/last refusal snapshots, and never retries a governed sample after launch.')
    if($GraphicalPlayerReady){$notes+=@('Each configuration receives one neutral base-only observer save before samples. Preparation processes are recorded separately and are not startup samples.','Graphical process elapsed includes the bounded post-ready benchmark and exit. engine_log_player_ready_seconds is recorded separately from the Factorio log. This diagnostic is not a main-menu readiness or full-startup claim.')}
    if($OrdinaryMenu){$notes+=@('Each launch uses a fresh private copy of the explicit player configuration. Only read-data, write-data, and enable-new-mods=false are changed for custody; graphics, sound, and thread-loading choices remain source-controlled.','An explicit hash-bound engine-prepared player-data seed is copied once before all samples into one shared ordinary-menu write-data/cache root. Seed preparation is excluded from every measured launch.','At least one ordinary-menu warmup block is required. Every warmup sample remains marked warmup=true and is excluded from primary comparison analysis.','Each elapsed sample is the actor QPC interval from owned Factorio Process.Start through a captured owned main menu and a distinct OCR-confirmed response to a harmless owned Settings action. OCR/Win32 preheat, shutdown, and cleanup are recorded separately and excluded. The actor validates no mod selection; the parent validates launch, selection, controls, and artifact custody.')}
    if($CandidateOnly){$notes+=@('Candidate-only stress diagnostic: no no-MIR or released baseline was run; this result establishes no relative speedup.')}
    $result=[pscustomobject][ordered]@{schema=1;kind='MIRDirectLibraryStartupMeasurementV1';status='completed';mode=$(if($CandidateOnly){'candidate-only-stress-diagnostic'}elseif($hasCandidate){'matched-three-input'}else{'preliminary-two-input'});target=$Target;source_observation=$sourceObservation;factorio=$engineIdentity;library=$library;profile_template_sha256=$templateSha;inputs=$inputs;endpoint_class=$endpointClass;preparations=@($preparations);ordinary_menu_preparation=$ordinaryMenuPreparation;resource_context=[ordered]@{expected_peak_memory_bytes=$resources.peak_memory_bytes;max_new_output_bytes=$resources.max_new_output_bytes;processes=@($resources.runs)};admission_wait_seconds=$AdmissionWaitSeconds;admission_waits=@($admissionWaits);samples=@($records);library_controls_restored=(-not(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json')));measurement_notes=$notes}
    $result|Add-Member -NotePropertyName duration_measurement -NotePropertyValue $durationMeasurement
    Write-MIRNativeProbeResult -Context $resources -Record $result;return $result
  } catch {
    $admissionWaitFailure=$_.Exception.Data['mir_direct_startup_admission_wait']
    if($null-ne$admissionWaitFailure){$admissionWaits.Add($admissionWaitFailure)}
    if($null-ne$resources){
      $failureInputs=[ordered]@{active_mods_observer=$(if([string]::IsNullOrWhiteSpace($selectedActiveModsObserver)){$null}else{[string]$selectedActiveModsObserver});player_ready_observer=$playerReadyObserver;ordinary_player_config=$(if($null-eq$ordinaryPlayerConfig){$null}else{[ordered]@{path=$ordinaryPlayerConfig.path;sha256=$ordinaryPlayerConfig.sha256;bytes=$ordinaryPlayerConfig.bytes}});ordinary_menu_player_data=$(if($null-eq$ordinaryMenuPlayerData){$null}else{[ordered]@{path=$ordinaryMenuPlayerData.path;sha256=$ordinaryMenuPlayerData.sha256;bytes=$ordinaryMenuPlayerData.bytes;engine_version=$ordinaryMenuPlayerData.engine_version;kind=$ordinaryMenuPlayerData.kind}});published_422=$(if($CandidateOnly-or$BaselineSourceVersion-cne'4.2.2'){$null}else{[ordered]@{archive=$published;authenticated_manifest=$publishedManifest}});baseline=$(if($CandidateOnly){$null}else{[ordered]@{archive=$published;authenticated_manifest=$publishedManifest}});candidate=$(if($hasCandidate -and $null-ne$candidate){[ordered]@{source_version=$StartupCandidateSourceVersion;archive=$candidate;materialization=$candidateMaterialization}}else{$null})}
      $failure=[pscustomobject][ordered]@{schema=1;kind='MIRDirectLibraryStartupMeasurementV1';status='failed';mode=$(if($CandidateOnly){'candidate-only-stress-diagnostic'}elseif($hasCandidate){'matched-three-input'}else{'preliminary-two-input'});target=$Target;source_observation=$sourceObservation;factorio=$engineIdentity;library=$library;profile_template_sha256=$templateSha;inputs=$failureInputs;endpoint_class=$(if($GraphicalPlayerReady){'graphical-player-ready-diagnostic'}elseif($OrdinaryMenu){'ordinary-responsive-menu'}else{'headless-create-diagnostic'});current_label=$currentLabel;preparations=$(if($null-ne$preparations){@($preparations)}else{@()});ordinary_menu_preparation=$ordinaryMenuPreparation;admission_wait_seconds=$AdmissionWaitSeconds;admission_waits=@($admissionWaits);samples_so_far=$(if($null-ne$records){@($records)}else{@()});error=$_.Exception.Message;library_controls_restored=(-not(Test-Path -LiteralPath (Join-Path $library '.mir-active-profile.json')));resource_context=[ordered]@{expected_peak_memory_bytes=$resources.peak_memory_bytes;max_new_output_bytes=$resources.max_new_output_bytes;processes=@($resources.runs)}}
      $failure|Add-Member -NotePropertyName duration_measurement -NotePropertyValue $durationMeasurement
      try{Write-MIRNativeProbeResult -Context $resources -Record $failure}catch{Write-Warning "[mir-direct-startup-failure-receipt] $($_.Exception.Message)"}
    }
    throw
  }
}

# Responsive-menu primary analysis is deliberately separate from the raw native
# receipt. It consumes only completed, hash-bound direct-library results and
# cannot create a release, native-acceptance, or product-performance claim.
function Assert-MIRDirectLibraryResponsiveMenuAnalysis {
  param([bool]$Condition,[Parameter(Mandatory)][string]$Code)
  if(-not $Condition){throw "[mir-responsive-menu-analysis-$Code]"}
}

function Get-MIRDirectLibraryResponsiveMenuAnalysisField {
  param([Parameter(Mandatory)]$Object,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Code)
  $property=$Object.PSObject.Properties[$Name]
  Assert-MIRDirectLibraryResponsiveMenuAnalysis ($null-ne$property-and$null-ne$property.Value) $Code
  return $property.Value
}

function Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 {
  param([AllowNull()][string]$Value)
  return (-not[string]::IsNullOrWhiteSpace($Value)-and$Value-match'^[A-Fa-f0-9]{64}$')
}

function Get-MIRDirectLibraryResponsiveMenuAnalysisMedian {
  param([Parameter(Mandatory)][double[]]$Values)
  Assert-MIRDirectLibraryResponsiveMenuAnalysis ($Values.Count-gt0) 'median-empty'
  $sorted=[double[]]::new($Values.Count)
  [Array]::Copy($Values,$sorted,$Values.Count)
  [Array]::Sort($sorted)
  $middle=[int][Math]::Floor($sorted.Count/2)
  if(($sorted.Count%2)-eq0){return ([double]$sorted[$middle-1]+[double]$sorted[$middle])/2}
  return [double]$sorted[$middle]
}

function Get-MIRDirectLibraryResponsiveMenuAnalysisQuantile {
  param([Parameter(Mandatory)][double[]]$Values,[Parameter(Mandatory)][double]$Probability)
  Assert-MIRDirectLibraryResponsiveMenuAnalysis ($Values.Count-gt0-and$Probability-gt0-and$Probability-lt1) 'quantile-input'
  # Frozen before primary launches: lower-tail nearest-rank (ceiling) order
  # statistic, with no interpolation or caller-controlled quantile rule.
  $sorted=[double[]]::new($Values.Count)
  [Array]::Copy($Values,$sorted,$Values.Count)
  [Array]::Sort($sorted)
  $index=[Math]::Max(0,[Math]::Ceiling($Probability*$sorted.Count)-1)
  return [double]$sorted[$index]
}

function Get-MIRDirectLibraryResponsiveMenuAnalysisSummary {
  param([Parameter(Mandatory)][double[]]$Values)
  Assert-MIRDirectLibraryResponsiveMenuAnalysis ($Values.Count-gt0) 'summary-empty'
  $sum=0.0;foreach($value in $Values){$sum+=[double]$value}
  $sorted=[double[]]@($Values|Sort-Object)
  return [ordered]@{
    observations_seconds=@($Values|ForEach-Object {[double]$_})
    median_seconds=Get-MIRDirectLibraryResponsiveMenuAnalysisMedian -Values $Values
    mean_seconds=$sum/$Values.Count
    minimum_seconds=[double]$sorted[0]
    maximum_seconds=[double]$sorted[-1]
    p90_seconds=Get-MIRDirectLibraryResponsiveMenuAnalysisQuantile -Values $Values -Probability 0.9
  }
}

function Get-MIRDirectLibraryResponsiveMenuAnalysisBootstrap {
  param([Parameter(Mandatory)][object[]]$Rows)
  $count=$Rows.Count
  Assert-MIRDirectLibraryResponsiveMenuAnalysis ($count-in@(5,10)) 'bootstrap-block-count'
  $iterations=if($count-eq5){3125}else{100000}
  $baselineLower=[double[]]::new($iterations)
  $marginLower=[double[]]::new($iterations)
  $nonRegressionLower=[double[]]::new($iterations)
  $selectedBaseline=[double[]]::new($count)
  $selectedCandidate=[double[]]::new($count)
  # xorshift32-v1 with this nonzero seed is the frozen ten-block procedure.
  # Five blocks enumerate all ordered draws instead of using it.
  [uint32]$state=0x4D495247
  for($iteration=0;$iteration-lt$iterations;$iteration++){
    if($count-eq5){
      [int64]$encoded=$iteration
      for($slot=0;$slot-lt$count;$slot++){
        $pick=[int]($encoded%$count);$encoded=[int64][Math]::Floor($encoded/$count)
        $selectedBaseline[$slot]=[double]$Rows[$pick].baseline_addition_lower_seconds
        $selectedCandidate[$slot]=[double]$Rows[$pick].candidate_addition_upper_seconds
      }
    } else {
      for($slot=0;$slot-lt$count;$slot++){
        $state=[uint32]($state-bxor([uint32]($state-shl13)))
        $state=[uint32]($state-bxor([uint32]($state-shr17)))
        $state=[uint32]($state-bxor([uint32]($state-shl5)))
        $pick=[int](([uint64]$state)%[uint64]$count)
        $selectedBaseline[$slot]=[double]$Rows[$pick].baseline_addition_lower_seconds
        $selectedCandidate[$slot]=[double]$Rows[$pick].candidate_addition_upper_seconds
      }
    }
    # Use the frozen median interpolation without allocating per-draw copies.
    [Array]::Sort($selectedBaseline);[Array]::Sort($selectedCandidate)
    if($count%2-eq1){$drawBaseline=$selectedBaseline[[int](($count-1)/2)];$drawCandidate=$selectedCandidate[[int]( ($count-1)/2 )]}else{$upper=[int]($count/2);$drawBaseline=($selectedBaseline[$upper-1]+$selectedBaseline[$upper])/2.0;$drawCandidate=($selectedCandidate[$upper-1]+$selectedCandidate[$upper])/2.0}
    $baselineLower[$iteration]=$drawBaseline
    $marginLower[$iteration]=(0.5*$drawBaseline)-$drawCandidate
    $nonRegressionLower[$iteration]=$drawBaseline-$drawCandidate
  }
  return [ordered]@{
    procedure=$(if($count-eq5){'ordered-block-enumeration-v1'}else{'xorshift32-joint-block-bootstrap-v1'})
    block_count=$count
    resample_count=$iterations
    lower_tail_probability=0.0125
    quantile_rule='nearest-rank-ceiling-v1'
    random_seed=$(if($count-eq5){$null}else{'0x4D495247'})
    baseline_addition_lower_bound_seconds=Get-MIRDirectLibraryResponsiveMenuAnalysisQuantile -Values $baselineLower -Probability 0.0125
    halving_margin_lower_bound_seconds=Get-MIRDirectLibraryResponsiveMenuAnalysisQuantile -Values $marginLower -Probability 0.0125
    non_regression_margin_lower_bound_seconds=Get-MIRDirectLibraryResponsiveMenuAnalysisQuantile -Values $nonRegressionLower -Probability 0.0125
  }
}

function Get-MIRDirectLibraryResponsiveMenuPrimaryAnalysis {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$PredeclarationPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$MeasurementPaths
  )
  # This reader deliberately accepts exactly an initial five-block result for
  # every predeclared profile, or those two results followed by exactly one
  # five-block extension for every profile.  It never selects a subset of a
  # longer campaign or fills in a missing arm.
  $predeclarationFile=Get-Item -LiteralPath $PredeclarationPath -ErrorAction Stop
  Assert-MIRDirectLibraryResponsiveMenuAnalysis ($predeclarationFile.Length-gt0-and$predeclarationFile.Length-le2MB-and-not($predeclarationFile.Attributes-band[IO.FileAttributes]::ReparsePoint)) 'predeclaration-file'
  $predeclaration=Get-Content -Raw -LiteralPath $predeclarationFile.FullName|ConvertFrom-Json -Depth 40 -DateKind String
  Assert-MIRDirectLibraryResponsiveMenuAnalysis ([string]$predeclaration.kind-ceq'MIR47ResponsiveMenuAnalysisPredeclaration'-and[bool]$predeclaration.declared_before_primary_launches-and[int]$predeclaration.primary_samples_so_far-eq0) 'predeclaration-identity'
  Assert-MIRDirectLibraryResponsiveMenuAnalysis ([string]$predeclaration.gate-ceq'At least 50% less MIR-added process-start to observed Settings response time in each of the four fixed cells; no absolute-overhead alternative.') 'predeclaration-gate'
  $conditions=@($predeclaration.conditions|ForEach-Object {[string]$_})
  Assert-MIRDirectLibraryResponsiveMenuAnalysis ($conditions.Count-eq2-and$conditions[0]-ceq'changed-configuration'-and$conditions[1]-ceq'warm-repeat') 'predeclaration-conditions'
  $arms=@($predeclaration.arms|ForEach-Object {[string]$_})
  Assert-MIRDirectLibraryResponsiveMenuAnalysis (($arms-join"`n")-ceq('without-mir'+"`n"+'published corrected 4.6.0'+"`n"+'complete frozen 4.7.0 candidate including support additions')) 'predeclaration-arms'
  $profiles=@($predeclaration.profiles)
  Assert-MIRDirectLibraryResponsiveMenuAnalysis ($profiles.Count-eq2) 'predeclaration-profiles'
  $profileAuthority=@{}
  foreach($profile in $profiles){
    $profileSha=([string]$profile.sha256).ToUpperInvariant()
    Assert-MIRDirectLibraryResponsiveMenuAnalysis ((Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 $profileSha)-and-not$profileAuthority.ContainsKey($profileSha)-and-not[string]::IsNullOrWhiteSpace([string]$profile.path)) 'predeclaration-profile-row'
    $profileAuthority[$profileSha]=[ordered]@{path=[string]$profile.path;sha256=$profileSha}
  }
  # Only the predeclared initial two result files, or those two followed in
  # the same profile order by exactly one extension pair, are admissible.
  Assert-MIRDirectLibraryResponsiveMenuAnalysis ($MeasurementPaths.Count-in@(2,4)) 'measurement-path-count'
  $extensionRequested=($MeasurementPaths.Count-eq4)

  $seenPaths=@{};$seenResultHashes=@{};$entries=[Collections.Generic.List[object]]::new();$rawReferences=[Collections.Generic.List[object]]::new();$globalIdentity=$null;$globalActorIdentity=$null
  for($inputIndex=0;$inputIndex-lt$MeasurementPaths.Count;$inputIndex++){
    $measurementFile=Get-Item -LiteralPath $MeasurementPaths[$inputIndex] -ErrorAction Stop
    $resolved=$measurementFile.FullName
    Assert-MIRDirectLibraryResponsiveMenuAnalysis ($measurementFile.Length-gt0-and$measurementFile.Length-le64MB-and-not($measurementFile.Attributes-band[IO.FileAttributes]::ReparsePoint)-and-not$seenPaths.ContainsKey($resolved)) 'measurement-file'
    $seenPaths[$resolved]=$true
    $measurementSha=(Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToUpperInvariant()
    Assert-MIRDirectLibraryResponsiveMenuAnalysis (-not$seenResultHashes.ContainsKey($measurementSha)) 'measurement-duplicate-content'
    $seenResultHashes[$measurementSha]=$true
    $measurement=Get-Content -Raw -LiteralPath $resolved|ConvertFrom-Json -Depth 60 -DateKind String
    Assert-MIRDirectLibraryResponsiveMenuAnalysis ([int]$measurement.schema-eq1-and[string]$measurement.kind-ceq'MIRDirectLibraryStartupMeasurementV1'-and[string]$measurement.status-ceq'completed'-and[string]$measurement.mode-ceq'matched-three-input'-and[string]$measurement.endpoint_class-ceq'ordinary-responsive-menu'-and[bool]$measurement.library_controls_restored) 'measurement-status'
    $profileSha=([string]$measurement.profile_template_sha256).ToUpperInvariant()
    Assert-MIRDirectLibraryResponsiveMenuAnalysis ($profileAuthority.ContainsKey($profileSha)) 'measurement-profile'
    Assert-MIRDirectLibraryResponsiveMenuAnalysis ((Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 ([string]$measurement.factorio.sha256))-and[string]$measurement.target-ceq'f200') 'measurement-engine'
    $baseline=Get-MIRDirectLibraryResponsiveMenuAnalysisField -Object $measurement.inputs -Name 'baseline' -Code 'measurement-baseline'
    $baselineArchive=Get-MIRDirectLibraryResponsiveMenuAnalysisField -Object $baseline -Name 'archive' -Code 'measurement-baseline-archive'
    $baselineManifest=Get-MIRDirectLibraryResponsiveMenuAnalysisField -Object $baseline -Name 'authenticated_manifest' -Code 'measurement-baseline-manifest'
    $candidate=Get-MIRDirectLibraryResponsiveMenuAnalysisField -Object $measurement.inputs -Name 'candidate' -Code 'measurement-candidate'
    $candidateArchive=Get-MIRDirectLibraryResponsiveMenuAnalysisField -Object $candidate -Name 'archive' -Code 'measurement-candidate-archive'
    $candidateMaterialization=Get-MIRDirectLibraryResponsiveMenuAnalysisField -Object $candidate -Name 'materialization' -Code 'measurement-candidate-materialization'
    $ordinaryConfig=Get-MIRDirectLibraryResponsiveMenuAnalysisField -Object $measurement.inputs -Name 'ordinary_player_config' -Code 'measurement-ordinary-config'
    $ordinaryPlayerData=Get-MIRDirectLibraryResponsiveMenuAnalysisField -Object $measurement.inputs -Name 'ordinary_menu_player_data' -Code 'measurement-ordinary-player-data'
    $baselineHash=([string]$baselineArchive.sha256).ToUpperInvariant();$candidateHash=([string]$candidateArchive.sha256).ToUpperInvariant();$materializationHash=([string]$candidateMaterialization.archive_sha256).ToUpperInvariant();$configHash=([string]$ordinaryConfig.sha256).ToUpperInvariant();$playerDataHash=([string]$ordinaryPlayerData.sha256).ToUpperInvariant()
    Assert-MIRDirectLibraryResponsiveMenuAnalysis ([string]$baselineManifest.source_version-ceq'4.6.0'-and[string]$candidate.source_version-ceq'4.7.0'-and(Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 $baselineHash)-and(Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 $candidateHash)-and(Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 $materializationHash)-and$materializationHash-ceq$candidateHash-and(Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 $configHash)-and(Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 $playerDataHash)) 'measurement-candidate-equivalence'
    Assert-MIRDirectLibraryResponsiveMenuAnalysis ($null-ne$measurement.ordinary_menu_preparation-and-not[bool]$measurement.ordinary_menu_preparation.primary_measurement-and(Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 ([string]$measurement.ordinary_menu_preparation.source.sha256))-and([string]$measurement.ordinary_menu_preparation.source.sha256).ToUpperInvariant()-ceq$playerDataHash) 'measurement-preparation'
    $identity=[ordered]@{target=[string]$measurement.target;factorio_sha256=([string]$measurement.factorio.sha256).ToUpperInvariant();baseline_archive_sha256=$baselineHash;baseline_manifest_sha256=([string]$baselineManifest.sha256).ToUpperInvariant();candidate_archive_sha256=$candidateHash;candidate_materialization_archive_sha256=$materializationHash;original_player_config_sha256=$configHash;prepared_player_data_sha256=$playerDataHash}
    foreach($identityHash in @($identity.factorio_sha256,$identity.baseline_archive_sha256,$identity.baseline_manifest_sha256,$identity.candidate_archive_sha256,$identity.candidate_materialization_archive_sha256,$identity.original_player_config_sha256,$identity.prepared_player_data_sha256)){Assert-MIRDirectLibraryResponsiveMenuAnalysis (Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 $identityHash) 'measurement-identity-hash'}
    $identityText=ConvertTo-Json -InputObject $identity -Compress
    if($null-eq$globalIdentity){$globalIdentity=$identityText}else{Assert-MIRDirectLibraryResponsiveMenuAnalysis ($globalIdentity-ceq$identityText) 'measurement-global-identity-drift'}
    $entries.Add([pscustomobject][ordered]@{input_index=$inputIndex;path=$resolved;sha256=$measurementSha;result=$measurement;profile_sha256=$profileSha;identity=$identity;phase=$null;blocks=$null;actor_identity=$null})
  }
  # Paths must retain the profile order stated by the predeclaration.  In an
  # extension, the first pair is the immutable five-block checkpoint and the
  # second pair is the only admitted incremental five-block addition.
  foreach($entry in @($entries)){
    $round=[Math]::Floor([double]$entry.input_index/[double]$profiles.Count)
    $profileIndex=$entry.input_index%$profiles.Count
    $expectedProfile=([string]$profiles[$profileIndex].sha256).ToUpperInvariant()
    Assert-MIRDirectLibraryResponsiveMenuAnalysis ($entry.profile_sha256-ceq$expectedProfile-and$round-lt$(if($extensionRequested){2}else{1})) 'measurement-input-order'
    $entry.phase=$(if($round-eq0){'initial-five-blocks'}else{'extension-five-blocks'})
  }

  $rowsByCell=@{};$initialRowsByCell=@{}
  foreach($entry in @($entries)){
    $measurement=$entry.result;$identity=$entry.identity;$samples=@($measurement.samples)
    # The current runner has one complete warmup block plus exactly five
    # measured blocks.  Reading the original chronological array prevents an
    # after-the-fact reordering from being treated as the same shared cache.
    Assert-MIRDirectLibraryResponsiveMenuAnalysis ($samples.Count-eq36) 'sample-layout-count'
    $blocks=@{};$previousSelection=$null;$writeDataRoot=$null;$selectionHashByLabel=@{}
    $cursor=0
    for($block=1;$block-le6;$block++){
      $offset=($block-1)%3;$order=@('without-mir','released-4.6.0','candidate-4.7.0')
      $rotated=@();for($rotationIndex=0;$rotationIndex-lt3;$rotationIndex++){$rotated+=$order[($offset+$rotationIndex)%3]}
      foreach($position in 0..2){
        $label=$rotated[$position]
        for($repeat=0;$repeat-lt2;$repeat++){
          $sample=$samples[$cursor];$cursor++
          $isWarmup=($block-eq1);$isRepeat=($repeat-eq1)
          $expectedCache=if($isRepeat){'warm-repeat'}elseif($null-eq$previousSelection){'initial-selection'}else{'changed-configuration'}
          $expectedPrior=if($isRepeat){$label}else{$previousSelection}
          $expectedChanged=if($isRepeat){$false}elseif($null-eq$previousSelection){$null}else{$true}
          Assert-MIRDirectLibraryResponsiveMenuAnalysis ([string]$sample.label-ceq$label-and[int]$sample.measurement_block-eq$block-and[int]$sample.configuration_order-eq($position+1)-and[bool]$sample.warmup-eq$isWarmup-and[string]$sample.cache_state-ceq$expectedCache) 'sample-cache-order'
          Assert-MIRDirectLibraryResponsiveMenuAnalysis ((($null-eq$expectedPrior)-and($null-eq$sample.prior_selection_label)) -or (($null-ne$expectedPrior)-and([string]$sample.prior_selection_label-ceq$expectedPrior))) 'sample-cache-transition'
          $changedValid=(($null-eq$expectedChanged)-and($null-eq$sample.selection_changed)) -or (($null-ne$expectedChanged)-and($sample.selection_changed-is[bool])-and([bool]$sample.selection_changed-eq$expectedChanged))
          Assert-MIRDirectLibraryResponsiveMenuAnalysis $changedValid 'sample-cache-transition'
          Assert-MIRDirectLibraryResponsiveMenuAnalysis ([string]$sample.endpoint_class-ceq'ordinary-responsive-menu'-and[string]$sample.menu_response.status-ceq'validated-recorded-menu-interaction-response'-and[string]$sample.menu_response.endpoint_class-ceq'ordinary-responsive-menu'-and-not[bool]$sample.menu_response.shutdown_and_cleanup_included-and-not[bool]$sample.menu_response.claims_live_process_or_native_acceptance) 'sample-endpoint'
          $upper=[double]$sample.elapsed_seconds;$responseElapsed=[double]$sample.menu_response.elapsed_seconds;$lower=[double]$sample.menu_response.elapsed_lower_bound_seconds;$bracket=[double]$sample.menu_response.process_start_bracket_seconds
          Assert-MIRDirectLibraryResponsiveMenuAnalysis ($upper-gt0-and[Math]::Abs($upper-$responseElapsed)-le0.000000001-and$lower-gt0-and$bracket-ge0-and$lower-le$upper-and[Math]::Abs($upper-($lower+$bracket))-le0.000001) 'sample-response-elapsed'
          Assert-MIRDirectLibraryResponsiveMenuAnalysis ([int]$sample.menu_response.process_id-gt0-and(Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 ([string]$sample.menu_response.first_menu_sha256)) -and (Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 ([string]$sample.menu_response.settings_response_sha256)) -and (Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 ([string]$sample.responsive_menu_actor.sha256)) -and (Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 ([string]$sample.responsive_menu_actor.script_sha256)) -and (Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 ([string]$sample.responsive_menu_actor.observation_sha256)) -and (Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 ([string]$sample.responsive_menu_actor.window_sha256)) -and (Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 ([string]$sample.responsive_menu_actor.launch_spec.sha256))) 'sample-ownership-hashes'
          $sampleConfig=Get-MIRDirectLibraryResponsiveMenuAnalysisField -Object $sample -Name 'ordinary_player_config' -Code 'sample-producer-link'
          $samplePreparation=Get-MIRDirectLibraryResponsiveMenuAnalysisField -Object $sample -Name 'ordinary_menu_preparation' -Code 'sample-producer-link'
          $controls=Get-MIRDirectLibraryResponsiveMenuAnalysisField -Object $sample -Name 'execution_controls' -Code 'sample-producer-link'
          $cache=Get-MIRDirectLibraryResponsiveMenuAnalysisField -Object $sample -Name 'cache_context' -Code 'sample-producer-link'
          Assert-MIRDirectLibraryResponsiveMenuAnalysis (([string]$sampleConfig.source.sha256).ToUpperInvariant()-ceq$identity.original_player_config_sha256-and(Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 ([string]$sampleConfig.private_config.sha256)) -and([string]$sampleConfig.private_config.sha256).ToUpperInvariant()-ceq([string]$controls.config.sha256).ToUpperInvariant()-and([string]$samplePreparation.source.sha256).ToUpperInvariant()-ceq$identity.prepared_player_data_sha256-and([string]$controls.player_data.preparation_sha256).ToUpperInvariant()-ceq$identity.prepared_player_data_sha256-and(Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 ([string]$controls.config.sha256))-and([string]$cache.configuration_sha256).ToUpperInvariant()-ceq([string]$controls.config.sha256).ToUpperInvariant()-and(Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 ([string]$controls.selection.sha256))-and([string]$cache.selection_sha256).ToUpperInvariant()-ceq([string]$controls.selection.sha256).ToUpperInvariant()-and([string]$cache.player_data_sha256_before).ToUpperInvariant()-ceq([string]$controls.player_data.sha256_before).ToUpperInvariant()-and(Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 ([string]$controls.player_data.sha256_before))) 'sample-producer-link'
          Assert-MIRDirectLibraryResponsiveMenuAnalysis ([bool]$cache.shared_across_arms-and(Test-MIRDirectLibraryResponsiveMenuAnalysisSha256 ([string]$controls.engine_sha256))-and([string]$controls.engine_sha256).ToUpperInvariant()-ceq$identity.factorio_sha256-and-not[string]::IsNullOrWhiteSpace([string]$cache.write_data_root)) 'sample-custody'
          if($null-eq$writeDataRoot){$writeDataRoot=[string]$cache.write_data_root}else{Assert-MIRDirectLibraryResponsiveMenuAnalysis ($writeDataRoot-ceq[string]$cache.write_data_root) 'sample-cache-root-drift'}
          $selectionHash=([string]$controls.selection.sha256).ToUpperInvariant()
          if($selectionHashByLabel.ContainsKey($label)){Assert-MIRDirectLibraryResponsiveMenuAnalysis ($selectionHashByLabel[$label]-ceq$selectionHash) 'sample-selection-drift'}else{$selectionHashByLabel[$label]=$selectionHash}
          $loaded=@($sample.loaded_selection|ForEach-Object {[string]$_})
          $mirLoaded=@($loaded|Where-Object {$_-cmatch'^more-infinite-research@'})
          if($label-ceq'without-mir'){Assert-MIRDirectLibraryResponsiveMenuAnalysis ($loaded.Count-gt0-and$mirLoaded.Count-eq0) 'sample-loaded-selection'}else{
            $expectedVersion=if($label-ceq'released-4.6.0'){[version][string]$measurement.inputs.baseline.archive.version}else{[version][string]$measurement.inputs.candidate.archive.version}
            Assert-MIRDirectLibraryResponsiveMenuAnalysis ($loaded.Count-gt0-and$mirLoaded.Count-eq1-and$mirLoaded[0]-ceq('more-infinite-research@'+$expectedVersion.ToString())) 'sample-loaded-selection'
          }
          $actorIdentity=([string]$sample.responsive_menu_actor.script_sha256).ToUpperInvariant()+'|'+([string]$sample.responsive_menu_actor.observation_sha256).ToUpperInvariant()+'|'+([string]$sample.responsive_menu_actor.window_sha256).ToUpperInvariant()
          if($null-eq$globalActorIdentity){$globalActorIdentity=$actorIdentity}else{Assert-MIRDirectLibraryResponsiveMenuAnalysis ($globalActorIdentity-ceq$actorIdentity) 'measurement-global-actor-drift'}
          if(-not$isRepeat){$previousSelection=$label}
          if($isWarmup){continue}
          $arm=if($label-ceq'without-mir'){'without'}elseif($label-ceq'released-4.6.0'){'released'}else{'candidate'}
          $condition=if($isRepeat){'warm-repeat'}else{'changed-configuration'}
          if(-not$blocks.ContainsKey($block)){$blocks[$block]=@{}}
          if(-not$blocks[$block].ContainsKey($condition)){$blocks[$block][$condition]=@{}}
          Assert-MIRDirectLibraryResponsiveMenuAnalysis (-not$blocks[$block][$condition].ContainsKey($arm)) 'sample-duplicate-arm'
          $blocks[$block][$condition][$arm]=[pscustomobject][ordered]@{upper_seconds=$upper;lower_seconds=$lower;source_result_sha256=$entry.sha256;measurement_block=[int]$block;label=$label;run_relative_path=[string]$sample.run_relative_path}
        }
      }
    }
    Assert-MIRDirectLibraryResponsiveMenuAnalysis ($cursor-eq$samples.Count-and$selectionHashByLabel.Count-eq3-and@($selectionHashByLabel.Values|Sort-Object -Unique).Count-eq3) 'sample-selection-layout'
    $entry.blocks=$blocks;$entry.actor_identity=$globalActorIdentity
    foreach($block in 2..6){
      foreach($condition in $conditions){
        Assert-MIRDirectLibraryResponsiveMenuAnalysis ($blocks.ContainsKey($block)-and$blocks[$block].ContainsKey($condition)) 'block-condition'
        foreach($arm in @('without','released','candidate')){Assert-MIRDirectLibraryResponsiveMenuAnalysis ($blocks[$block][$condition].ContainsKey($arm)) 'block-arm'}
        $without=$blocks[$block][$condition]['without'];$released=$blocks[$block][$condition]['released'];$candidateRow=$blocks[$block][$condition]['candidate']
        $row=[pscustomobject][ordered]@{phase=$entry.phase;source_result_sha256=$entry.sha256;measurement_block=[int]$block;without_mir=$without;released_46=$released;candidate_47=$candidateRow;baseline_addition_seconds=([double]$released.upper_seconds-[double]$without.upper_seconds);candidate_addition_seconds=([double]$candidateRow.upper_seconds-[double]$without.upper_seconds);baseline_addition_lower_seconds=([double]$released.lower_seconds-[double]$without.upper_seconds);candidate_addition_upper_seconds=([double]$candidateRow.upper_seconds-[double]$without.lower_seconds)}
        $cellKey=$entry.profile_sha256+'|'+$condition
        if(-not$rowsByCell.ContainsKey($cellKey)){$rowsByCell[$cellKey]=[Collections.Generic.List[object]]::new()}
        $rowsByCell[$cellKey].Add($row)
        if($entry.phase-ceq'initial-five-blocks'){
          if(-not$initialRowsByCell.ContainsKey($cellKey)){$initialRowsByCell[$cellKey]=[Collections.Generic.List[object]]::new()}
          $initialRowsByCell[$cellKey].Add($row)
        }
      }
    }
    $rawReferences.Add([ordered]@{phase=$entry.phase;path=$entry.path;sha256=$entry.sha256;profile_template_sha256=$entry.profile_sha256;target=$identity.target;factorio_sha256=$identity.factorio_sha256;baseline_archive_sha256=$identity.baseline_archive_sha256;candidate_archive_sha256=$identity.candidate_archive_sha256;candidate_materialization_archive_sha256=$identity.candidate_materialization_archive_sha256;original_player_config_sha256=$identity.original_player_config_sha256;prepared_player_data_sha256=$identity.prepared_player_data_sha256})
  }

  $initialCells=[Collections.Generic.List[object]]::new();$initialAllPointHalve=$true;$initialAllBoundsPass=$true
  foreach($profile in $profiles){foreach($condition in $conditions){
    $cellKey=([string]$profile.sha256).ToUpperInvariant()+'|'+$condition;$initialRows=@($initialRowsByCell[$cellKey])
    Assert-MIRDirectLibraryResponsiveMenuAnalysis ($initialRows.Count-eq5) 'initial-cell-block-count'
    $initialD46=Get-MIRDirectLibraryResponsiveMenuAnalysisMedian -Values ([double[]]@($initialRows|ForEach-Object {[double]$_.baseline_addition_seconds}))
    $initialD47=Get-MIRDirectLibraryResponsiveMenuAnalysisMedian -Values ([double[]]@($initialRows|ForEach-Object {[double]$_.candidate_addition_seconds}))
    $initialMargin=(0.5*$initialD46)-$initialD47;$initialBootstrap=Get-MIRDirectLibraryResponsiveMenuAnalysisBootstrap -Rows $initialRows;$initialPass=($initialD46-gt0-and$initialMargin-ge0);$initialBoundsPass=([double]$initialBootstrap.baseline_addition_lower_bound_seconds-gt0-and[double]$initialBootstrap.halving_margin_lower_bound_seconds-ge0)
    if(-not$initialPass){$initialAllPointHalve=$false};if(-not$initialBoundsPass){$initialAllBoundsPass=$false}
    $initialCells.Add([ordered]@{profile=[ordered]@{path=[string]$profile.path;sha256=([string]$profile.sha256).ToUpperInvariant()};condition=$condition;block_count=5;baseline_added_time_median_seconds=$initialD46;candidate_added_time_median_seconds=$initialD47;halving_margin_seconds=$initialMargin;reduction_fraction=$(if($initialD46-gt0){1-($initialD47/$initialD46)}else{$null});point_estimate_halves_added_time=$initialPass;bootstrap=$initialBootstrap;bounds_pass=$initialBoundsPass})
  }}
  Assert-MIRDirectLibraryResponsiveMenuAnalysis ((-not$extensionRequested)-or$initialAllPointHalve) 'extension-initial-point-estimate'
  Assert-MIRDirectLibraryResponsiveMenuAnalysis ((-not$extensionRequested)-or-not$initialAllBoundsPass) 'extension-initial-uncertainty'

  $cells=[Collections.Generic.List[object]]::new();$allPointHalve=$true;$allBoundsPass=$true;$blockCount=$null
  foreach($profile in $profiles){
    $profileSha=([string]$profile.sha256).ToUpperInvariant()
    foreach($condition in $conditions){
      $rows=@($rowsByCell[$profileSha+'|'+$condition])
      $expectedRows=if($extensionRequested){10}else{5}
      Assert-MIRDirectLibraryResponsiveMenuAnalysis ($rows.Count-eq$expectedRows) 'cell-block-count'
      if($null-eq$blockCount){$blockCount=$rows.Count}else{Assert-MIRDirectLibraryResponsiveMenuAnalysis ($blockCount-eq$rows.Count) 'cell-block-count-mismatch'}
      $baselineValues=[double[]]@($rows|ForEach-Object {[double]$_.baseline_addition_seconds});$candidateValues=[double[]]@($rows|ForEach-Object {[double]$_.candidate_addition_seconds})
      $d46=Get-MIRDirectLibraryResponsiveMenuAnalysisMedian -Values $baselineValues;$d47=Get-MIRDirectLibraryResponsiveMenuAnalysisMedian -Values $candidateValues;$margin=(0.5*$d46)-$d47
      $bootstrap=Get-MIRDirectLibraryResponsiveMenuAnalysisBootstrap -Rows $rows;$pointHalves=($d46-gt0-and$margin-ge0);$boundsPass=([double]$bootstrap.baseline_addition_lower_bound_seconds-gt0-and[double]$bootstrap.halving_margin_lower_bound_seconds-ge0)
      if(-not$pointHalves){$allPointHalve=$false};if(-not$boundsPass){$allBoundsPass=$false}
      $nonRegressionMargin=$d46-$d47
      $nonRegressionPass=($nonRegressionMargin-ge0-and[double]$bootstrap.non_regression_margin_lower_bound_seconds-ge0)
      $cells.Add([ordered]@{profile=[ordered]@{path=[string]$profile.path;sha256=$profileSha};condition=$condition;block_count=$rows.Count;paired_blocks=@($rows|ForEach-Object {[ordered]@{phase=$_.phase;source_result_sha256=$_.source_result_sha256;measurement_block=$_.measurement_block;without_mir_upper_seconds=$_.without_mir.upper_seconds;without_mir_lower_seconds=$_.without_mir.lower_seconds;released_46_upper_seconds=$_.released_46.upper_seconds;released_46_lower_seconds=$_.released_46.lower_seconds;candidate_47_upper_seconds=$_.candidate_47.upper_seconds;candidate_47_lower_seconds=$_.candidate_47.lower_seconds;baseline_addition_seconds=$_.baseline_addition_seconds;candidate_addition_seconds=$_.candidate_addition_seconds;baseline_addition_lower_seconds=$_.baseline_addition_lower_seconds;candidate_addition_upper_seconds=$_.candidate_addition_upper_seconds}});baseline_added_time=Get-MIRDirectLibraryResponsiveMenuAnalysisSummary -Values $baselineValues;candidate_added_time=Get-MIRDirectLibraryResponsiveMenuAnalysisSummary -Values $candidateValues;halving_margin_seconds=$margin;reduction_fraction=$(if($d46-gt0){1-($d47/$d46)}else{$null});point_estimate_halves_added_time=$pointHalves;bootstrap=$bootstrap;bounds_pass=$boundsPass})
      $cell=$cells[$cells.Count-1]
      $cell['non_regression_margin_seconds']=$nonRegressionMargin
      $cell['point_estimate_not_slower']=($nonRegressionMargin-ge0)
      $cell['non_regression_bounds_pass']=$nonRegressionPass
    }
  }
  # The maintainer's later fallback is reported separately. It neither changes
  # the original halving decision nor opens another sample-extension loop.
  # Uncertain bounds do not establish non-regression, even with a better median.
  $nonRegressionEstablished=(@($cells|Where-Object {-not$_.non_regression_bounds_pass}).Count-eq0)
  $decision=if(-not$allPointHalve){'return-development'}elseif($allBoundsPass){'analysis-gate-satisfied'}elseif($blockCount-eq5){'extend-to-10'}else{'inconclusive-after-10'}
  $initialReferences=@($rawReferences|Where-Object {$_.phase -ceq 'initial-five-blocks'});$extensionReferences=@($rawReferences|Where-Object {$_.phase -ceq 'extension-five-blocks'})
  [pscustomobject][ordered]@{
    schema=1;kind='MIRDirectLibraryResponsiveMenuPrimaryAnalysisV1';status='completed-analysis-only';claims_final_release_authority=$false;claims_native_acceptance=$false
    raw_references=[ordered]@{predeclaration=[ordered]@{path=$predeclarationFile.FullName;sha256=(Get-FileHash -LiteralPath $predeclarationFile.FullName -Algorithm SHA256).Hash.ToUpperInvariant()};measurements=@($rawReferences);initial_measurements=@($initialReferences);extension_measurements=@($extensionReferences)}
    input_identity=($globalIdentity|ConvertFrom-Json -Depth 10)
    extension_protocol=[ordered]@{predeclared_one_time_extension=$extensionRequested;input_order='initial profile order, then one extension in the same profile order';initial_five_block_checkpoint=@($initialCells);all_initial_point_estimates_halve=$initialAllPointHalve;all_initial_bounds_pass=$initialAllBoundsPass;extension_admitted=($extensionRequested-and$initialAllPointHalve-and-not$initialAllBoundsPass);limitation='The existing result schema has no launch-time continuation receipt. This analysis binds the retained input order and raw initial references, and rejects any other result count or profile order; it cannot independently prove wall-clock chronology between separate completed result files.'}
    method=[ordered]@{endpoint='actor-qpc-process-start-bracket-to-owned-settings-response';comparison='paired complete blocks, separate medians of released46-minus-without-mir and candidate47-minus-without-mir';halving_margin='0.5*median(B)-median(C)';launch_bracket_bounds='baseline lower uses released lower minus without upper; candidate upper uses candidate upper minus without lower';five_block_bootstrap='enumerate all 5^5 ordered joint triple-arm resamples';ten_block_bootstrap='100000 xorshift32-v1 joint triple-arm resamples, seed 0x4D495247';lower_bound='one-sided 1.25th percentile, nearest-rank-ceiling-v1';warmups='one complete initial block is retained and excluded from metric rows';failure_policy='failed, incomplete, wrong-endpoint, ownership, producer-link, hash, cache-order, selection, or input-drift records are rejected; no duration-based exclusion or synthetic replacement'}
    cells=@($cells);decision=$decision
    non_regression=[ordered]@{established=$nonRegressionEstablished;criterion='median(B)-median(C) >= 0 and its conservative one-sided 1.25th-percentile joint-block bootstrap lower bound >= 0 in every fixed cell';decision=$(if($nonRegressionEstablished){'non-regression-supported'}else{'non-regression-not-established'});changes_halving_decision=$false;authorizes_additional_samples=$false;claims_release_authority=$false;limitation='Approximate bootstrap evidence for the predeclared profiles and conditions only; unresolved variation or endpoint uncertainty is not a pass. A nonpositive added-time denominator still cannot support a percentage-reduction claim.'}
  }
}
