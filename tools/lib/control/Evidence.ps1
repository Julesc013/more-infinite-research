function Get-MIRCPEvidenceRoot {
  param(
    [string]$RepoRoot = "",
    [string]$Root = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  if (-not [string]::IsNullOrWhiteSpace($Root)) {
    if ([IO.Path]::IsPathRooted($Root)) { return [IO.Path]::GetFullPath($Root) }
    return [IO.Path]::GetFullPath((Join-Path $repo $Root))
  }
  $policy = Get-MIRCPPolicy -RepoRoot $repo
  $relative = Resolve-MIRCPPathToken -Path ([string]$policy.outputs.evidence_store) -RepoRoot $repo
  return [IO.Path]::GetFullPath((Join-Path $repo $relative))
}

function Initialize-MIRCPEvidenceStore {
  param(
    [string]$RepoRoot = "",
    [string]$Root = ""
  )
  $store = Get-MIRCPEvidenceRoot -RepoRoot $RepoRoot -Root $Root
  foreach ($relative in @("objects/sha256", "indexes", "leases", "quarantine")) {
    $path = Join-Path $store $relative
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $path) }
  }
  return $store
}

function Get-MIRCPEvidenceObjectPath {
  param(
    [Parameter(Mandatory)][string]$Digest,
    [string]$RepoRoot = "",
    [string]$Root = ""
  )
  if ($Digest -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid evidence object digest: $Digest" }
  $store = Get-MIRCPEvidenceRoot -RepoRoot $RepoRoot -Root $Root
  $upper = $Digest.ToUpperInvariant()
  return Join-Path (Join-Path (Join-Path $store "objects/sha256") $upper.Substring(0, 2)) "$upper.json"
}

function New-MIRCPEvidenceObject {
  param(
    [ValidateSet("observation", "evaluation", "task-result", "execution-manifest", "aggregate", "seal", "artifact-descriptor")][string]$Kind,
    [Parameter(Mandatory)][string]$ContextDigest,
    [Parameter(Mandatory)][string]$IdentityKey,
    [Parameter(Mandatory)]$Subject,
    [Parameter(Mandatory)]$Producer,
    [Parameter(Mandatory)]$Payload,
    [string[]]$Links = @(),
    [int]$ObjectAbi = 1
  )
  foreach ($digest in @($ContextDigest, $IdentityKey) + @($Links)) {
    if ([string]$digest -notmatch '^[0-9A-Fa-f]{64}$') { throw "Evidence object contains invalid digest: $digest" }
  }
  return [pscustomobject][ordered]@{
    schema = 1
    kind = $Kind
    object_abi = $ObjectAbi
    context_digest = $ContextDigest.ToUpperInvariant()
    identity_key = $IdentityKey.ToUpperInvariant()
    subject = $Subject
    producer = $Producer
    payload = $Payload
    links = @($Links | ForEach-Object { $_.ToUpperInvariant() } | Sort-Object -Unique)
  }
}

function Write-MIRCPEvidenceObject {
  param(
    [Parameter(Mandatory)]$Object,
    [string]$RepoRoot = "",
    [string]$Root = ""
  )
  $store = Initialize-MIRCPEvidenceStore -RepoRoot $RepoRoot -Root $Root
  $content = (ConvertTo-MIRCPCanonicalJson -Value $Object) + "`n"
  $digest = Get-MIRCPSha256Text -Value $content
  $path = Get-MIRCPEvidenceObjectPath -Digest $digest -RepoRoot $RepoRoot -Root $store
  $parent = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $parent) }
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    $existing = (Get-Content -Raw -LiteralPath $path).Replace("`r`n", "`n")
    if ($existing -cne $content) { throw "Content-addressed evidence collision at $digest." }
  } else {
    [IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false))
  }
  return [pscustomobject][ordered]@{digest=$digest; path=$path; store=$store}
}

