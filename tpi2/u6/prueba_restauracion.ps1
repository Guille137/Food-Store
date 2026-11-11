# Unidad 6 - Prueba semanal de restauracion: toma el respaldo MAS RECIENTE de la
# base, lo restaura en una base temporal con otro nombre, verifica integridad y
# elimina la base temporal. Un respaldo que nunca se restauro no es un respaldo.
# Uso:  .\prueba_restauracion.ps1 -Base food_store -PgBin "C:\Program Files\PostgreSQL\17\bin" -Puerto 5432
param(
    [Parameter(Mandatory = $true)][string]$Base,
    [string]$PgBin = $env:FS_PGBIN,
    [string]$Servidor = "127.0.0.1",
    [int]$Puerto = 5432,
    [string]$Usuario = "postgres",
    [string]$Origen = (Join-Path $PSScriptRoot "respaldos"),
    [string]$PgPassFile
)
$ErrorActionPreference = "Stop"
if ($PgPassFile) { $env:PGPASSFILE = $PgPassFile }

$ultimo = Get-ChildItem -Path $Origen -Filter "${Base}_*.dump" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $ultimo) { Write-Output "ERROR: no hay respaldos de '$Base' en $Origen"; exit 1 }
$antiguedad = [math]::Round(((Get-Date) - $ultimo.LastWriteTime).TotalHours, 1)
Write-Output "Respaldo mas reciente: $($ultimo.Name) (hace $antiguedad horas)"
if ($antiguedad -gt 26) { Write-Output "AVISO: el ultimo respaldo tiene mas de un dia; revisar la tarea diaria" }

$temporal = "restauracion_prueba_" + (Get-Date -Format "yyyyMMdd_HHmmss")
& (Join-Path $PSScriptRoot "restaurar.ps1") -Dump $ultimo.FullName -Modo Prueba -BaseDestino $temporal `
    -PgBin $PgBin -Servidor $Servidor -Puerto $Puerto -Usuario $Usuario
$codigo = $LASTEXITCODE

# La base temporal se elimina siempre; su nombre fue generado aca y no coincide con ninguna otra.
$dropdb = Join-Path $PgBin "dropdb.exe"
Start-Process -FilePath $dropdb -NoNewWindow -Wait -ArgumentList @(
    "--if-exists", "--no-password", "--host", $Servidor, "--port", "$Puerto", "--username", $Usuario, $temporal)
Write-Output "Base temporal '$temporal' eliminada"
exit $codigo
