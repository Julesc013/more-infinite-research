# MIR 4 API V1 developer-preview binding. Copied deterministically into preview archives.
$script:MIR4ApiV1Surfaces=@('continuity-bundle','host-manifest','observation','profile','proof','query','release','target-provider-abi','tooling')
$script:MIR4ApiV1MaxPageItems=128
$script:MIR4ApiV1MaxCapabilities=128
$script:MIR4ApiV1MaxExtensions=32
$canonicalModule=Join-Path $PSScriptRoot '../../canonical-json-v1/powershell/MIR4.CanonicalJson.V1.psm1'
if(-not(Test-Path -LiteralPath $canonicalModule -PathType Leaf)){throw '[mir4-sdk-canonical-module-missing]'}
Import-Module $canonicalModule -Force

function Copy-MIR4ApiV1Data {
  param([AllowNull()]$Value)
  if($null-eq$Value){return $null}
  return (($Value|ConvertTo-Json -Depth 100 -Compress)|ConvertFrom-Json -Depth 100)
}

function ConvertFrom-MIR4ApiV1Json {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)
  $canonical=ConvertFrom-MIR4CanonicalJsonTextV1 -Json $Json
  return $canonical|ConvertFrom-Json -Depth 100
}

function ConvertTo-MIR4ApiV1CanonicalJson {
  param([Parameter(Mandatory)][AllowNull()]$Value)
  return ConvertTo-MIR4CanonicalJsonV1 -Value $Value
}

function Get-MIR4ApiV1Digest {
  param([Parameter(Mandatory)]$Value)
  return Get-MIR4CanonicalDigestV1 -Value $Value -Domain 'mir4:api-response-v1' -OmitTopLevelDigest
}

function Test-MIR4ApiV1OrdinalSet {
  param([AllowEmptyCollection()][object[]]$Values,[Parameter(Mandatory)][string]$Code)
  $strings=@($Values|ForEach-Object{[string]$_})
  $expected=@($strings|Sort-Object -CaseSensitive -Unique)
  if($strings.Count-ne$expected.Count){throw "[$Code]"}
  for($i=0;$i-lt$strings.Count;$i++){if(-not[StringComparer]::Ordinal.Equals($strings[$i],$expected[$i])){throw "[$Code]"}}
}

function Test-MIR4ApiV1Response {
  param([Parameter(Mandatory)]$Response)
  $required=@('availability','canonicalization','capabilities','digest','extensions','items','kind','mutation_authorized','package_visible','page','public_support_claim','schema','source_identity','surface','target','versions')
  $actual=@($Response.PSObject.Properties.Name|Sort-Object -CaseSensitive)
  if(($actual-join'|')-cne(($required|Sort-Object -CaseSensitive)-join'|')){throw '[mir4-api-v1-schema]'}
  if([string]$Response.kind-cne'MIR4ApiResponseV1'-or[int]$Response.schema-ne1){throw '[mir4-api-v1-schema]'}
  if([string]$Response.surface-notin$script:MIR4ApiV1Surfaces){throw '[mir4-api-v1-surface]'}
  if([string]$Response.target.id-cnotmatch'^f[0-9]{3}$'){throw '[mir4-api-v1-target]'}
  if([string]$Response.target.factorio_line-cnotmatch'^[0-9]+\.[0-9]+$'-or[string]::IsNullOrWhiteSpace([string]$Response.target.transport)){throw '[mir4-api-v1-target]'}
  if([string]::IsNullOrWhiteSpace([string]$Response.versions.source)-or[string]::IsNullOrWhiteSpace([string]$Response.versions.distribution)){throw '[mir4-api-v1-version]'}
  if([string]$Response.canonicalization-cne'mir-canonical-json/1'){throw '[mir4-api-v1-canonicalization]'}
  if([bool]$Response.package_visible-or[bool]$Response.mutation_authorized-or[bool]$Response.public_support_claim){throw '[mir4-api-v1-authority-boundary]'}
  $capabilities=@($Response.capabilities)
  if($capabilities.Count-gt$script:MIR4ApiV1MaxCapabilities){throw '[mir4-api-v1-capability-cardinality]'}
  Test-MIR4ApiV1OrdinalSet -Values $capabilities -Code 'mir4-api-v1-capability-order'
  foreach($capability in $capabilities){if([string]$capability-cnotmatch'^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$'){throw '[mir4-api-v1-capability]'}}
  if([string]$Response.availability.status-notin@('available','unavailable')){throw '[mir4-api-v1-availability]'}
  if([string]::IsNullOrWhiteSpace([string]$Response.availability.reason)){throw '[mir4-api-v1-availability]'}
  Test-MIR4ApiV1OrdinalSet -Values @($Response.availability.evidence) -Code 'mir4-api-v1-evidence-order'
  $offset=[long]$Response.page.offset;$limit=[long]$Response.page.limit;$returned=[long]$Response.page.returned
  if($offset-lt0-or$limit-lt1-or$limit-gt$script:MIR4ApiV1MaxPageItems-or$returned-lt0-or$returned-gt$limit){throw '[mir4-api-v1-page]'}
  if($returned-ne@($Response.items).Count){throw '[mir4-api-v1-returned-count]'}
  if($null-ne$Response.page.total-and([long]$Response.page.total-lt0-or$offset+$returned-gt[long]$Response.page.total)){throw '[mir4-api-v1-page]'}
  if($null-ne$Response.page.next_cursor-and[string]$Response.page.next_cursor-cnotmatch'^[0-9]+$'){throw '[mir4-api-v1-cursor]'}
  if([string]$Response.availability.status-eq'unavailable'){
    if($null-ne$Response.page.total-or$returned-ne0-or@($Response.items).Count-ne0-or$null-ne$Response.page.next_cursor){throw '[mir4-api-v1-unavailable-is-not-zero]'}
  }
  $extensionNames=@($Response.extensions.PSObject.Properties|ForEach-Object{$_.Name})
  if($extensionNames.Count-gt$script:MIR4ApiV1MaxExtensions){throw '[mir4-api-v1-extension-cardinality]'}
  foreach($name in $extensionNames){if([string]$name-cnotmatch'^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$'){throw '[mir4-api-v1-extension-namespace]'}}
  if([string]$Response.digest-cne(Get-MIR4ApiV1Digest -Value $Response)){throw '[mir4-api-v1-digest]'}
  return $true
}

