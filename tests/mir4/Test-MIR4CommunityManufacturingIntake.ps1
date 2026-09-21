# MIR4-CANONICAL-STATIC-TEST
[CmdletBinding()]
param(
  [string]$RepoRoot=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
  [string]$ArchiveRoot='',
  [string]$OutputRoot='build/tests/mir42-community-manufacturing-intake'
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$repo=(Resolve-Path -LiteralPath $RepoRoot).Path
$output=[IO.Path]::GetFullPath((Join-Path $repo $OutputRoot))
$buildRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build'))+[IO.Path]::DirectorySeparatorChar
if(-not $output.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)){throw '[mir-community-manufacturing-intake] evidence must remain under build.'}

function Assert-CMI([bool]$Condition,[string]$Message){if(-not $Condition){throw "[mir-community-manufacturing-intake] $Message"}}
function Get-CMIHash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Get-CMIArchiveText([string]$Archive,[string]$Member){
  $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
  try {
    $entry=@($zip.Entries|Where-Object{$_.FullName -ceq $Member})
    Assert-CMI ($entry.Count -eq 1) "archive member is missing or ambiguous: $Member"
    $reader=[IO.StreamReader]::new($entry[0].Open(),[Text.UTF8Encoding]::new($false),$true)
    try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
  } finally {$zip.Dispose()}
}
function Get-CMIArchiveTextBySuffix([string]$Archive,[string]$Suffix){
  return [Text.UTF8Encoding]::new($false).GetString((Get-CMIArchiveBytesBySuffix -Archive $Archive -Suffix $Suffix))
}
function Get-CMIArchiveBytesBySuffix([string]$Archive,[string]$Suffix){
  $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
  try {
    $entry=@($zip.Entries|Where-Object{$_.FullName.EndsWith($Suffix,[StringComparison]::Ordinal)})
    Assert-CMI ($entry.Count -eq 1) "archive member suffix is missing or ambiguous: $Suffix"
    $stream=$entry[0].Open()
    $memory=[IO.MemoryStream]::new()
    try {$stream.CopyTo($memory);return $memory.ToArray()}finally{$memory.Dispose();$stream.Dispose()}
  } finally {$zip.Dispose()}
}
function Test-CMIByteEquality([byte[]]$Actual,[byte[]]$Expected){
  if($Actual.Length -ne $Expected.Length){return $false}
  for($index=0;$index -lt $Actual.Length;$index++){if($Actual[$index] -ne $Expected[$index]){return $false}}
  return $true
}
function Get-CMIRecipeWindow([string]$Text,[string]$Recipe){
  $marker='name = "'+$Recipe+'"'
  $start=$Text.IndexOf($marker,[StringComparison]::Ordinal)
  Assert-CMI ($start -ge 0) "observed recipe is absent: $Recipe"
  return $Text.Substring($start,[Math]::Min(2400,$Text.Length-$start))
}
function Get-CMIStreamBlock([string]$Text,[string]$Stream){
  $marker="  $Stream = {"
  $start=$Text.IndexOf($marker,[StringComparison]::Ordinal)
  Assert-CMI ($start -ge 0) "source stream is absent: $Stream"
  $next=$Text.IndexOf("`n`n  research_",$start+$marker.Length,[StringComparison]::Ordinal)
  Assert-CMI ($next -gt $start) "source stream boundary is absent: $Stream"
  return $Text.Substring($start,$next-$start)
}
function Get-CMIManifestRow([string]$Text,[string]$Stream){
  $marker="    recipe-prod-$Stream-1:"
  $start=$Text.IndexOf($marker,[StringComparison]::Ordinal)
  Assert-CMI ($start -ge 0) "stream manifest row is absent: $Stream"
  $tail=$Text.Substring($start+$marker.Length)
  $nextMatch=[regex]::Match($tail,'(?m)^    [a-z][a-z0-9_-]+:')
  Assert-CMI ($nextMatch.Success) "stream manifest row boundary is absent: $Stream"
  $next=$start+$marker.Length+$nextMatch.Index
  Assert-CMI ($next -gt $start) "stream manifest row boundary is absent: $Stream"
  return $Text.Substring($start,$next-$start)
}
function Get-CMIGroupItems([string]$Block,[double]$PerLevel){
  $number=[string]::Format([Globalization.CultureInfo]::InvariantCulture,'{0:0.00}',$PerLevel)
  $pattern='(?s)\{\s*change\s*=\s*'+[regex]::Escape($number)+'\s*,\s*items\s*=\s*\{(?<items>[^}]*)\}'
  $matches=@([regex]::Matches($Block,$pattern))
  Assert-CMI ($matches.Count -eq 1) "expected exactly one $number item group."
  return [string]$matches[0].Groups['items'].Value
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$fixturePath=Join-Path $repo 'fixtures/assert-community-manufacturing-intake/expected-vs-observed-vs-realized.json'
$fixture=Get-Content -Raw -LiteralPath $fixturePath|ConvertFrom-Json -Depth 30 -DateKind String
Assert-CMI ($fixture.kind -ceq 'MIR4CommunityManufacturingIntakeStaticFixtureV1') 'unexpected fixture kind.'
Assert-CMI ($fixture.status -ceq 'static-provenance-fixture-and-canonical-materialization-only') 'fixture must remain static-only.'
Assert-CMI (-not [bool]$fixture.authority.engine_qualification -and -not [bool]$fixture.authority.public_support_authority) 'fixture must not grant engine or public-support authority.'
Assert-CMI ($fixture.external_input_custody.kind -ceq 'MIR4CommittedProvenanceSafeExternalObservationFixtureV1') 'fixture must use approved provenance-safe external-input custody.'
Assert-CMI (-not [bool]$fixture.external_input_custody.archive_bytes_vendored) 'external archive bytes must not be vendored.'
Assert-CMI ($fixture.external_input_custody.hosted_evaluation -ceq 'fixture-and-canonical-source-only') 'hosted execution must remain portable and fixture-only.'
Assert-CMI ($fixture.external_input_custody.offline_replay.parameter -ceq 'ArchiveRoot' -and [bool]$fixture.external_input_custody.offline_replay.archive_root_must_be_explicit -and [bool]$fixture.external_input_custody.offline_replay.archive_hashes_must_match) 'offline archive replay custody is incomplete.'
Assert-CMI (-not [bool]$fixture.external_input_custody.offline_replay.engine_qualification -and -not [bool]$fixture.external_input_custody.offline_replay.public_support_authority) 'offline replay must not grant qualification or public support authority.'

$sourcePath=Join-Path $repo $fixture.realization.source_path
$sourceText=Get-Content -Raw -LiteralPath $sourcePath
$directEffects=Get-Content -Raw -LiteralPath (Join-Path $repo 'source/prototypes/streams/direct-effects.lua')
$streamManifest=Get-Content -Raw -LiteralPath (Join-Path $repo '.mir/streams.yml')
$requests=(Get-Content -Raw -LiteralPath (Join-Path $repo 'spec/programmes/community-requests.json')|ConvertFrom-Json -Depth 100 -DateKind String).requests
$requestIds=@($fixture.authority.request_ids)
$requestRows=@($requests|Where-Object{$_.id -in $requestIds})
Assert-CMI ($requestRows.Count -eq $requestIds.Count) 'expected community authorities are missing or duplicated.'
foreach($id in $requestIds){Assert-CMI (@($requestRows|Where-Object{$_.id -ceq $id}).Count -eq 1) "community authority must be unique: $id"}

Assert-CMI ($sourceText.Contains('local function bob_or_angel_wire_material_family(material)',[StringComparison]::Ordinal)) 'wire family must use the shared material-family mechanism.'
Assert-CMI ($sourceText.Contains('if aluminium_mod_active("angelssmelting") and not aluminium_mod_active("bobplates") then',[StringComparison]::Ordinal)) 'wire family must exclude Bob plates to prevent serial plate/wire ownership.'
foreach($wire in @($fixture.wire_routes)){
  $request=@($requestRows|Where-Object{$_.id -ceq $wire.request_id})[0]
  $declaration=$request.material_route_declaration.angel_only_wire_intake
  Assert-CMI ($null -ne $declaration) "wire intake is absent from the existing request authority: $($wire.request_id)"
  Assert-CMI (([string]$declaration.output -ceq [string]$wire.product) -and (@($declaration.recipes).Count -eq 1) -and ([string]$declaration.recipes[0] -ceq [string]$wire.recipe)) "wire authority differs for $($wire.request_id)"
  Assert-CMI ($sourceText.Contains("streams.$($wire.stream) = bob_or_angel_wire_material_family(`"$($wire.material)`")",[StringComparison]::Ordinal)) "stable stream does not select its wire material: $($wire.stream)"
  Assert-CMI ([string]$wire.recipe -ceq ('angels-wire-'+[string]$wire.material+'-2') -and [string]$wire.product -ceq ('angels-wire-'+[string]$wire.material)) "wire provenance fixture is internally inconsistent: $($wire.request_id)"
  Assert-CMI ([string]$wire.unpermitted_direct_recipe -ceq ('angels-wire-'+[string]$wire.material)) "direct-wire negative control is internally inconsistent: $($wire.request_id)"
  Assert-CMI ([string]$wire.coolant_return_recipe -ceq ('angels-wire-coil-'+[string]$wire.material+'-2')) "coolant-return negative control is internally inconsistent: $($wire.request_id)"
  Assert-CMI (-not $sourceText.Contains('"'+[string]$wire.coolant_return_recipe+'"',[StringComparison]::Ordinal)) "coolant-returning route was declared by MIR: $($wire.coolant_return_recipe)"
}

$streamBlocks=@{}
foreach($stream in @('research_bullets','research_heavy_ammo','research_rockets')){
  $streamBlocks[$stream]=Get-CMIStreamBlock $sourceText $stream
  $row=Get-CMIManifestRow $streamManifest $stream
  Assert-CMI ($row.Contains('capability: recipe-productivity',[StringComparison]::Ordinal)) "manufacturing stream is not recipe-productivity: $stream"
  Assert-CMI ($row.Contains('fixtures/assert-community-manufacturing-intake',[StringComparison]::Ordinal)) "manufacturing stream lacks static fixture evidence: $stream"
  Assert-CMI (-not $directEffects.Contains("  $stream = {",[StringComparison]::Ordinal)) "manufacturing stream was also declared as a direct effect: $stream"
}

$declaredAmmo=@()
foreach($group in @($fixture.ammunition_groups)){
  $items=Get-CMIGroupItems $streamBlocks[[string]$group.stream] ([double]$group.per_level)
  foreach($product in @($group.products)){
    Assert-CMI ($items.Contains('"'+[string]$product+'"',[StringComparison]::Ordinal)) "declared product is missing from its exact contribution group: $product"
    $owners=@($streamBlocks.GetEnumerator()|Where-Object{$_.Value.Contains('"'+[string]$product+'"',[StringComparison]::Ordinal)}|ForEach-Object{$_.Key})
    Assert-CMI ($owners.Count -eq 1 -and $owners[0] -ceq [string]$group.stream) "ammunition has an ambiguous manufacturing stream owner: $product"
    Assert-CMI (-not $directEffects.Contains('"'+[string]$product+'"',[StringComparison]::Ordinal)) "ammunition was bound to a direct damage or firing-speed stream: $product"
    $declaredAmmo += [string]$product
  }
}
Assert-CMI (($declaredAmmo|Sort-Object -Unique).Count -eq $declaredAmmo.Count) 'ammunition intake duplicates a final product.'
foreach($negative in @($fixture.ammunition_negative_controls)){
  foreach($block in $streamBlocks.Values){Assert-CMI (-not $block.Contains('"'+[string]$negative.recipe+'"',[StringComparison]::Ordinal)) "withheld ammunition was admitted: $($negative.recipe)"}
}

$archiveReplay = -not [string]::IsNullOrWhiteSpace($ArchiveRoot)
$archives=@{}
if($archiveReplay){
  $archiveRoot=(Resolve-Path -LiteralPath $ArchiveRoot).Path
  foreach($property in $fixture.archives.PSObject.Properties){
    $path=Join-Path $archiveRoot $property.Name
    Assert-CMI (Test-Path -LiteralPath $path -PathType Leaf) "explicit replay archive is absent: $($property.Name)"
    Assert-CMI ((Get-CMIHash $path) -ceq ([string]$property.Value)) "explicit replay archive hash differs: $($property.Name)"
    $archives[$property.Name]=$path
  }

  $angelArchive=$archives['angelssmelting_2.1.1.zip']
  $angelPermission=Get-CMIArchiveText $angelArchive 'angelssmelting/prototypes/override/smelting-override-productivity.lua'
  foreach($wire in @($fixture.wire_routes)){
    $recipeText=Get-CMIArchiveText $angelArchive ([string]$wire.recipe_member)
    $final=Get-CMIRecipeWindow $recipeText ([string]$wire.recipe)
    Assert-CMI ($final -match ('(?s)results\s*=\s*\{.*?name\s*=\s*"'+[regex]::Escape([string]$wire.product)+'"')) "observed final recipe does not produce its declared wire: $($wire.recipe)"
    Assert-CMI ($angelPermission.Contains('allow_productivity("'+[string]$wire.recipe+'")',[StringComparison]::Ordinal)) "observed final route lacks explicit productivity permission: $($wire.recipe)"
    Assert-CMI (-not $angelPermission.Contains('allow_productivity("'+[string]$wire.unpermitted_direct_recipe+'")',[StringComparison]::Ordinal)) "unpermitted direct wire was silently admitted: $($wire.unpermitted_direct_recipe)"
    $coolant=Get-CMIRecipeWindow $recipeText ([string]$wire.coolant_return_recipe)
    Assert-CMI ($coolant.Contains('angels-liquid-coolant-used',[StringComparison]::Ordinal)) "coolant return control is no longer observed: $($wire.coolant_return_recipe)"
  }
  $bobAmmo=Get-CMIArchiveText $archives['bobwarfare_3.0.1.zip'] 'bobwarfare/prototypes/recipe/ammo-recipe.lua'
  foreach($product in $declaredAmmo){
    $recipe=Get-CMIRecipeWindow $bobAmmo $product
    Assert-CMI ($recipe -match ('(?s)results\s*=\s*\{.*?name\s*=\s*"'+[regex]::Escape($product)+'"')) "observed Bob recipe does not produce the declared final ammunition: $product"
  }
  foreach($negative in @($fixture.ammunition_negative_controls)){[void](Get-CMIRecipeWindow $bobAmmo ([string]$negative.recipe))}
}

. (Join-Path $repo 'tools/mir/application/package/TargetMaterializer.ps1')
$sourceHash=Get-CMIHash $sourcePath
$sourceBytes=[IO.File]::ReadAllBytes($sourcePath)
$bindings=@()
foreach($target in @($fixture.realization.targets)){
  $state=Get-MIR4TargetMaterializerState -RepoRoot $repo -Target ([string]$target)
  $selection=Get-MIR4TargetMaterializationBindings -State $state
  $binding=@($selection.bindings|Where-Object{$_.source_path -ceq [string]$fixture.realization.source_path -and $_.output_path -ceq [string]$fixture.realization.output_path})
  Assert-CMI ($binding.Count -eq 1) "target composition lacks the canonical productivity binding: $target"
  Assert-CMI ([string]$binding[0].output_sha256 -ceq $sourceHash) "target composition hash differs from canonical source: $target"
  $bindings += [ordered]@{target=[string]$target;output_sha256=[string]$binding[0].output_sha256}
}
$materializedPackages=@()
foreach($target in @($fixture.realization.targets)){
  $identity=Resolve-MIR4CanonicalPackageIdentity -RepoRoot $repo -Target ([string]$target)
  $candidateA=New-MIR4TargetPackage -RepoRoot $repo -Target ([string]$target) -CandidateId ('CMI-STATIC-'+([string]$target).ToUpperInvariant()+'-A') -SourceVersion ([string]$identity.source_version) -OutputRoot $OutputRoot
  $candidateB=New-MIR4TargetPackage -RepoRoot $repo -Target ([string]$target) -CandidateId ('CMI-STATIC-'+([string]$target).ToUpperInvariant()+'-B') -SourceVersion ([string]$identity.source_version) -OutputRoot $OutputRoot
  Assert-CMI (([string]$candidateA.archive_sha256 -ceq [string]$candidateB.archive_sha256) -and ([string]$candidateA.content_sha256 -ceq [string]$candidateB.content_sha256) -and ([int]$candidateA.entry_count -eq [int]$candidateB.entry_count)) "target materialization is not deterministic: $target"
  foreach($candidate in @($candidateA,$candidateB)){
    $realized=Get-CMIArchiveBytesBySuffix ([string]$candidate.archive_path) '/prototypes/streams/productivity.lua'
    Assert-CMI (Test-CMIByteEquality -Actual $realized -Expected $sourceBytes) "materialized productivity bytes differ from canonical source: $target/$($candidate.candidate_id)"
  }
  $materializedPackages += [ordered]@{
    target=[string]$target
    source_version=[string]$candidateA.source_version
    productivity_lua_byte_identical_to_canonical=$true
    candidates=@($candidateA,$candidateB|ForEach-Object{[ordered]@{candidate_id=[string]$_.candidate_id;archive_sha256=[string]$_.archive_sha256;content_sha256=[string]$_.content_sha256;entry_count=[int]$_.entry_count}})
  }
}

if(-not (Test-Path -LiteralPath $output -PathType Container)){New-Item -ItemType Directory -Force -Path $output|Out-Null}
$result=[ordered]@{
  schema=1
  kind='MIR4CommunityManufacturingIntakeStaticResultV1'
  status='passed-static-provenance-fixture-and-canonical-materialization-only'
  authority=[ordered]@{request_ids=$requestIds;new_request_records=0;engine_qualification=$false;public_support_authority=$false}
  source=[ordered]@{path=[string]$fixture.realization.source_path;sha256=$sourceHash}
  external_input_custody=[ordered]@{kind=[string]$fixture.external_input_custody.kind;archive_bytes_vendored=$false;archive_replay=if($archiveReplay){'passed-explicit-hash-bound-source-observation-only'}else{'not-run-fixture-and-canonical-source-only'}}
  archives=@($fixture.archives.PSObject.Properties|ForEach-Object{[ordered]@{name=$_.Name;sha256=[string]$_.Value}})
  wire_routes=@($fixture.wire_routes)
  ammunition_products=@($declaredAmmo|Sort-Object)
  target_bindings=$bindings
  materialized_packages=$materializedPackages
  non_claims=@($fixture.non_claims)
}
$resultPath=Join-Path $output 'result.json'
[IO.File]::WriteAllText($resultPath,(($result|ConvertTo-Json -Depth 30)+"`n"),[Text.UTF8Encoding]::new($false))
$result|ConvertTo-Json -Depth 30
Write-Output "Evidence: $resultPath"
