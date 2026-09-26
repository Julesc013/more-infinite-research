Set-StrictMode -Version Latest

$mir42SealRepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../../..')).Path
if (-not (Get-Command Test-MIR4BootstrapRecordHash -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Assert-MIR4NoReparseAncestors -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/lib/mir4/BootstrapMaterialization.ps1')
}
if (-not (Get-Command Get-MIR4CanonicalPackageSourceFingerprint -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/mir/application/package/PackageAuthority.ps1')
}
if (-not (Get-Command Test-MIR4OpenSshSignatureV1 -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/mir/application/custody/OfflineCandidateCustody.ps1')
}
if (-not (Get-Command Assert-MIR42FourTargetPackageExcludedSurface -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1')
}
if (-not (Get-Command Test-MIR4FixedFactorioEngineIdentity -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/lib/validation/FactorioVersionPolicy.ps1')
}
if (-not (Get-Command Get-MIR4F210CurrentEngineCapHarnessAdmissionV3 -ErrorAction SilentlyContinue)) {
  . (Join-Path $mir42SealRepoRoot 'tools/mir/application/release/F210QualificationPolicy.ps1')
}

$script:MIR42SealTargets = @('f210', 'f200', 'f110', 'f100')
$script:MIR42SealNineTargetCandidates = @('f210', 'f200', 'f110', 'f100', 'f017', 'f016', 'f015', 'f014', 'f013')
$script:MIR42SealVerifierDependencyPaths = @(
  'tools/mir/application/release/readiness/MIR42TechnicalSeal.ps1',
  'tools/mir/application/release/readiness/MIR42ProtectedMainPromotion.ps1',
  'tools/commands/release/Invoke-MIR42FourTargetSealPromotion.ps1',
  'tools/lib/mir4/BootstrapMaterialization.ps1',
  'tools/mir/application/package/PackageAuthority.ps1',
  'tools/mir/application/custody/OfflineCandidateCustody.ps1',
  'tools/mir/application/release/readiness/MIR42FourTargetPreflight.ps1',
  'tools/lib/validation/FactorioVersionPolicy.ps1',
  'tools/mir/application/release/F210QualificationPolicy.ps1'
)

function Read-MIR42SealRecord {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "[$Code-missing] $Path" }
  try { $record = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100 -DateKind String }
  catch { throw "[$Code-json] $Path" }
  if ($null -eq $record) { throw "[$Code-empty] $Path" }
  if ($record.PSObject.Properties.Name -notcontains 'record_sha256' -or
      [string]$record.record_sha256 -notmatch '^[A-F0-9]{64}$' -or
      -not (Test-MIR4BootstrapRecordHash -Record $record)) { throw "[$Code-record-hash] $Path" }
  return [pscustomobject][ordered]@{
    path = (Resolve-Path -LiteralPath $Path).Path
    sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    record = $record
  }
}

function Assert-MIR42SealSource {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Source,[Parameter(Mandatory)][string]$Code)
  foreach ($field in @('commit','tree','package_source_sha256')) {
    if ($Source.PSObject.Properties.Name -notcontains $field -or [string]::IsNullOrWhiteSpace([string]$Source.$field)) {
      throw "[$Code-source-field] $field"
    }
  }
  $dirty = @(& git -C $RepoRoot status --porcelain=v1 --untracked-files=all)
  if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw "[$Code-source-dirty]" }
  $commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
  $tree = (& git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
  if ($LASTEXITCODE -ne 0 -or $commit -cne [string]$Source.commit -or $tree -cne [string]$Source.tree) {
    throw "[$Code-source-tree-drift]"
  }
  $packageSource = Get-MIR4CanonicalPackageSourceFingerprint -RepoRoot $RepoRoot
  if ($packageSource -cne [string]$Source.package_source_sha256) { throw "[$Code-package-source-drift]" }
  return [pscustomobject][ordered]@{commit=$commit;tree=$tree;package_source_sha256=$packageSource}
}

function Assert-MIR42SealExternalPathSeparatedFromRepository {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  $full = [IO.Path]::GetFullPath($Path)
  $repo = [IO.Path]::GetFullPath($RepoRoot)
  $fullBoundary = if ($full.EndsWith([string][IO.Path]::DirectorySeparatorChar) -or $full.EndsWith([string][IO.Path]::AltDirectorySeparatorChar)) { $full } else { $full + [IO.Path]::DirectorySeparatorChar }
  $repoBoundary = if ($repo.EndsWith([string][IO.Path]::DirectorySeparatorChar) -or $repo.EndsWith([string][IO.Path]::AltDirectorySeparatorChar)) { $repo } else { $repo + [IO.Path]::DirectorySeparatorChar }
  if ($full -ceq $repo -or $full.StartsWith($repoBoundary,[StringComparison]::OrdinalIgnoreCase) -or $repo.StartsWith($fullBoundary,[StringComparison]::OrdinalIgnoreCase)) {
    throw "[$Code-repository]"
  }
}

function Assert-MIR42SealTargetSet {
  param([Parameter(Mandatory)]$Rows,[Parameter(Mandatory)][string]$Code)
  $actual = @($Rows | ForEach-Object { [string]$_.target })
  if ($actual.Count -ne 4 -or ($actual -join '|') -cne ($script:MIR42SealTargets -join '|')) {
    throw "[$Code-target-set]"
  }
}

function Get-MIR42SealCandidateTargetScope {
  param([Parameter(Mandatory)]$Rows,[Parameter(Mandatory)][string]$Code)
  $actual = @($Rows | ForEach-Object { [string]$_.target })
  if (($actual -join '|') -ceq ($script:MIR42SealTargets -join '|')) { return 'four-target' }
  if (($actual -join '|') -ceq ($script:MIR42SealNineTargetCandidates -join '|')) { return 'nine-target' }
  throw "[$Code-target-set]"
}

function Get-MIR42SealCandidateScope {
  param([Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$Code)
  $derived = Get-MIR42SealCandidateTargetScope -Rows @($Candidate.targets) -Code $Code
  if ($Candidate.PSObject.Properties.Name -contains 'scope' -and -not [string]::IsNullOrWhiteSpace([string]$Candidate.scope) -and [string]$Candidate.scope -cne $derived) {
    throw "[$Code-scope]"
  }
  return $derived
}

function Resolve-MIR42SealContainedArtifactPath {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$RelativePath,[Parameter(Mandatory)][string]$Code)
  if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath) -or
      $RelativePath.Replace('\','/') -match '(^|/)\.\.(/|$)') { throw "[$Code-path]" }
  $candidate = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
  try {
    $null = Assert-MIR4DescendantPath -Root $Root -Path $candidate
    $null = Assert-MIR4NoReparseAncestors -Root $Root -Path $candidate
  } catch { throw "[$Code-path]" }
  return $candidate
}

function Resolve-MIR42SealImmutableFile {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Sha256,[Parameter(Mandatory)][string]$Code)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path) -or $Sha256 -notmatch '^[A-F0-9]{64}$') { throw "[$Code-path]" }
  $full = [IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[$Code-missing]" }
  try {
    $cursor = $full
    while ($true) {
      if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse' }
      $parent = Split-Path -Parent $cursor
      if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $cursor) { break }
      $cursor = $parent
    }
  } catch { throw "[$Code-reparse]" }
  if ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant() -cne $Sha256) { throw "[$Code-hash]" }
  return $full
}

function Test-MIR42SealCurrentIdentityHasEffectiveRights {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][Security.AccessControl.FileSystemRights]$RequestedRights)
  try {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    [int64]$denied = 0; [int64]$allowed = 0
    foreach ($rule in @((Get-Acl -LiteralPath $Path).GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))) {
      if ($principal.IsInRole([Security.Principal.SecurityIdentifier]$rule.IdentityReference)) {
        if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Deny) {
          $denied = $denied -bor [int64]$rule.FileSystemRights
        } elseif ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow) {
          $allowed = $allowed -bor [int64]$rule.FileSystemRights
        }
      }
    }
    return (($allowed -band (-bnot $denied) -band [int64]$RequestedRights) -ne 0)
  } catch {
    throw '[mir42-seal-external-trust-acl-unreadable]'
  }
}

function Test-MIR42SealCurrentIdentityCanWritePath {
  param([Parameter(Mandatory)][string]$Path,[switch]$Ancestor)
  $rights = if ($Ancestor) {
    [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
      [Security.AccessControl.FileSystemRights]::Delete -bor
      [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
      [Security.AccessControl.FileSystemRights]::TakeOwnership
  } else {
    [Security.AccessControl.FileSystemRights]::WriteData -bor
      [Security.AccessControl.FileSystemRights]::AppendData -bor
      [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
      [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
      [Security.AccessControl.FileSystemRights]::Delete -bor
      [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
      [Security.AccessControl.FileSystemRights]::TakeOwnership
  }
  return Test-MIR42SealCurrentIdentityHasEffectiveRights -Path $Path -RequestedRights $rights
}

function Resolve-MIR42SealExternalProtectedFile {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) { throw "[$Code-path]" }
  $full = [IO.Path]::GetFullPath($Path)
  Assert-MIR42SealExternalPathSeparatedFromRepository -RepoRoot $RepoRoot -Path $full -Code $Code
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[$Code-missing]" }
  $null = Resolve-MIR42SealImmutableFile -Path $full -Sha256 ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()) -Code $Code
  $cursor = $full; $ancestor = $false
  while ($true) {
    if (Test-MIR42SealCurrentIdentityCanWritePath -Path $cursor -Ancestor:$ancestor) { throw "[$Code-not-protected]" }
    $parent = Split-Path -Parent $cursor
    if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $cursor) { break }
    $cursor = $parent; $ancestor = $true
  }
  return $full
}

function Resolve-MIR42SealExternalProtectedDirectory {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) { throw "[$Code-path]" }
  $full = [IO.Path]::GetFullPath($Path)
  Assert-MIR42SealExternalPathSeparatedFromRepository -RepoRoot $RepoRoot -Path $full -Code $Code
  if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "[$Code-missing]" }
  try {
    $cursor = $full; $ancestor = $false
    while ($true) {
      if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse' }
      if (Test-MIR42SealCurrentIdentityCanWritePath -Path $cursor -Ancestor:$ancestor) { throw 'not-protected' }
      $parent = Split-Path -Parent $cursor
      if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $cursor) { break }
      $cursor = $parent; $ancestor = $true
    }
  } catch {
    if ($_.Exception.Message -eq 'not-protected') { throw "[$Code-not-protected]" }
    throw "[$Code-reparse]"
  }
  return $full
}

function Get-MIR42SealAclAssessment {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  try {
    $acl = Get-Acl -LiteralPath $Path
    $ownerSid = ([Security.Principal.NTAccount]$acl.Owner).Translate([Security.Principal.SecurityIdentifier]).Value
    $rows = @(
      foreach ($rule in @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))) {
        [pscustomobject][ordered]@{
          sid = [string]$rule.IdentityReference.Value
          type = [string]$rule.AccessControlType
          rights = [Security.AccessControl.FileSystemRights]$rule.FileSystemRights
          inherited = [bool]$rule.IsInherited
        }
      }
    )
    return [pscustomobject][ordered]@{inheritance_protected=[bool]$acl.AreAccessRulesProtected;owner_sid=[string]$ownerSid;rows=$rows}
  } catch { throw "[$Code-acl-unreadable]" }
}

function New-MIR42T16AclContract {
  param([Parameter(Mandatory)][string]$ApprovedOwnerSid,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ApprovedMutationSids)
  $broad = @('S-1-1-0','S-1-5-11','S-1-5-32-545','S-1-5-32-546')
  $mutators = @($ApprovedMutationSids | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  if ($ApprovedOwnerSid -notmatch '^S-1-' -or $mutators.Count -eq 0 -or $mutators.Count -ne $ApprovedMutationSids.Count -or
      $ApprovedOwnerSid -notin $mutators -or @($mutators | Where-Object { $_ -notmatch '^S-1-' -or $_ -in $broad }).Count -ne 0) {
    throw '[mir42-seal-t16-acl-contract-human-input-required]'
  }
  $record = [pscustomobject][ordered]@{owner_sid=$ApprovedOwnerSid;mutation_sids=$mutators;broad_principals_forbidden=$broad}
  $canonical = ConvertTo-MIR4BootstrapCanonicalJson -Value @($mutators)
  return [pscustomobject][ordered]@{record=$record;custodian_sid_set_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical)))}
}

function Assert-MIR42SealT16AclContract {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$AclContract,[Parameter(Mandatory)][string]$Code)
  $assessment = Get-MIR42SealAclAssessment -Path $Path -Code $Code
  $record = $AclContract.record
  $approvedOwner = [string]$record.owner_sid
  $approvedMutators = @($record.mutation_sids | ForEach-Object { [string]$_ })
  $broad = @($record.broad_principals_forbidden | ForEach-Object { [string]$_ })
  if (-not [bool]$assessment.inheritance_protected) { throw "[$Code-acl-inheritance]" }
  if ([string]$assessment.owner_sid -cne $approvedOwner -or [string]$assessment.owner_sid -in $broad) { throw "[$Code-acl-owner]" }
  $actualAllowSids = @($assessment.rows | Where-Object { [string]$_.type -ceq 'Allow' } | ForEach-Object { [string]$_.sid } | Sort-Object -Unique)
  if (($actualAllowSids -join '|') -cne (($approvedMutators | Sort-Object -Unique) -join '|')) { throw "[$Code-acl-allow-sid]" }
  foreach ($row in @($assessment.rows)) {
    if ([bool]$row.inherited -or [string]$row.type -notin @('Allow','Deny') -or [string]$row.sid -in $broad) { throw "[$Code-acl-row]" }
    if ([string]$row.type -ceq 'Allow') {
      if ([string]$row.sid -notin $approvedMutators -or
          (([Security.AccessControl.FileSystemRights]$row.rights -band ([Security.AccessControl.FileSystemRights]::Modify -bor [Security.AccessControl.FileSystemRights]::FullControl)) -eq 0)) {
        throw "[$Code-acl-mutation]"
      }
    } elseif ([string]$row.sid -notin $approvedMutators) {
      throw "[$Code-acl-deny-sid]"
    }
  }
}

function Assert-MIR42SealT16AclContractTree {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$AclContract,[Parameter(Mandatory)][string]$Code)
  Assert-MIR42SealT16AclContract -Path $Path -AclContract $AclContract -Code $Code
  if (Test-Path -LiteralPath $Path -PathType Container) {
    foreach ($item in @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction Stop)) {
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "[$Code-reparse]" }
      Assert-MIR42SealT16AclContract -Path $item.FullName -AclContract $AclContract -Code $Code
    }
  }
}