function Get-MIR4ApiV1Capabilities {
  param([Parameter(Mandatory)]$Response,[string[]]$Requested=@(),[string[]]$Required=@())
  Test-MIR4ApiV1Response $Response|Out-Null
  $offered=@($Response.capabilities|ForEach-Object{[string]$_})
  $requestedSet=if(@($Requested).Count-eq0){$offered}else{@($Requested)}
  $selected=@($requestedSet|Where-Object{$_-in$offered}|Sort-Object -CaseSensitive -Unique)
  $missing=@($Required|Where-Object{$_-notin$offered}|Sort-Object -CaseSensitive -Unique)
  if($missing.Count-gt0){throw "[mir4-api-v1-capability-required] $($missing-join',')"}
  return [pscustomobject][ordered]@{offered=$offered;selected=$selected;missing=@()}
}

function Get-MIR4ApiV1Availability {
  param([Parameter(Mandatory)]$Response)
  Test-MIR4ApiV1Response $Response|Out-Null
  return [pscustomobject][ordered]@{available=([string]$Response.availability.status-eq'available');status=[string]$Response.availability.status;reason=[string]$Response.availability.reason;evidence=@($Response.availability.evidence)}
}

function Get-MIR4ApiV1Page {
  param([Parameter(Mandatory)]$Response,[AllowNull()][string]$ExpectedCursor=$null)
  Test-MIR4ApiV1Response $Response|Out-Null
  if($null-ne$ExpectedCursor-and[string]$ExpectedCursor-cne[string]$Response.page.offset){throw '[mir4-api-v1-cursor-mismatch]'}
  return [pscustomobject][ordered]@{items=@(Copy-MIR4ApiV1Data @($Response.items));offset=[long]$Response.page.offset;limit=[long]$Response.page.limit;returned=[long]$Response.page.returned;total=$Response.page.total;next_cursor=$Response.page.next_cursor}
}

function Compare-MIR4ApiV1Snapshot {
  param([Parameter(Mandatory)]$Before,[Parameter(Mandatory)]$After)
  Test-MIR4ApiV1Response $Before|Out-Null;Test-MIR4ApiV1Response $After|Out-Null
  if([string]$Before.surface-cne[string]$After.surface-or[string]$Before.target.id-cne[string]$After.target.id){throw '[mir4-api-v1-snapshot-identity]'}
  $beforeItems=ConvertTo-MIR4ApiV1CanonicalJson @($Before.items);$afterItems=ConvertTo-MIR4ApiV1CanonicalJson @($After.items)
  return [pscustomobject][ordered]@{equal=($beforeItems-ceq$afterItems-and[string]$Before.digest-ceq[string]$After.digest);before_digest=[string]$Before.digest;after_digest=[string]$After.digest;items_changed=($beforeItems-cne$afterItems)}
}

