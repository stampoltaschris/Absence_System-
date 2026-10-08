# Εξαγωγή πλήρους αντιγράφου της βάσης (σχήμα + δεδομένα) σε SQL.
# Χρήση (από τον δικό σου υπολογιστή):
#   powershell -ExecutionPolicy Bypass -File .\scripts\export_db.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root ".env"

if (-not (Test-Path $envFile)) {
  Write-Error "Δεν βρέθηκε .env στο $root"
}

$vars = @{}
Get-Content $envFile | ForEach-Object {
  if ($_ -match '^\s*([^#=]+)=(.*)$') {
    $vars[$matches[1].Trim()] = $matches[2].Trim()
  }
}

$pgDump = $null
foreach ($ver in @("17", "16", "15", "14")) {
  $candidate = "C:\Program Files\PostgreSQL\$ver\bin\pg_dump.exe"
  if (Test-Path $candidate) { $pgDump = $candidate; break }
}
if (-not $pgDump) {
  $cmd = Get-Command pg_dump -ErrorAction SilentlyContinue
  if ($cmd) { $pgDump = $cmd.Source }
}
if (-not $pgDump) {
  Write-Error "Δεν βρέθηκε pg_dump. Εγκατέστησε PostgreSQL ή πρόσθεσε το bin στο PATH."
}

$outDir = Join-Path $root "backups"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$dbName = $vars["DB_NAME"]
$outFile = Join-Path $outDir "${dbName}_$stamp.sql"
$latest = Join-Path $outDir "${dbName}_latest.sql"

$env:PGPASSWORD = $vars["DB_PASSWORD"]
try {
  & $pgDump `
    -h $vars["DB_HOST"] `
    -p $vars["DB_PORT"] `
    -U $vars["DB_USER"] `
    -d $dbName `
    --no-owner `
    --no-acl `
    -F p `
    -f $outFile
  if ($LASTEXITCODE -ne 0) { throw "pg_dump απέτυχε (exit $LASTEXITCODE)" }
  Copy-Item $outFile $latest -Force
  Write-Host "OK: $outFile"
  Write-Host "Αντίγραφο: $latest"
  Write-Host "ΠΡΟΣΟΧΗ: Το αρχείο μπορεί να περιέχει κωδικούς (users/SMTP). Μην το ανεβάσεις στο GitHub."
}
finally {
  Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
