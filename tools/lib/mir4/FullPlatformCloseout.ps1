$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'BootstrapMaterialization.ps1')

function Get-MIR4FullPlatformFileSha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function New-MIR4FullPlatformEvidenceRef {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Role
  )
  $full = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $RepoRoot $Path }
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "[mir4-full-platform-evidence-missing] $Path" }
  $relative = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetRelativePath($RepoRoot, $full).Replace('\','/') } else { $Path.Replace('\','/') }
  return [pscustomobject][ordered]@{path=$relative;sha256=Get-MIR4FullPlatformFileSha256 $full;role=$Role}
}

function New-MIR4FullPlatformRecord {
  param(
    [Parameter(Mandatory)]$SourceIdentity,
    [Parameter(Mandatory)][string]$Kind,
    [Parameter(Mandatory)][string]$Status,
    [Parameter(Mandatory)][ValidateSet('stable-governance','stable-shadow','preview','shadow','experimental','blocked-with-evidence','mixed')][string]$Maturity,
    [Parameter(Mandatory)][string]$AuthorityId,
    [Parameter(Mandatory)][ValidateSet('canonical','read-only-composition','evidence-only-aggregation','external-independent-audit')][string]$AuthorityMode,
    [Parameter(Mandatory)][string[]]$AuthoritySourcePaths,
    [Parameter(Mandatory)][object[]]$EvidenceRefs,
    [Parameter(Mandatory)]$Payload
  )
  $record = [pscustomobject][ordered]@{
    schema = 1
    kind = $Kind
    status = $Status
    source_identity = $SourceIdentity
    maturity = $Maturity
    authority = [ordered]@{id=$AuthorityId;mode=$AuthorityMode;source_paths=@($AuthoritySourcePaths)}
    package_visible = $false
    public_release_proof_exists = $false
    evidence_refs = @($EvidenceRefs)
    payload = $Payload
    record_sha256 = ''
  }
  $record.record_sha256 = Get-MIR4BootstrapRecordSha256 -Record $record
  return $record
}

function Test-MIR4FullPlatformAuditInput {
  param(
    [Parameter(Mandatory)]$Audit,
    [Parameter(Mandatory)]$SourceIdentity
  )
  if ([int]$Audit.schema -ne 1 -or [string]$Audit.kind -cne 'MIR4LunaAuditInputV1' -or
      [string]$Audit.programme_id -cne 'M4C02-09-24H' -or [string]$Audit.auditor_model -cne 'gpt-5.6-luna' -or
      [string]$Audit.audit_scope.commit -cne [string]$SourceIdentity.commit -or
      [string]$Audit.audit_scope.tree -cne [string]$SourceIdentity.tree -or
      [string]$Audit.decision -notin @('ACCEPT','REJECT') -or
      [string]$Audit.merge_recommendation -notin @('APPROVE','DO-NOT-MERGE')) { return $false }
  if ([string]$Audit.decision -eq 'ACCEPT' -and (@($Audit.b0_findings).Count -ne 0 -or [string]$Audit.merge_recommendation -cne 'APPROVE')) { return $false }
  foreach ($reference in @($Audit.evidence_refs)) {
    if ([string]::IsNullOrWhiteSpace([string]$reference.path) -or [string]$reference.sha256 -notmatch '^[A-F0-9]{64}$' -or [string]::IsNullOrWhiteSpace([string]$reference.role)) { return $false }
  }
  return $true
}

function Get-MIR4FullPlatformBlockers {
  return @(
    [pscustomobject][ordered]@{id='BLOCKED-HUMAN-SECRET-INPUT';scope=@('release-governance','source-freeze','production-signing','release-ledger');owner='maintainer-protected-secret-authority';required_input='Protected signing-key passphrase or an approved existing protected signing authority.';workaround_permitted=$false},
    [pscustomobject][ordered]@{id='BLOCKED-INDEPENDENT-PRODUCTION-CONSUMER';scope=@('module-ecosystem','reference-consumer','future-successor-host');owner='independent-external-consumer';required_input='An independently produced real extension or successor host and its conformance evidence.';workaround_permitted=$false},
    [pscustomobject][ordered]@{id='BLOCKED-EXACT-TARGET-PROCESSIR-SNAPSHOT';scope=@('processir-parity','synthesis-graduation','assurance-slice');owner='exact-target-runtime-observation';required_input='A governed exact-target ProcessIR snapshot from the real target pipeline.';workaround_permitted=$false},
    [pscustomobject][ordered]@{id='BLOCKED-MISSING-EXACT-ENGINE-f018';scope=@('historical-f018-runtime');owner='local-engine-custody';required_input='A lawful exact Factorio 0.18 engine installation under the preserved historical engine root.';workaround_permitted=$false},
    [pscustomobject][ordered]@{id='BLOCKED-MISSING-TRUSTED-TIMING-CAPACITY-EVIDENCE';scope=@('official-release-budget');owner='trusted-campaign-observation';required_input='Trusted timing and capacity observations for the governed release campaign.';workaround_permitted=$false},
    [pscustomobject][ordered]@{id='BLOCKED-MUSEUM-RIGHTS-CUSTODY-RESTORE-CLOSURE';scope=@('museum-products','museum-support-claims');owner='maintainer-rights-and-custody-authority';required_input='Explicit rights, custody, restore, and redistribution closure for each museum target.';workaround_permitted=$false},
    [pscustomobject][ordered]@{id='BLOCKED-FUTURE-INDEPENDENT-PRODUCTION-HOST';scope=@('successor-host-production-claim');owner='future-independent-host';required_input='An independently implemented production host and governed evidence packet.';workaround_permitted=$false}
  )
}
