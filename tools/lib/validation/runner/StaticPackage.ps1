Invoke-RepoCheck "generated package archive matches metadata" {
  Add-Type -AssemblyName System.IO.Compression.FileSystem

  function Read-ZipEntryText {
    param($Entry)
    $stream = $Entry.Open()
    try {
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
      try {
        return $reader.ReadToEnd()
      } finally {
        $reader.Dispose()
      }
    } finally {
      $stream.Dispose()
    }
  }

  function Get-StreamSha256 {
    param([System.IO.Stream]$Stream)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      return -join ($sha.ComputeHash($Stream) | ForEach-Object { $_.ToString("x2") })
    } finally {
      $sha.Dispose()
    }
  }

  function Get-FileSha256 {
    param([string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    try {
      return Get-StreamSha256 -Stream $stream
    } finally {
      $stream.Dispose()
    }
  }

  function Get-ZipEntrySha256 {
    param($Entry)
    $stream = $Entry.Open()
    try {
      return Get-StreamSha256 -Stream $stream
    } finally {
      $stream.Dispose()
    }
  }

  function Normalize-TextForPackageComparison {
    param([string]$Text)
    return ($Text -replace "`r`n", "`n").TrimEnd()
  }

  function Test-PackageTextPath {
    param([string]$RelativePath)
    $extension = [System.IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
    if ($extension -in @(".cfg", ".json", ".lua", ".md", ".txt")) {
      return $true
    }

    $fileName = [System.IO.Path]::GetFileName($RelativePath)
    return $fileName -in @("LICENSE")
  }

  if ([string]::IsNullOrWhiteSpace($CandidateZip)) {
    $validationOutputDir = "build/packages/validation-dist"
    $packageResult = & (Join-Path $repo "tools\commands\package\Build-MIRPackage.ps1") -Target f210 -CandidateId MIR4-VALIDATION -OutputDir $validationOutputDir
    $zipPath = [string]$packageResult.archive_path
    $packageName = "more-infinite-research_$([string]$packageResult.distribution_version)"
  } else {
    $candidatePath = if ([System.IO.Path]::IsPathRooted($CandidateZip)) { $CandidateZip } else { Join-Path $repo $CandidateZip }
    if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
      throw "Candidate package not found: $CandidateZip"
    }
    $zipPath = (Resolve-Path -LiteralPath $candidatePath).Path
    Write-Host "[check] validating exact candidate package $zipPath"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $candidateArchive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
      $roots = @($candidateArchive.Entries | ForEach-Object { ([string]$_.FullName -split '/')[0] } | Where-Object { $_ } | Sort-Object -Unique)
      if ($roots.Count -ne 1) { throw "Candidate package does not contain one package root: $zipPath" }
      $packageName = [string]$roots[0]
    } finally { $candidateArchive.Dispose() }
  }
  if (-not (Test-Path -LiteralPath $zipPath)) {
    throw "Validation package not found: $zipPath"
  }
  $script:ValidationPackageZipPath = (Resolve-Path -LiteralPath $zipPath).Path

  $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
  try {
    $entries = @($zip.Entries)
    $entryNames = @($entries | ForEach-Object { $_.FullName })
    $root = "$packageName/"

    $outsideRoot = @($entryNames | Where-Object { -not $_.StartsWith($root) })
    if ($outsideRoot.Count -gt 0) {
      throw "Package entries outside expected root ${root}: $($outsideRoot -join ', ')"
    }

    $requiredEntries = @(
      "${root}info.json",
      "${root}changelog.txt",
      "${root}README.md",
      "${root}LICENSE",
      "${root}thumbnail.png",
      "${root}data.lua",
      "${root}control.lua",
      "${root}data-updates.lua",
      "${root}data-final-fixes.lua",
      "${root}settings.lua",
      "${root}locale/en/more-infinite-research.cfg",
      "${root}migrations/more-infinite-research_2.0.5.json"
    )
    $missingEntries = @($requiredEntries | Where-Object { $_ -notin $entryNames })
    if ($missingEntries.Count -gt 0) {
      throw "Package is missing expected entries: $($missingEntries -join ', ')"
    }

    $forbiddenPatterns = @(
      "^$([regex]::Escape($root))(\.git|\.github|\.mir|\.codex|artifacts|build|dist|docs|fixtures|scripts|tests|tools)(/|$)",
      "^$([regex]::Escape($root))(AGENTS\.md|CONTRIBUTING\.md|todo\.md)$",
      "(^|/)(\.DS_Store|Thumbs\.db)$",
      "(^|/)__MACOSX(/|$)",
      "~$",
      "\.(tmp|bak|swp)$"
    )
    $forbiddenEntries = @(
      foreach ($entryName in $entryNames) {
        foreach ($pattern in $forbiddenPatterns) {
          if ($entryName -match $pattern) {
            $entryName
            break
          }
        }
      }
    )
    if ($forbiddenEntries.Count -gt 0) {
      throw "Package contains forbidden entries: $($forbiddenEntries -join ', ')"
    }

    $innerInfoEntry = $entries | Where-Object { $_.FullName -eq "${root}info.json" } | Select-Object -First 1
    $innerInfo = Read-ZipEntryText $innerInfoEntry | ConvertFrom-Json
    if ($innerInfo.name -ne $info.name -or $innerInfo.version -ne $info.version -or $innerInfo.factorio_version -ne $info.factorio_version) {
      throw "Package info.json metadata does not match repository info.json."
    }
    $repoDeps = @($info.dependencies)
    $packageDeps = @($innerInfo.dependencies)
    $depDiff = @(Compare-Object -ReferenceObject $repoDeps -DifferenceObject $packageDeps)
    if ($depDiff.Count -gt 0) {
      throw "Package info.json dependencies do not match repository info.json."
    }

    $repoPath = $repo.Path
    $mustMatchRepo = @(
      "README.md",
      "changelog.txt",
      "control.lua",
      "data.lua",
      "data-updates.lua",
      "data-final-fixes.lua",
      "settings.lua",
      "thumbnail.png"
    )

    foreach ($directory in @("locale", "migrations", "prototypes")) {
      $directoryPath = Join-Path $repo $directory
      if (Test-Path -LiteralPath $directoryPath) {
        $mustMatchRepo += @(
          Get-ChildItem -LiteralPath $directoryPath -Recurse -File |
          ForEach-Object { [System.IO.Path]::GetRelativePath($repoPath, $_.FullName).Replace("\", "/") }
        )
      }
    }

    $mustMatchRepo = @($mustMatchRepo | Sort-Object -Unique)

    foreach ($relative in $mustMatchRepo) {
      $entryName = "${root}$relative"
      $entry = $entries | Where-Object { $_.FullName -eq $entryName } | Select-Object -First 1
      if (-not $entry) {
        throw "Package is missing expected source file: $entryName"
      }

      if (Test-PackageTextPath -RelativePath $relative) {
        $repoText = Get-Content -Raw -LiteralPath (Join-Path $repo $relative)
        $zipText = Read-ZipEntryText $entry
        if ((Normalize-TextForPackageComparison $repoText) -ne (Normalize-TextForPackageComparison $zipText)) {
          throw "Package source file differs from repository source: $relative"
        }
      } else {
        $repoHash = Get-FileSha256 -Path (Join-Path $repo $relative)
        $zipHash = Get-ZipEntrySha256 -Entry $entry
        if ($repoHash -ne $zipHash) {
          throw "Package source file differs from repository source: $relative"
        }
      }
    }
  } finally {
    $zip.Dispose()
  }
}

Invoke-RepoCheck "package construction is byte deterministic" {
  if ([string]::IsNullOrWhiteSpace($CandidateZip)) {
    & (Join-Path $repo "tests\package\Test-MIRDeterministicPackage.ps1") -RepoRoot $repo | Out-Host
  } else {
    Write-Host "[skip] exact candidate lane reuses separate deterministic-package evidence"
  }
}

Invoke-RepoCheck "git whitespace check" {
  git -C $repo diff --check
  if ($LASTEXITCODE -ne 0) {
    throw "git diff --check failed."
  }
}
