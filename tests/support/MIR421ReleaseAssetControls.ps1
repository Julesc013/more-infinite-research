Set-StrictMode -Version Latest

function New-MIR421ReleaseAssetCustodyFixture {
  param([Parameter(Mandatory)][string]$RepoRoot,[ValidateSet('4.2.1','4.2.2')][string]$CandidateSourceVersion='4.2.1')
  # Structural fixtures only: IDs and paths are synthetic. No network, native
  # campaign, signature or actual release qualification is claimed here.
  $contract=Get-MIR42PublishedMaintenancePredecessorContract -CandidateSourceVersion $CandidateSourceVersion
  $pinPath=if($CandidateSourceVersion-ceq'4.2.2'){'fixtures/release-inputs/mir422-published-421-manifest.json'}else{'fixtures/release-inputs/mir421-published-420-manifest.json'}
  $pin=Read-MIR42PublishedMaintenancePredecessorManifest -ManifestPath (Join-Path $RepoRoot $pinPath) -CandidateSourceVersion $CandidateSourceVersion
  return [pscustomobject][ordered]@{
    release_id=$contract.release_id;source_tag=$contract.source_tag;source=$pin.manifest.source
    tag_object=('a' * 40);remote_tag_readback=$true
    manifest=[ordered]@{path='structural-fixture-only';sha256=$pin.sha256;bytes=$pin.bytes}
    signed=$false
    targets=@(foreach ($index in 0..8) {
      $row=$pin.manifest.targets[$index]
      [pscustomobject][ordered]@{target=$row.target;version=$row.distribution_version;path='structural-fixture-only';sha256=$row.sha256;bytes=$row.bytes;content_sha256=$row.content_sha256;entry_count=$row.entry_count;github_asset_id=($index + 1);github_digest=('sha256:' + $row.sha256.ToLowerInvariant())}
    })
    native_qualification='not-performed';release_qualification='not-performed'
  }
}
