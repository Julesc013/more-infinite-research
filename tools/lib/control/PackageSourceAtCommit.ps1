function Get-MIRCPCommitPackageSourceHashV2 {
  param(
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)][string]$RepoRoot
  )

  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  . (Join-Path $repo 'tools/lib/validation/PackageIdentity.ps1')
  $temporaryBase=[IO.Path]::GetFullPath((Join-Path $repo 'build/tmp')).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
  $temporaryRoot=[IO.Path]::GetFullPath((Join-Path $temporaryBase ('mir-cp-package-'+[guid]::NewGuid().ToString('N'))))
  if(-not$temporaryRoot.StartsWith($temporaryBase+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw '[mir-cp-package-source-temporary-containment]'
  }
  $archive=Join-Path $temporaryRoot 'source.zip'
  try {
    [void](New-Item -ItemType Directory -Path $temporaryRoot)
    $layout=Get-MIRPackageSourceLayoutAtCommit -RepoRoot $repo -Commit $Commit
    $roots=@($layout.roots)
    & git -C $repo archive --format=zip --output=$archive $Commit -- @roots 2>$null
    if($LASTEXITCODE-ne0-or-not(Test-Path -LiteralPath $archive -PathType Leaf)){throw "Unable to archive package roots at commit $Commit."}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    try {
      $rows=[Collections.Generic.List[string]]::new()
      foreach($entry in @($zip.Entries|Where-Object{-not[string]::IsNullOrEmpty($_.Name)}|Sort-Object FullName)){
        $relative=([string]$entry.FullName).Replace('\','/')
        $identity=Get-MIRZipEntryContentIdentity -Entry $entry -RelativePath $relative
        $rows.Add(("{0}`t{1}`t{2}"-f$relative,$identity.Length,$identity.Sha256))
      }
      if($rows.Count-lt1){throw "Commit $Commit has no recognized package-source files."}
      return Get-MIRStringSha256 -Value ($rows-join"`n")
    }finally{$zip.Dispose()}
  }finally{
    if(Test-Path -LiteralPath $temporaryRoot){
      $cleanupRoot=(Resolve-Path -LiteralPath $temporaryRoot).ProviderPath
      if(-not$cleanupRoot.StartsWith($temporaryBase+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or
         (Get-Item -LiteralPath $cleanupRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint-or
         (Split-Path -Leaf $cleanupRoot)-notlike'mir-cp-package-*'){throw '[mir-cp-package-source-cleanup-containment]'}
    }
    if(Test-Path -LiteralPath $archive -PathType Leaf){Remove-Item -LiteralPath $archive -Force}
    if(Test-Path -LiteralPath $temporaryRoot -PathType Container){Remove-Item -LiteralPath $temporaryRoot -Force}
  }
}
