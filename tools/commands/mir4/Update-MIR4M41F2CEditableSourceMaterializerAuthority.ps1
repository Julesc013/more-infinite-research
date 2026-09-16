[CmdletBinding()]
param([string]$RepoRoot = '', [switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path } else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }

. (Join-Path $RepoRoot 'tools/mir/application/package/HistoricalSourceAuthority.ps1')

# This formerly generated M41-F2C evidence.  It now only verifies that frozen
# receipt while confirming that current authority comes from source/ composition.
return Assert-MIR4PinnedHistoricalSourceAuthority -RepoRoot $RepoRoot -ReceiptPath 'releases/migrations/MIR4-M41-F2C-Editable-Source-Materializer-Authority-EvolutionV1.json' -SchemaPath 'contracts/repository/mir4-m41-f2c-editable-source-materializer-authority-evolution-v1.schema.json' -Kind 'MIR4M41F2CEditableSourceMaterializerAuthorityEvolutionV1' -AuthorityId 'M41-F2C-editable-source-materializer'
