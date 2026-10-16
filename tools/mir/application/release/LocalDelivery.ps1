Set-StrictMode -Version Latest

function Invoke-MIR4LocalDelivery {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][object[]]$Files,
    [Parameter(Mandatory)][string]$ReleaseId,
    [scriptblock]$AfterCopy,
    [System.Collections.IDictionary]$ReceiptMetadata
  )
  function Assert-DeliveryPhysicalPath([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while($current) {
      if(Test-Path -LiteralPath $current) {
        if((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "[mir4-delivery-reparse-path] $current" }
      }
      $parent=Split-Path -Parent $current
      if($parent -eq $current) { break };$current=$parent
    }
  }
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $source=(Resolve-Path -LiteralPath $SourceRoot).Path
  if($ReleaseId -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,63}$') { throw '[mir4-delivery-release-id]' }
  $dist=Join-Path $repo 'dist'
  $records=Join-Path $repo "build/delivery/$ReleaseId"
  Assert-DeliveryPhysicalPath $source
  Assert-DeliveryPhysicalPath $dist
  Assert-DeliveryPhysicalPath $records
  New-Item -ItemType Directory -Force -Path $dist,$records | Out-Null
  $lock=[IO.File]::Open((Join-Path $records 'delivery.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try {
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $plan=@(foreach($file in $Files) {
      foreach($name in @('source_path','destination_path')) {
        $relative=[string]$file.$name
        if([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[/\\])[.][.]?([/\\]|$)|[:\x00-\x1f]' -or [string]::IsNullOrWhiteSpace($relative)) { throw "[mir4-delivery-path] $name" }
      }
      $from=[IO.Path]::GetFullPath((Join-Path $source ([string]$file.source_path)))
      $to=[IO.Path]::GetFullPath((Join-Path $dist ([string]$file.destination_path)))
      if(-not $from.StartsWith($source+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not $to.StartsWith($dist+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-delivery-boundary]' }
      Assert-DeliveryPhysicalPath $from
      Assert-DeliveryPhysicalPath $to
      if(-not $seen.Add($to)) { throw '[mir4-delivery-duplicate-destination]' }
      $replaceExistingSha256 = if ($null -ne $file.PSObject.Properties['replace_existing_sha256']) { [string]$file.replace_existing_sha256 } else { '' }
      $preserveExistingDestinationPath = if ($null -ne $file.PSObject.Properties['preserve_existing_destination_path']) { [string]$file.preserve_existing_destination_path } else { '' }
      $replacementOwner = if ($null -ne $file.PSObject.Properties['replacement_owner']) { [string]$file.replacement_owner } else { '' }
      if (($replaceExistingSha256.Length -eq 0) -xor ($preserveExistingDestinationPath.Length -eq 0)) { throw '[mir4-delivery-replacement-contract]' }
      $preserve = $null
      if ($replaceExistingSha256.Length -gt 0) {
        $destinationName=[IO.Path]::GetFileName([string]$file.destination_path)
        if ($replaceExistingSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or $replacementOwner -cne 'mir42-nine-target-generated-pointer' -or
            ($destinationName -cnotin @('LATEST-MIR42-PUBLISHED.txt','LATEST-MIR42-FINAL-CANDIDATE.txt') -and $destinationName -notmatch '^UPLOAD-[0-9]+\.[0-9]+\.[0-9]+\.txt$') -or
            [IO.Path]::IsPathRooted($preserveExistingDestinationPath) -or $preserveExistingDestinationPath -match '(^|[/\\])[.][.]?([/\\]|$)|[:\x00-\x1f]') { throw '[mir4-delivery-replacement-contract]' }
        $preserve=[IO.Path]::GetFullPath((Join-Path $dist $preserveExistingDestinationPath))
        if(-not $preserve.StartsWith($dist+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '[mir4-delivery-boundary]' }
        Assert-DeliveryPhysicalPath $preserve
        if(-not $seen.Add($preserve)) { throw '[mir4-delivery-duplicate-destination]' }
      }
      $expected=[string]$file.sha256
      if($expected -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash -ine $expected) { throw "[mir4-delivery-source-identity] $($file.source_path)" }
      if(Test-Path -LiteralPath $to) {
        if(-not(Test-Path -LiteralPath $to -PathType Leaf)) { throw "[mir4-delivery-destination-conflict] $($file.destination_path)" }
        $actual=(Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash
        if($actual -ine $expected -and ($replaceExistingSha256.Length -eq 0 -or $actual -ine $replaceExistingSha256)) { throw "[mir4-delivery-destination-conflict] $($file.destination_path)" }
      } elseif ($replaceExistingSha256.Length -gt 0) {
        throw "[mir4-delivery-replacement-missing] $($file.destination_path)"
      }
      $entry=[ordered]@{source_path=[string]$file.source_path;destination_path=[string]$file.destination_path;sha256=$expected.ToUpperInvariant();bytes=(Get-Item -LiteralPath $from).Length}
      if($replaceExistingSha256.Length -gt 0) {
        $entry.replace_existing_sha256=$replaceExistingSha256.ToUpperInvariant()
        $entry.preserve_existing_destination_path=$preserveExistingDestinationPath
        $entry.replacement_owner=$replacementOwner
      } elseif ($replacementOwner.Length -gt 0) {
        throw '[mir4-delivery-replacement-contract]'
      }
      [pscustomobject]$entry
    })
    if($plan.Count -eq 0) { throw '[mir4-delivery-empty]' }
    $intent=[ordered]@{schema=1;release_id=$ReleaseId;files=$plan;build_authorized=$false;publication_authorized=$false}
    if ($null -ne $ReceiptMetadata) {
      foreach ($name in $ReceiptMetadata.Keys) {
        if ($name -cnotin @('frozen_inventory','source_version','release_tag','direct_root_package_count','versioned_bundle','versioned_bundle_sha256','versioned_bundle_bytes','mod_portal_upload_performed')) { throw '[mir4-delivery-receipt-metadata]' }
      }
      # Inventory identity is part of the resumable intent, even when a new
      # inventory happens to name the same files. Refuse a changed authority
      # before delivery effects rather than rewriting a completed receipt.
      $intent.receipt_metadata = $ReceiptMetadata
    }
    $intentJson=($intent | ConvertTo-Json -Depth 8).Replace("`r`n","`n")+"`n"
    $intentPath=Join-Path $records 'intent.json'
    if(Test-Path -LiteralPath $intentPath) {
      if([IO.File]::ReadAllText($intentPath) -cne $intentJson) { throw '[mir4-delivery-intent-conflict]' }
    } else {
      [IO.File]::WriteAllText($intentPath+'.tmp',$intentJson,[Text.UTF8Encoding]::new($false))
      [IO.File]::Move($intentPath+'.tmp',$intentPath)
    }
    foreach($file in $plan) {
      $from=Join-Path $source $file.source_path
      $to=Join-Path $dist $file.destination_path
      $isReplacement=$null -ne $file.PSObject.Properties['replace_existing_sha256']
      if($isReplacement) {
        $previous=[string]$file.replace_existing_sha256
        $preserve=Join-Path $dist ([string]$file.preserve_existing_destination_path)
        $current=(Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash
        if($current -ieq $file.sha256) {
          if(-not(Test-Path -LiteralPath $preserve -PathType Leaf) -or (Get-FileHash -LiteralPath $preserve -Algorithm SHA256).Hash -ine $previous) { throw "[mir4-delivery-preservation-conflict] $($file.destination_path)" }
          continue
        }
        if($current -ine $previous) { throw "[mir4-delivery-destination-conflict] $($file.destination_path)" }
        $preserveParent=Split-Path -Parent $preserve
        New-Item -ItemType Directory -Force -Path $preserveParent | Out-Null
        if(Test-Path -LiteralPath $preserve) {
          if(-not(Test-Path -LiteralPath $preserve -PathType Leaf) -or (Get-FileHash -LiteralPath $preserve -Algorithm SHA256).Hash -ine $previous) { throw "[mir4-delivery-preservation-conflict] $($file.destination_path)" }
        } else {
          $preserveTemporary=$preserve+'.mir-partial-'+[guid]::NewGuid().ToString('N')
          [IO.File]::Copy($to,$preserveTemporary,$false)
          if((Get-FileHash -LiteralPath $preserveTemporary -Algorithm SHA256).Hash -ine $previous) { throw '[mir4-delivery-copy-identity]' }
          [IO.File]::Move($preserveTemporary,$preserve,$false)
        }
        $temporary=$to+'.mir-partial-'+[guid]::NewGuid().ToString('N')
        [IO.File]::Copy($from,$temporary,$false)
        if((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ine $file.sha256) { throw '[mir4-delivery-copy-identity]' }
        $backup=Join-Path $records ('replacement-backup-'+[guid]::NewGuid().ToString('N'))
        [IO.File]::Replace($temporary,$to,$backup,$false)
        if(Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
        if($AfterCopy) { & $AfterCopy $file }
        continue
      }
      if(Test-Path -LiteralPath $to) { continue }
      $parent=Split-Path -Parent $to
      New-Item -ItemType Directory -Force -Path $parent | Out-Null
      # A crash leaves only a private partial file. Rerun verifies and replaces
      # a fresh staging file; an existing destination or staging file is never overwritten.
      $temporary=$to+'.mir-partial-'+[guid]::NewGuid().ToString('N')
      [IO.File]::Copy($from,$temporary,$false)
      if((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -cne $file.sha256) { throw '[mir4-delivery-copy-identity]' }
      [IO.File]::Move($temporary,$to,$false)
      if($AfterCopy) { & $AfterCopy $file }
    }
    foreach($file in $plan) {
      if((Get-FileHash -LiteralPath (Join-Path $dist $file.destination_path) -Algorithm SHA256).Hash -cne $file.sha256) { throw '[mir4-delivery-final-identity]' }
      if($null -ne $file.PSObject.Properties['replace_existing_sha256']) {
        $preserve=Join-Path $dist ([string]$file.preserve_existing_destination_path)
        if(-not(Test-Path -LiteralPath $preserve -PathType Leaf) -or (Get-FileHash -LiteralPath $preserve -Algorithm SHA256).Hash -ine [string]$file.replace_existing_sha256) { throw '[mir4-delivery-final-preservation-identity]' }
      }
    }
    $receipt=[ordered]@{schema=1;kind='MIR4LocalDeliveryV1';status='delivered-and-verified';release_id=$ReleaseId;files=$plan;source_and_remote_sync='separate-required-postcondition';build_performed=$false;publication_performed=$false}
    if ($null -ne $ReceiptMetadata) {
      foreach ($name in $ReceiptMetadata.Keys) {
        if ($name -cnotin @('frozen_inventory','source_version','release_tag','direct_root_package_count','versioned_bundle','versioned_bundle_sha256','versioned_bundle_bytes','mod_portal_upload_performed') -or $receipt.Contains($name)) { throw '[mir4-delivery-receipt-metadata]' }
        $receipt[$name] = $ReceiptMetadata[$name]
      }
    }
    $receiptPath=Join-Path $records 'receipt.json'
    [IO.File]::WriteAllText($receiptPath+'.tmp',(($receipt|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
    [IO.File]::Move($receiptPath+'.tmp',$receiptPath,$true)
    return [pscustomobject]$receipt
  } finally { $lock.Dispose() }
}

function Assert-MIR42NineTargetLocalDeliveryFile {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$Sha256,
    [Parameter(Mandatory)][int64]$Bytes
  )
  if ([IO.Path]::IsPathRooted($SourcePath) -or $SourcePath -match '(^|[/\\])[.][.]?([/\\]|$)|[:\x00-\x1f]' -or
      [string]::IsNullOrWhiteSpace($SourcePath)) {
    throw '[mir42-delivery-inventory-path]'
  }
  $root = (Resolve-Path -LiteralPath $SourceRoot).Path
  $full = [IO.Path]::GetFullPath((Join-Path $root $SourcePath))
  if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-Path -LiteralPath $full -PathType Leaf) -or
      (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -cne $Sha256 -or
      (Get-Item -LiteralPath $full -Force).Length -ne $Bytes) {
    throw "[mir42-delivery-source-identity] $SourcePath"
  }
  return $full
}

function Assert-MIR42NineTargetLocalDeliveryBundle {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][object[]]$Packages
  )
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
  } catch {
    throw '[mir42-delivery-bundle-open]'
  }
  try {
    $entries = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) })
    if ($entries.Count -ne $Packages.Count) { throw '[mir42-delivery-bundle-member-set]' }
    $byName = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($entry in $entries) {
      if ([string]$entry.FullName -cne [string]$entry.Name -or -not $byName.TryAdd([string]$entry.Name, $entry)) {
        throw '[mir42-delivery-bundle-member-set]'
      }
    }
    foreach ($package in $Packages) {
      $name = [string]$package.public_name
      if (-not $byName.ContainsKey($name)) { throw "[mir42-delivery-bundle-package] $name" }
      $entry = $byName[$name]
      $stream = $entry.Open()
      try {
        $hash = [Security.Cryptography.SHA256]::Create()
        try { $actual = [Convert]::ToHexString($hash.ComputeHash($stream)) } finally { $hash.Dispose() }
      } finally { $stream.Dispose() }
      if ($actual -cne [string]$package.sha256 -or [int64]$entry.Length -ne [int64]$package.bytes) {
        throw "[mir42-delivery-bundle-package] $name"
      }
    }
  } finally {
    $archive.Dispose()
  }
}

function Get-MIR42NineTargetLocalDeliveryPointerSelection {
  param(
    [Parameter(Mandatory)][string]$Path
  )
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "[mir42-delivery-pointer-missing] $([IO.Path]::GetFileName($Path))" }
  $text = [IO.File]::ReadAllText($Path)
  $patterns = [ordered]@{
    release_tag = '^Published:[ \t]*(?<value>v[0-9]+\.[0-9]+\.[0-9]+)[ \t]*\r?$'
    github_tag = '^GitHub:[ \t]*https://github\.com/Julesc013/more-infinite-research/releases/tag/(?<value>v[0-9]+\.[0-9]+\.[0-9]+)[ \t]*\r?$'
    source_version = '^Nine correct player ZIPs:[ \t]*dist/(?<value>[0-9]+\.[0-9]+\.[0-9]+)[ \t]+and[ \t]+top-level[ \t]+dist[ \t]*\r?$'
    f210 = '^Factorio 2\.1 upload:[ \t]*(?<value>more-infinite-research_[0-9]+\.[0-9]+\.[0-9]+\.zip)[ \t]*\r?$'
    f200 = '^Factorio 2\.0 upload:[ \t]*(?<value>more-infinite-research_[0-9]+\.[0-9]+\.[0-9]+\.zip)[ \t]*\r?$'
  }
  $selection = [ordered]@{}
  foreach ($field in $patterns.Keys) {
    $matches = [regex]::Matches($text, [string]$patterns[$field], [Text.RegularExpressions.RegexOptions]::Multiline -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if ($matches.Count -ne 1) { throw "[mir42-delivery-pointer-selector] $([IO.Path]::GetFileName($Path)):$field" }
    $selection[$field] = $matches[0].Groups['value'].Value
  }
  return [pscustomobject]$selection
}

function Get-MIR42NineTargetLocalDeliveryPointerPackageName {
  param(
    [Parameter(Mandatory)][string]$SourceVersion,
    [Parameter(Mandatory)][ValidateSet('f210','f200')][string]$Target
  )
  if ($SourceVersion -notmatch '^(?<major>[0-9]+)\.(?<minor>[0-9]+)\.(?<patch>[0-9]{1,2})$') { throw '[mir42-delivery-pointer-version]' }
  $code = if ($Target -ceq 'f210') { '210' } else { '200' }
  return ('more-infinite-research_{0}.{1}.{2}{3:D2}.zip' -f $Matches.major,$Matches.minor,$code,[int]$Matches.patch)
}

function Assert-MIR42NineTargetLocalDeliveryPointerSelection {
  param(
    [Parameter(Mandatory)]$Selection,
    [Parameter(Mandatory)][string]$Path
  )
  $sourceVersion = ([string]$Selection.release_tag).Substring(1)
  if ([string]$Selection.github_tag -cne [string]$Selection.release_tag -or
      [string]$Selection.source_version -cne $sourceVersion -or
      [string]$Selection.f210 -cne (Get-MIR42NineTargetLocalDeliveryPointerPackageName -SourceVersion $sourceVersion -Target f210) -or
      [string]$Selection.f200 -cne (Get-MIR42NineTargetLocalDeliveryPointerPackageName -SourceVersion $sourceVersion -Target f200)) {
    throw "[mir42-delivery-pointer-unrecognised] $([IO.Path]::GetFileName($Path))"
  }
  return $sourceVersion
}

function Assert-MIR42NineTargetLocalDeliveryPointer {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$SourceVersion,
    [Parameter(Mandatory)][string]$ReleaseTag,
    [Parameter(Mandatory)]$F210Package,
    [Parameter(Mandatory)]$F200Package
  )
  $selection = Get-MIR42NineTargetLocalDeliveryPointerSelection -Path $Path
  if ([string]$selection.release_tag -cne $ReleaseTag -or
      [string]$selection.github_tag -cne $ReleaseTag -or
      [string]$selection.source_version -cne $SourceVersion -or
      [string]$selection.f210 -cne [string]$F210Package.public_name -or
      [string]$selection.f200 -cne [string]$F200Package.public_name) {
    throw "[mir42-delivery-pointer-stale] $([IO.Path]::GetFileName($Path))"
  }
  $null = Assert-MIR42NineTargetLocalDeliveryPointerSelection -Selection $selection -Path $Path
}

function Get-MIR42NineTargetLocalDeliveryPriorIntentEntries {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ReleaseId
  )
  $entries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
  $intentPath = Join-Path $RepoRoot ('build/delivery/' + $ReleaseId + '/intent.json')
  if (-not (Test-Path -LiteralPath $intentPath)) { return $entries }
  try { $intent = [IO.File]::ReadAllText($intentPath) | ConvertFrom-Json } catch { throw '[mir42-delivery-prior-intent]' }
  if ($null -eq $intent -or [int]$intent.schema -ne 1 -or [string]$intent.release_id -cne $ReleaseId -or $null -eq $intent.files) { throw '[mir42-delivery-prior-intent]' }
  foreach ($file in @($intent.files)) {
    $destination = if ($null -ne $file.PSObject.Properties['destination_path']) { [string]$file.destination_path } else { '' }
    if ([string]::IsNullOrWhiteSpace($destination) -or -not $entries.TryAdd($destination, $file)) { throw '[mir42-delivery-prior-intent]' }
  }
  return $entries
}

function Get-MIR42NineTargetLocalDeliveryReplayPointerReplacement {
  param(
    [Parameter(Mandatory)][Collections.Generic.Dictionary[string, object]]$PriorIntentEntries,
    [Parameter(Mandatory)][string]$PointerName,
    [Parameter(Mandatory)][string]$PointerSha256,
    [Parameter(Mandatory)][string]$SourceVersion
  )
  if (-not $PriorIntentEntries.ContainsKey($PointerName)) { return $null }
  $entry = $PriorIntentEntries[$PointerName]
  if ($null -eq $entry.PSObject.Properties['replace_existing_sha256']) { return $null }
  $expectedPreservation = $SourceVersion + '/previous-' + $PointerName
  if ([string]$entry.source_path -cne $PointerName -or [string]$entry.destination_path -cne $PointerName -or
      [string]$entry.sha256 -ine $PointerSha256 -or [string]$entry.replace_existing_sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
      [string]$entry.preserve_existing_destination_path -cne $expectedPreservation -or
      [string]$entry.replacement_owner -cne 'mir42-nine-target-generated-pointer') {
    throw "[mir42-delivery-prior-pointer-intent] $PointerName"
  }
  return [pscustomobject][ordered]@{
    replace_existing_sha256 = ([string]$entry.replace_existing_sha256).ToUpperInvariant()
    preserve_existing_destination_path = $expectedPreservation
  }
}

function New-MIR42NineTargetLocalDeliveryBundle {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$BundleName,
    [Parameter(Mandatory)][object[]]$Packages
  )
  if ([IO.Path]::IsPathRooted($BundleName) -or $BundleName -match '(^|[/\\])[.][.]?([/\\]|$)|[:\x00-\x1f]' -or
      [IO.Path]::GetFileName($BundleName) -cne $BundleName -or $BundleName -notmatch '^MIR_[0-9]+_[0-9]+_[0-9]+_DISTRIBUTIONS\.zip$') {
    throw '[mir42-delivery-bundle-name]'
  }
  if (@($Packages).Count -ne 9) { throw '[mir42-delivery-bundle-package-count]' }
  $root = (Resolve-Path -LiteralPath $SourceRoot).Path
  $output = [IO.Path]::GetFullPath((Join-Path $root $BundleName))
  if (-not $output.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw '[mir42-delivery-bundle-boundary]'
  }
  $payloadsByName = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  $orderedNames = [Collections.Generic.List[string]]::new()
  foreach ($package in @($Packages)) {
    $name = [string]$package.public_name
    if ([string]::IsNullOrWhiteSpace($name) -or [IO.Path]::GetFileName($name) -cne $name -or $name -match '[/\\:\x00-\x1f]') {
      throw '[mir42-delivery-bundle-package-name]'
    }
    $path = Assert-MIR42NineTargetLocalDeliveryFile -SourceRoot $root -SourcePath ([string]$package.path) -Sha256 ([string]$package.sha256) -Bytes ([int64]$package.bytes)
    $payload = [pscustomobject][ordered]@{name=$name;path=$path;sha256=([string]$package.sha256).ToUpperInvariant();bytes=[int64]$package.bytes}
    if (-not $payloadsByName.TryAdd($name, $payload)) { throw '[mir42-delivery-bundle-package-name]' }
    $orderedNames.Add($name)
  }
  $orderedNames.Sort([StringComparer]::Ordinal)
  if (Test-Path -LiteralPath $output) {
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw '[mir42-delivery-bundle-output-conflict]' }
    Assert-MIR42NineTargetLocalDeliveryBundle -Path $output -Packages $Packages
    $item = Get-Item -LiteralPath $output -Force
    return [pscustomobject][ordered]@{name=$BundleName;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64]$item.Length;created=$false}
  }
  Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
  $temporary = Join-Path $root ('.mir42-delivery-bundle-' + [guid]::NewGuid().ToString('N') + '.zip')
  try {
    $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
      $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
      try {
        foreach ($name in $orderedNames) {
          $payload = $payloadsByName[$name]
          $entry = $archive.CreateEntry([string]$payload.name, [IO.Compression.CompressionLevel]::Optimal)
          $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
          $entry.ExternalAttributes = 0
          $input = $null
          $entryStream = $null
          try {
            $input = [IO.File]::OpenRead([string]$payload.path)
            $entryStream = $entry.Open()
            $input.CopyTo($entryStream)
          } finally {
            if ($null -ne $entryStream) { $entryStream.Dispose() }
            if ($null -ne $input) { $input.Dispose() }
          }
        }
      } finally { $archive.Dispose() }
    } finally { $stream.Dispose() }
    Assert-MIR42NineTargetLocalDeliveryBundle -Path $temporary -Packages $Packages
    [IO.File]::Move($temporary, $output)
    Assert-MIR42NineTargetLocalDeliveryBundle -Path $output -Packages $Packages
    $item = Get-Item -LiteralPath $output -Force
    return [pscustomobject][ordered]@{name=$BundleName;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToUpperInvariant();bytes=[int64]$item.Length;created=$true}
  } finally {
    if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
  }
}

function Get-MIR42NineTargetLocalDeliveryPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$FrozenInventoryPath,
    [Parameter(Mandatory)][string]$ReleaseId
  )
  if ($ReleaseId -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,63}$') { throw '[mir4-delivery-release-id]' }
  if (-not (Get-Command Read-MIR42NineTargetReleaseAssetInventory -ErrorAction SilentlyContinue)) {
    . (Join-Path $RepoRoot 'tools/mir/application/release/readiness/MIR42ReleaseAssets.ps1')
  }
  $inventory = Read-MIR42NineTargetReleaseAssetInventory -Path $FrozenInventoryPath
  $record = $inventory.record
  $priorIntentEntries = Get-MIR42NineTargetLocalDeliveryPriorIntentEntries -RepoRoot $RepoRoot -ReleaseId $ReleaseId
  $sourceVersion = [string]$record.release.source_version
  $releaseTag = [string]$record.release.tag
  if ($releaseTag -cne ('v' + $sourceVersion) -or @($record.package_assets).Count -ne 9) {
    throw '[mir42-delivery-inventory-release]'
  }
  $packages = @($record.package_assets)
  $byTarget = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
  foreach ($package in $packages) {
    if (-not $byTarget.TryAdd([string]$package.target, $package)) { throw '[mir42-delivery-inventory-package]' }
    $null = Assert-MIR42NineTargetLocalDeliveryFile -SourceRoot $SourceRoot -SourcePath ([string]$package.path) -Sha256 ([string]$package.sha256) -Bytes ([int64]$package.bytes)
  }
  foreach ($target in @('f210','f200','f110','f100','f017','f016','f015','f014','f013')) {
    if (-not $byTarget.ContainsKey($target)) { throw "[mir42-delivery-inventory-package] $target" }
  }

  $files = [Collections.Generic.List[object]]::new()
  $destinations = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  function Add-MIR42NineTargetLocalDeliveryPlanFile {
    param(
      [string]$SourcePath,
      [string]$DestinationPath,
      [string]$Sha256,
      [int64]$Bytes,
      [string]$ReplaceExistingSha256 = '',
      [string]$PreserveExistingDestinationPath = ''
    )
    $null = Assert-MIR42NineTargetLocalDeliveryFile -SourceRoot $SourceRoot -SourcePath $SourcePath -Sha256 $Sha256 -Bytes $Bytes
    if (-not $destinations.Add($DestinationPath)) { throw "[mir42-delivery-plan-duplicate] $DestinationPath" }
    $entry = [ordered]@{source_path=$SourcePath;destination_path=$DestinationPath;sha256=$Sha256.ToUpperInvariant()}
    if ($ReplaceExistingSha256.Length -gt 0) {
      $entry.replace_existing_sha256 = $ReplaceExistingSha256.ToUpperInvariant()
      $entry.preserve_existing_destination_path = $PreserveExistingDestinationPath
      $entry.replacement_owner = 'mir42-nine-target-generated-pointer'
    }
    $files.Add([pscustomobject]$entry)
  }

  foreach ($package in $packages) {
    Add-MIR42NineTargetLocalDeliveryPlanFile -SourcePath ([string]$package.path) -DestinationPath ([string]$package.public_name) -Sha256 ([string]$package.sha256) -Bytes ([int64]$package.bytes)
    Add-MIR42NineTargetLocalDeliveryPlanFile -SourcePath ([string]$package.path) -DestinationPath ($sourceVersion + '/' + [string]$package.public_name) -Sha256 ([string]$package.sha256) -Bytes ([int64]$package.bytes)
  }

  $support = @(
    $record.checksum,
    $record.signature,
    $record.qualification,
    $record.provenance,
    $record.components,
    $record.release_manifest,
    $record.release_notes
  )
  foreach ($asset in $support) {
    Add-MIR42NineTargetLocalDeliveryPlanFile -SourcePath ([string]$asset.path) -DestinationPath ($sourceVersion + '/' + [string]$asset.path) -Sha256 ([string]$asset.sha256) -Bytes ([int64]$asset.bytes)
  }
  $collector = @($record.github_assets | Where-Object { [string]$_.role -ceq 'support-collector' })
  if ($collector.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$collector[0].name)) { throw '[mir42-delivery-inventory-collector]' }
  Add-MIR42NineTargetLocalDeliveryPlanFile -SourcePath ([string]$collector[0].name) -DestinationPath ($sourceVersion + '/' + [string]$collector[0].name) -Sha256 ([string]$collector[0].sha256) -Bytes ([int64]$collector[0].bytes)
  foreach ($upload in @($record.mod_portal_upload_texts)) {
    Add-MIR42NineTargetLocalDeliveryPlanFile -SourcePath ([string]$upload.path) -DestinationPath ($sourceVersion + '/' + [string]$upload.path) -Sha256 ([string]$upload.sha256) -Bytes ([int64]$upload.bytes)
  }

  $bundleName = 'MIR_' + $sourceVersion.Replace('.', '_') + '_DISTRIBUTIONS.zip'
  # Build only after the authoritative inventory reader has bound every package.
  # The returned identity is then frozen into the plan, intent and receipt.
  $bundle = New-MIR42NineTargetLocalDeliveryBundle -SourceRoot $SourceRoot -BundleName $bundleName -Packages $packages
  Add-MIR42NineTargetLocalDeliveryPlanFile -SourcePath $bundleName -DestinationPath ($sourceVersion + '/' + $bundleName) -Sha256 ([string]$bundle.sha256) -Bytes ([int64]$bundle.bytes)

  $dist = Join-Path ((Resolve-Path -LiteralPath $RepoRoot).Path) 'dist'
  foreach ($pointerName in @('LATEST-MIR42-PUBLISHED.txt','LATEST-MIR42-FINAL-CANDIDATE.txt',('UPLOAD-' + $sourceVersion + '.txt'))) {
    $pointerPath = Join-Path $SourceRoot $pointerName
    Assert-MIR42NineTargetLocalDeliveryPointer -Path $pointerPath -SourceVersion $sourceVersion -ReleaseTag $releaseTag -F210Package $byTarget['f210'] -F200Package $byTarget['f200']
    $pointerHash = (Get-FileHash -LiteralPath $pointerPath -Algorithm SHA256).Hash
    $existingPointerPath = Join-Path $dist $pointerName
    if (Test-Path -LiteralPath $existingPointerPath) {
      $previousSelection = Get-MIR42NineTargetLocalDeliveryPointerSelection -Path $existingPointerPath
      $previousVersion = Assert-MIR42NineTargetLocalDeliveryPointerSelection -Selection $previousSelection -Path $existingPointerPath
      if ($previousVersion -cne $sourceVersion) {
        Add-MIR42NineTargetLocalDeliveryPlanFile -SourcePath $pointerName -DestinationPath $pointerName -Sha256 $pointerHash -Bytes ((Get-Item -LiteralPath $pointerPath -Force).Length) -ReplaceExistingSha256 ((Get-FileHash -LiteralPath $existingPointerPath -Algorithm SHA256).Hash) -PreserveExistingDestinationPath ($sourceVersion + '/previous-' + $pointerName)
        continue
      }
      $replayReplacement = Get-MIR42NineTargetLocalDeliveryReplayPointerReplacement -PriorIntentEntries $priorIntentEntries -PointerName $pointerName -PointerSha256 $pointerHash -SourceVersion $sourceVersion
      if ($null -ne $replayReplacement) {
        Add-MIR42NineTargetLocalDeliveryPlanFile -SourcePath $pointerName -DestinationPath $pointerName -Sha256 $pointerHash -Bytes ((Get-Item -LiteralPath $pointerPath -Force).Length) -ReplaceExistingSha256 ([string]$replayReplacement.replace_existing_sha256) -PreserveExistingDestinationPath ([string]$replayReplacement.preserve_existing_destination_path)
        continue
      }
    }
    Add-MIR42NineTargetLocalDeliveryPlanFile -SourcePath $pointerName -DestinationPath $pointerName -Sha256 $pointerHash -Bytes ((Get-Item -LiteralPath $pointerPath -Force).Length)
  }
  return [pscustomobject][ordered]@{
    inventory = [ordered]@{path=(Resolve-Path -LiteralPath $FrozenInventoryPath).Path;sha256=[string]$inventory.sha256;record_sha256=[string]$record.record_sha256}
    source_version = $sourceVersion
    release_tag = $releaseTag
    bundle_name = $bundleName
    bundle = [pscustomobject][ordered]@{name=[string]$bundle.name;sha256=[string]$bundle.sha256;bytes=[int64]$bundle.bytes}
    packages = @($packages | ForEach-Object { [pscustomobject][ordered]@{public_name=[string]$_.public_name;sha256=[string]$_.sha256;bytes=[int64]$_.bytes} })
    files = @($files)
  }
}