function Get-MIRCPWindowsAlternateDataStreams {
  param([Parameter(Mandatory)][string]$Path)

  if ($env:OS -ne "Windows_NT") { return @() }
  if (-not ("MIR.NativeStreams" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MIR {
  public static class NativeStreams {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct StreamData {
      public long StreamSize;
      [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 296)] public string StreamName;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr FindFirstStreamW(string fileName, int infoLevel, out StreamData data, int flags);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] public static extern bool FindNextStreamW(IntPtr handle, out StreamData data);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] public static extern bool FindClose(IntPtr handle);
  }
}
'@
  }
  $fullPath = [IO.Path]::GetFullPath($Path)
  $nativePath = if ($fullPath.StartsWith("\\", [StringComparison]::Ordinal)) {
    "\\?\UNC\" + $fullPath.Substring(2)
  } else {
    "\\?\" + $fullPath
  }
  $data = New-Object MIR.NativeStreams+StreamData
  $handle = [MIR.NativeStreams]::FindFirstStreamW($nativePath, 0, [ref]$data, 0)
  $invalidHandle = [IntPtr](-1)
  if ($handle -eq $invalidHandle) {
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw [ComponentModel.Win32Exception]::new($errorCode, "Unable to enumerate alternate data streams for '$fullPath'.")
  }
  $streams = [Collections.Generic.List[string]]::new()
  try {
    do {
      if ([string]$data.StreamName -ne '::$DATA') { $streams.Add([string]$data.StreamName) }
      $hasNext = [MIR.NativeStreams]::FindNextStreamW($handle, [ref]$data)
    } while ($hasNext)
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($errorCode -notin @(18, 38)) {
      throw [ComponentModel.Win32Exception]::new($errorCode, "Unable to complete alternate data stream enumeration for '$fullPath'.")
    }
  } finally {
    [void][MIR.NativeStreams]::FindClose($handle)
  }
  return @($streams)
}

