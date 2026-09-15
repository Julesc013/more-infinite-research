[CmdletBinding()]
param([string]$RepoRoot = '', [switch]$Check)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path } else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }
. (Join-Path $RepoRoot 'tools/mir/application/package/HistoricalSourceAuthority.ps1')
return Assert-MIR4PinnedHistoricalSourceAuthority -RepoRoot $RepoRoot -ReceiptPath 'releases/migrations/MIR4-M42-02-Stream-Compiler-DecompositionV1.json' -SchemaPath 'contracts/repository/mir4-m42-02-stream-compiler-decomposition-v1.schema.json' -Kind 'MIR4M4202StreamCompilerDecompositionV1' -AuthorityId 'M42-02-stream-compiler'