function Assert-MIR42SealT16AclAncestorAssessment {
  param([Parameter(Mandatory)]$Assessment,[Parameter(Mandatory)]$AclContract,[Parameter(Mandatory)][string]$Code)
  $record = $AclContract.record
  $approvedOwner = [string]$record.owner_sid
  $approvedMutators = @($record.mutation_sids | ForEach-Object { [string]$_ } | Sort-Object -Unique)
  $broad = @($record.broad_principals_forbidden | ForEach-Object { [string]$_ })
  $mutationRights = [Security.AccessControl.FileSystemRights]::WriteData -bor
    [Security.AccessControl.FileSystemRights]::AppendData -bor
    [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
    [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
    [Security.AccessControl.FileSystemRights]::Delete -bor
    [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
    [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
    [Security.AccessControl.FileSystemRights]::TakeOwnership
  if (-not [bool]$assessment.inheritance_protected) { throw "[$Code-acl-ancestor-inheritance]" }
  if ([string]$assessment.owner_sid -cne $approvedOwner -or [string]$assessment.owner_sid -in $broad) { throw "[$Code-acl-ancestor-owner]" }
  $actualMutationAllowSids = @(
    $assessment.rows | Where-Object {
      [string]$_.type -ceq 'Allow' -and
      (([Security.AccessControl.FileSystemRights]$_.rights -band $mutationRights) -ne 0)
    } | ForEach-Object { [string]$_.sid } | Sort-Object -Unique
  )
  if (($actualMutationAllowSids -join '|') -cne ($approvedMutators -join '|')) { throw "[$Code-acl-ancestor-allow-sid]" }
  foreach ($row in @($assessment.rows)) {
    if ([bool]$row.inherited -or [string]$row.type -notin @('Allow','Deny')) { throw "[$Code-acl-ancestor-row]" }
    $hasMutationRight = (([Security.AccessControl.FileSystemRights]$row.rights -band $mutationRights) -ne 0)
    if ([string]$row.type -ceq 'Allow' -and $hasMutationRight) {
      if ([string]$row.sid -in $broad -or [string]$row.sid -notin $approvedMutators -or
          (([Security.AccessControl.FileSystemRights]$row.rights -band ([Security.AccessControl.FileSystemRights]::Modify -bor [Security.AccessControl.FileSystemRights]::FullControl)) -eq 0)) {
        throw "[$Code-acl-ancestor-mutation]"
      }
    }
  }
}

function Assert-MIR42SealT16AclAncestorContract {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$AclContract,[Parameter(Mandatory)][string]$Code)
  $assessment = Get-MIR42SealAclAssessment -Path $Path -Code $Code
  Assert-MIR42SealT16AclAncestorAssessment -Assessment $assessment -AclContract $AclContract -Code $Code
}

function Assert-MIR42SealT16AclProtectedAncestors {
  param(
    [Parameter(Mandatory)][string]$ArtifactPath,
    [Parameter(Mandatory)][string]$ProtectedRootPath,
    [Parameter(Mandatory)]$AclContract,
    [Parameter(Mandatory)][string]$Code
  )
  $artifact = [IO.Path]::GetFullPath($ArtifactPath)
  $protectedRootFull = [IO.Path]::GetFullPath($ProtectedRootPath)
  if ($protectedRootFull -ceq [IO.Path]::GetPathRoot($protectedRootFull)) { throw "[$Code-protected-root-path]" }
  $protectedRoot = $protectedRootFull.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
  $relative = [IO.Path]::GetRelativePath($protectedRoot,$artifact)
  if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)) {
    throw "[$Code-protected-root-containment]"
  }
  $cursor = Split-Path -Parent $artifact
  while ($true) {
    if ([string]::IsNullOrWhiteSpace($cursor)) { throw "[$Code-protected-root-containment]" }
    $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "[$Code-reparse]" }
    Assert-MIR42SealT16AclAncestorContract -Path $cursor -AclContract $AclContract -Code $Code
    if ($cursor -ceq $protectedRoot) { break }
    $parent = Split-Path -Parent $cursor
    if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $cursor) { throw "[$Code-protected-root-containment]" }
    $cursor = $parent
  }
}

function Resolve-MIR42SealImmutableVolumeShareAnchor {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Code)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) { throw "[$Code-path]" }
  $full = [IO.Path]::GetFullPath($Path)
  $root = [IO.Path]::GetPathRoot($full)
  if ($full.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)) -cne $root.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))) {
    throw "[$Code-volume-or-share-boundary]"
  }
  if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw "[$Code-missing]" }
  try {
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse' }
    if (Test-MIR42SealCurrentIdentityCanWritePath -Path $full) { throw 'not-protected' }
  } catch {
    if ($_.Exception.Message -eq 'not-protected') { throw "[$Code-not-protected]" }
    throw "[$Code-reparse]"
  }
  return $full
}

function Assert-MIR42SealT16AclImmutableAnchorAssessment {
  param([Parameter(Mandatory)]$Assessment,[Parameter(Mandatory)]$AclContract,[Parameter(Mandatory)][string]$Code)
  $approvedMutators = @($AclContract.record.mutation_sids | ForEach-Object { [string]$_ })
  $broad = @($AclContract.record.broad_principals_forbidden | ForEach-Object { [string]$_ })
  $mutationRights = [Security.AccessControl.FileSystemRights]::WriteData -bor
    [Security.AccessControl.FileSystemRights]::AppendData -bor
    [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
    [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
    [Security.AccessControl.FileSystemRights]::Delete -bor
    [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
    [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
    [Security.AccessControl.FileSystemRights]::TakeOwnership
  if ([string]$Assessment.owner_sid -in $broad -or [string]$Assessment.owner_sid -notin $approvedMutators) {
    throw "[$Code-acl-anchor-owner]"
  }
  foreach ($row in @($Assessment.rows)) {
    if ([string]$row.type -notin @('Allow','Deny')) { throw "[$Code-acl-anchor-row]" }
    if ([string]$row.type -ceq 'Allow' -and (([Security.AccessControl.FileSystemRights]$row.rights -band $mutationRights) -ne 0) -and
        ([string]$row.sid -in $broad -or [string]$row.sid -notin $approvedMutators)) {
      throw "[$Code-acl-anchor-mutation]"
    }
  }
}

function Assert-MIR42SealT16AclRootToImmutableAnchor {
  param(
    [Parameter(Mandatory)][string]$ProtectedRootPath,
    [Parameter(Mandatory)][string]$ImmutableAnchorPath,
    [Parameter(Mandatory)]$AclContract,
    [Parameter(Mandatory)][string]$Code
  )
  $protectedRoot = [IO.Path]::GetFullPath($ProtectedRootPath)
  $anchor = [IO.Path]::GetFullPath($ImmutableAnchorPath)
  $relative = [IO.Path]::GetRelativePath($anchor,$protectedRoot)
  if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)) {
    throw "[$Code-immutable-anchor-containment]"
  }
  $cursor = Split-Path -Parent $protectedRoot
  while ($true) {
    if ([string]::IsNullOrWhiteSpace($cursor)) { throw "[$Code-immutable-anchor-containment]" }
    $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "[$Code-reparse]" }
    $assessment = Get-MIR42SealAclAssessment -Path $cursor -Code $Code
    if ($cursor -ceq $anchor) {
      Assert-MIR42SealT16AclImmutableAnchorAssessment -Assessment $assessment -AclContract $AclContract -Code $Code
      break
    }
    Assert-MIR42SealT16AclAncestorAssessment -Assessment $assessment -AclContract $AclContract -Code $Code
    $parent = Split-Path -Parent $cursor
    if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $cursor) { throw "[$Code-immutable-anchor-containment]" }
    $cursor = $parent
  }
}

function Get-MIR42SealGitBlobSha256 {
  param([Parameter(Mandatory)][string]$RepositoryPath,[Parameter(Mandatory)][string]$Revision,[Parameter(Mandatory)][string]$Code)
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = 'git'; $info.UseShellExecute = $false; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
  foreach ($argument in @('-C',$RepositoryPath,'show',$Revision)) { $null = $info.ArgumentList.Add($argument) }
  $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
  try {
    if (-not $process.Start()) { throw "[$Code-start]" }
    $bytes = [IO.MemoryStream]::new()
    try { $process.StandardOutput.BaseStream.CopyTo($bytes); $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes.ToArray())) }
    finally { $bytes.Dispose() }
    $stderr = $process.StandardError.ReadToEnd(); $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "[$Code-show] $stderr" }
    return $digest
  } finally { $process.Dispose() }
}

function Assert-MIR42SealExternalVerifierAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Verifier,[Parameter(Mandatory)][string]$Code)
  Assert-MIR42SealPropertyNames -Value $Verifier -Expected @('source','dependencies') -Code "$Code-shape"
  Assert-MIR42SealPropertyNames -Value $Verifier.source -Expected @('commit','tree') -Code "$Code-source-shape"
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $dirty = @(& git -C $repo status --porcelain=v1 --untracked-files=all)
  if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw "[$Code-source-dirty]" }
  $commit = (& git -C $repo rev-parse HEAD).Trim()
  $tree = (& git -C $repo rev-parse 'HEAD^{tree}').Trim()
  if ($LASTEXITCODE -ne 0 -or [string]$Verifier.source.commit -cne $commit -or [string]$Verifier.source.tree -cne $tree) {
    throw "[$Code-source-binding]"
  }
  $rows = @($Verifier.dependencies)
  $actualPaths = @($rows | ForEach-Object { [string]$_.path })
  if ($rows.Count -ne $script:MIR42SealVerifierDependencyPaths.Count -or ($actualPaths -join '|') -cne ($script:MIR42SealVerifierDependencyPaths -join '|')) {
    throw "[$Code-dependency-set]"
  }
  foreach ($row in $rows) {
    Assert-MIR42SealPropertyNames -Value $row -Expected @('path','sha256') -Code "$Code-dependency-shape"
    $relative = [string]$row.path
    $full = Join-Path $repo $relative
    if ($relative -match '(^|[\\/])\.\.([\\/]|$)' -or -not (Test-Path -LiteralPath $full -PathType Leaf) -or [string]$row.sha256 -notmatch '^[A-F0-9]{64}$') {
      throw "[$Code-dependency-path]"
    }
    $currentSha = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToUpperInvariant()
    $committedSha = Get-MIR42SealGitBlobSha256 -RepositoryPath $repo -Revision ($commit + ':' + $relative) -Code "$Code-dependency"
    if ($currentSha -cne [string]$row.sha256 -or $committedSha -cne [string]$row.sha256) { throw "[$Code-dependency-hash]" }
  }
  return [pscustomobject][ordered]@{source=[pscustomobject][ordered]@{commit=$commit;tree=$tree};dependencies=@($rows)}
}