function Import-MIRCPWorkerEvidenceObjects {
  param(
    [Parameter(Mandatory)][string]$WorkerRoot,
    [string]$EvidenceRoot = "",
    [string]$RepoRoot = ""
  )

  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $workers = if ([IO.Path]::IsPathRooted($WorkerRoot)) { [IO.Path]::GetFullPath($WorkerRoot) } else { [IO.Path]::GetFullPath((Join-Path $repo $WorkerRoot)) }
  $repoBoundary = [IO.Path]::GetFullPath($repo).TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
  if (-not $workers.StartsWith($repoBoundary, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Control-plane worker artifacts must stay inside the repository workspace."
  }
  if (-not (Test-Path -LiteralPath $workers -PathType Container)) {
    return [pscustomobject][ordered]@{schema=1;status="incomplete";worker_root=$workers;artifacts=0;objects=0;ignored=0}
  }

  $artifactDirectories = @(Get-ChildItem -LiteralPath $workers -Directory -Force | Sort-Object Name)
  if ($artifactDirectories.Count -gt 512) { throw "Control-plane worker artifact count exceeds the ingestion limit." }
  $imported = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $ignored = 0
  [long]$expandedBytes = 0
  $entryCount = 0
  foreach ($artifact in $artifactDirectories) {
    if (($artifact.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Control-plane worker artifact is a symlink or reparse point: $($artifact.Name)"
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $artifact.FullName -Recurse -Force)) {
      $entryCount++
      if ($entryCount -gt 100000) { throw "Control-plane worker artifacts exceed the entry-count limit." }
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Control-plane worker artifacts contain a symlink or reparse point: $($item.FullName)"
      }
      if ($item.PSIsContainer) { continue }
      if ($item -isnot [IO.FileInfo]) { throw "Control-plane worker artifacts contain an unsupported filesystem entry." }
      if ($env:OS -eq "Windows_NT") {
        $alternateStreams = @(Get-MIRCPWindowsAlternateDataStreams -Path $item.FullName)
        if ($alternateStreams.Count -gt 0) {
          throw "Control-plane worker artifacts contain an NTFS alternate data stream: $($item.FullName)"
        }
      }
      if ([long]$item.Length -gt 536870912) { throw "Control-plane worker artifact contains an oversized file: $($item.FullName)" }
      $expandedBytes += [long]$item.Length
      if ($expandedBytes -gt 4294967296) { throw "Control-plane worker artifacts exceed the expanded-byte limit." }
      $relative = [IO.Path]::GetRelativePath($artifact.FullName, $item.FullName).Replace("\", "/")
      if ($relative -notmatch '(?:^|/)artifacts/evidence/objects/sha256/[0-9A-Fa-f]{2}/([0-9A-Fa-f]{64})\.json$') {
        $ignored++
        continue
      }
      $declaredDigest = $Matches[1].ToUpperInvariant()
      if ($item.BaseName.ToUpperInvariant() -ne $declaredDigest -or (Get-MIRCPSha256File -Path $item.FullName) -ne $declaredDigest) {
        throw "Control-plane worker evidence object bytes do not match their content address: $relative"
      }
      try { $object = Get-Content -Raw -LiteralPath $item.FullName | ConvertFrom-Json }
      catch { throw "Control-plane worker evidence object is invalid JSON: $relative" }
      if ([int]$object.schema -ne 1 -or [string]$object.kind -notin @("observation", "evaluation", "task-result", "execution-manifest", "aggregate", "seal", "artifact-descriptor")) {
        throw "Control-plane worker evidence object has an invalid schema or kind: $relative"
      }
      $destination = Get-MIRCPEvidenceObjectPath -Digest $declaredDigest -RepoRoot $repo -Root $EvidenceRoot
      [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination))
      if (Test-Path -LiteralPath $destination -PathType Leaf) {
        if ((Get-MIRCPSha256File -Path $destination) -ne $declaredDigest) { throw "Control-plane evidence store contains a conflicting immutable object: $declaredDigest" }
      } else {
        Copy-Item -LiteralPath $item.FullName -Destination $destination
      }
      [void](Read-MIRCPEvidenceObject -Digest $declaredDigest -RepoRoot $repo -Root $EvidenceRoot)
      [void]$imported.Add($declaredDigest)
    }
  }
  return [pscustomobject][ordered]@{
    schema=1
    status="passed"
    worker_root=$workers
    artifacts=$artifactDirectories.Count
    objects=$imported.Count
    ignored=$ignored
    expanded_bytes=$expandedBytes
  }
}

function Get-MIRCPEvidenceRevocationAuthority {
  param([string]$RepoRoot = "")
  return Read-MIRCPJson -Path ".mir/control-plane/evidence-revocations.json" -RepoRoot $RepoRoot
}

function Test-MIRCPEvidenceRevocation {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Digest,
    $Authority = $null,
    [string]$RepoRoot = ""
  )
  if ($null -eq $Authority) { $Authority = Get-MIRCPEvidenceRevocationAuthority -RepoRoot $RepoRoot }
  foreach ($rule in @($Authority.rules | Where-Object active)) {
    $matched = switch ([string]$rule.type) {
      "object-digest-set" { @($rule.digests | ForEach-Object { [string]$_ }) -contains $Digest }
      "context-digest-set" { @($rule.digests | ForEach-Object { [string]$_ }) -contains [string]$Object.context_digest }
      "producer-abi" { [int]$Object.producer.abi -eq [int]$rule.abi }
      "evaluator-abi" { $null -ne $Object.payload.PSObject.Properties["evaluation_abi"] -and [int]$Object.payload.evaluation_abi -eq [int]$rule.abi }
      "canonicalization-abi" { $null -ne $Object.payload.PSObject.Properties["canonicalization_abi"] -and [int]$Object.payload.canonicalization_abi -eq [int]$rule.abi }
      "produced-time-range" {
        if ($null -eq $Object.producer.PSObject.Properties["produced_at"]) { $false } else {
          $value = [datetimeoffset]$Object.producer.produced_at
          $from = [datetimeoffset]$rule.from
          $through = [datetimeoffset]$rule.through
          $value -ge $from -and $value -le $through
        }
      }
      default { throw "Unknown evidence revocation rule type: $($rule.type)" }
    }
    if ($matched) { return [pscustomobject][ordered]@{revoked=$true; rule_id=[string]$rule.id; reason=[string]$rule.reason} }
  }
  return [pscustomobject][ordered]@{revoked=$false; rule_id=""; reason=""}
}

