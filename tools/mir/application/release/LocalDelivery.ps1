Set-StrictMode -Version Latest

function Invoke-MIR4LocalDelivery {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][object[]]$Files,
    [Parameter(Mandatory)][string]$ReleaseId,
    [scriptblock]$AfterCopy
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
      $expected=[string]$file.sha256
      if($expected -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash -ine $expected) { throw "[mir4-delivery-source-identity] $($file.source_path)" }
      if(Test-Path -LiteralPath $to) {
        if(-not(Test-Path -LiteralPath $to -PathType Leaf) -or (Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash -ine $expected) { throw "[mir4-delivery-destination-conflict] $($file.destination_path)" }
      }
      [pscustomobject][ordered]@{source_path=[string]$file.source_path;destination_path=[string]$file.destination_path;sha256=$expected.ToUpperInvariant();bytes=(Get-Item -LiteralPath $from).Length}
    })
    if($plan.Count -eq 0) { throw '[mir4-delivery-empty]' }
    $intent=[ordered]@{schema=1;release_id=$ReleaseId;files=$plan;build_authorized=$false;publication_authorized=$false}
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
    }
    $receipt=[ordered]@{schema=1;kind='MIR4LocalDeliveryV1';status='delivered-and-verified';release_id=$ReleaseId;files=$plan;source_and_remote_sync='separate-required-postcondition';build_performed=$false;publication_performed=$false}
    $receiptPath=Join-Path $records 'receipt.json'
    [IO.File]::WriteAllText($receiptPath+'.tmp',(($receipt|ConvertTo-Json -Depth 8)+"`n"),[Text.UTF8Encoding]::new($false))
    [IO.File]::Move($receiptPath+'.tmp',$receiptPath,$true)
    return [pscustomobject]$receipt
  } finally { $lock.Dispose() }
}
