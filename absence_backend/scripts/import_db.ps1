# Εισαγωγή πλήρους αντιγράφου στη PostgreSQL του σχολικού laptop.
# Προϋπόθεση: PostgreSQL εγκατεστημένο, κενή ή προς αντικατάσταση βάση.
#
# Χρήση:
#   1) Αντίγραψε το backups\school_attendance_db_latest.sql στο laptop
#   2) Ρύθμισε το .env (ίδιο DB_NAME κ.λπ.)
#   3) powershell -ExecutionPolicy Bypass -File .\scripts\import_db.ps1
#
# Προαιρετικά:
#   .\scripts\import_db.ps1 -SqlFile "C:\path\to\dump.sql"

param(
  [string]$SqlFile = ""
)

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

$dbName = $vars["DB_NAME"]
if (-not $SqlFile) {
  $SqlFile = Join-Path $root "backups\${dbName}_latest.sql"
}
if (-not (Test-Path $SqlFile)) {
  Write-Error "Δεν βρέθηκε dump: $SqlFile"
}

function Find-PgTool([string]$name) {
  foreach ($ver in @("17", "16", "15", "14")) {
    $candidate = "C:\Program Files\PostgreSQL\$ver\bin\$name.exe"
    if (Test-Path $candidate) { return $candidate }
  }
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

$psql = Find-PgTool "psql"
if (-not $psql) {
  Write-Error "Δεν βρέθηκε psql. Εγκατέστησε PostgreSQL ή πρόσθεσε το bin στο PATH."
}

$env:PGPASSWORD = $vars["DB_PASSWORD"]
try {
  $hostName = $vars["DB_HOST"]
  $port = $vars["DB_PORT"]
  $user = $vars["DB_USER"]

  Write-Host "Δημιουργία βάσης '$dbName' (αν δεν υπάρχει)..."
  & $psql -h $hostName -p $port -U $user -d postgres -v ON_ERROR_STOP=1 `
    -c "SELECT 'ok' FROM pg_database WHERE datname = '$dbName';" | Out-Null

  $exists = & $psql -h $hostName -p $port -U $user -d postgres -tAc `
    "SELECT 1 FROM pg_database WHERE datname = '$dbName';"
  if (-not $exists) {
    & $psql -h $hostName -p $port -U $user -d postgres -v ON_ERROR_STOP=1 `
      -c "CREATE DATABASE `"$dbName`" ENCODING 'UTF8';"
  } else {
    Write-Host "Η βάση υπάρχει. Θα γίνει DROP SCHEMA public CASCADE και επαναφορά από το dump."
    & $psql -h $hostName -p $port -U $user -d $dbName -v ON_ERROR_STOP=1 `
      -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
  }

  Write-Host "Εισαγωγή από: $SqlFile"
  & $psql -h $hostName -p $port -U $user -d $dbName -v ON_ERROR_STOP=1 -f $SqlFile
  if ($LASTEXITCODE -ne 0) { throw "psql import απέτυχε (exit $LASTEXITCODE)" }

  Write-Host "OK: Η βάση '$dbName' είναι αντίγραφο του dump."
}
finally {
  Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}