function Read-MIRCPEvidenceObject {
  param(
    [Parameter(Mandatory)][string]$Digest,
    [string]$RepoRoot = "",
    [string]$Root = "",
    [switch]$AllowRevoked
  )
  $path = Get-MIRCPEvidenceObjectPath -Digest $Digest -RepoRoot $RepoRoot -Root $Root
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Evidence object not found: $Digest" }
  $actual = Get-MIRCPSha256File -Path $path
  if ($actual -ne $Digest.ToUpperInvariant()) { throw "Evidence object bytes do not match address $Digest." }
  $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
  if ([int]$record.schema -ne 1 -or [string]$record.kind -notin @("observation", "evaluation", "task-result", "execution-manifest", "aggregate", "seal", "artifact-descriptor")) { throw "Evidence object schema or kind is invalid: $Digest" }
  $revocation = Test-MIRCPEvidenceRevocation -Object $record -Digest $actual -RepoRoot $RepoRoot
  if ([bool]$revocation.revoked -and -not $AllowRevoked) { throw "Evidence object $Digest is revoked by $($revocation.rule_id): $($revocation.reason)" }
  return [pscustomobject][ordered]@{digest=$actual; path=$path; object=$record; revocation=$revocation}
}

function Move-MIRCPEvidenceObjectToQuarantine {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Reason,
    [string]$RepoRoot = "",
    [string]$Root = ""
  )
  $store = Get-MIRCPEvidenceRoot -RepoRoot $RepoRoot -Root $Root
  $full = [IO.Path]::GetFullPath($Path)
  $objectsRoot = [IO.Path]::GetFullPath((Join-Path $store "objects/sha256")).TrimEnd('\') + '\'
  if (-not $full.StartsWith($objectsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe evidence quarantine target: $full" }
  $quarantine = Join-Path $store "quarantine"
  if (-not (Test-Path -LiteralPath $quarantine -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $quarantine) }
  $suffix = (Get-MIRCPSha256Text -Value $Reason).Substring(0, 12)
  $destination = Join-Path $quarantine ("$([IO.Path]::GetFileNameWithoutExtension($full))-$suffix.json")
  Move-Item -LiteralPath $full -Destination $destination
  return $destination
}

function Update-MIRCPEvidenceIndex {
  param(
    [string]$RepoRoot = "",
    [string]$Root = "",
    [switch]$QuarantineInvalid
  )
  $store = Initialize-MIRCPEvidenceStore -RepoRoot $RepoRoot -Root $Root
  $rows = [Collections.Generic.List[object]]::new()
  $invalid = [Collections.Generic.List[object]]::new()
  foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $store "objects/sha256") -Filter *.json -File -Recurse | Sort-Object FullName)) {
    try {
      $digest = Get-MIRCPSha256File -Path $file.FullName
      if ($file.BaseName -ne $digest) { throw "object filename does not match byte digest" }
      $record = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
      $revocation = Test-MIRCPEvidenceRevocation -Object $record -Digest $digest -RepoRoot $RepoRoot
      $rows.Add([pscustomobject][ordered]@{
        digest = $digest
        kind = [string]$record.kind
        context_digest = [string]$record.context_digest
        identity_key = [string]$record.identity_key
        task_id = [string]$record.subject.task_id
        target = [string]$record.subject.target
        status = [string]$record.payload.status
        trust_class = [string]$record.producer.trust_class
        object_abi = [int]$record.object_abi
        producer_abi = [int]$record.producer.abi
        evaluation_abi = if ($null -ne $record.payload.PSObject.Properties["evaluation_abi"]) { [int]$record.payload.evaluation_abi } else { 0 }
        canonicalization_abi = if ($null -ne $record.payload.PSObject.Properties["canonicalization_abi"]) { [int]$record.payload.canonicalization_abi } else { 0 }
        revoked = [bool]$revocation.revoked
        revocation_rule = [string]$revocation.rule_id
        valid = $true
      })
    } catch {
      $invalid.Add([pscustomobject][ordered]@{path=$file.FullName; reason=$_.Exception.Message})
      if ($QuarantineInvalid) { [void](Move-MIRCPEvidenceObjectToQuarantine -Path $file.FullName -Reason $_.Exception.Message -RepoRoot $RepoRoot -Root $store) }
    }
  }
  $index = [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-control-plane-v5-rebuildable-evidence-index"
    store = $store
    objects = @($rows | Sort-Object digest)
    invalid = @($invalid)
  }
  $indexPath = Join-Path $store "indexes/objects.json"
  Write-MIRCPJson -Path $indexPath -Value $index -RepoRoot (Get-MIRCPRepoRoot -RepoRoot $RepoRoot)
  return [pscustomobject][ordered]@{path=$indexPath; objects=$rows.Count; invalid=$invalid.Count; index=$index}
}

