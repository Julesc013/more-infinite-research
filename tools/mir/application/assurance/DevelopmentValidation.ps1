function Invoke-MIR4DevelopmentStaticChecks {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)
  $repo=(Resolve-Path -LiteralPath $RepoRoot).Path
  $epoch=Get-Content -Raw (Join-Path $repo 'governance/repository/development-epoch-v1.json') | ConvertFrom-Json
  if($epoch.schema -ne 1 -or $epoch.current_profile -cne 'mir4-development' -or $epoch.release_authority) { throw '[mir4-development-profile-authority]' }
  $catalog=Get-Content -Raw (Join-Path $repo 'validation/tests.yml') | ConvertFrom-Json
  $assurance=Get-Content -Raw (Join-Path $repo '.mir/assurance.json') | ConvertFrom-Json
  $sourceCommit=(@(& git -C $repo rev-parse HEAD) -join '').Trim()
  $sourceTree=(@(& git -C $repo rev-parse 'HEAD^{tree}') -join '').Trim()
  if($LASTEXITCODE -ne 0 -or $sourceCommit -cnotmatch '^[0-9a-f]{40}$' -or $sourceTree -cnotmatch '^[0-9a-f]{40}$') {
    throw '[mir4-development-static-source-identity]'
  }
  . (Join-Path $repo 'tools/mir/application/package/PackageAuthority.ps1')
  $packageSourceSha256=Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $repo
  if($packageSourceSha256 -cnotmatch '^[A-F0-9]{64}$') { throw '[mir4-development-static-package-source-identity]' }
  foreach($id in $assurance.profiles.($epoch.current_profile)) {
    $row=@($catalog.tests | Where-Object id -CEQ $id)
    if($row.Count -ne 1 -or $row[0].requires_factorio) { throw "[mir4-development-static-selection] $id" }
    $parts=([string]$row[0].command).Split(' ',[StringSplitOptions]::RemoveEmptyEntries)
    if($parts[0] -notmatch '^\./(?:tests|scripts)/[A-Za-z0-9/.-]+[.]ps1$') { throw "[mir4-development-static-command] $id" }
    $testOutput=''
    if('<test-output>' -in $parts) {
      $identityBytes=[Text.Encoding]::UTF8.GetBytes("$id`n$sourceCommit`n$sourceTree`n$packageSourceSha256")
      $identity=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($identityBytes))
      $workId=[guid]::NewGuid().ToString('N')
      $testOutput=Join-Path $repo "build/results/assurance/evidence/$id/$identity/work/$workId/test-output.json"
    }
    $replacements=@{
      '<source-commit>'=$sourceCommit
      '<source-tree>'=$sourceTree
      '<package-source-sha256>'=$packageSourceSha256
      '<test-output>'=$testOutput
    }
    for($index=1;$index-lt$parts.Count;$index++) {
      if($replacements.ContainsKey([string]$parts[$index])) {
        $replacement=[string]$replacements[[string]$parts[$index]]
        if([string]::IsNullOrWhiteSpace($replacement)) { throw "[mir4-development-static-placeholder] $id/$($parts[$index])" }
        $parts[$index]=$replacement
      } elseif([string]$parts[$index] -match '<[^>]+>') {
        throw "[mir4-development-static-unresolved-placeholder] $id/$($parts[$index])"
      }
    }
    $parts[0]=Join-Path $repo $parts[0]
    Write-Host "[current-development] $id"
    & pwsh -NoProfile -File @parts
    if($LASTEXITCODE -ne 0) { throw "[mir4-development-static-failed] $id" }
  }
  & git -C $repo diff --check
  if($LASTEXITCODE -ne 0) { throw '[mir4-development-whitespace]' }
}