function Assert-MIR42SealAuthorizedLedgerCommitSignature {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$RepositoryPath,
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)]$AuthorizedSigner,
    [Parameter(Mandatory)][string]$SshKeygenPath
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $scratchRoot = Assert-MIR4NoReparseAncestors -Root $repo -Path (Join-Path $repo 'build/tmp')
  if (-not (Test-Path -LiteralPath $scratchRoot -PathType Container)) { New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null }
  $scratch = Assert-MIR4NoReparseAncestors -Root $scratchRoot -Path (Join-Path $scratchRoot ('mir42-ledger-commit-' + [guid]::NewGuid().ToString('N')))
  try {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $publicKeyPath = Join-Path $scratch 'ledger.pub'; $allowedSignersPath = Join-Path $scratch 'allowed-signers'
    [IO.File]::WriteAllText($publicKeyPath, ([string]$AuthorizedSigner.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    if ((Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKeyPath) -cne [string]$AuthorizedSigner.fingerprint) {
      throw '[mir42-seal-external-t16-ledger-commit-key-fingerprint]'
    }
    [IO.File]::WriteAllText($allowedSignersPath, "$([string]$AuthorizedSigner.principal) namespaces=`"git`" $([string]$AuthorizedSigner.public_key)`n", [Text.UTF8Encoding]::new($false))
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = 'git'; $info.UseShellExecute = $false; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    foreach ($argument in @('-C',$RepositoryPath,'-c','gpg.format=ssh','-c',("gpg.ssh.allowedSignersFile=" + $allowedSignersPath),'verify-commit',$Commit)) { $null = $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
    try {
      if (-not $process.Start()) { throw '[mir42-seal-external-t16-ledger-commit-start]' }
      $null = $process.StandardOutput.ReadToEnd(); $stderr = $process.StandardError.ReadToEnd(); $process.WaitForExit()
      if ($process.ExitCode -ne 0) { throw "[mir42-seal-external-t16-ledger-commit-signature] $stderr" }
    } finally { $process.Dispose() }
  } finally {
    if (Test-Path -LiteralPath $scratch) { Remove-MIR4BuildTree -OutputRoot $scratchRoot -Path $scratch }
  }
}

function Get-MIR42T16TrustRootSignaturePayload {
  param([Parameter(Mandatory)]$Record)
  return [pscustomobject][ordered]@{
    schema = [int]$Record.schema
    kind = [string]$Record.kind
    status = [string]$Record.status
    release_line = [string]$Record.release_line
    turn = [string]$Record.turn
    scope = [string]$Record.scope
    signing_ceremony = $Record.signing_ceremony
    authorized_signer = $Record.authorized_signer
    independent_reviewer = $Record.independent_reviewer
    recovery = $Record.recovery
    operator_trust = $Record.operator_trust
    verifier = $Record.verifier
    ledger = $Record.ledger
  }
}

function Get-MIR42ExternalT16LedgerTrustRoot {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$T16TrustRootPath,
    [Parameter(Mandatory)][string]$OperatorTrustSourcePath,
    [Parameter(Mandatory)][string]$ProtectedRootPath,
    [Parameter(Mandatory)][string]$ImmutableAnchorPath,
    [Parameter(Mandatory)]$AclContract,
    [Parameter(Mandatory)][string]$SshKeygenPath
  )
  if ([string]::IsNullOrWhiteSpace($T16TrustRootPath) -or [string]::IsNullOrWhiteSpace($OperatorTrustSourcePath) -or [string]::IsNullOrWhiteSpace($SshKeygenPath)) {
    throw '[mir42-seal-external-t16-trust-root-required]'
  }
  $immutableAnchor = Resolve-MIR42SealImmutableVolumeShareAnchor -Path $ImmutableAnchorPath -Code 'mir42-seal-external-t16-immutable-anchor'
  $protectedRoot = Resolve-MIR42SealExternalProtectedDirectory -RepoRoot $RepoRoot -Path $ProtectedRootPath -Code 'mir42-seal-external-t16-protected-root'
  Assert-MIR42SealT16AclContract -Path $protectedRoot -AclContract $AclContract -Code 'mir42-seal-external-t16-protected-root'
  Assert-MIR42SealT16AclRootToImmutableAnchor -ProtectedRootPath $protectedRoot -ImmutableAnchorPath $immutableAnchor -AclContract $AclContract -Code 'mir42-seal-external-t16-protected-root'
  $trustPath = Resolve-MIR42SealExternalProtectedFile -RepoRoot $RepoRoot -Path $T16TrustRootPath -Code 'mir42-seal-external-t16-trust-root'
  $operatorPath = Resolve-MIR42SealExternalProtectedFile -RepoRoot $RepoRoot -Path $OperatorTrustSourcePath -Code 'mir42-seal-external-operator-trust-source'
  $trust = Read-MIR42SealRecord -Path $trustPath -Code 'mir42-seal-external-t16-trust-root'
  $operator = Read-MIR42SealRecord -Path $operatorPath -Code 'mir42-seal-external-operator-trust-source'
  Assert-MIR42SealT16AclContract -Path $trust.path -AclContract $AclContract -Code 'mir42-seal-external-t16-trust-root'
  Assert-MIR42SealT16AclContract -Path $operator.path -AclContract $AclContract -Code 'mir42-seal-external-operator-trust-source'
  Assert-MIR42SealT16AclProtectedAncestors -ArtifactPath $trust.path -ProtectedRootPath $protectedRoot -AclContract $AclContract -Code 'mir42-seal-external-t16-trust-root'
  Assert-MIR42SealT16AclProtectedAncestors -ArtifactPath $operator.path -ProtectedRootPath $protectedRoot -AclContract $AclContract -Code 'mir42-seal-external-operator-trust-source'
  $record = $trust.record
  $operatorRecord = $operator.record
  Assert-MIR42SealPropertyNames -Value $operatorRecord -Expected @('schema','kind','status','operator','namespaces','record_sha256') -Code 'mir42-seal-external-operator-trust-source-shape'
  Assert-MIR42SealPropertyNames -Value $operatorRecord.operator -Expected @('identity','algorithm','public_key','fingerprint') -Code 'mir42-seal-external-operator-trust-source-operator-shape'
  if ([int]$operatorRecord.schema -ne 1 -or [string]$operatorRecord.kind -cne 'MIR42ExternalOperatorTrustSourceV1' -or
      [string]$operatorRecord.status -cne 'active-external-protected-operator-trust-source' -or
      [string]$operatorRecord.operator.algorithm -cne 'ssh-ed25519' -or
      [string]$operatorRecord.operator.public_key -notmatch '^ssh-ed25519\s+' -or
      [string]$operatorRecord.operator.fingerprint -notmatch '^SHA256:' -or
      (@($operatorRecord.namespaces | ForEach-Object { [string]$_ }) -join '|') -cne 'mir4-t16-trust-root') {
    throw '[mir42-seal-external-operator-trust-source-state]'
  }
  Assert-MIR42SealPropertyNames -Value $record -Expected @('schema','kind','status','release_line','turn','scope','signing_ceremony','authorized_signer','independent_reviewer','recovery','operator_trust','verifier','ledger','trust_signature','record_sha256') -Code 'mir42-seal-external-t16-trust-root-shape'
  Assert-MIR42SealPropertyNames -Value $record.signing_ceremony -Expected @('path','sha256','record_sha256') -Code 'mir42-seal-external-t16-trust-root-signing-shape'
  Assert-MIR42SealPropertyNames -Value $record.authorized_signer -Expected @('principal','algorithm','public_key','fingerprint','namespaces') -Code 'mir42-seal-external-t16-trust-root-signer-shape'
  Assert-MIR42SealPropertyNames -Value $record.independent_reviewer -Expected @('identity','public_key','fingerprint') -Code 'mir42-seal-external-t16-trust-root-reviewer-shape'
  Assert-MIR42SealPropertyNames -Value $record.operator_trust -Expected @('path','sha256','record_sha256') -Code 'mir42-seal-external-t16-trust-root-operator-binding-shape'
  Assert-MIR42SealPropertyNames -Value $record.verifier -Expected @('source','dependencies') -Code 'mir42-seal-external-t16-trust-root-verifier-shape'
  Assert-MIR42SealPropertyNames -Value $record.ledger -Expected @('repository_path','ref','commit','event_path','event_sha256') -Code 'mir42-seal-external-t16-trust-root-ledger-shape'
  Assert-MIR42SealPropertyNames -Value $record.trust_signature -Expected @('identity','namespace','signature_path','signature_sha256','payload_sha256') -Code 'mir42-seal-external-t16-trust-root-signature-shape'
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42ExternalT16LedgerTrustRootV1' -or
      [string]$record.status -cne 'MIR-4.2-T16-PROTECTED-SIGNING-RECOVERY-ACCEPTED' -or [string]$record.release_line -cne '4.2' -or
      [string]$record.turn -cne 'T16' -or [string]$record.scope -cne 'four-target-release-cut' -or
      [string]$record.authorized_signer.algorithm -cne 'ssh-ed25519' -or [string]$record.authorized_signer.public_key -notmatch '^ssh-ed25519\s+' -or
      [string]$record.authorized_signer.fingerprint -notmatch '^SHA256:' -or
      (@($record.authorized_signer.namespaces | ForEach-Object { [string]$_ }) -join '|') -cne 'mir4-source|mir4-target|mir4-ledger' -or
      [string]$record.independent_reviewer.public_key -notmatch '^ssh-ed25519\s+' -or [string]$record.independent_reviewer.fingerprint -notmatch '^SHA256:' -or
      [string]$record.operator_trust.path -cne $operator.path -or [string]$record.operator_trust.sha256 -cne $operator.sha256 -or
      [string]$record.operator_trust.record_sha256 -cne [string]$operator.record.record_sha256 -or
      [string]$record.trust_signature.identity -cne [string]$operatorRecord.operator.identity -or
      [string]$record.trust_signature.namespace -cne 'mir4-t16-trust-root' -or
      [string]$record.trust_signature.signature_sha256 -notmatch '^[A-F0-9]{64}$') {
    throw '[mir42-seal-external-t16-trust-root-state]'
  }
  $verifier = Assert-MIR42SealExternalVerifierAuthority -RepoRoot $RepoRoot -Verifier $record.verifier -Code 'mir42-seal-external-t16-trust-root-verifier'
  $ledgerPath = Resolve-MIR42SealExternalProtectedDirectory -RepoRoot $RepoRoot -Path ([string]$record.ledger.repository_path) -Code 'mir42-seal-external-t16-ledger'
  Assert-MIR42SealT16AclContractTree -Path $ledgerPath -AclContract $AclContract -Code 'mir42-seal-external-t16-ledger'
  Assert-MIR42SealT16AclProtectedAncestors -ArtifactPath $ledgerPath -ProtectedRootPath $protectedRoot -AclContract $AclContract -Code 'mir42-seal-external-t16-ledger'
  if ([string]$record.ledger.ref -notmatch '^refs/heads/release-ledger/mir4$' -or
      [string]$record.ledger.commit -notmatch '^[0-9a-f]{40}$' -or [string]$record.ledger.event_path -match '(^|[\\/])\.\.([\\/]|$)' -or
      [IO.Path]::IsPathRooted([string]$record.ledger.event_path) -or [string]$record.ledger.event_sha256 -cne [string]$trust.sha256) {
    throw '[mir42-seal-external-t16-ledger-state]'
  }
  $refCommit = (& git -C $ledgerPath rev-parse ([string]$record.ledger.ref) 2>$null).Trim()
  $revision = ([string]$record.ledger.commit) + ':' + ([string]$record.ledger.event_path)
  $blobSha256 = Get-MIR42SealGitBlobSha256 -RepositoryPath $ledgerPath -Revision $revision -Code 'mir42-seal-external-t16-ledger'
  if ($LASTEXITCODE -ne 0 -or $refCommit -cne [string]$record.ledger.commit -or
      $blobSha256 -cne [string]$trust.sha256) {
    throw '[mir42-seal-external-t16-ledger-binding]'
  }
  Assert-MIR42SealAuthorizedLedgerCommitSignature -RepoRoot $RepoRoot -RepositoryPath $ledgerPath -Commit ([string]$record.ledger.commit) -AuthorizedSigner $record.authorized_signer -SshKeygenPath $SshKeygenPath
  $signaturePath = Resolve-MIR42SealExternalProtectedFile -RepoRoot $RepoRoot -Path ([string]$record.trust_signature.signature_path) -Code 'mir42-seal-external-t16-trust-signature'
  Assert-MIR42SealT16AclContract -Path $signaturePath -AclContract $AclContract -Code 'mir42-seal-external-t16-trust-signature'
  Assert-MIR42SealT16AclProtectedAncestors -ArtifactPath $signaturePath -ProtectedRootPath $protectedRoot -AclContract $AclContract -Code 'mir42-seal-external-t16-trust-signature'
  if ((Get-FileHash -LiteralPath $signaturePath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$record.trust_signature.signature_sha256) {
    throw '[mir42-seal-external-t16-trust-signature-hash]'
  }
  $payload = ConvertTo-MIR4BootstrapCanonicalJson -Value (Get-MIR42T16TrustRootSignaturePayload -Record $record)
  $payloadSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payload)))
  if ([string]$record.trust_signature.payload_sha256 -cne $payloadSha) { throw '[mir42-seal-external-t16-trust-signature-payload]' }
  $scratchRoot = Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path (Join-Path $RepoRoot 'build/tmp')
  if (-not (Test-Path -LiteralPath $scratchRoot -PathType Container)) { New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null }
  $scratch = Assert-MIR4NoReparseAncestors -Root $scratchRoot -Path (Join-Path $scratchRoot ('mir42-t16-trust-root-' + [guid]::NewGuid().ToString('N')))
  try {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $publicKeyPath = Join-Path $scratch 'operator.pub'; $authorizedSignerPath = Join-Path $scratch 'authorized-signer.pub'; $reviewerPath = Join-Path $scratch 'reviewer.pub'; $payloadPath = Join-Path $scratch 'trust-root.json'
    [IO.File]::WriteAllText($publicKeyPath, ([string]$operatorRecord.operator.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($authorizedSignerPath, ([string]$record.authorized_signer.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($reviewerPath, ([string]$record.independent_reviewer.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($payloadPath, $payload, [Text.UTF8Encoding]::new($false))
    if ((Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKeyPath) -cne [string]$operatorRecord.operator.fingerprint -or
        (Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $authorizedSignerPath) -cne [string]$record.authorized_signer.fingerprint -or
        (Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $reviewerPath) -cne [string]$record.independent_reviewer.fingerprint -or
        -not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKeyPath -Identity ([string]$operatorRecord.operator.identity) -Namespace 'mir4-t16-trust-root' -PayloadPath $payloadPath -SignaturePath $signaturePath -ScratchRoot (Join-Path $scratch 'verify'))) {
      throw '[mir42-seal-external-t16-trust-signature-verification]'
    }
  } finally {
    if (Test-Path -LiteralPath $scratch) { Remove-MIR4BuildTree -OutputRoot $scratchRoot -Path $scratch }
  }
  return [pscustomobject][ordered]@{path=$trust.path;sha256=$trust.sha256;record=$record;operator=$operator;verifier=$verifier;protected_root=$protectedRoot;immutable_anchor=$immutableAnchor;acl_contract=$AclContract}
}

function Get-MIR42ExactFourTargetCandidate {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$CandidateManifestPath)
  $candidateInput = Read-MIR42SealRecord -Path $CandidateManifestPath -Code 'mir42-seal-candidate'
  $candidate = $candidateInput.record
  if ($candidate.PSObject.Properties.Name -notcontains 'target_authority') { throw '[mir42-seal-candidate-target-authority-missing]' }
  $targetScope = Get-MIR42SealCandidateTargetScope -Rows @($candidate.targets) -Code 'mir42-seal-candidate-targets'
  $authorityScope = Get-MIR42SealCandidateTargetScope -Rows @($candidate.target_authority) -Code 'mir42-seal-candidate-target-authority'
  $expectedStatus = if ($targetScope -ceq 'four-target') {
    'private-deterministic-four-target-candidate-built-unqualified'
  } else {
    'private-deterministic-nine-target-candidate-built-unqualified'
  }
  if ([string]$candidate.kind -cne 'MIR42FourTargetDeterministicCandidateManifestV1' -or
      $authorityScope -cne $targetScope -or [string]$candidate.status -cne $expectedStatus -or
      -not [bool]$candidate.build_complete -or
      [string]$candidate.qualification -cne 'not-performed' -or
      [bool]$candidate.publication_authorized) {
    throw '[mir42-seal-candidate-state]'
  }
  $candidateSource = [pscustomobject][ordered]@{
    commit = [string]$candidate.source.commit
    tree = [string]$candidate.source.tree
    package_source_sha256 = [string]$candidate.package_source_sha256
  }
  $source = Assert-MIR42SealSource -RepoRoot $RepoRoot -Source $candidateSource -Code 'mir42-seal-candidate'
  $root = Split-Path -Parent $candidateInput.path
  $rows = [Collections.Generic.List[object]]::new()
  foreach ($target in @($candidate.targets)) {
    foreach ($field in @('target','distribution_version','target_row_path','asset','content_sha256','entry_count')) {
      if ($target.PSObject.Properties.Name -notcontains $field) { throw "[mir42-seal-candidate-target-field] $([string]$target.target)/$field" }
    }
    if (-not [bool]$target.asset.bytes -or [string]$target.asset.sha256 -notmatch '^[A-F0-9]{64}$') {
      throw "[mir42-seal-candidate-asset-shape] $([string]$target.target)"
    }
    $assetPath = Resolve-MIR42SealContainedArtifactPath -Root $root -RelativePath ([string]$target.asset.path) -Code 'mir42-seal-candidate-asset'
    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$target.asset.sha256 -or
        [int64](Get-Item -LiteralPath $assetPath).Length -ne [int64]$target.asset.bytes) {
      throw "[mir42-seal-candidate-asset-drift] $([string]$target.target)"
    }
    $rowPath = Resolve-MIR42SealContainedArtifactPath -Root $root -RelativePath ([string]$target.target_row_path) -Code 'mir42-seal-candidate-target-row'
    $rowInput = Read-MIR42SealRecord -Path $rowPath -Code 'mir42-seal-target-row'
    $row = $rowInput.record
    if ([int]$row.schema -ne 1 -or [string]$row.kind -cne 'MIR42FourTargetCandidateRowV1') {
      throw "[mir42-seal-candidate-target-row-schema] $([string]$target.target)"
    }
    $expected = Get-MIR42ReleaseTargetIdentity -RepoRoot $RepoRoot -Target ([string]$target.target)
    $authorityRow = @($candidate.target_authority | Where-Object { [string]$_.target -ceq [string]$target.target })
    if ($authorityRow.Count -ne 1) { throw "[mir42-seal-candidate-target-authority-binding] $([string]$target.target)" }
    foreach ($field in @('target','target_id','source_version','distribution_version')) {
      if ($authorityRow[0].PSObject.Properties.Name -notcontains $field) { throw "[mir42-seal-candidate-target-authority-field] $([string]$target.target)/$field" }
    }
    if ([string]$authorityRow[0].target -cne [string]$expected.target -or
        [string]$authorityRow[0].target_id -cne [string]$expected.target_id -or
        [string]$authorityRow[0].source_version -cne [string]$expected.source_version -or
        [string]$authorityRow[0].distribution_version -cne [string]$expected.distribution_version) {
      throw "[mir42-seal-candidate-target-authority-binding] $([string]$target.target)"
    }
    try { $inventory = Get-MIR4ArchiveInventory -Path $assetPath }
    catch { throw "[mir42-seal-candidate-archive-invalid] $([string]$target.target)" }
    if ([IO.Path]::GetFileName($assetPath) -cne [string]$expected.package_name -or
        [string]$inventory.root -cne [string]$expected.distribution_root -or
        [string]$target.distribution_version -cne [string]$expected.distribution_version -or
        [string]$inventory.archive_sha256 -cne [string]$target.asset.sha256 -or
        [string]$inventory.content_sha256 -cne [string]$target.content_sha256 -or
        [int]$inventory.entry_count -ne [int]$target.entry_count) {
      throw "[mir42-seal-candidate-package-identity] $([string]$target.target)"
    }
    Assert-MIR42FourTargetPackageExcludedSurface -Inventory $inventory -Target ([string]$target.target)
    try { $info = Read-MIR4ArchiveText -Path $assetPath -RelativePath 'info.json' | ConvertFrom-Json -Depth 20 -DateKind String }
    catch { throw "[mir42-seal-candidate-info-json] $([string]$target.target)" }
    if ([string]$info.name -cne 'more-infinite-research' -or [string]$info.version -cne [string]$expected.distribution_version -or
        [string]$info.factorio_version -cne ([string]$expected.target_id -replace '^factorio-', '')) {
      throw "[mir42-seal-candidate-info-identity] $([string]$target.target)"
    }
    foreach ($field in @('source','package_authority_sha256','package_source_sha256')) {
      if ($row.PSObject.Properties.Name -notcontains $field) { throw "[mir42-seal-candidate-target-row-field] $([string]$target.target)/$field" }
    }
    foreach ($field in @('commit','tree')) {
      if ($row.source.PSObject.Properties.Name -notcontains $field) { throw "[mir42-seal-candidate-target-row-source-field] $([string]$target.target)/$field" }
    }
    if ([string]$row.target -cne [string]$target.target -or
        [string]$row.distribution_version -cne [string]$target.distribution_version -or
        [string]$row.asset.sha256 -cne [string]$target.asset.sha256 -or
        [string]$row.content_sha256 -cne [string]$target.content_sha256 -or
        [int]$row.entry_count -ne [int]$target.entry_count -or
        -not [bool]$row.deterministic_archive_bytes -or -not [bool]$row.package_excluded_surface -or
        [string]$row.build_a_sha256 -cne [string]$target.asset.sha256 -or
        [string]$row.build_b_sha256 -cne [string]$target.asset.sha256 -or
        [string]$row.source.commit -cne [string]$Candidate.source.commit -or
        [string]$row.source.tree -cne [string]$Candidate.source.tree -or
        [string]$row.package_authority_sha256 -cne [string]$candidate.package_authority_sha256 -or
        [string]$row.package_source_sha256 -cne [string]$candidate.package_source_sha256) {
      throw "[mir42-seal-candidate-target-row-drift] $([string]$target.target)"
    }
    if ($expected.PSObject.Properties.Name -contains 'target_record_path') {
      foreach ($field in @('materializer','base_materializer_target','target_record','factorio_line','public_output_authorized','publication_authorized')) {
        if ($row.PSObject.Properties.Name -notcontains $field) { throw "[mir42-seal-candidate-historical-row-field] $([string]$target.target)/$field" }
      }
      Assert-MIR42SealPropertyNames -Value $row.target_record -Expected @('path','sha256') -Code 'mir42-seal-candidate-historical-target-record-shape'
      $targetRecordPath = Resolve-MIR42SealContainedArtifactPath -Root $RepoRoot -RelativePath ([string]$expected.target_record_path) -Code 'mir42-seal-candidate-historical-target-record'
      $targetRecord = Read-MIR42SealRecord -Path $targetRecordPath -Code 'mir42-seal-candidate-historical-target-record'
      if ([string]$row.materializer -cne 'historical-playtest-target' -or [string]$row.base_materializer_target -cne 'f100' -or
          [string]$row.factorio_line -cne ([string]$expected.target_id -replace '^factorio-', '') -or
          [bool]$row.public_output_authorized -or [bool]$row.publication_authorized -or
          [string]$row.target_record.path -cne [string]$expected.target_record_path -or
          [string]$row.target_record.sha256 -cne [string]$expected.target_record_record_sha256 -or
          [string]$targetRecord.record.record_sha256 -cne [string]$expected.target_record_record_sha256 -or
          [string]$targetRecord.sha256 -cne [string]$expected.target_record_file_sha256) {
        throw "[mir42-seal-candidate-historical-target-record-binding] $([string]$target.target)"
      }
    }
    $rows.Add([pscustomobject][ordered]@{
      target = [string]$target.target
      distribution_version = [string]$target.distribution_version
      archive_sha256 = [string]$target.asset.sha256
      content_sha256 = [string]$target.content_sha256
      entry_count = [int]$target.entry_count
      archive_path = $assetPath
    })
  }
  return [pscustomobject][ordered]@{identity=$candidateInput;source=$source;scope=$targetScope;targets=@($rows)}
}

function Assert-MIR42ReceiptBinding {
  param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$Code,[string]$ExpectedTargetStatus='passed')
  $record = $Receipt.record
  if ([string]$record.candidate_manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
      [string]$record.candidate_manifest.record_sha256 -cne [string]$Candidate.identity.record.record_sha256 -or
      [string]$record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$record.source.tree -cne [string]$Candidate.source.tree -or
      [string]$record.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256) {
    throw "[$Code-candidate-binding]"
  }
  $candidateTargets = @($Candidate.targets | ForEach-Object { [string]$_.target })
  $receiptTargets = @($record.targets | ForEach-Object { [string]$_.target })
  if (($receiptTargets -join '|') -cne ($candidateTargets -join '|')) {
    throw "[$Code-target-set]"
  }
  foreach ($candidateTarget in @($Candidate.targets)) {
    $row = @($record.targets | Where-Object { [string]$_.target -ceq [string]$candidateTarget.target })
    if ($row.Count -ne 1 -or [string]$row[0].distribution_version -cne [string]$candidateTarget.distribution_version -or
        [string]$row[0].archive.sha256 -cne [string]$candidateTarget.archive_sha256 -or
        [string]$row[0].archive.content_sha256 -cne [string]$candidateTarget.content_sha256 -or
        [int]$row[0].archive.entry_count -ne [int]$candidateTarget.entry_count -or
        [string]$row[0].status -cne $ExpectedTargetStatus) {
      throw "[$Code-target-binding] $([string]$candidateTarget.target)"
    }
  }
}

function Assert-MIR42JoinedAcceptanceCoverage {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)]$Candidate)
  $expectedCriteria = @(
    'fresh-exact-loads',
    'settings-profile-continuity',
    'research-progression',
    'migrations-two-reload',
    'compatibility-canaries',
    'target-omissions',
    'performance-telemetry',
    'package-exclusion',
    'deterministic-reconstruction'
  )
  $candidateTargets = @($Candidate.targets | ForEach-Object { [string]$_.target })
  $rows = @($Receipt.record.release_acceptance)
  $actualCriteria = @($rows | ForEach-Object { [string]$_.criterion })
  if ($rows.Count -ne $expectedCriteria.Count -or ($actualCriteria -join '|') -cne ($expectedCriteria -join '|')) {
    throw '[mir42-seal-qualification-joined-acceptance-missing]'
  }
  foreach ($row in $rows) {
    Assert-MIR42SealPropertyNames -Value $row -Expected @('criterion','status','observed_targets','not_applicable_targets','evidence','limits') -Code 'mir42-seal-qualification-joined-acceptance-shape'
    $observed = @($row.observed_targets | ForEach-Object { [string]$_ })
    $notApplicable = @($row.not_applicable_targets)
    $notApplicableIds = @($notApplicable | ForEach-Object { [string]$_.target })
    foreach ($omission in $notApplicable) {
      Assert-MIR42SealPropertyNames -Value $omission -Expected @('target','reason') -Code 'mir42-seal-qualification-not-applicable-shape'
      if ([string]::IsNullOrWhiteSpace([string]$omission.reason)) {
        throw "[mir42-seal-qualification-not-applicable-binding] $([string]$row.criterion)/$([string]$omission.target)"
      }
    }
    foreach ($evidence in @($row.evidence)) {
      Assert-MIR42SealPropertyNames -Value $evidence -Expected @('path','sha256','record_sha256') -Code 'mir42-seal-qualification-evidence-shape'
      $evidencePath = Resolve-MIR42SealImmutableFile -Path ([string]$evidence.path) -Sha256 ([string]$evidence.sha256) -Code 'mir42-seal-qualification-evidence'
      $evidenceRecord = Read-MIR42SealRecord -Path $evidencePath -Code 'mir42-seal-qualification-evidence'
      if ([string]$evidenceRecord.record.record_sha256 -cne [string]$evidence.record_sha256) { throw '[mir42-seal-qualification-evidence-record-binding]' }
    }
    Assert-MIR42SealPropertyNames -Value $row.limits -Expected @('claim','known_limitations') -Code 'mir42-seal-qualification-limits-shape'
    if ([string]$row.status -cne 'passed' -or $observed.Count -eq 0 -or @($row.evidence).Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$row.limits.claim) -or
        @($observed + $notApplicableIds).Count -ne $candidateTargets.Count -or
        (@($observed + $notApplicableIds | Sort-Object -Unique).Count -ne $candidateTargets.Count) -or
        ((@($observed + $notApplicableIds | Sort-Object { [array]::IndexOf($candidateTargets, [string]$_) }) -join '|') -cne ($candidateTargets -join '|')) -or
        @($row.evidence | Where-Object { [string]$_.sha256 -notmatch '^[A-F0-9]{64}$' -or [string]$_.record_sha256 -notmatch '^[A-F0-9]{64}$' }).Count -ne 0) {
      throw "[mir42-seal-qualification-joined-acceptance-binding] $([string]$row.criterion)"
    }
  }
}

