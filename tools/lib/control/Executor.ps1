. (Join-Path $PSScriptRoot "../validation/PerformanceCampaign.ps1")

. (Join-Path $PSScriptRoot 'executor/ContextAndTaskExecution.ps1')
. (Join-Path $PSScriptRoot 'executor/EnvironmentExecution.ps1')
. (Join-Path $PSScriptRoot 'executor/PerformanceSourceAndArtifacts.ps1')
. (Join-Path $PSScriptRoot 'executor/RuntimeMeasurements.ps1')
. (Join-Path $PSScriptRoot 'executor/PackageDeltaMeasurements.ps1')
. (Join-Path $PSScriptRoot 'executor/AggregateGate.ps1')