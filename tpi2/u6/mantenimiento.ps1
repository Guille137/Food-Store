# Unidad 6 - Mantenimiento semanal desatendido: limpieza, estadisticas, copias
# derivadas y verificacion de integridad. Deja un log fechado y termina con
# codigo 1 si la integridad no se confirma (el programador de tareas lo marca
# como fallido).
# Uso:  .\mantenimiento.ps1 -Base food_store -PgBin "C:\Program Files\PostgreSQL\17\bin" -Puerto 5432
param(
    [Parameter(Mandatory = $true)][string]$Base,
    [string]$PgBin = $env:FS_PGBIN,
    [string]$Servidor = "127.0.0.1",
    [int]$Puerto = 5432,
    [string]$Usuario = "postgres",
    [string]$Registros = (Join-Path $PSScriptRoot "registros"),
    [string]$PgPassFile
)
$ErrorActionPreference = "Stop"
if ($PgPassFile) { $env:PGPASSFILE = $PgPassFile }
New-Item -ItemType Directory -Force -Path $Registros | Out-Null
$log = Join-Path $Registros ("mantenimiento_{0}_{1}.log" -f $Base, (Get-Date -Format "yyyyMMdd_HHmmss"))
$psql = Join-Path $PgBin "psql.exe"
if (-not (Test-Path $psql)) { Write-Output "No se encuentra $psql"; exit 1 }

$codigo = 0
foreach ($archivo in @("mantenimiento.sql", "verificar_integridad.sql")) {
    $ruta = Join-Path $PSScriptRoot $archivo
    $salida = [System.IO.Path]::GetTempFileName()
    $errores = [System.IO.Path]::GetTempFileName()
    $proceso = Start-Process -FilePath $psql -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $salida -RedirectStandardError $errores `
        -ArgumentList @("-X", "-v", "ON_ERROR_STOP=1", "--no-password", "--host", $Servidor,
                        "--port", "$Puerto", "--username", $Usuario, "-d", $Base, "-f", "`"$ruta`"")
    Add-Content -Path $log -Encoding UTF8 -Value "===== $archivo (codigo $($proceso.ExitCode)) ====="
    Get-Content $salida, $errores | Add-Content -Path $log -Encoding UTF8
    Remove-Item $salida, $errores -Force
    if ($proceso.ExitCode -ne 0) { $codigo = 1 }
}
if ($codigo -eq 0) { Write-Output "MANTENIMIENTO CORRECTO. Log: $log" } else { Write-Output "MANTENIMIENTO CON ERRORES. Log: $log" }
exit $codigo