function Resolve-MIRCPTaskEvidenceAction {
  param(
    [Parameter(Mandatory)]$Task,
    [Parameter(Mandatory)][string]$EffectiveInputSha256,
    [Parameter(Mandatory)][string]$Mode,
    [string]$EvidenceIndex = "",
    [string]$TrustClass = "",
    [string]$RepoRoot = ""
  )
  $repo = Get-MIRCPRepoRoot -RepoRoot $RepoRoot
  $freshness = Read-MIRCPJson -Path ".mir/control-plane/freshness.json" -RepoRoot $repo
  $class = $freshness.classes.PSObject.Properties[[string]$Task.freshness].Value
  if (@($class.modes_forcing_fresh | ForEach-Object { [string]$_ }) -contains $Mode) {
    return [pscustomobject][ordered]@{action="RUN"; reason="freshness class $($Task.freshness) forces $Mode"; object_digest=""; followup=""}
  }
  $runtimeInputs = @($Task.effective_inputs | Where-Object { [string]$_ -in @("prior-release-archive", "factorio-installation", "mod-closure") })
  if ($runtimeInputs.Count -gt 0) {
    return [pscustomobject][ordered]@{action="RUN"; reason="worker-resolved runtime input(s) require execution: $($runtimeInputs -join ', ')"; object_digest=""; followup=""}
  }
  if ([string]::IsNullOrWhiteSpace($EvidenceIndex) -or -not (Test-Path -LiteralPath $EvidenceIndex -PathType Leaf)) {
    return [pscustomobject][ordered]@{action="RUN"; reason="no rebuildable evidence index supplied"; object_digest=""; followup=""}
  }
  $index = Get-Content -Raw -LiteralPath $EvidenceIndex | ConvertFrom-Json
  $matches = @($index.objects | Where-Object {
    [string]$_.kind -eq "task-result" -and [string]$_.task_id -eq [string]$Task.id -and
    [string]$_.identity_key -eq $EffectiveInputSha256 -and [string]$_.status -eq "passed" -and
    ([string]::IsNullOrWhiteSpace($TrustClass) -or [string]$_.trust_class -eq $TrustClass)
  } | Sort-Object digest)
  if ($matches.Count -eq 0) { return [pscustomobject][ordered]@{action="RUN"; reason="no exact passing evidence object"; object_digest=""; followup=""} }
  $valid = @($matches | Where-Object { [bool]$_.valid -and -not [bool]$_.revoked })
  if ($valid.Count -eq 0) {
    return [pscustomobject][ordered]@{action="INVALID"; reason="matching evidence is invalid or revoked"; object_digest=[string]$matches[0].digest; followup="RUN"}
  }
  $requiredAbi = [int](Get-MIRCPPolicy -RepoRoot $repo).component_abis.evidence_store
  $abiMatches = @($valid | Where-Object { [int]$_.object_abi -eq $requiredAbi })
  if ($abiMatches.Count -eq 0) { return [pscustomobject][ordered]@{action="INVALID"; reason="matching evidence object ABI is stale"; object_digest=[string]$valid[0].digest; followup="RUN"} }
  return [pscustomobject][ordered]@{action="REUSE"; reason="exact unrevoked passing evidence object"; object_digest=[string]$abiMatches[0].digest; followup=""}
}