function Get-MIR42ExactQualificationReceipt {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate)
  if ((Get-MIR42SealCandidateScope -Candidate $Candidate -Code 'mir42-seal-qualification-candidate') -cne 'four-target') { throw '[mir42-seal-nine-target-campaign-not-wired]' }
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-qualification'
  if ([int]$receipt.record.schema -ne 1 -or [string]$receipt.record.kind -cne 'MIR42FourTargetEvidenceReconciliationV1' -or
      [string]$receipt.record.status -cne 'MIR-4.2-FOUR-TARGET-EVIDENCE-RECONCILED-PRIVATE-UNQUALIFIED' -or
      [int]$receipt.record.factorio_processes -ne 0 -or
      [string]$receipt.record.release_qualification -cne 'not-performed' -or
      [string]$receipt.record.independent_verification -cne 'not-performed' -or
      [bool]$receipt.record.publication_authorized) {
    throw '[mir42-seal-evidence-reconciliation-state]'
  }
  Assert-MIR42ReceiptBinding -Receipt $receipt -Candidate $Candidate -Code 'mir42-seal-qualification' -ExpectedTargetStatus 'reconciled'
  return $receipt
}

function Assert-MIR42FreshEngineLoads {
  param([Parameter(Mandatory)]$Target,[Parameter(Mandatory)]$CandidateTarget,[Parameter(Mandatory)]$Execution)
  $targetId = [string]$Target.target
  $expectedFactorioVersion = [regex]::Match([string]$Execution.version, '^[0-9]+[.][0-9]+[.][0-9]+').Value
  if ([string]::IsNullOrWhiteSpace($expectedFactorioVersion)) { throw "[mir42-seal-real-engine-version-shape] $targetId" }
  [string[]]$expectedScenarios = if ($targetId -ceq 'f210') { @('package-zip-base','package-zip-space-age') } else { @('package-zip-base') }
  $freshLoads = @($Execution.fresh_loads)
  if ($freshLoads.Count -ne $expectedScenarios.Count -or
      ((@($freshLoads | ForEach-Object { [string]$_.scenario }) -join '|') -cne ($expectedScenarios -join '|'))) {
    throw "[mir42-seal-real-engine-fresh-load-set] $targetId"
  }
  foreach ($fresh in $freshLoads) {
    Assert-MIR42SealPropertyNames -Value $fresh -Expected @('scenario','receipt','log','stdout','stderr') -Code 'mir42-seal-real-engine-fresh-load-shape'
    foreach ($field in @('receipt','log','stdout','stderr')) {
      Assert-MIR42SealPropertyNames -Value $fresh.$field -Expected @('path','sha256') -Code "mir42-seal-real-engine-fresh-load-$field-shape"
      $null = Resolve-MIR42SealImmutableFile -Path ([string]$fresh.$field.path) -Sha256 ([string]$fresh.$field.sha256) -Code "mir42-seal-real-engine-fresh-load-$field"
    }
    try { $summary = Get-Content -Raw -LiteralPath ([string]$fresh.receipt.path) | ConvertFrom-Json -Depth 100 -DateKind String }
    catch { throw "[mir42-seal-real-engine-fresh-load-receipt-json] $targetId/$([string]$fresh.scenario)" }
    $scenarioRows = @($summary.scenarios)
    if ([int]$summary.schema -ne 2 -or
        [string]$summary.status -cne 'passed' -or
        [string]$summary.git_commit -cne [string]$CandidateTarget.source.commit -or
        [string]$summary.validation_package_sha256 -cne [string]$Target.archive.sha256 -or
        [string]$summary.validation_package_content_sha256 -cne [string]$Target.archive.content_sha256 -or
        [string]$summary.factorio_binary_version -cne $expectedFactorioVersion -or
        @($summary.expected_scenarios).Count -ne 1 -or
        [string]$summary.expected_scenarios[0] -cne [string]$fresh.scenario -or
        $scenarioRows.Count -ne 1 -or
        [string]$scenarioRows[0].name -cne [string]$fresh.scenario -or
        [string]$scenarioRows[0].status -cne 'passed' -or
        [int]$scenarioRows[0].assertions_executed -le 0) {
      throw "[mir42-seal-real-engine-fresh-load-binding] $targetId/$([string]$fresh.scenario)"
    }
    $logText = Get-Content -Raw -LiteralPath ([string]$fresh.log.path)
    if (-not $logText.Contains("Loading mod more-infinite-research $([string]$Target.distribution_version)") -or
        -not $logText.Contains('Factorio initialised') -or -not $logText.Contains('Creating new map')) {
      throw "[mir42-seal-real-engine-fresh-load-log-marker] $targetId/$([string]$fresh.scenario)"
    }
  }
}

