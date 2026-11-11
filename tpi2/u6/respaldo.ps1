# Unidad 6 - Respaldo programado de Food Store (PostgreSQL, formato custom).
# Spec: .kiro/specs/u6-mantenimiento/
#
# Que hace:
#   1. pg_dump -Fc de la base indicada, con nombre fechado.
#   2. Verifica el archivo: codigo de salida, tamano y lectura del indice (pg_restore --list).
#   3. Guarda su SHA-256 para detectar corrupcion antes de restaurar.
#   4. Guarda la definicion de roles (sin contrasenas) para poder restaurar en otro servidor.
#   5. Borra los respaldos mas viejos que la retencion (solo los de ESTA base y carpeta).
#
# No guarda ni pide contrasenas: usa el archivo de contrasenas de PostgreSQL
# (parametro -PgPassFile o variable PGPASSFILE). --no-password hace que falle en
# lugar de quedarse esperando una clave cuando corre desatendido.
# Se conecta con el rol operador_respaldo (solo lectura), no con el superusuario.
#
# Uso:  .\respaldo.ps1 -Base food_store -PgBin "C:\Program Files\PostgreSQL\17\bin" -Puerto 5432
param(
    [Parameter(Mandatory = $true)][string]$Base,
    [string]$PgBin = $env:FS_PGBIN,
    [string]$Servidor = "127.0.0.1",
    [int]$Puerto = 5432,
    [string]$Usuario = "operador_respaldo",
    [string]$Destino = (Join-Path $PSScriptRoot "respaldos"),
    [int]$RetencionDias = 14,
    [string]$PgPassFile
)
$ErrorActionPreference = "Stop"
if ($PgPassFile) { $env:PGPASSFILE = $PgPassFile }

$sello = Get-Date -Format "yyyyMMdd_HHmmss"
$dump = Join-Path $Destino "${Base}_${sello}.dump"
$log = Join-Path $Destino "respaldo_${Base}_${sello}.log"
New-Item -ItemType Directory -Force -Path $Destino | Out-Null

function Anotar([string]$texto) {
    $linea = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $texto"
    Add-Content -Path $log -Value $linea -Encoding UTF8
    Write-Output $linea
}

# Ejecuta una herramienta de PostgreSQL sin mezclar stderr con el flujo de PowerShell.
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
}

$reloj = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Anotar "INICIO respaldo de '$Base' en ${Servidor}:${Puerto} con el rol $Usuario"
    $conexion = @("--host", $Servidor, "--port", "$Puerto", "--username", $Usuario, "--no-password")

    Ejecutar "pg_dump" ($conexion + @("--format=custom", "--file", $dump, $Base))
    $tamano = (Get-Item $dump).Length
    if ($tamano -le 0) { throw "El respaldo quedo vacio" }
    Anotar "Respaldo creado: $(Split-Path $dump -Leaf) ($tamano bytes)"

    # Un archivo que no se puede listar no se puede restaurar.
    $indice = [System.IO.Path]::GetTempFileName()
    Ejecutar "pg_restore" @("--list", $dump) $indice
    $objetos = (Get-Content $indice | Where-Object { $_ -and -not $_.StartsWith(";") }).Count
    Remove-Item $indice -Force
    if ($objetos -le 0) { throw "El indice del respaldo no contiene objetos" }
    Anotar "Indice legible: $objetos objetos"

    $hash = (Get-FileHash -Algorithm SHA256 -Path $dump).Hash.ToLower()
    Set-Content -Path "$dump.sha256" -Value "$hash  $(Split-Path $dump -Leaf)" -Encoding ASCII
    Anotar "SHA-256: $hash"

    $roles = Join-Path $Destino "roles_${sello}.sql"
    Ejecutar "pg_dumpall" ($conexion + @("--roles-only", "--no-role-passwords", "--file", $roles))
    Anotar "Roles guardados sin contrasenas: $(Split-Path $roles -Leaf)"

    $limite = (Get-Date).AddDays(-$RetencionDias)
    $viejos = @(Get-ChildItem -Path $Destino -Filter "${Base}_*.dump" | Where-Object { $_.LastWriteTime -lt $limite })
    foreach ($v in $viejos) {
        Remove-Item -Force -Path $v.FullName
        Remove-Item -Force -Path "$($v.FullName).sha256" -ErrorAction SilentlyContinue
    }
    Anotar "Retencion de $RetencionDias dias: $($viejos.Count) respaldos antiguos eliminados"

    $reloj.Stop()
    Anotar "FIN correcto en $([math]::Round($reloj.Elapsed.TotalSeconds, 2)) s"
    $resultado = @{ exito = $true; base = $Base; dump = $dump; bytes = $tamano; objetos = $objetos
                    sha256 = $hash; segundos = [math]::Round($reloj.Elapsed.TotalSeconds, 2)
                    termino = (Get-Date -Format "o") }
    Write-Output ("RESULTADO " + ($resultado | ConvertTo-Json -Compress))
    exit 0
}
catch {
    Anotar "ERROR: $($_.Exception.Message)"
    # Un respaldo a medias no debe confundirse con uno valido.
    if (Test-Path $dump) { Remove-Item -Force $dump }
    Write-Output ("RESULTADO " + (@{ exito = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress))
    exit 1
}
