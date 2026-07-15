function New-MIRHtmlReport {
  param(
    [Parameter(Mandatory)][string]$OutputRoot,
    [string]$Title = "MIR Run Report"
  )

  $summaryFiles = @(Get-ChildItem -LiteralPath $OutputRoot -Recurse -Filter "*summary.md" -File -ErrorAction SilentlyContinue)
  $failureFiles = @(Get-ChildItem -LiteralPath $OutputRoot -Recurse -Filter "compat-failures.grouped.json" -File -ErrorAction SilentlyContinue)
  $observationFiles = @(Get-ChildItem -LiteralPath $OutputRoot -Recurse -Filter "compat-observations.md" -File -ErrorAction SilentlyContinue)
  $missingFiles = @(Get-ChildItem -LiteralPath $OutputRoot -Recurse -Filter "missing-dependencies.csv" -File -ErrorAction SilentlyContinue)

  $html = @()
  $html += "<!doctype html><html><head><meta charset='utf-8'><title>$Title</title>"
  $html += "<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;line-height:1.4}code,pre{background:#f4f4f4;padding:2px 4px}table{border-collapse:collapse}td,th{border:1px solid #ddd;padding:4px 8px}</style>"
  $html += "</head><body>"
  $html += "<h1>$Title</h1>"
  $html += "<p>Output root: <code>$OutputRoot</code></p>"
  $html += "<h2>Summary Files</h2><ul>"
  foreach ($file in $summaryFiles) { $html += "<li><code>$($file.FullName)</code></li>" }
  $html += "</ul><h2>Grouped Failure Files</h2><ul>"
  foreach ($file in $failureFiles) { $html += "<li><code>$($file.FullName)</code></li>" }
  $html += "</ul><h2>Compatibility Observation Files</h2><ul>"
  foreach ($file in $observationFiles) { $html += "<li><code>$($file.FullName)</code></li>" }
  $html += "</ul><h2>Missing Dependency Files</h2><ul>"
  foreach ($file in $missingFiles) { $html += "<li><code>$($file.FullName)</code></li>" }
  $html += "</ul></body></html>"

  $path = Join-Path $OutputRoot "index.html"
  $html -join "`n" | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}