function Assert-MIR42ExactEngineAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Target,[Parameter(Mandatory)]$Execution)
  $targetId = [string]$Target.target
  $binary = Get-Item -LiteralPath ([string]$Execution.executable_path)
  $productVersion = [string]$binary.VersionInfo.ProductVersion
  if ($productVersion -match '^([0-9]+[.][0-9]+[.][0-9]+)') { $productVersion = [string]$Matches[1] }
  $observed = [pscustomobject][ordered]@{
    version = $productVersion
    file_version = [string]$binary.VersionInfo.FileVersion
    binary_sha256 = (Get-FileHash -LiteralPath $binary.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
  }
  if ([string]$Execution.executable_sha256 -cne [string]$observed.binary_sha256 -or
      [string]$Execution.version -cne [string]$observed.file_version) {
    throw "[mir42-seal-engine-local-identity-drift] $targetId"
  }
  if ($targetId -ceq 'f210') {
    $admission = Get-MIR4F210CurrentEngineCapHarnessAdmissionV3 -RepoRoot $RepoRoot
    if ([string]$admission.engine.binary.sha256 -cne [string]$observed.binary_sha256 -or
        [string]$admission.engine.file_version -cne [string]$observed.file_version) {
      throw '[mir42-seal-f210-engine-authority-drift]'
    }
  } elseif (-not (Test-MIR4FixedFactorioEngineIdentity -Target $targetId -ObservedIdentity $observed -RepoRoot $RepoRoot)) {
    throw "[mir42-seal-fixed-engine-authority-drift] $targetId"
  }
}

function Get-MIR42DirectPredecessorAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Reference)
  Assert-MIR42SealPropertyNames -Value $Reference -Expected @('path','sha256','record_sha256') -Code 'mir42-seal-predecessor-authority-reference-shape'
  $authorityPath = Resolve-MIR42SealImmutableFile -Path ([string]$Reference.path) -Sha256 ([string]$Reference.sha256) -Code 'mir42-seal-predecessor-authority-reference'
  $authority = Read-MIR42SealRecord -Path $authorityPath -Code 'mir42-seal-predecessor-authority'
  $record = $authority.record
  if ([string]$record.record_sha256 -cne [string]$Reference.record_sha256) { throw '[mir42-seal-predecessor-authority-reference-binding]' }
  Assert-MIR42SealPropertyNames -Value $record -Expected @('schema','kind','status','public_v410_checksums','targets','release_transition_authority','publication_authorized','record_sha256') -Code 'mir42-seal-predecessor-authority-shape'
  Assert-MIR42SealPropertyNames -Value $record.public_v410_checksums -Expected @('tag','tag_object','tagged_commit','path','sha256','verified_tag_fingerprint','release_asset_id','release_asset_bytes') -Code 'mir42-seal-predecessor-checksums-shape'
  if ([int]$record.schema -ne 1 -or
      [string]$record.kind -cne 'MIR42DirectPredecessorInputsV1' -or
      [string]$record.status -cne 'verified-published-v410-checksum-and-local-custody-private' -or
      [bool]$record.release_transition_authority -or [bool]$record.publication_authorized) {
    throw '[mir42-seal-predecessor-authority-state]'
  }
  $checksumRelative = [string]$record.public_v410_checksums.path
  if ($checksumRelative -cne '.mir/releases/governance/mir4/MIR42-v410-SHA256SUMS.txt') { throw '[mir42-seal-predecessor-checksums-path]' }
  $checksumPath = Resolve-MIR42SealContainedArtifactPath -Root $RepoRoot -RelativePath $checksumRelative -Code 'mir42-seal-predecessor-checksums'
  if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $checksumPath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$record.public_v410_checksums.sha256) {
    throw '[mir42-seal-predecessor-checksums-drift]'
  }
  if ([int64]$record.public_v410_checksums.release_asset_id -le 0 -or [int64]$record.public_v410_checksums.release_asset_bytes -ne [int64](Get-Item -LiteralPath $checksumPath).Length) {
    throw '[mir42-seal-predecessor-public-asset-shape]'
  }
  $tag = [string]$record.public_v410_checksums.tag
  $tagObject = (& git -C $RepoRoot rev-parse "${tag}^{object}").Trim()
  $taggedCommit = (& git -C $RepoRoot rev-parse "${tag}^{commit}").Trim()
  $tagVerification = @(& git -C $RepoRoot tag --verify $tag 2>&1)
  if ($LASTEXITCODE -ne 0 -or $tagObject -cne [string]$record.public_v410_checksums.tag_object -or
      $taggedCommit -cne [string]$record.public_v410_checksums.tagged_commit -or
      (($tagVerification -join "`n") -notmatch ('Good "git" signature.*key ' + [regex]::Escape([string]$record.public_v410_checksums.verified_tag_fingerprint)))) {
    throw '[mir42-seal-predecessor-public-tag-binding]'
  }
  Assert-MIR42SealTargetSet -Rows @($record.targets) -Code 'mir42-seal-predecessor-authority'
  foreach ($row in @($record.targets)) {
    Assert-MIR42SealPropertyNames -Value $row -Expected @('target','predecessor','published_checksum_sha256','engine') -Code 'mir42-seal-predecessor-target-shape'
    Assert-MIR42SealPropertyNames -Value $row.predecessor -Expected @('version','path','sha256','bytes') -Code 'mir42-seal-predecessor-input-shape'
    Assert-MIR42SealPropertyNames -Value $row.engine -Expected @('path','file_version','product_version','sha256','channel') -Code 'mir42-seal-predecessor-engine-shape'
    $predecessorPath = Resolve-MIR42SealImmutableFile -Path ([string]$row.predecessor.path) -Sha256 ([string]$row.predecessor.sha256) -Code 'mir42-seal-predecessor-input'
    if ([int64](Get-Item -LiteralPath $predecessorPath).Length -ne [int64]$row.predecessor.bytes -or
        [string]$row.published_checksum_sha256 -cne [string]$row.predecessor.sha256 -or
        ([IO.Path]::GetFileName($predecessorPath) -cne "more-infinite-research_$([string]$row.predecessor.version).zip") -or
        @((Get-Content -LiteralPath $checksumPath | Where-Object { $_ -match ('^' + [regex]::Escape([string]$row.predecessor.sha256) + '\s{2}' + [regex]::Escape([IO.Path]::GetFileName($predecessorPath)) + '$') })).Count -ne 1) {
      throw "[mir42-seal-predecessor-input-binding] $([string]$row.target)"
    }
  }
  return $authority
}

function Assert-MIR42PublishedV410ChecksumAsset {
  param([Parameter(Mandatory)]$Authority,[Parameter(Mandatory)]$RunAsset)
  Assert-MIR42SealPropertyNames -Value $RunAsset -Expected @('release_id','asset_id','digest','bytes','download_verified') -Code 'mir42-seal-predecessor-run-asset-shape'
  $checksums = $Authority.record.public_v410_checksums
  $expectedDigest = 'sha256:' + ([string]$checksums.sha256).ToLowerInvariant()
  if ([int64]$RunAsset.release_id -le 0 -or
      [int64]$RunAsset.asset_id -ne [int64]$checksums.release_asset_id -or
      [int64]$RunAsset.bytes -ne [int64]$checksums.release_asset_bytes -or
      [string]$RunAsset.digest -cne $expectedDigest -or -not [bool]$RunAsset.download_verified) {
    throw '[mir42-seal-predecessor-run-asset-binding]'
  }
  $gh = Get-Command gh -ErrorAction SilentlyContinue
  if ($null -eq $gh) { throw '[mir42-seal-predecessor-public-asset-client-missing]' }
  try {
    $raw = & $gh.Source api ("repos/Julesc013/more-infinite-research/releases/tags/" + [string]$checksums.tag) 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'gh-failed' }
    $release = ($raw -join "`n") | ConvertFrom-Json -Depth 100 -DateKind String
    $asset = @($release.assets | Where-Object { [string]$_.name -ceq 'SHA256SUMS.txt' })
    if ([string]$release.tag_name -cne [string]$checksums.tag -or $asset.Count -ne 1 -or
        [int64]$release.id -ne [int64]$RunAsset.release_id -or [int64]$asset[0].id -ne [int64]$RunAsset.asset_id -or
        [int64]$asset[0].size -ne [int64]$RunAsset.bytes -or [string]$asset[0].digest -cne [string]$RunAsset.digest) {
      throw 'asset-drift'
    }
  } catch { throw '[mir42-seal-predecessor-public-asset-live-binding]' }
}

function Assert-MIR42GovernedPredecessor {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)]$Target,[Parameter(Mandatory)]$Execution,[Parameter(Mandatory)]$AuthorityReference,[Parameter(Mandatory)]$RunAsset)
  $authority = Get-MIR42DirectPredecessorAuthority -RepoRoot $RepoRoot -Reference $AuthorityReference
  Assert-MIR42PublishedV410ChecksumAsset -Authority $authority -RunAsset $RunAsset
  $rows = @($authority.record.targets | Where-Object { [string]$_.target -ceq [string]$Target.target })
  $authorityPredecessorPath = if ($rows.Count -eq 1) { [IO.Path]::GetFullPath([string]$rows[0].predecessor.path) } else { '' }
  $executionPredecessorPath = [IO.Path]::GetFullPath([string]$Execution.predecessor.path)
  $authorityEnginePath = if ($rows.Count -eq 1) { [IO.Path]::GetFullPath([string]$rows[0].engine.path) } else { '' }
  $executionEnginePath = [IO.Path]::GetFullPath([string]$Execution.executable_path)
  $productVersion = [string](Get-Item -LiteralPath $executionEnginePath).VersionInfo.ProductVersion
  if ($productVersion -match '^([0-9]+[.][0-9]+[.][0-9]+)') { $productVersion = [string]$Matches[1] }
  if ($rows.Count -ne 1 -or
      [string]$rows[0].predecessor.version -cne [string]$Execution.predecessor.version -or
      -not $authorityPredecessorPath.Equals($executionPredecessorPath,[StringComparison]::OrdinalIgnoreCase) -or
      [string]$rows[0].predecessor.sha256 -cne [string]$Execution.predecessor.sha256 -or
      -not $authorityEnginePath.Equals($executionEnginePath,[StringComparison]::OrdinalIgnoreCase) -or
      [string]$rows[0].engine.file_version -cne [string]$Execution.version -or
      [string]$rows[0].engine.product_version -cne $productVersion -or
      [string]$rows[0].engine.sha256 -cne [string]$Execution.executable_sha256) {
    throw "[mir42-seal-predecessor-execution-binding] $([string]$Target.target)"
  }
}

function Get-MIR42BoundEngineRun {
  param([Parameter(Mandatory)]$Reference,[Parameter(Mandatory)]$Candidate)
  Assert-MIR42SealPropertyNames -Value $Reference -Expected @('path','sha256','record_sha256') -Code 'mir42-seal-engine-run-reference-shape'
  $runPath = Resolve-MIR42SealImmutableFile -Path ([string]$Reference.path) -Sha256 ([string]$Reference.sha256) -Code 'mir42-seal-engine-run-reference'
  $run = Read-MIR42SealRecord -Path $runPath -Code 'mir42-seal-engine-run'
  if ([string]$run.record.record_sha256 -cne [string]$Reference.record_sha256) { throw '[mir42-seal-engine-run-reference-binding]' }
  Assert-MIR42SealPropertyNames -Value $run.record -Expected @('schema','kind','status','source','candidate_manifest','predecessor_authority','public_v410_checksum_asset','runner','harness','targets','factorio_processes','release_qualification','publication_authorized','record_sha256') -Code 'mir42-seal-engine-run-shape'
  if ([int]$run.record.schema -ne 1 -or
      [string]$run.record.kind -cne 'MIR42FourTargetEngineRunV1' -or
      [string]$run.record.status -cne 'four-target-base-default-real-engine-probes-passed-private-unqualified' -or
      [string]$run.record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$run.record.source.tree -cne [string]$Candidate.source.tree -or
      [int]$run.record.factorio_processes -lt 9 -or
      [string]$run.record.release_qualification -cne 'not-performed' -or
      [bool]$run.record.publication_authorized) {
    throw '[mir42-seal-engine-run-state]'
  }
  foreach ($field in @('candidate_manifest','runner','harness')) {
    $expected = if ($field -eq 'candidate_manifest') { @('path','sha256','record_sha256') } else { @('path','sha256') }
    Assert-MIR42SealPropertyNames -Value $run.record.$field -Expected $expected -Code "mir42-seal-engine-run-$field-shape"
    $path = Resolve-MIR42SealImmutableFile -Path ([string]$run.record.$field.path) -Sha256 ([string]$run.record.$field.sha256) -Code "mir42-seal-engine-run-$field"
    if ($field -eq 'candidate_manifest') {
      $manifest = Read-MIR42SealRecord -Path $path -Code 'mir42-seal-engine-run-candidate-manifest'
      if ([string]$manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
          [string]$manifest.record.record_sha256 -cne [string]$Candidate.identity.record.record_sha256 -or
          [string]$manifest.record.record_sha256 -cne [string]$run.record.candidate_manifest.record_sha256) {
        throw '[mir42-seal-engine-run-candidate-manifest-binding]'
      }
    } elseif ($field -eq 'runner' -and (Get-Content -Raw -LiteralPath $path) -notmatch 'Test-MIRUpgrade[.]ps1') {
      throw '[mir42-seal-engine-run-runner-content]'
    } elseif ($field -eq 'harness' -and (Get-Content -Raw -LiteralPath $path) -notmatch 'upgraded-save-second-reload-passed') {
      throw '[mir42-seal-engine-run-harness-content]'
    }
  }
  Assert-MIR42SealTargetSet -Rows @($run.record.targets) -Code 'mir42-seal-engine-run'
  foreach ($candidateTarget in @($Candidate.targets)) {
    $row = @($run.record.targets | Where-Object { [string]$_.target -ceq [string]$candidateTarget.target })
    if ($row.Count -ne 1) { throw "[mir42-seal-engine-run-target-cardinality] $([string]$candidateTarget.target)" }
    Assert-MIR42SealPropertyNames -Value $row[0] -Expected @('target','status','archive','engine_execution') -Code 'mir42-seal-engine-run-target-shape'
    Assert-MIR42SealPropertyNames -Value $row[0].archive -Expected @('path','sha256') -Code 'mir42-seal-engine-run-archive-shape'
    $archivePath = Resolve-MIR42SealImmutableFile -Path ([string]$row[0].archive.path) -Sha256 ([string]$row[0].archive.sha256) -Code 'mir42-seal-engine-run-archive'
    $expectedStagedArchive = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $run.path) ("staged-assets/$([string]$candidateTarget.target)/" + [IO.Path]::GetFileName([string]$candidateTarget.archive_path))))
    if ([string]$row[0].status -cne 'passed' -or
        $archivePath -cne $expectedStagedArchive -or
        [string]$row[0].archive.sha256 -cne [string]$candidateTarget.archive_sha256) {
      throw "[mir42-seal-engine-run-target-binding] $([string]$candidateTarget.target)"
    }
  }
  return $run
}

