$ErrorActionPreference = "Stop"

$database = "food_store_lab"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $PSScriptRoot "backups"
$logDir = Join-Path $PSScriptRoot "logs"
$dumpPath = Join-Path $backupDir "${database}_${timestamp}.dump"
$logPath = Join-Path $logDir "backup_${timestamp}.log"

New-Item -ItemType Directory -Force -Path $backupDir, $logDir | Out-Null
"Inicio del respaldo: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" |
    Set-Content -Path $logPath -Encoding UTF8
"Base: $database" | Add-Content -Path $logPath -Encoding UTF8

try {
    $pgDump = "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe"
    & $pgDump `
        --host localhost `
        --port 5432 `
        --username postgres `
        --dbname $database `
        --format custom `
        --file $dumpPath `
        --password 2>&1 |
        Tee-Object -FilePath $logPath -Append

    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "pg_dump terminó con código $exitCode."
    }

    if (-not (Test-Path $dumpPath) -or (Get-Item $dumpPath).Length -eq 0) {
        throw "No se creó un archivo de respaldo válido."
    }

    "OK: respaldo creado. Tamaño: $((Get-Item $dumpPath).Length) bytes." |
        Add-Content -Path $logPath -Encoding UTF8
    "Fin: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" |
        Add-Content -Path $logPath -Encoding UTF8
    exit 0
}
catch {
    "ERROR: $($_.Exception.Message)" | Add-Content -Path $logPath -Encoding UTF8
    "Falló el respaldo. Revisá el log: $logPath"
    exit 1
}