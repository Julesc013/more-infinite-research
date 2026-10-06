Set-StrictMode -Version Latest

function Get-MIR421PinnedV2PackageInputs {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  . (Join-Path $repo 'tools/mir/application/package/SourceCompositionProof.ps1')
  $commit='f7f9bab7bb1d1a63c98b5e21178fbaed418a3f6e'
  $tree=Get-MIR4GitTree -RepoRoot $repo -Commit $commit
  if($tree -cne 'cfba4858cee79ddc326064862b829d29895bb81d'){throw '[mir421-v2-pinned-tree]'}
  $paths=@('targets/package-authority.json','src/mod/package-source.json','targets/f210/overlay.json','targets/registry.json','targets/support-policy.json','tools/mir/application/package/TargetMaterializer.ps1')
  $blobs=Read-MIR4GitBlobSet -RepoRoot $repo -Commit $commit -RelativePath $paths
  $utf8=[Text.UTF8Encoding]::new($false,$true)
  $records=@{}
  foreach($path in $paths|Where-Object {$_ -like '*.json'}){
    $record=$utf8.GetString($blobs[$path])|ConvertFrom-Json -Depth 100 -DateKind String
    if(-not (Test-MIR4BootstrapRecordHash -Record $record)){throw "[mir421-v2-pinned-record] $path"}
    $records[$path]=$record
  }
  $authority=$records['targets/package-authority.json'];$manifest=$records['src/mod/package-source.json'];$overlay=$records['targets/f210/overlay.json']
  $registry=$records['targets/registry.json'];$support=$records['targets/support-policy.json']
  if($authority.kind -cne 'MIR4CanonicalPackageAuthorityV1' -or $authority.editable_source_root -cne 'src/mod' -or
      $authority.source_manifest.path -cne 'src/mod/package-source.json' -or $manifest.kind -cne 'MIR4PackageSourceManifestV1' -or
      $manifest.record_sha256 -cne $authority.source_manifest.record_sha256 -or $registry.record_sha256 -cne $authority.target_registry.record_sha256 -or
      $support.record_sha256 -cne $authority.support_policy.record_sha256 -or $overlay.kind -cne 'MIR4TargetOverlayV1' -or $overlay.target -cne 'f210' -or
      $manifest.materializer_abi -cne $authority.materializer_abi -or $overlay.materializer_abi -cne $manifest.materializer_abi){throw '[mir421-v2-pinned-authority]'}
  # Consume the exact pinned materializer's read-only binding selector. Do not
  # execute its writer or recreate its former editable roots/worktree.
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseInput($utf8.GetString($blobs['tools/mir/application/package/TargetMaterializer.ps1']),[ref]$tokens,[ref]$errors)
  $definitions=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-MIR4TargetMaterializationBindings'},$false))
  if(@($errors).Count -or $definitions.Count -ne 1){throw '[mir421-v2-pinned-selector]'}
  $body=$definitions[0].Body.Extent.Text
  $selector=[scriptblock]::Create($body.Substring(1,$body.Length-2))
  $selection=& $selector -State @{manifest=$manifest;overlay=$overlay;target=@{target='f210'}}
  if($selection.bindings.Count -ne 337 -or $selection.omissions.Count -ne 0){throw '[mir421-v2-pinned-membership]'}
  $sources=Read-MIR4GitBlobSet -RepoRoot $repo -Commit $commit -RelativePath @($selection.bindings.source_path)
  $entries=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal)
  [int64]$total=0
  foreach($binding in $selection.bindings){
    $source=$sources[[string]$binding.source_path]
    if($source.Length -ne $binding.source_bytes -or (Get-MIR4Sha256Bytes -Bytes $source) -cne $binding.source_sha256){throw "[mir421-v2-pinned-source] $($binding.source_path)"}
    $bytes=switch([string]$binding.transform){
      'copy-exact-bytes' {$source;break}
      'exact-template-v1' {$source;break}
      'decode-base64-v1' {[Convert]::FromBase64String($utf8.GetString($source).Trim());break}
      default {throw '[mir421-v2-pinned-transform]'}
    }
    if($bytes.Length -ne $binding.output_bytes -or (Get-MIR4Sha256Bytes -Bytes $bytes) -cne $binding.output_sha256){throw "[mir421-v2-pinned-output] $($binding.output_path)"}
    $total+=$bytes.Length
    if($total -gt 16MB){throw '[mir421-v2-pinned-byte-budget]'}
    $entries.Add([string]$binding.output_path,[byte[]]$bytes)
  }
  # This is the sole version substitution made by the pinned writer for 4.2.0.
  $info=$utf8.GetString($entries['info.json'])|ConvertFrom-Json -Depth 20 -DateKind String
  if($info.name -cne 'more-infinite-research' -or $info.factorio_version -cne '2.1' -or $info.version -cne '4.0.21000'){throw '[mir421-v2-pinned-info]'}
  $info.version='4.2.21000'
  $entries['info.json']=$utf8.GetBytes(($info|ConvertTo-Json -Depth 20).Replace("`r`n","`n")+"`n")
  [pscustomobject]@{commit=$commit;tree=$tree;entries=$entries;source_manifest_sha256=$manifest.record_sha256;target_overlay_sha256=$overlay.record_sha256;package_authority_sha256=$authority.record_sha256;classification='pinned-private-V2-source-input-only';publication_authorized=$false}
}

