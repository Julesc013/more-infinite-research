$ErrorActionPreference = "Stop"

function ConvertFrom-MIRAuditToken {
  param([Parameter(Mandatory)][string]$Token)

  $idx = $Token.IndexOf("=")
  if ($idx -lt 1) { return $null }
  $name = $Token.Substring(0, $idx)
  $value = $Token.Substring($idx + 1)
  if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
    $value = $value.Substring(1, $value.Length - 2)
  }
  $value = $value.Replace("\t", "`t").Replace("\n", "`n").Replace("\r", "`r").Replace('\"', '"').Replace("\\", "\")
  [pscustomobject]@{
    name = $name
    value = $value
  }
}

function Split-MIRAuditFields {
  param([Parameter(Mandatory)][string]$Text)

  $tokens = @()
  $current = ""
  $quoted = $false
  $escaped = $false
  foreach ($ch in $Text.ToCharArray()) {
    if ($escaped) {
      $current += $ch
      $escaped = $false
      continue
    }
    if ($ch -eq "\") {
      $current += $ch
      $escaped = $true
      continue
    }
    if ($ch -eq '"') {
      $current += $ch
      $quoted = -not $quoted
      continue
    }
    if (-not $quoted -and [char]::IsWhiteSpace($ch)) {
      if ($current -ne "") {
        $tokens += $current
        $current = ""
      }
      continue
    }
    $current += $ch
  }
  if ($current -ne "") { $tokens += $current }
  return $tokens
}

function ConvertFrom-MIRAuditLine {
  param([Parameter(Mandatory)][string]$Line)

  $prefix = "[more-infinite-research] audit "
  $idx = $Line.IndexOf($prefix)
  if ($idx -lt 0) { return $null }

  $body = $Line.Substring($idx + $prefix.Length)
  $row = [ordered]@{}
  foreach ($token in Split-MIRAuditFields -Text $body) {
    $field = ConvertFrom-MIRAuditToken -Token $token
    if ($field) { $row[$field.name] = $field.value }
  }
  [pscustomobject]$row
}

function Read-MIRAuditLog {
  param([Parameter(Mandatory)][string]$Path)

  $rows = @()
  foreach ($line in Get-Content -LiteralPath $Path) {
    $row = ConvertFrom-MIRAuditLine -Line $line
    if ($row) { $rows += $row }
  }
  return $rows
}
