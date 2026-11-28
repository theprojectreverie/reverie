$cutoff = (Get-Date).AddDays(-14)
Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter 'auth-diagnostics-*' |
  Where-Object { $_.Extension -in '.log', '.err' -and $_.LastWriteTime -lt $cutoff } |
  Remove-Item -Force
