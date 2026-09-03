Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot '../../mir/application/release/F210QualificationPolicy.ps1')

. (Join-Path $PSScriptRoot 'pre-freeze-release/Common.ps1')
. (Join-Path $PSScriptRoot 'pre-freeze-release/PolicyLocks.ps1')
. (Join-Path $PSScriptRoot 'pre-freeze-release/AuthorityState.ps1')
. (Join-Path $PSScriptRoot 'pre-freeze-release/AuthorityValidation.ps1')
. (Join-Path $PSScriptRoot 'pre-freeze-release/ReleaseDoctor.ps1')
. (Join-Path $PSScriptRoot 'pre-freeze-release/PlaytestSessions.ps1')