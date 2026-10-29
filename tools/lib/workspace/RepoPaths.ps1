Set-StrictMode -Version Latest

function Assert-MIRCheckoutHardLinkBoundary {
  param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)

  # Derive the checkout from this implementation, never from a caller-supplied
  # run/library root. Both names must belong to this checkout. External archive
  # libraries are consumed directly; refusing a link must not trigger a copy.
  $checkout=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..')).TrimEnd('\','/')
  if(-not(Test-Path -LiteralPath (Join-Path $checkout '.git'))){throw '[mir-hardlink-checkout-missing]'}
  foreach($path in @($Source,$Destination)){
    $full=[IO.Path]::GetFullPath($path)
    if(-not$full.StartsWith($checkout+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
      throw "[mir-hardlink-outside-checkout] $full; use direct-library activation for external inputs."
    }
    # Also inspect existing ancestors of a not-yet-created destination. A
    # lexical descendant through a junction is not a checkout-contained path.
    $current=$full
    while(-not[string]::IsNullOrWhiteSpace($current)){
      if(Test-Path -LiteralPath $current){
        if((Get-Item -LiteralPath $current -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){
          throw "[mir-hardlink-reparse] $current"
        }
      }
      $current=[IO.Path]::GetDirectoryName($current)
    }
  }
}