function New-MIR42FourTargetRealEngineEvidenceBinder {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [Parameter(Mandatory)][string]$EvidenceReconciliationPath,
    [Parameter(Mandatory)][string]$EngineRunPath,
    [Parameter(Mandatory)][string]$OutputPath
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $candidate = Get-MIR42ExactFourTargetCandidate -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath
  if ((Get-MIR42SealCandidateScope -Candidate $candidate -Code 'mir42-engine-evidence-candidate') -cne 'four-target') { throw '[mir42-seal-nine-target-predecessor-campaign-not-wired]' }
  $reconciliation = Get-MIR42ExactQualificationReceipt -Path $EvidenceReconciliationPath -Candidate $candidate
  $engineInput = Read-MIR42SealRecord -Path $EngineRunPath -Code 'mir42-engine-evidence-engine-run'
  $engineRun = Get-MIR42BoundEngineRun -Reference ([pscustomobject][ordered]@{
    path = $engineInput.path
    sha256 = $engineInput.sha256
    record_sha256 = [string]$engineInput.record.record_sha256
  }) -Candidate $candidate
  $targets = [Collections.Generic.List[object]]::new()
  foreach ($candidateTarget in @($candidate.targets)) {
    $engineTarget = @($engineRun.record.targets | Where-Object { [string]$_.target -ceq [string]$candidateTarget.target })
    if ($engineTarget.Count -ne 1) { throw "[mir42-engine-evidence-target-cardinality] $([string]$candidateTarget.target)" }
    $targets.Add([pscustomobject][ordered]@{
      target = [string]$candidateTarget.target
      distribution_version = [string]$candidateTarget.distribution_version
      status = 'observed-real-engine-private-unqualified'
      archive = [ordered]@{
        sha256 = [string]$candidateTarget.archive_sha256
        content_sha256 = [string]$candidateTarget.content_sha256
        entry_count = [int]$candidateTarget.entry_count
      }
      engine_execution = $engineTarget[0].engine_execution
    })
  }
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetRealEngineEvidenceBinderV1'
    status = 'MIR-4.2-FOUR-TARGET-REAL-ENGINE-EVIDENCE-BOUND-PRIVATE-UNQUALIFIED'
    source = $candidate.source
    candidate_manifest = [ordered]@{sha256=[string]$candidate.identity.sha256;record_sha256=[string]$candidate.identity.record.record_sha256}
    evidence_reconciliation = [ordered]@{sha256=[string]$reconciliation.sha256;record_sha256=[string]$reconciliation.record.record_sha256}
    engine_run = [ordered]@{sha256=[string]$engineRun.sha256;record_sha256=[string]$engineRun.record.record_sha256}
    runner = [ordered]@{sha256=[string]$engineRun.record.runner.sha256}
    targets = @($targets)
    factorio_processes = [int]$engineRun.record.factorio_processes
    release_qualification = 'not-performed'
    release_acceptance = 'not-performed'
    technical_seal = 'not-performed'
    publication_authorized = $false
    record_sha256 = ''
  }
  return (Write-MIR42NormalizedRecord -Record $record -OutputPath $OutputPath -Code 'mir42-engine-evidence-output')
}

function Get-MIR42RealEngineCandidateCampaign {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Reconciliation)
  if ((Get-MIR42SealCandidateScope -Candidate $Candidate -Code 'mir42-seal-real-engine-candidate') -cne 'four-target') { throw '[mir42-seal-nine-target-campaign-not-wired]' }
  $campaign = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-real-engine'
  $record = $campaign.record
  Assert-MIR42SealPropertyNames -Value $record -Expected @('schema','kind','status','source','candidate_manifest','evidence_reconciliation','engine_run','runner','targets','factorio_processes','release_qualification','release_acceptance','technical_seal','publication_authorized','record_sha256') -Code 'mir42-seal-real-engine-shape'
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42FourTargetRealEngineCandidateCampaignV1' -or
      [string]$record.status -cne 'MIR-4.2-FOUR-TARGET-REAL-ENGINE-CAMPAIGN-PASSED-PRIVATE-UNSEALED' -or
      [string]$record.evidence_reconciliation.sha256 -cne [string]$Reconciliation.sha256 -or
      [string]$record.evidence_reconciliation.record_sha256 -cne [string]$Reconciliation.record.record_sha256 -or
      [int]$record.factorio_processes -lt 4 -or
      [string]$record.release_qualification -cne 'passed' -or
      [string]$record.technical_seal -cne 'not-performed' -or
      [bool]$record.publication_authorized) {
    throw '[mir42-seal-real-engine-campaign-state]'
  }
  Assert-MIR42SealPropertyNames -Value $record.runner -Expected @('path','sha256') -Code 'mir42-seal-real-engine-runner-shape'
  $runnerPath = Resolve-MIR42SealImmutableFile -Path ([string]$record.runner.path) -Sha256 ([string]$record.runner.sha256) -Code 'mir42-seal-real-engine-runner'
  if ((Get-Content -Raw -LiteralPath $runnerPath) -notmatch 'Invoke-MIR42FourTargetEngineRun|Test-MIRUpgrade') { throw '[mir42-seal-real-engine-runner-content]' }
  Assert-MIR42ReceiptBinding -Receipt $campaign -Candidate $Candidate -Code 'mir42-seal-real-engine'
  $engineRun = Get-MIR42BoundEngineRun -Reference $record.engine_run -Candidate $Candidate
  if ([string]$record.runner.sha256 -cne [string]$engineRun.record.runner.sha256) { throw '[mir42-seal-real-engine-runner-binding]' }
  foreach ($target in @($record.targets)) {
    $candidateTarget = @($Candidate.targets | Where-Object { [string]$_.target -ceq [string]$target.target })[0]
    $engineRunTarget = @($engineRun.record.targets | Where-Object { [string]$_.target -ceq [string]$target.target })[0]
    if ((ConvertTo-MIR4BootstrapCanonicalJson -Value $target.engine_execution) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $engineRunTarget.engine_execution)) {
      throw "[mir42-seal-real-engine-run-binding] $([string]$target.target)"
    }
    Assert-MIR42SealPropertyNames -Value $target.engine_execution -Expected @('executable_path','executable_sha256','version','predecessor','harness_receipt','harness_exit_code','logs','fresh_loads','fresh_exact_load','predecessor_upgrade','reload_count') -Code 'mir42-seal-real-engine-target-shape'
    Assert-MIR42SealPropertyNames -Value $target.engine_execution.predecessor -Expected @('path','sha256','version') -Code 'mir42-seal-real-engine-predecessor-shape'
    Assert-MIR42SealPropertyNames -Value $target.engine_execution.harness_receipt -Expected @('path','sha256') -Code 'mir42-seal-real-engine-receipt-shape'
    $executablePath = Resolve-MIR42SealImmutableFile -Path ([string]$target.engine_execution.executable_path) -Sha256 ([string]$target.engine_execution.executable_sha256) -Code 'mir42-seal-real-engine-executable'
    $predecessorPath = Resolve-MIR42SealImmutableFile -Path ([string]$target.engine_execution.predecessor.path) -Sha256 ([string]$target.engine_execution.predecessor.sha256) -Code 'mir42-seal-real-engine-predecessor'
    $harnessPath = Resolve-MIR42SealImmutableFile -Path ([string]$target.engine_execution.harness_receipt.path) -Sha256 ([string]$target.engine_execution.harness_receipt.sha256) -Code 'mir42-seal-real-engine-receipt'
    try { $harness = Get-Content -Raw -LiteralPath $harnessPath | ConvertFrom-Json -Depth 100 -DateKind String } catch { throw '[mir42-seal-real-engine-receipt-json]' }
    $logs = @($target.engine_execution.logs)
    $logPhases = @($logs | ForEach-Object { [string]$_.phase })
    foreach ($log in $logs) {
      Assert-MIR42SealPropertyNames -Value $log -Expected @('phase','path','sha256') -Code 'mir42-seal-real-engine-log-shape'
      $null = Resolve-MIR42SealImmutableFile -Path ([string]$log.path) -Sha256 ([string]$log.sha256) -Code 'mir42-seal-real-engine-log'
    }
    if ([string]$target.engine_execution.executable_sha256 -notmatch '^[A-F0-9]{64}$' -or
        [string]::IsNullOrWhiteSpace([string]$target.engine_execution.version) -or
        [int]$target.engine_execution.harness_exit_code -ne 0 -or @($logs).Count -ne 4 -or
        ($logPhases -join '|') -cne 'create|load|reload|second-reload' -or
        @($logs | Where-Object { [string]$_.sha256 -notmatch '^[A-F0-9]{64}$' }).Count -ne 0 -or
        -not [bool]$target.engine_execution.fresh_exact_load -or
        -not [bool]$target.engine_execution.predecessor_upgrade -or [int]$target.engine_execution.reload_count -lt 2 -or
        [string]$harness.status -cne 'passed' -or [string]$harness.git_commit -cne [string]$Candidate.source.commit -or
        [string]$harness.factorio_binary_sha256 -cne [string]$target.engine_execution.executable_sha256 -or
        [string]$harness.factorio_binary_version -cne [string]$target.engine_execution.version -or
        [string]$harness.from.sha256 -cne [string]$target.engine_execution.predecessor.sha256 -or
        [string]$harness.from.version -cne [string]$target.engine_execution.predecessor.version -or
        [string]$harness.to.sha256 -cne [string]$candidateTarget.archive_sha256 -or
        [string]$harness.to.path -cne [IO.Path]::GetFileName([string]$candidateTarget.archive_path) -or
        @($harness.assertions | ForEach-Object { [string]$_ }) -notcontains 'exact-candidate-normal-mod-directory-load' -or
        @($harness.assertions | ForEach-Object { [string]$_ }) -notcontains 'upgraded-save-reload-passed' -or
        @($harness.assertions | ForEach-Object { [string]$_ }) -notcontains 'upgraded-save-second-reload-passed') {
      throw "[mir42-seal-real-engine-target-binding] $([string]$target.target)"
    }
    foreach ($log in $logs) {
      $text = Get-Content -Raw -LiteralPath ([string]$log.path)
      $marker = switch ([string]$log.phase) {
        'create' { '[mir-fixture]' }
        'load' { 'upgrade proof complete' }
        default { 'upgraded save reload proof complete' }
      }
      if (-not $text.Contains($marker)) { throw "[mir42-seal-real-engine-log-marker] $([string]$target.target)/$([string]$log.phase)" }
    }
    Assert-MIR42ExactEngineAuthority -RepoRoot $RepoRoot -Target $target -Execution $target.engine_execution
    Assert-MIR42GovernedPredecessor -RepoRoot $RepoRoot -Target $target -Execution $target.engine_execution -AuthorityReference $engineRun.record.predecessor_authority -RunAsset $engineRun.record.public_v410_checksum_asset
    Assert-MIR42FreshEngineLoads -Target $target -CandidateTarget $Candidate -Execution $target.engine_execution
  }
  Assert-MIR42JoinedAcceptanceCoverage -RepoRoot $RepoRoot -Receipt $campaign -Candidate $Candidate
  return $campaign
}

function Get-MIR42ExactIndependentVerificationReceipt {
  param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Qualification)
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-independent'
  if ([int]$receipt.record.schema -ne 1 -or [string]$receipt.record.kind -cne 'MIR42FourTargetIndependentEvidenceRehashV1' -or
      [string]$receipt.record.status -cne 'MIR-4.2-FOUR-TARGET-INDEPENDENT-EVIDENCE-REHASH-PASSED-PRIVATE-UNQUALIFIED' -or
      [int]$receipt.record.factorio_processes -ne 0 -or
      [string]$receipt.record.release_qualification -cne 'not-performed' -or
      [string]$receipt.record.independent_release_acceptance -cne 'not-performed' -or
      [string]$receipt.record.qualification.sha256 -cne [string]$Qualification.sha256 -or
      [string]$receipt.record.qualification.record_sha256 -cne [string]$Qualification.record.record_sha256 -or
      [bool]$receipt.record.publication_authorized) {
    throw '[mir42-seal-independent-evidence-reconciliation-state]'
  }
  Assert-MIR42ReceiptBinding -Receipt $receipt -Candidate $Candidate -Code 'mir42-seal-independent' -ExpectedTargetStatus 'reconciled'
  return $receipt
}

function Get-MIR42ProtectedSigningCeremony {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$T16TrustRoot)
  $receipt = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-signing'
  $schema = Join-Path $RepoRoot 'spec/schemas/mir4-protected-signing-ceremony-receipt-v1.schema.json'
  $raw = Get-Content -Raw -LiteralPath $receipt.path
  if (-not ($raw | Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue)) { throw '[mir42-seal-signing-schema]' }
  if ([string]$receipt.record.status -cne 'accepted-protected-signing-authority' -or
      [string]$receipt.record.authorization.decision -cne 'AUTHORIZED' -or
      [bool]$receipt.record.secret_values_present) { throw '[mir42-seal-signing-state]' }
  $root = $T16TrustRoot.record
  if ([string]$root.signing_ceremony.path -cne [string]$receipt.path -or [string]$root.signing_ceremony.sha256 -cne [string]$receipt.sha256 -or
      [string]$root.signing_ceremony.record_sha256 -cne [string]$receipt.record.record_sha256 -or
      [string]$root.authorized_signer.principal -cne [string]$receipt.record.public_signer.principal -or
      [string]$root.authorized_signer.algorithm -cne [string]$receipt.record.public_signer.algorithm -or
      [string]$root.authorized_signer.public_key -cne [string]$receipt.record.public_signer.public_key -or
      [string]$root.authorized_signer.fingerprint -cne [string]$receipt.record.public_signer.fingerprint -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value @($root.authorized_signer.namespaces)) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value @($receipt.record.public_signer.namespaces)) -or
      [string]$receipt.record.custody_validation.approved_custodian_sid_set_sha256 -cne [string]$T16TrustRoot.acl_contract.custodian_sid_set_sha256 -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $root.recovery) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $receipt.record.recovery)) {
    throw '[mir42-seal-external-t16-signing-binding]'
  }
  return [pscustomobject][ordered]@{path=$receipt.path;sha256=$receipt.sha256;record=$receipt.record;ledger_signer=$root.authorized_signer;independent_reviewer=$root.independent_reviewer;t16_trust_root=$T16TrustRoot}
}

function Assert-MIR42SealPropertyNames {
  param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string[]]$Expected,[Parameter(Mandatory)][string]$Code)
  $actual = @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
  if ($actual.Count -ne $Expected.Count -or @($actual | Where-Object { $_ -cnotin $Expected }).Count -ne 0) { throw "[$Code]" }
}