function Acquire-MIRCPEvidenceLease {
  param(
    [Parameter(Mandatory)][string]$IdentityKey,
    [ValidateSet("process", "ci-job")][string]$Scope = "process",
    [int]$TtlMinutes = 60,
    $CiIdentity = $null,
    [string]$RepoRoot = "",
    [string]$Root = ""
  )
  if ($IdentityKey -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid lease identity key." }
  $store = Initialize-MIRCPEvidenceStore -RepoRoot $RepoRoot -Root $Root
  $path = Join-Path $store "leases/$($IdentityKey.ToUpperInvariant()).json"
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    $existing = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    if (Test-MIRCPEvidenceLeaseActive -Lease $existing) {
      return [pscustomobject][ordered]@{disposition="ADOPT"; path=$path; lease=$existing}
    }
  }
  $process = Get-Process -Id $PID
  $owner = if ($Scope -eq "process") {
    [pscustomobject][ordered]@{host=[Environment]::MachineName; pid=$PID; process_start_at=$process.StartTime.ToUniversalTime().ToString("o")}
  } else {
    if ($null -eq $CiIdentity) { throw "ci-job leases require an explicit CI identity." }
    $CiIdentity
  }
  $lease = [pscustomobject][ordered]@{
    schema = 1
    identity_key = $IdentityKey.ToUpperInvariant()
    scope = $Scope
    owner = $owner
    acquired_at = [datetimeoffset]::UtcNow.ToString("o")
    expires_at = [datetimeoffset]::UtcNow.AddMinutes($TtlMinutes).ToString("o")
  }
  Write-MIRCPJson -Path $path -Value $lease -RepoRoot (Get-MIRCPRepoRoot -RepoRoot $RepoRoot)
  return [pscustomobject][ordered]@{disposition="ACQUIRE"; path=$path; lease=$lease}
}

function Test-MIRCPEvidenceLeaseActive {
  param([Parameter(Mandatory)]$Lease)
  if ([datetimeoffset]$Lease.expires_at -le [datetimeoffset]::UtcNow) { return $false }
  if ([string]$Lease.scope -eq "process") {
    if ([string]$Lease.owner.host -ne [Environment]::MachineName) { return $false }
    try { $ownerProcess = Get-Process -Id ([int]$Lease.owner.pid) -ErrorAction Stop } catch { return $false }
    $actualStart = $ownerProcess.StartTime.ToUniversalTime().ToString("o")
    $expectedStart = ([datetimeoffset]$Lease.owner.process_start_at).UtcDateTime.ToString("o")
    return $actualStart -eq $expectedStart
  }
  if ([string]$Lease.scope -eq "ci-job") {
    foreach ($field in @("run_id", "run_attempt", "job", "host", "trust_class")) {
      if ($null -eq $Lease.owner.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$Lease.owner.$field)) { return $false }
    }
    return $true
  }
  return $false
}

function New-MIRCPExecutionManifest {
  param(
    [Parameter(Mandatory)][string]$ContextDigest,
    [Parameter(Mandatory)][string]$PlanId,
    [Parameter(Mandatory)]$Producer,
    [Parameter(Mandatory)][object[]]$TaskResults,
    [ValidateSet("passed", "failed", "incomplete")][string]$Status
  )
  $objects = @($TaskResults | ForEach-Object { [string]$_.object_digest } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
  return [pscustomobject][ordered]@{
    schema = 1
    authority = "mir-control-plane-v5-execution-manifest"
    context_digest = $ContextDigest.ToUpperInvariant()
    plan_id = $PlanId.ToUpperInvariant()
    producer = $Producer
    objects = $objects
    task_results = @($TaskResults)
    status = $Status
  }
}
