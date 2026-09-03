function Invoke-MIR4OpenSshProcessV1 {
  param(
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Arguments,
    [string]$InputPath = ""
  )

  $executable = Assert-MIR4ExplicitExecutableV1 -Path $SshKeygenPath
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $executable
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.RedirectStandardInput = -not [string]::IsNullOrWhiteSpace($InputPath)
  if ($startInfo.RedirectStandardInput -and -not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "OpenSSH verification input is missing: $InputPath"
  }
  foreach ($argument in $Arguments) { $null = $startInfo.ArgumentList.Add([string]$argument) }

  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  try {
    if (-not $process.Start()) { throw "Unable to start OpenSSH ssh-keygen." }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if ($startInfo.RedirectStandardInput) {
      $input = [IO.File]::OpenRead($InputPath)
      try {
        $input.CopyTo($process.StandardInput.BaseStream)
        $process.StandardInput.BaseStream.Flush()
      } finally {
        $input.Dispose()
        $process.StandardInput.Close()
      }
    }
    $process.WaitForExit()
    return [pscustomobject][ordered]@{
      exit_code = [int]$process.ExitCode
      stdout = [string]$stdoutTask.GetAwaiter().GetResult()
      stderr = [string]$stderrTask.GetAwaiter().GetResult()
    }
  } finally {
    $process.Dispose()
  }
}

function Get-MIR4OpenSshPublicKeyLineV1 {
  param([Parameter(Mandatory)][string]$PublicKeyPath)

  if (-not [IO.Path]::IsPathRooted($PublicKeyPath)) { throw "The Ed25519 public key requires an explicit absolute path." }
  if (-not (Test-Path -LiteralPath $PublicKeyPath -PathType Leaf)) { throw "Ed25519 public key is missing: $PublicKeyPath" }
  $lines = @([IO.File]::ReadAllLines($PublicKeyPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($lines.Count -ne 1 -or $lines[0] -notmatch '^ssh-ed25519 [A-Za-z0-9+/]+={0,3}(?: [^\r\n]+)?$') {
    throw "The proof-only public key must contain one OpenSSH Ed25519 key."
  }
  return ([string]$lines[0]).Trim()
}

function Get-MIR4OpenSshPublicKeyFingerprintV1 {
  param(
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$PublicKeyPath
  )

  $result = Invoke-MIR4OpenSshProcessV1 -SshKeygenPath $SshKeygenPath -Arguments @("-lf", $PublicKeyPath, "-E", "sha256")
  if ($result.exit_code -ne 0 -or $result.stdout -notmatch 'SHA256:[A-Za-z0-9+/]+') {
    throw "OpenSSH could not fingerprint the proof-only Ed25519 public key."
  }
  return [string]$Matches[0]
}

function New-MIR4ProofOnlyEd25519KeyPairV1 {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$PrivateKeyPath,
    [Parameter(Mandatory)][string]$PublicKeyPath,
    [Parameter(Mandatory)][string]$Identity,
    [string]$Mode = "proof-only"
  )

  Assert-MIR4OfflineCustodyModeV1 -Mode $Mode -Allowed "proof-only"
  if ($Identity -notmatch '^[A-Za-z0-9][A-Za-z0-9._@+-]{0,127}$') { throw "Invalid proof-only signing identity." }
  $private = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $RepoRoot -Path $PrivateKeyPath -Label "Proof-only private key"
  $public = Assert-MIR4UntrackedCustodyPathV1 -RepoRoot $RepoRoot -Path $PublicKeyPath -Label "Proof-only public key"
  if ($public -cne "$private.pub") { throw "The explicit public key path must be the private key path plus '.pub'." }
  if ((Test-Path -LiteralPath $private) -or (Test-Path -LiteralPath $public)) {
    throw "Proof-only signing keys already exist; custody never overwrites keys."
  }
  $parent = Split-Path -Parent $private
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $result = Invoke-MIR4OpenSshProcessV1 -SshKeygenPath $SshKeygenPath -Arguments @(
    "-q", "-t", "ed25519", "-N", "", "-C", $Identity, "-f", $private
  )
  if ($result.exit_code -ne 0 -or -not (Test-Path -LiteralPath $private -PathType Leaf) -or
      -not (Test-Path -LiteralPath $public -PathType Leaf)) {
    throw "OpenSSH failed to create the proof-only Ed25519 key pair."
  }
  return [pscustomobject][ordered]@{
    kind = "MIR4SigningProviderV1"
    algorithm = "ssh-ed25519"
    signature_format = "sshsig"
    public_key = Get-MIR4OpenSshPublicKeyLineV1 -PublicKeyPath $public
    public_key_fingerprint = Get-MIR4OpenSshPublicKeyFingerprintV1 -SshKeygenPath $SshKeygenPath -PublicKeyPath $public
    private_key_committed = $false
  }
}

function Test-MIR4OpenSshSignatureV1 {
  param(
    [Parameter(Mandatory)][string]$SshKeygenPath,
    [Parameter(Mandatory)][string]$PublicKeyPath,
    [Parameter(Mandatory)][string]$Identity,
    [Parameter(Mandatory)][string]$Namespace,
    [Parameter(Mandatory)][string]$PayloadPath,
    [Parameter(Mandatory)][string]$SignaturePath,
    [Parameter(Mandatory)][string]$ScratchRoot
  )

  if ($Identity -notmatch '^[A-Za-z0-9][A-Za-z0-9._@+-]{0,127}$' -or
      $Namespace -notmatch '^[a-z0-9][a-z0-9._-]{0,63}$') { return $false }
  try {
    $publicKey = Get-MIR4OpenSshPublicKeyLineV1 -PublicKeyPath $PublicKeyPath
    if (-not (Test-Path -LiteralPath $PayloadPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $SignaturePath -PathType Leaf)) { return $false }
    if (-not (Test-Path -LiteralPath $ScratchRoot -PathType Container)) {
      New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null
    }
    $allowedSigners = Join-Path $ScratchRoot "allowed-signers"
    [IO.File]::WriteAllText(
      $allowedSigners,
      "$Identity namespaces=`"$Namespace`" $publicKey`n",
      [Text.UTF8Encoding]::new($false)
    )
    $result = Invoke-MIR4OpenSshProcessV1 -SshKeygenPath $SshKeygenPath -Arguments @(
      "-Y", "verify", "-f", $allowedSigners, "-I", $Identity,
      "-n", $Namespace, "-s", $SignaturePath
    ) -InputPath $PayloadPath
    return $result.exit_code -eq 0
  } catch {
    return $false
  }
}