function Get-MIR42LiveProgrammeTransition {
  param([Parameter(Mandatory)][string]$RepoRoot)
  $relative = '.mir/releases/governance/mir4/MIR42-Release-Cut-ProgrammeV1.json'
  $path = Join-Path $RepoRoot $relative
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw '[mir42-seal-current-programme-missing]' }
  $programmeReceipt = Read-MIR42SealRecord -Path $path -Code 'mir42-seal-current-programme'
  $programme = $programmeReceipt.record
  Assert-MIR42SealPropertyNames -Value $programme -Expected @('schema','kind','status','release_line','selected_targets','candidate','direct_predecessor_authority','direct_predecessors','required_gates','transition_gate','release_transition_authority','publication_authorized','record_sha256') -Code 'mir42-seal-current-programme-shape'
  Assert-MIR42SealPropertyNames -Value $programme.candidate -Expected @('version_line','state','exact_candidate_required') -Code 'mir42-seal-current-programme-candidate-shape'
  Assert-MIR42SealPropertyNames -Value $programme.direct_predecessor_authority -Expected @('path','kind','record_sha256','sha256') -Code 'mir42-seal-current-programme-predecessor-authority-shape'
  Assert-MIR42SealPropertyNames -Value $programme.transition_gate -Expected @('source_freeze','candidate_allocation','production_signing','technical_seal','promotion','tagging','publication') -Code 'mir42-seal-current-programme-transition-shape'
  if ([int]$programme.schema -ne 1 -or [string]$programme.kind -cne 'MIR42ReleaseCutProgrammeV1' -or
      [string]$programme.status -notmatch '^active-current-4[.]2-release-cut-' -or [string]$programme.release_line -cne '4.2' -or
      [string]$programme.candidate.version_line -cne '4.2' -or -not [bool]$programme.candidate.exact_candidate_required -or
      [string]$programme.direct_predecessor_authority.path -cne '.mir/releases/governance/mir4/MIR42-Direct-Predecessor-InputsV1.json' -or
      [string]$programme.direct_predecessor_authority.kind -cne 'MIR42DirectPredecessorInputsV1' -or
      [bool]$programme.release_transition_authority -or [bool]$programme.publication_authorized) {
    throw '[mir42-seal-current-programme-state]'
  }
  Assert-MIR42SealTargetSet -Rows @($programme.selected_targets | ForEach-Object { [pscustomobject]@{target=[string]$_} }) -Code 'mir42-seal-current-programme'
  $predecessorAuthority = Get-MIR42DirectPredecessorAuthority -RepoRoot $RepoRoot -Reference ([pscustomobject][ordered]@{
    path = Resolve-MIR42SealContainedArtifactPath -Root $RepoRoot -RelativePath ([string]$programme.direct_predecessor_authority.path) -Code 'mir42-seal-current-programme-predecessor-authority'
    sha256 = [string]$programme.direct_predecessor_authority.sha256
    record_sha256 = [string]$programme.direct_predecessor_authority.record_sha256
  })
  Assert-MIR42SealTargetSet -Rows @($programme.direct_predecessors) -Code 'mir42-seal-current-programme-predecessors'
  foreach ($row in @($programme.direct_predecessors)) {
    Assert-MIR42SealPropertyNames -Value $row -Expected @('target','version','sha256','engine') -Code 'mir42-seal-current-programme-predecessor-shape'
    Assert-MIR42SealPropertyNames -Value $row.engine -Expected @('file_version','product_version','sha256') -Code 'mir42-seal-current-programme-predecessor-engine-shape'
    $authorityRow = @($predecessorAuthority.record.targets | Where-Object { [string]$_.target -ceq [string]$row.target })
    if ($authorityRow.Count -ne 1 -or [string]$row.version -cne [string]$authorityRow[0].predecessor.version -or
        [string]$row.sha256 -cne [string]$authorityRow[0].predecessor.sha256 -or
        [string]$row.engine.file_version -cne [string]$authorityRow[0].engine.file_version -or
        [string]$row.engine.product_version -cne [string]$authorityRow[0].engine.product_version -or
        [string]$row.engine.sha256 -cne [string]$authorityRow[0].engine.sha256) {
      throw "[mir42-seal-current-programme-predecessor-binding] $([string]$row.target)"
    }
  }
  $requiredGateIds = @($programme.required_gates | ForEach-Object { [string]$_.id })
  if (($requiredGateIds -join '|') -cne 'exact-candidate-allocation|joined-real-engine-campaign|independent-acceptance|protected-signing-and-recovery|source-freeze-ledger-authorization|governed-offline-restore|human-go-after-main-readback') {
    throw '[mir42-seal-current-programme-gate-set]'
  }
  foreach ($gate in @($programme.required_gates)) {
    Assert-MIR42SealPropertyNames -Value $gate -Expected @('id','state','scope') -Code 'mir42-seal-current-programme-gate-shape'
    if ([string]$gate.scope -cne 'four-target-release-cut') { throw '[mir42-seal-current-programme-gate-scope]' }
  }
  if (-not [bool]$programme.transition_gate.source_freeze -or -not [bool]$programme.transition_gate.candidate_allocation -or
      -not [bool]$programme.transition_gate.production_signing) {
    throw '[mir42-seal-current-programme-transition-not-authorized]'
  }
  return [pscustomobject][ordered]@{path=$relative;sha256=$programmeReceipt.sha256;source_freeze_state=[string]$programme.transition_gate.source_freeze;candidate_allocation_state=[string]$programme.transition_gate.candidate_allocation;record=$programme}
}

function Get-MIR42SourceFreezeLedgerPayload {
  param([Parameter(Mandatory)]$Record)
  Assert-MIR42SealPropertyNames -Value $Record -Expected @('schema','kind','status','source','frozen_dev','promotion_base','programme','candidate_manifest','signing_ceremony','independent_reviewer','transition_gate','ledger_signature','record_sha256') -Code 'mir42-seal-freeze-authority-shape'
  Assert-MIR42SealPropertyNames -Value $Record.frozen_dev -Expected @('ref','commit','tree') -Code 'mir42-seal-freeze-frozen-dev-shape'
  Assert-MIR42SealPropertyNames -Value $Record.promotion_base -Expected @('remote','ref','commit') -Code 'mir42-seal-freeze-promotion-base-shape'
  Assert-MIR42SealPropertyNames -Value $Record.programme -Expected @('path','sha256','source_freeze_state','candidate_allocation_state') -Code 'mir42-seal-freeze-programme-shape'
  Assert-MIR42SealPropertyNames -Value $Record.ledger_signature -Expected @('identity','namespace','signature_path','signature_sha256','payload_sha256') -Code 'mir42-seal-freeze-ledger-signature-shape'
  Assert-MIR42SealPropertyNames -Value $Record.independent_reviewer -Expected @('identity','public_key','fingerprint') -Code 'mir42-seal-freeze-reviewer-shape'
  return [pscustomobject][ordered]@{
    schema = [int]$Record.schema
    kind = [string]$Record.kind
    status = [string]$Record.status
    source = $Record.source
    frozen_dev = $Record.frozen_dev
    promotion_base = $Record.promotion_base
    programme = $Record.programme
    candidate_manifest = $Record.candidate_manifest
    signing_ceremony = $Record.signing_ceremony
    independent_reviewer = $Record.independent_reviewer
    transition_gate = $Record.transition_gate
  }
}

function Assert-MIR42SourceFreezeLedgerSignature {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)]$Authority,
    [Parameter(Mandatory)]$Signing,
    [Parameter(Mandatory)][string]$SshKeygenPath
  )
  $record = $Authority.record
  $signature = $record.ledger_signature
  $payload = ConvertTo-MIR4BootstrapCanonicalJson -Value (Get-MIR42SourceFreezeLedgerPayload -Record $record)
  $payloadSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payload)))
  if ([string]$signature.identity -cne [string]$Signing.ledger_signer.principal -or
      [string]$signature.namespace -cne 'mir4-ledger' -or
      [string]$signature.payload_sha256 -cne $payloadSha -or
      [string]$signature.signature_sha256 -notmatch '^[A-F0-9]{64}$' -or
      -not [IO.Path]::IsPathRooted([string]$signature.signature_path)) {
    throw '[mir42-seal-freeze-ledger-signature-binding]'
  }
  $signaturePath = [IO.Path]::GetFullPath([string]$signature.signature_path)
  $repo = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
  if ($signaturePath.StartsWith($repo + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-Path -LiteralPath $signaturePath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $signaturePath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$signature.signature_sha256) {
    throw '[mir42-seal-freeze-ledger-signature-path]'
  }
  $scratchRoot = Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path (Join-Path $RepoRoot 'build/tmp')
  if (-not (Test-Path -LiteralPath $scratchRoot -PathType Container)) { New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null }
  $scratch = Assert-MIR4NoReparseAncestors -Root $scratchRoot -Path (Join-Path $scratchRoot ('mir42-ledger-signature-' + [guid]::NewGuid().ToString('N')))
  try {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $publicKey = Join-Path $scratch 'ledger-signing.pub'
    $payloadPath = Join-Path $scratch 'source-freeze-payload.json'
    [IO.File]::WriteAllText($publicKey, ([string]$Signing.ledger_signer.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($payloadPath, $payload, [Text.UTF8Encoding]::new($false))
    if (-not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKey -Identity ([string]$Signing.ledger_signer.principal) -Namespace 'mir4-ledger' -PayloadPath $payloadPath -SignaturePath $signaturePath -ScratchRoot (Join-Path $scratch 'verify'))) {
      throw '[mir42-seal-freeze-ledger-signature-verification]'
    }
  } finally {
    if (Test-Path -LiteralPath $scratch) { Remove-MIR4BuildTree -OutputRoot $scratchRoot -Path $scratch }
  }
}

function Get-MIR42SourceFreezeAuthority {
  param([Parameter(Mandatory)][string]$RepoRoot,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)]$Signing,[Parameter(Mandatory)][string]$SshKeygenPath)
  $authority = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-freeze'
  $record = $authority.record
  $null = Get-MIR42SourceFreezeLedgerPayload -Record $record
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42SourceFreezeAuthorizationV1' -or
      [string]$record.status -cne 'MIR-4.2-SOURCE-FROZEN-AND-CANDIDATE-ALLOCATED' -or
      [string]$record.signing_ceremony.sha256 -cne [string]$Signing.sha256 -or
      [string]$record.signing_ceremony.record_sha256 -cne [string]$Signing.record.record_sha256 -or
      -not [bool]$record.transition_gate.source_freeze -or -not [bool]$record.transition_gate.candidate_allocation -or
      -not [bool]$record.transition_gate.production_signing -or [bool]$record.transition_gate.technical_seal) {
    throw '[mir42-seal-freeze-authority-state]'
  }
  if ([string]$record.candidate_manifest.sha256 -cne [string]$Candidate.identity.sha256 -or
      [string]$record.candidate_manifest.record_sha256 -cne [string]$Candidate.identity.record.record_sha256 -or
      [string]$record.source.commit -cne [string]$Candidate.source.commit -or
      [string]$record.source.tree -cne [string]$Candidate.source.tree -or
      [string]$record.source.package_source_sha256 -cne [string]$Candidate.source.package_source_sha256) {
    throw '[mir42-seal-freeze-authority-binding]'
  }
  if ([string]$record.frozen_dev.ref -cne 'refs/heads/dev' -or
      [string]$record.frozen_dev.commit -cne [string]$Candidate.source.commit -or
      [string]$record.frozen_dev.tree -cne [string]$Candidate.source.tree -or
      [string]$record.promotion_base.remote -cne 'origin' -or
      [string]$record.promotion_base.ref -cne 'refs/heads/main' -or
      [string]$record.promotion_base.commit -notmatch '^[0-9a-f]{40}$') {
    throw '[mir42-seal-freeze-promotion-topology-binding]'
  }
  if ([string]$record.independent_reviewer.identity -cne [string]$Signing.independent_reviewer.identity -or
      [string]$record.independent_reviewer.public_key -cne [string]$Signing.independent_reviewer.public_key -or
      [string]$record.independent_reviewer.fingerprint -cne [string]$Signing.independent_reviewer.fingerprint) {
    throw '[mir42-seal-freeze-reviewer-trust-binding]'
  }
  Assert-MIR42SourceFreezeLedgerSignature -RepoRoot $RepoRoot -Authority $authority -Signing $Signing -SshKeygenPath $SshKeygenPath
  $programme = Get-MIR42LiveProgrammeTransition -RepoRoot $RepoRoot
  if ([string]$record.programme.path -cne [string]$programme.path -or [string]$record.programme.sha256 -cne [string]$programme.sha256 -or
      [string]$record.programme.source_freeze_state -cne [string]$programme.source_freeze_state -or [string]$record.programme.candidate_allocation_state -cne [string]$programme.candidate_allocation_state) {
    throw '[mir42-seal-freeze-programme-binding]'
  }
  return $authority
}

function Get-MIR42IndependentReviewerAttestation {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Independent,
    [Parameter(Mandatory)]$Campaign,
    [Parameter(Mandatory)]$Freeze,
    [Parameter(Mandatory)][string]$SshKeygenPath
  )
  $attestation = Read-MIR42SealRecord -Path $Path -Code 'mir42-seal-reviewer'
  $record = $attestation.record
  Assert-MIR42SealPropertyNames -Value $record -Expected @('schema','kind','status','independent_verification','real_engine_campaign','source_freeze_authority','acceptance_coverage','reviewer','review_signature','record_sha256') -Code 'mir42-seal-reviewer-shape'
  Assert-MIR42SealPropertyNames -Value $record.reviewer -Expected @('identity','public_key','fingerprint') -Code 'mir42-seal-reviewer-identity-shape'
  Assert-MIR42SealPropertyNames -Value $record.review_signature -Expected @('namespace','signature_path','signature_sha256','payload_sha256') -Code 'mir42-seal-reviewer-signature-shape'
  $trusted = $Freeze.record.independent_reviewer
  if ([int]$record.schema -ne 1 -or [string]$record.kind -cne 'MIR42IndependentReviewerAttestationV1' -or
      [string]$record.status -cne 'MIR-4.2-INDEPENDENT-REVIEW-ACCEPTED' -or
      [string]$record.independent_verification.sha256 -cne [string]$Independent.sha256 -or
      [string]$record.independent_verification.record_sha256 -cne [string]$Independent.record.record_sha256 -or
      [string]$record.real_engine_campaign.sha256 -cne [string]$Campaign.sha256 -or
      [string]$record.real_engine_campaign.record_sha256 -cne [string]$Campaign.record.record_sha256 -or
      [string]$record.source_freeze_authority.sha256 -cne [string]$Freeze.sha256 -or
      [string]$record.source_freeze_authority.record_sha256 -cne [string]$Freeze.record.record_sha256 -or
      [string]$record.reviewer.identity -cne [string]$trusted.identity -or
      [string]$record.reviewer.public_key -cne [string]$trusted.public_key -or
      [string]$record.reviewer.fingerprint -cne [string]$trusted.fingerprint -or
      [string]$record.review_signature.namespace -cne 'mir4-independent-review' -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $record.acceptance_coverage) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $Campaign.record.release_acceptance) -or
      [string]$record.review_signature.signature_sha256 -notmatch '^[A-F0-9]{64}$') {
    throw '[mir42-seal-reviewer-binding]'
  }
  $payload = [pscustomobject][ordered]@{
    schema = [int]$record.schema
    kind = [string]$record.kind
    status = [string]$record.status
    independent_verification = $record.independent_verification
    real_engine_campaign = $record.real_engine_campaign
    source_freeze_authority = $record.source_freeze_authority
    acceptance_coverage = $record.acceptance_coverage
    reviewer = $record.reviewer
  }
  $payloadJson = ConvertTo-MIR4BootstrapCanonicalJson -Value $payload
  $payloadSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payloadJson)))
  $signaturePath = [string]$record.review_signature.signature_path
  if ([string]$record.review_signature.payload_sha256 -cne $payloadSha -or -not [IO.Path]::IsPathRooted($signaturePath)) {
    throw '[mir42-seal-reviewer-signature-path]'
  }
  $signaturePath = [IO.Path]::GetFullPath($signaturePath)
  $repo = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))
  if ($signaturePath.StartsWith($repo + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-Path -LiteralPath $signaturePath -PathType Leaf) -or
      (Get-FileHash -LiteralPath $signaturePath -Algorithm SHA256).Hash.ToUpperInvariant() -cne [string]$record.review_signature.signature_sha256) {
    throw '[mir42-seal-reviewer-signature-path]'
  }
  $scratchRoot = Assert-MIR4NoReparseAncestors -Root $RepoRoot -Path (Join-Path $RepoRoot 'build/tmp')
  if (-not (Test-Path -LiteralPath $scratchRoot -PathType Container)) { New-Item -ItemType Directory -Force -Path $scratchRoot | Out-Null }
  $scratch = Assert-MIR4NoReparseAncestors -Root $scratchRoot -Path (Join-Path $scratchRoot ('mir42-review-signature-' + [guid]::NewGuid().ToString('N')))
  try {
    New-Item -ItemType Directory -Force -Path $scratch | Out-Null
    $publicKey = Join-Path $scratch 'reviewer.pub'; $payloadPath = Join-Path $scratch 'review.json'
    [IO.File]::WriteAllText($publicKey, ([string]$trusted.public_key).Trim() + "`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($payloadPath, $payloadJson, [Text.UTF8Encoding]::new($false))
    if ((Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKey) -cne [string]$trusted.fingerprint -or
        -not (Test-MIR4OpenSshSignatureV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $publicKey -Identity ([string]$trusted.identity) -Namespace 'mir4-independent-review' -PayloadPath $payloadPath -SignaturePath $signaturePath -ScratchRoot (Join-Path $scratch 'verify'))) {
      throw '[mir42-seal-reviewer-signature-verification]'
    }
  } finally {
    if (Test-Path -LiteralPath $scratch) { Remove-MIR4BuildTree -OutputRoot $scratchRoot -Path $scratch }
  }
  return $attestation
}

