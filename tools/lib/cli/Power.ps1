function Disable-MIRACSleep {
  $powercfg = Get-Command powercfg -ErrorAction SilentlyContinue
  if (-not $powercfg) {
    return [pscustomobject]@{ changed = $false; reason = "powercfg not found" }
  }

  & powercfg /change standby-timeout-ac 0 | Out-Null
  & powercfg /change hibernate-timeout-ac 0 | Out-Null
  return [pscustomobject]@{ changed = $true; reason = "" }
}
