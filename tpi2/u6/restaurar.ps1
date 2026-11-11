# Unidad 6 - Restauracion de Food Store desde un respaldo, cronometrada por fases.
# Spec: .kiro/specs/u6-mantenimiento/
#
# Dos modos:
#   -Modo Prueba     Restaura en una base NUEVA con otro nombre (-BaseDestino) para
#                    comprobar que el respaldo sirve. Nunca toca la base original.
#   -Modo Siniestro  Recrea la base con su nombre original (pg_restore --create),
#                    incluidos sus permisos a nivel de base. Falla si la base
#                    todavia existe: este script jamas pisa una base.
#
# En ambos casos, despues de restaurar: actualiza estadisticas y ejecuta
# verificar_integridad.sql. Si algo falla termina con codigo 1.
# Requiere un rol que pueda crear bases y extensiones (superusuario de laboratorio);
# la clave se resuelve con -PgPassFile / PGPASSFILE, nunca se escribe aca.
#
# Uso:  .\restaurar.ps1 -Dump .\respaldos\food_store_20261110_020000.dump -Modo Prueba -BaseDestino food_store_prueba
param(
    [Parameter(Mandatory = $true)][string]$Dump,
    [ValidateSet("Prueba", "Siniestro")][string]$Modo = "Prueba",
    [string]$BaseDestino,
    [string]$PgBin = $env:FS_PGBIN,
    [string]$Servidor = "127.0.0.1",
    [int]$Puerto = 5432,
    [string]$Usuario = "postgres",
    [string]$PgPassFile
)
$ErrorActionPreference = "Stop"
if ($PgPassFile) { $env:PGPASSFILE = $PgPassFile }
$integridad = Join-Path $PSScriptRoot "verificar_integridad.sql"

function Ejecutar([string]$herramienta, [string[]]$argumentos, [string]$salida) {
    $exe = Join-Path $PgBin "$herramienta.exe"
    if (-not (Test-Path $exe)) { throw "No se encuentra $exe (revisar -PgBin)" }
    $errores = [System.IO.Path]::GetTempFileName()
    $citados = $argumentos | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
    $opciones = @{ FilePath = $exe; ArgumentList = $citados; NoNewWindow = $true; Wait = $true
                   PassThru = $true; RedirectStandardError = $errores }
    if ($salida) { $opciones.RedirectStandardOutput = $salida }
    $proceso = Start-Process @opciones
    $detalle = (Get-Content $errores -Raw)
    Remove-Item $errores -Force
    if ($proceso.ExitCode -ne 0) { throw "$herramienta termino con codigo $($proceso.ExitCode): $detalle" }
    return $detalle
}

function Consultar([string]$base, [string]$sql) {
    $tmp = [System.IO.Path]::GetTempFileName()
    Ejecutar "psql" ($conexion + @("-X", "-At", "-v", "ON_ERROR_STOP=1", "-d", $base, "-c", $sql)) $tmp | Out-Null
    $r = (Get-Content $tmp -Raw)
    Remove-Item $tmp -Force
    if ($r) { return $r.Trim() } else { return "" }
}

$fases = [ordered]@{}
$total = [System.Diagnostics.Stopwatch]::StartNew()
$conexion = @("--host", $Servidor, "--port", "$Puerto", "--username", $Usuario, "--no-password")
try {
    if (-not (Test-Path $Dump)) { throw "No existe el respaldo $Dump" }

    # Fase 1: el archivo es el mismo que se guardo.
    $reloj = [System.Diagnostics.Stopwatch]::StartNew()
    if (Test-Path "$Dump.sha256") {
        $esperado = ((Get-Content "$Dump.sha256" -Raw).Trim() -split '\s+')[0]
        $real = (Get-FileHash -Algorithm SHA256 -Path $Dump).Hash.ToLower()
        if ($esperado -ne $real) { throw "El respaldo esta alterado o corrupto (SHA-256 distinto)" }
        Write-Output "SHA-256 verificado"
    } else {
        Write-Output "AVISO: el respaldo no tiene archivo .sha256; no se pudo verificar su integridad"
    }
    $fases["verificar_archivo"] = [math]::Round($reloj.Elapsed.TotalSeconds, 3)

    # Fase 2: crear la base y restaurar.
    $reloj.Restart()
    if ($Modo -eq "Siniestro") {
        $indice = [System.IO.Path]::GetTempFileName()
        Ejecutar "pg_restore" @("--list", $Dump) $indice | Out-Null
        $linea = Get-Content $indice | Where-Object { $_ -match '^;\s+dbname:\s+(\S+)' } | Select-Object -First 1
        Remove-Item $indice -Force
        if (-not $linea) { throw "No se pudo leer el nombre de la base dentro del respaldo" }
        $BaseDestino = ($linea -replace '^;\s+dbname:\s+', '').Trim()
        if ((Consultar "postgres" "SELECT count(*) FROM pg_database WHERE datname = '$BaseDestino'") -ne "0") {
            throw "La base '$BaseDestino' todavia existe: no se pisa una base existente"
        }
        Ejecutar "pg_restore" ($conexion + @("--create", "--exit-on-error", "--dbname", "postgres", $Dump)) | Out-Null
    } else {
        if (-not $BaseDestino) { throw "En modo Prueba hay que indicar -BaseDestino" }
        if ($BaseDestino -notmatch '^[a-z_][a-z0-9_]*$') { throw "Nombre de base no valido: $BaseDestino" }
        if ((Consultar "postgres" "SELECT count(*) FROM pg_database WHERE datname = '$BaseDestino'") -ne "0") {
            throw "La base '$BaseDestino' ya existe: elegir otro nombre"
        }
        Ejecutar "createdb" ($conexion + @($BaseDestino)) | Out-Null
        Ejecutar "pg_restore" ($conexion + @("--exit-on-error", "--dbname", $BaseDestino, $Dump)) | Out-Null
    }
    $fases["restaurar"] = [math]::Round($reloj.Elapsed.TotalSeconds, 3)
    Write-Output "Base '$BaseDestino' restaurada"

    # Fase 3: las estadisticas del planificador no viajan en el respaldo.
    $reloj.Restart()
    Consultar $BaseDestino "ANALYZE" | Out-Null
    $fases["estadisticas"] = [math]::Round($reloj.Elapsed.TotalSeconds, 3)

    # Fase 4: integridad fisica y logica.
    $reloj.Restart()
    $tmp = [System.IO.Path]::GetTempFileName()
    $avisos = Ejecutar "psql" ($conexion + @("-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", $BaseDestino, "-f", $integridad)) $tmp
    Remove-Item $tmp -Force
    if ($avisos -notmatch "INTEGRIDAD VERIFICADA") { throw "La verificacion de integridad no confirmo el resultado" }
    $fases["integridad"] = [math]::Round($reloj.Elapsed.TotalSeconds, 3)
    Write-Output (($avisos -split "`n" | Where-Object { $_ -match "INTEGRIDAD VERIFICADA" }) -join "")

    $total.Stop()
    $resultado = @{ exito = $true; modo = $Modo; base = $BaseDestino; fases = $fases
                    segundos = [math]::Round($total.Elapsed.TotalSeconds, 3) }
    Write-Output ("RESULTADO " + ($resultado | ConvertTo-Json -Compress))
    exit 0
}
catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    Write-Output ("RESULTADO " + (@{ exito = $false; error = $_.Exception.Message; fases = $fases } | ConvertTo-Json -Compress))
    exit 1
}