function Read-MIR421PinnedV2Candidate {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Archive)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $path=(Resolve-Path -LiteralPath $Archive).Path
  if([IO.Path]::GetFileName($path) -cne 'more-infinite-research_4.2.21000.zip' -or (Get-Item -LiteralPath $path).Length -gt 16MB){throw '[mir421-v2-archive-identity]'}
  $pinned=Get-MIR421PinnedV2PackageInputs -RepoRoot $repo
  $root='more-infinite-research_4.2.21000/'
  $zip=[IO.Compression.ZipFile]::OpenRead($path)
  try {
    if($zip.Entries.Count -ne $pinned.entries.Count){throw '[mir421-v2-archive-membership]'}
    foreach($entry in $pinned.entries.GetEnumerator()){
      $members=@($zip.Entries|Where-Object FullName -CEQ ($root+$entry.Key))
      if($members.Count -ne 1 -or $members[0].Length -ne $entry.Value.Length){throw "[mir421-v2-archive-binding] $($entry.Key)"}
      $bytes=Read-MIR4BoundedZipEntryBytes -Entry $members[0] -MaximumBytes ([Math]::Max(1,$entry.Value.Length))
      if((Get-MIR4Sha256Bytes -Bytes $bytes) -cne (Get-MIR4Sha256Bytes -Bytes $entry.Value)){throw "[mir421-v2-archive-binding] $($entry.Key)"}
    }
  } finally {$zip.Dispose()}
  $utf8=[Text.UTF8Encoding]::new($false,$true)
  if(-not $utf8.GetString($pinned.entries['prototypes/mir/emit/mod_data.lua']).Contains('maximum-level-policy-v2') -or
      $utf8.GetString($pinned.entries['prototypes/mir/runtime/maximum_level_control.lua']) -notmatch 'local POLICY_VERSION = 1'){throw '[mir421-v2-authentic-controller]'}
  [pscustomobject]@{path=$path;archive_sha256=Get-MIR4Sha256File -Path $path;source_commit=$pinned.commit;source_tree=$pinned.tree;source_manifest_sha256=$pinned.source_manifest_sha256;target_overlay_sha256=$pinned.target_overlay_sha256;verified_bindings=$pinned.entries.Count;source_version='4.2.0';distribution_version='4.2.21000';classification=$pinned.classification;publication_authorized=$false}
}

function Assert-MIR4PinnedHistoricalSourceAuthority {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [Parameter(Mandatory)][string]$SchemaPath,
    [Parameter(Mandatory)][string]$Kind,
    [Parameter(Mandatory)][string]$AuthorityId
  )

  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  . (Join-Path $repo 'tools/lib/mir4/BootstrapMaterialization.ps1')
  . (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
  $absoluteReceipt = Join-Path $repo $ReceiptPath
  $raw = Get-Content -Raw -LiteralPath $absoluteReceipt
  $schemaValid = $false
  try { $schemaValid = $raw | Test-Json -SchemaFile (Join-Path $repo $SchemaPath) -ErrorAction Stop } catch { $schemaValid = $false }
  if (-not $schemaValid) { throw "[mir4-pinned-historical-source-authority-schema] $AuthorityId" }
  $receipt = $raw | ConvertFrom-Json -Depth 100 -DateKind String
  if ([string]$receipt.kind -cne $Kind) { throw "[mir4-pinned-historical-source-authority-kind] $AuthorityId" }
  if ($receipt.PSObject.Properties['record_sha256'] -and -not (Test-MIR4BootstrapRecordHash -Record $receipt)) {
    throw "[mir4-pinned-historical-source-authority-hash] $AuthorityId"
  }
  if ($receipt.PSObject.Properties['transition_gate'] -and @($receipt.transition_gate.PSObject.Properties | Where-Object { [bool]$_.Value }).Count -ne 0) {
    throw "[mir4-pinned-historical-source-authority-gate] $AuthorityId"
  }
  $current = Get-MIR4CanonicalPackageAuthority -RepoRoot $repo
  if ([string]$current.editable_source_root -cne 'source' -or
      [string]$current.source_manifest.path -cne 'source/package-source.json' -or
      [string]$current.writer.implementation -cne 'tools/mir/application/package/TargetMaterializer.ps1') {
    throw "[mir4-pinned-historical-source-authority-current-successor] $AuthorityId"
  }
  return [pscustomobject][ordered]@{
    status = 'passed-pinned-historical-source-authority-verification'
    authority_id = $AuthorityId
    classification = 'historical-verification-only'
    receipt_path = $ReceiptPath
    receipt_kind = $Kind
    current_source_root = 'source'
    current_writer = 'tools/mir/application/package/TargetMaterializer.ps1'
    player_package_mutation_authorized = $false
    publication_authorized = $false
  }
}