function Format-MIR4ApiV1Diagnostic {
  param([Parameter(Mandatory)]$Diagnostic,[string]$RegistryPath=(Join-Path $PSScriptRoot '../diagnostics.json'))
  $registry=Get-Content -Raw -LiteralPath $RegistryPath|ConvertFrom-Json -Depth 100
  $entry=@($registry.diagnostics|Where-Object code -eq([string]$Diagnostic.code))
  if($entry.Count-ne1){throw '[mir4-api-v1-diagnostic-code]'}
  $path=if([string]::IsNullOrWhiteSpace([string]$Diagnostic.path)){'$'}else{[string]$Diagnostic.path}
  return "[$([string]$entry[0].code)] $path $([string]$Diagnostic.message)".Trim()
}

function Test-MIR4ApiV1Extension {
  param([Parameter(Mandatory)]$Extension,[string]$SchemaPath=(Join-Path $PSScriptRoot '../../mep-v1/json-schema/mir4-mep-v1.schema.json'))
  if(-not(($Extension|ConvertTo-Json -Depth 100)|Test-Json -SchemaFile $SchemaPath)){throw '[mir4-mep-v1-schema]'}
  $forbidden=@('callback','callbacks','compiler_context','data_raw','executor','prototype','prototype_write','safety_kernel','safety_kernel_override')
  $scan={param($Value,[string]$Path='$');if($null-eq$Value){return};if($Value-is[pscustomobject]){foreach($p in $Value.PSObject.Properties){if($p.Name-in$forbidden){throw "[mir4-mep-v1-forbidden-field] $Path.$($p.Name)"};&$scan $p.Value "$Path.$($p.Name)"}}elseif($Value-is[Collections.IEnumerable]-and$Value-isnot[string]){$i=0;foreach($item in $Value){&$scan $item "$Path[$i]";$i++}}}
  &$scan $Extension
  $expected=Get-MIR4CanonicalDigestV1 -Value $Extension -Domain 'mir4:extension-envelope-v1' -OmitTopLevelDigest
  if([string]$Extension.digest-cne$expected){throw '[mir4-mep-v1-digest]'}
  return $true
}

function Test-MIR4ApiV1Manifest {
  param([Parameter(Mandatory)]$Manifest,[Parameter(Mandatory)][string]$Root)
  $resolved=(Resolve-Path -LiteralPath $Root).Path;$prefix=$resolved.TrimEnd('\')+'\'
  $rows=@($Manifest.files)
  if($rows.Count-eq0){throw '[mir4-api-v1-manifest-empty]'}
  $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach($row in $rows){
    $relative=([string]$row.path).Replace('\','/')
    if([IO.Path]::IsPathRooted($relative)-or$relative-match'(^|/)\.\.(/|$)'-or$relative.Contains(':')-or-not$seen.Add($relative)){throw '[mir4-api-v1-manifest-path]'}
    $path=[IO.Path]::GetFullPath((Join-Path $resolved $relative))
    if(-not$path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)-or-not(Test-Path -LiteralPath $path -PathType Leaf)){throw '[mir4-api-v1-manifest-file]'}
    $item=Get-Item -LiteralPath $path
    if([long]$row.bytes-ne$item.Length-or[string]$row.sha256-cne(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()){throw '[mir4-api-v1-manifest-digest]'}
  }
  return $true
}

function Test-MIR4ApiV1Archive {
  param([Parameter(Mandatory)][string]$ArchivePath)
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $scratch=Join-Path ([IO.Path]::GetTempPath()) ('mir4-sdk-v1-'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $scratch|Out-Null
  try{
    [IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path -LiteralPath $ArchivePath).Path,$scratch)
    $roots=@(Get-ChildItem -LiteralPath $scratch -Directory)
    if($roots.Count-ne1){throw '[mir4-api-v1-archive-root]'}
    $manifestPath=Join-Path $roots[0].FullName 'manifest.json'
    if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw '[mir4-api-v1-archive-manifest]'}
    $manifest=Get-Content -Raw -LiteralPath $manifestPath|ConvertFrom-Json -Depth 100
    return Test-MIR4ApiV1Manifest -Manifest $manifest -Root $roots[0].FullName
  }finally{if(Test-Path -LiteralPath $scratch){Remove-Item -LiteralPath $scratch -Recurse -Force}}
}

Export-ModuleMember -Function Copy-MIR4ApiV1Data,ConvertFrom-MIR4ApiV1Json,ConvertTo-MIR4ApiV1CanonicalJson,Get-MIR4ApiV1Digest,Test-MIR4ApiV1Response,Get-MIR4ApiV1Capabilities,Get-MIR4ApiV1Availability,Get-MIR4ApiV1Page,Compare-MIR4ApiV1Snapshot,Format-MIR4ApiV1Diagnostic,Test-MIR4ApiV1Extension,Test-MIR4ApiV1Manifest,Test-MIR4ApiV1Archive