function Assert-MIR42NineTargetLocalDeliveryProjection {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Plan
  )
  $dist = Join-Path ((Resolve-Path -LiteralPath $RepoRoot).Path) 'dist'
  foreach ($file in @($Plan.files)) {
    $path = Join-Path $dist ([string]$file.destination_path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne [string]$file.sha256) {
      throw "[mir42-delivery-projection-identity] $([string]$file.destination_path)"
    }
  }
  Assert-MIR42NineTargetLocalDeliveryBundle -Path (Join-Path $dist ($Plan.source_version + '/' + $Plan.bundle_name)) -Packages @($Plan.packages)
}

function Invoke-MIR42NineTargetLocalDelivery {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$FrozenInventoryPath,
    [Parameter(Mandatory)][string]$ReleaseId,
    [scriptblock]$AfterCopy
  )
  $plan = Get-MIR42NineTargetLocalDeliveryPlan -RepoRoot $RepoRoot -SourceRoot $SourceRoot -FrozenInventoryPath $FrozenInventoryPath -ReleaseId $ReleaseId
  $receiptMetadata = [ordered]@{
    frozen_inventory = $plan.inventory
    source_version = $plan.source_version
    release_tag = $plan.release_tag
    direct_root_package_count = 9
    versioned_bundle = ($plan.source_version + '/' + $plan.bundle_name)
    versioned_bundle_sha256 = [string]$plan.bundle.sha256
    versioned_bundle_bytes = [int64]$plan.bundle.bytes
    mod_portal_upload_performed = $false
  }
  $delivery = Invoke-MIR4LocalDelivery -RepoRoot $RepoRoot -SourceRoot $SourceRoot -Files @($plan.files) -ReleaseId $ReleaseId -AfterCopy $AfterCopy -ReceiptMetadata $receiptMetadata
  Assert-MIR42NineTargetLocalDeliveryProjection -RepoRoot $RepoRoot -Plan $plan
  return $delivery
}
