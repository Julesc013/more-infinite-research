# Generated package-excluded MIR 4 API V1 preview helpers.
function Test-MIR4ApiV1Availability {
  param([Parameter(Mandatory)]$Response)
  if([string]$Response.availability.status -notin @('available','unavailable')){throw '[mir4-api-v1-availability]'}
  if([string]$Response.availability.status -eq 'unavailable' -and $null -ne $Response.page.total){throw '[mir4-api-v1-unavailable-is-not-zero]'}
  return $true
}
function Copy-MIR4ApiV1Data { param([AllowNull()]$Value) if($null-eq$Value){return $null};return (($Value|ConvertTo-Json -Depth 100 -Compress)|ConvertFrom-Json) }
Export-ModuleMember -Function Test-MIR4ApiV1Availability,Copy-MIR4ApiV1Data