function Get-MIR42FourTargetTechnicalSealReadiness {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [string]$QualificationPath='',
    [string]$RealEngineCampaignPath='',
    [string]$IndependentVerificationPath='',
    [string]$SigningCeremonyPath='',
    [string]$T16TrustRootPath='',
    [string]$OperatorTrustSourcePath='',
    [string]$T16ProtectedRootPath='',
    [string]$T16ImmutableAnchorPath='',
    [string]$T16ApprovedOwnerSid='',
    [string[]]$T16ApprovedMutationSids=@(),
    [string]$SourceFreezeAuthorityPath='',
    [string]$ReviewerAttestationPath='',
    [string]$SshKeygenPath=''
  )
  $repo = (Resolve-Path -LiteralPath $RepoRoot).Path
  $checks = [ordered]@{}
  $blockers = [Collections.Generic.List[string]]::new()
  $state = [ordered]@{candidate=$null;programme=$null;qualification=$null;campaign=$null;independent=$null;t16_acl_contract=$null;t16_trust_root=$null;signing=$null;freeze=$null;reviewer=$null}
  try { $state.candidate = Get-MIR42ExactFourTargetCandidate -RepoRoot $repo -CandidateManifestPath $CandidateManifestPath; $checks.candidate = $true } catch { $checks.candidate = $false; $blockers.Add($_.Exception.Message) }
  if ($checks.candidate) { try { $state.programme = Get-MIR42LiveProgrammeTransition -RepoRoot $repo; $checks.programme = $true } catch { $checks.programme = $false; $blockers.Add($_.Exception.Message) } } else { $checks.programme = $false; $blockers.Add('[mir42-seal-programme-unavailable]') }
  if ($checks.candidate -and -not [string]::IsNullOrWhiteSpace($QualificationPath)) { try { $state.qualification = Get-MIR42ExactQualificationReceipt -Path $QualificationPath -Candidate $state.candidate; $checks.qualification = $true } catch { $checks.qualification = $false; $blockers.Add($_.Exception.Message) } } else { $checks.qualification = $false; $blockers.Add('[mir42-seal-qualification-missing]') }
  if ($checks.qualification -and -not [string]::IsNullOrWhiteSpace($RealEngineCampaignPath)) { try { $state.campaign = Get-MIR42RealEngineCandidateCampaign -RepoRoot $repo -Path $RealEngineCampaignPath -Candidate $state.candidate -Reconciliation $state.qualification; $checks.campaign = $true } catch { $checks.campaign = $false; $blockers.Add($_.Exception.Message) } } else { $checks.campaign = $false; $blockers.Add('[mir42-seal-real-engine-campaign-missing]') }
  if ($checks.qualification -and -not [string]::IsNullOrWhiteSpace($IndependentVerificationPath)) { try { $state.independent = Get-MIR42ExactIndependentVerificationReceipt -Path $IndependentVerificationPath -Candidate $state.candidate -Qualification $state.qualification; $checks.independent = $true } catch { $checks.independent = $false; $blockers.Add($_.Exception.Message) } } else { $checks.independent = $false; $blockers.Add('[mir42-seal-independent-missing]') }
  if (-not [string]::IsNullOrWhiteSpace($T16ApprovedOwnerSid) -and @($T16ApprovedMutationSids).Count -gt 0) { try { $state.t16_acl_contract = New-MIR42T16AclContract -ApprovedOwnerSid $T16ApprovedOwnerSid -ApprovedMutationSids $T16ApprovedMutationSids; $checks.t16_acl_contract = $true } catch { $checks.t16_acl_contract = $false; $blockers.Add($_.Exception.Message) } } else { $checks.t16_acl_contract = $false; $blockers.Add('[mir42-seal-t16-acl-contract-human-input-required]') }
  if ($checks.t16_acl_contract -and -not [string]::IsNullOrWhiteSpace($T16TrustRootPath) -and -not [string]::IsNullOrWhiteSpace($OperatorTrustSourcePath) -and -not [string]::IsNullOrWhiteSpace($T16ProtectedRootPath) -and -not [string]::IsNullOrWhiteSpace($T16ImmutableAnchorPath) -and -not [string]::IsNullOrWhiteSpace($SshKeygenPath)) { try { $state.t16_trust_root = Get-MIR42ExternalT16LedgerTrustRoot -RepoRoot $repo -T16TrustRootPath $T16TrustRootPath -OperatorTrustSourcePath $OperatorTrustSourcePath -ProtectedRootPath $T16ProtectedRootPath -ImmutableAnchorPath $T16ImmutableAnchorPath -AclContract $state.t16_acl_contract -SshKeygenPath $SshKeygenPath; $checks.t16_trust_root = $true } catch { $checks.t16_trust_root = $false; $blockers.Add($_.Exception.Message) } } else { $checks.t16_trust_root = $false; $blockers.Add('[mir42-seal-external-t16-trust-root-or-protected-root-or-immutable-anchor-or-verifier-missing]') }
  if ($checks.t16_trust_root -and -not [string]::IsNullOrWhiteSpace($SigningCeremonyPath)) { try { $state.signing = Get-MIR42ProtectedSigningCeremony -RepoRoot $repo -Path $SigningCeremonyPath -T16TrustRoot $state.t16_trust_root; $checks.signing = $true } catch { $checks.signing = $false; $blockers.Add($_.Exception.Message) } } else { $checks.signing = $false; $blockers.Add('[mir42-seal-signing-or-external-t16-trust-root-missing]') }
  if ($checks.candidate -and $checks.signing -and -not [string]::IsNullOrWhiteSpace($SourceFreezeAuthorityPath) -and -not [string]::IsNullOrWhiteSpace($SshKeygenPath)) { try { $state.freeze = Get-MIR42SourceFreezeAuthority -RepoRoot $repo -Path $SourceFreezeAuthorityPath -Candidate $state.candidate -Signing $state.signing -SshKeygenPath $SshKeygenPath; $checks.freeze = $true } catch { $checks.freeze = $false; $blockers.Add($_.Exception.Message) } } else { $checks.freeze = $false; $blockers.Add('[mir42-seal-freeze-authority-or-verifier-missing]') }
  if ($checks.qualification -and $checks.campaign -and $checks.independent -and $checks.freeze -and -not [string]::IsNullOrWhiteSpace($ReviewerAttestationPath) -and -not [string]::IsNullOrWhiteSpace($SshKeygenPath)) { try { $state.reviewer = Get-MIR42IndependentReviewerAttestation -RepoRoot $repo -Path $ReviewerAttestationPath -Independent $state.independent -Campaign $state.campaign -Freeze $state.freeze -SshKeygenPath $SshKeygenPath; $checks.reviewer = $true } catch { $checks.reviewer = $false; $blockers.Add($_.Exception.Message) } } else { $checks.reviewer = $false; $blockers.Add('[mir42-seal-independent-reviewer-attestation-missing]') }
  $ready = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value }).Count -eq 0
  return [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetTechnicalSealReadinessV1'
    status = if ($ready) { 'MIR-4.2-FOUR-TARGET-TECHNICAL-SEAL-READY' } else { 'MIR-4.2-FOUR-TARGET-TECHNICAL-SEAL-BLOCKED' }
    checks = [pscustomobject]$checks
    blockers = @($blockers | Select-Object -Unique)
    technical_seal_authorized = $ready
    protected_main_promotion_authorized = $false
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
    _state = [pscustomobject]$state
  }
}

function Write-MIR42NormalizedRecord {
  param([Parameter(Mandatory)]$Record,[Parameter(Mandatory)][string]$OutputPath,[Parameter(Mandatory)][string]$Code)
  # Ordered dictionaries and PSCustomObjects do not always round-trip to the
  # same canonical representation. Hash the parsed canonical form that will
  # actually be persisted, then prove the written receipt can be read back.
  $normalized = (ConvertTo-MIR4BootstrapCanonicalJson -Value $Record | ConvertFrom-Json -Depth 100 -DateKind String)
  $normalized.record_sha256 = ''
  $normalized.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $normalized
  Write-MIR4BootstrapRecord -Record $normalized -Path $OutputPath | Out-Null
  $readback = Read-MIR42SealRecord -Path $OutputPath -Code $Code
  if (-not (Test-MIR4BootstrapRecordHash -Record $readback.record) -or
      (ConvertTo-MIR4BootstrapCanonicalJson -Value $readback.record) -cne (ConvertTo-MIR4BootstrapCanonicalJson -Value $normalized)) {
    throw "[$Code-roundtrip]"
  }
  return $readback.record
}

function New-MIR42FourTargetTechnicalSeal {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$CandidateManifestPath,
    [AllowEmptyString()][string]$QualificationPath='',
    [AllowEmptyString()][string]$RealEngineCampaignPath='',
    [AllowEmptyString()][string]$IndependentVerificationPath='',
    [AllowEmptyString()][string]$SigningCeremonyPath='',
    [AllowEmptyString()][string]$T16TrustRootPath='',
    [AllowEmptyString()][string]$OperatorTrustSourcePath='',
    [AllowEmptyString()][string]$T16ProtectedRootPath='',
    [AllowEmptyString()][string]$T16ImmutableAnchorPath='',
    [AllowEmptyString()][string]$T16ApprovedOwnerSid='',
    [AllowEmptyCollection()][string[]]$T16ApprovedMutationSids=@(),
    [AllowEmptyString()][string]$SourceFreezeAuthorityPath='',
    [AllowEmptyString()][string]$ReviewerAttestationPath='',
    [AllowEmptyString()][string]$SshKeygenPath='',
    [Parameter(Mandatory)][string]$OutputPath
  )
  $readiness = Get-MIR42FourTargetTechnicalSealReadiness -RepoRoot $RepoRoot -CandidateManifestPath $CandidateManifestPath `
    -QualificationPath $QualificationPath -RealEngineCampaignPath $RealEngineCampaignPath -IndependentVerificationPath $IndependentVerificationPath `
    -SigningCeremonyPath $SigningCeremonyPath -T16TrustRootPath $T16TrustRootPath -OperatorTrustSourcePath $OperatorTrustSourcePath -T16ProtectedRootPath $T16ProtectedRootPath -T16ImmutableAnchorPath $T16ImmutableAnchorPath -T16ApprovedOwnerSid $T16ApprovedOwnerSid -T16ApprovedMutationSids $T16ApprovedMutationSids `
    -SourceFreezeAuthorityPath $SourceFreezeAuthorityPath -ReviewerAttestationPath $ReviewerAttestationPath -SshKeygenPath $SshKeygenPath
  if (-not [bool]$readiness.technical_seal_authorized) { throw "[mir42-seal-not-authorized] $($readiness.blockers -join '; ')" }
  $state = $readiness._state
  $seal = [pscustomobject][ordered]@{
    schema = 1
    kind = 'MIR42FourTargetTechnicalSealV1'
    status = 'MIR-4.2-FOUR-TARGET-TECHNICALLY-SEALED-AWAITING-PROTECTED-MAIN-PR'
    source = $state.candidate.source
    candidate_manifest = [ordered]@{sha256=[string]$state.candidate.identity.sha256;record_sha256=[string]$state.candidate.identity.record.record_sha256}
    qualification = [ordered]@{sha256=[string]$state.qualification.sha256;record_sha256=[string]$state.qualification.record.record_sha256}
    real_engine_campaign = [ordered]@{sha256=[string]$state.campaign.sha256;record_sha256=[string]$state.campaign.record.record_sha256}
    independent_verification = [ordered]@{sha256=[string]$state.independent.sha256;record_sha256=[string]$state.independent.record.record_sha256}
    t16_acl_contract = [ordered]@{owner_sid=[string]$state.t16_acl_contract.record.owner_sid;mutation_sids=@($state.t16_acl_contract.record.mutation_sids);custodian_sid_set_sha256=[string]$state.t16_acl_contract.custodian_sid_set_sha256}
    t16_protected_root = [string]$state.t16_trust_root.protected_root
    t16_immutable_anchor = [string]$state.t16_trust_root.immutable_anchor
    t16_ledger_trust_root = [ordered]@{path=[string]$state.t16_trust_root.path;sha256=[string]$state.t16_trust_root.sha256;record_sha256=[string]$state.t16_trust_root.record.record_sha256}
    signing_ceremony = [ordered]@{sha256=[string]$state.signing.sha256;record_sha256=[string]$state.signing.record.record_sha256}
    source_freeze_authority = [ordered]@{sha256=[string]$state.freeze.sha256;record_sha256=[string]$state.freeze.record.record_sha256}
    independent_reviewer_attestation = [ordered]@{sha256=[string]$state.reviewer.sha256;record_sha256=[string]$state.reviewer.record.record_sha256}
    targets = @($state.candidate.targets)
    protected_main_promotion_authorized = $false
    human_go_required_after_main_readback = $true
    tagging_authorized = $false
    publication_authorized = $false
    record_sha256 = ''
  }
  return (Write-MIR42NormalizedRecord -Record $seal -OutputPath $OutputPath -Code 'mir42-seal-output')
}
