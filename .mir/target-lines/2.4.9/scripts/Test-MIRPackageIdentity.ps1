param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

$ErrorActionPreference = "Stop"
. (Join-Path $RepoRoot "scripts\validation\PackageIdentity.ps1")

function Write-MIRTestText {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Text
  )

  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function New-MIRIdentityTestZip {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Text
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $file = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create)
  try {
    $archive = [System.IO.Compression.ZipArchive]::new(
      $file,
      [System.IO.Compression.ZipArchiveMode]::Create,
      $false
    )
    try {
      $textEntry = $archive.CreateEntry("mir-test/README.md")
      $textStream = $textEntry.Open()
      try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
        $textStream.Write($bytes, 0, $bytes.Length)
      } finally {
        $textStream.Dispose()
      }

      $binaryEntry = $archive.CreateEntry("mir-test/thumbnail.png")
      $binaryStream = $binaryEntry.Open()
      try {
        $binaryStream.Write([byte[]](0, 1, 2, 3), 0, 4)
      } finally {
        $binaryStream.Dispose()
      }
    } finally {
      $archive.Dispose()
    }
  } finally {
    $file.Dispose()
  }
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mir-package-identity-" + [Guid]::NewGuid().ToString("N"))
try {
  $lfRoot = Join-Path $testRoot "lf"
  $crlfRoot = Join-Path $testRoot "crlf"
  foreach ($relative in @("README.md", "settings.lua")) {
    Write-MIRTestText -Path (Join-Path $lfRoot $relative) -Text "one`ntwo`n"
    Write-MIRTestText -Path (Join-Path $crlfRoot $relative) -Text "one`r`ntwo`r`n"
  }

  $harnessFiles = @(
    "scripts/check.ps1",
    "fixtures/case.json",
    ".mir/config.yml",
    ".github/workflows/validate.yml"
  )
  foreach ($relative in $harnessFiles) {
    Write-MIRTestText -Path (Join-Path $lfRoot $relative) -Text "one`ntwo`n"
    Write-MIRTestText -Path (Join-Path $crlfRoot $relative) -Text "one`r`ntwo`r`n"
  }

  $lfPackage = Get-MIRPackageSourceFingerprint -RepoRoot $lfRoot
  $crlfPackage = Get-MIRPackageSourceFingerprint -RepoRoot $crlfRoot
  if ($lfPackage -ne $crlfPackage) {
    throw "Package-source fingerprint differs between LF and CRLF checkouts."
  }

  $lfHarness = Get-MIRValidationHarnessFingerprint -RepoRoot $lfRoot
  $crlfHarness = Get-MIRValidationHarnessFingerprint -RepoRoot $crlfRoot
  if ($lfHarness -ne $crlfHarness) {
    throw "Validation-harness fingerprint differs between LF and CRLF checkouts."
  }

  $lfExpected = Get-MIRFileContentSha256 `
    -Path (Join-Path $lfRoot "fixtures/case.json") `
    -RelativePath "fixtures/compat-matrix/expected-scenarios.json"
  $crlfExpected = Get-MIRFileContentSha256 `
    -Path (Join-Path $crlfRoot "fixtures/case.json") `
    -RelativePath "fixtures/compat-matrix/expected-scenarios.json"
  if ($lfExpected -ne $crlfExpected) {
    throw "Expected-scenario fingerprint differs between LF and CRLF checkouts."
  }

  $lfZip = Join-Path $testRoot "lf.zip"
  $crlfZip = Join-Path $testRoot "crlf.zip"
  New-MIRIdentityTestZip -Path $lfZip -Text "one`ntwo`n"
  New-MIRIdentityTestZip -Path $crlfZip -Text "one`r`ntwo`r`n"
  if ((Get-MIRZipContentFingerprint -Path $lfZip) -ne (Get-MIRZipContentFingerprint -Path $crlfZip)) {
    throw "ZIP content fingerprint differs between LF and CRLF text entries."
  }
  if ((Get-MIRFileSha256 -Path $lfZip) -eq (Get-MIRFileSha256 -Path $crlfZip)) {
    throw "Test ZIPs unexpectedly have identical byte hashes."
  }

  Write-MIRTestText -Path (Join-Path $crlfRoot "README.md") -Text "one`r`nchanged`r`n"
  if ($lfPackage -eq (Get-MIRPackageSourceFingerprint -RepoRoot $crlfRoot)) {
    throw "Package-source fingerprint ignored a semantic text change."
  }
} finally {
  if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}

Write-Host "[ok] MIR package identity line-ending invariance tests passed."
