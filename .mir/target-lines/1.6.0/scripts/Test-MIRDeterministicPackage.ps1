param([string]$CandidateZip)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$info = Get-Content -Raw -LiteralPath (Join-Path $repo "info.json") | ConvertFrom-Json
$archiveName = "$($info.name)_$($info.version).zip"
$roots = @("build\deterministic-package-a", "build\deterministic-package-b")

foreach ($root in $roots) {
  $path = Join-Path $repo $root
  if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
  & (Join-Path $PSScriptRoot "Build-MIRPackage.ps1") -OutputDir $root -CompressionLevel Optimal | Out-Host
}

$left = Join-Path (Join-Path $repo $roots[0]) $archiveName
$right = Join-Path (Join-Path $repo $roots[1]) $archiveName
$leftHash = (Get-FileHash -LiteralPath $left -Algorithm SHA256).Hash
$rightHash = (Get-FileHash -LiteralPath $right -Algorithm SHA256).Hash
if ($leftHash -ne $rightHash) { throw "Package rebuilds differ: $leftHash != $rightHash" }
if (-not [string]::IsNullOrWhiteSpace($CandidateZip)) {
  $candidateHash = (Get-FileHash -LiteralPath $CandidateZip -Algorithm SHA256).Hash
  if ($candidateHash -ne $leftHash) { throw "Candidate differs from deterministic rebuild: $candidateHash != $leftHash" }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($left)
try {
  $entries = @($zip.Entries)
  $names = @($entries | ForEach-Object FullName)
  if (($names -join "`n") -ne (@($names | Sort-Object) -join "`n")) { throw "Archive paths are not canonically ordered." }
  if (@($entries | Where-Object { $_.LastWriteTime.DateTime -ne [DateTime]::new(1980,1,1,0,0,0) }).Count) {
    throw "Archive contains non-canonical timestamps."
  }
  $forbidden = '(?i)(^|/)(docs|fixtures|scripts|tests|\.mir|\.codex|\.github|build|dist)(/|$)|(^|/)(AGENTS\.md|CONTRIBUTING\.md|todo\.md)$'
  $bad = @($names | Where-Object { $_ -match $forbidden })
  if ($bad.Count) { throw "Archive includes forbidden files: $($bad -join ', ')" }
} finally { $zip.Dispose() }

Write-Host "[ok] deterministic package SHA-256 $leftHash"
