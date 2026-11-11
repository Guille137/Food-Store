# Unidad 6 - Programa el plan de mantenimiento en el Programador de tareas de Windows.
#
#   FoodStore-Respaldo-Diario        todos los dias 02:00   respaldo.ps1
#   FoodStore-Mantenimiento-Semanal  domingos 03:00         mantenimiento.ps1
#   FoodStore-Restauracion-Semanal   domingos 04:00         prueba_restauracion.ps1
#
# Sin -Registrar solo MUESTRA lo que haria (no cambia nada en el equipo).
# Con -Registrar crea o actualiza las tres tareas para el usuario actual.
# Con -Quitar las elimina.
# Las tareas no contienen contrasenas: cada script lee el archivo de contrasenas
# de PostgreSQL indicado en -PgPassFile, que debe ser legible solo por esta cuenta.
#
# Uso:  .\programar_tareas.ps1 -Base food_store -PgBin "C:\Program Files\PostgreSQL\17\bin" -Puerto 5432 -PgPassFile C:\ruta\pgpass.conf -Registrar
param(
    [Parameter(Mandatory = $true)][string]$Base,
    [string]$PgBin = $env:FS_PGBIN,
    [int]$Puerto = 5432,
    [string]$PgPassFile = $env:PGPASSFILE,
    [string]$Prefijo = "FoodStore",
    [switch]$Registrar,
    [switch]$Quitar
)
$ErrorActionPreference = "Stop"
$comunes = "-Base $Base -PgBin `"$PgBin`" -Puerto $Puerto -PgPassFile `"$PgPassFile`""
$plan = @(
    @{ Nombre = "$Prefijo-Respaldo-Diario"; Script = "respaldo.ps1"; Argumentos = $comunes
       Disparador = { New-ScheduledTaskTrigger -Daily -At "02:00" }; Cuando = "todos los dias 02:00" },
    @{ Nombre = "$Prefijo-Mantenimiento-Semanal"; Script = "mantenimiento.ps1"; Argumentos = $comunes
       Disparador = { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "03:00" }; Cuando = "domingos 03:00" },
    @{ Nombre = "$Prefijo-Restauracion-Semanal"; Script = "prueba_restauracion.ps1"; Argumentos = $comunes
       Disparador = { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "04:00" }; Cuando = "domingos 04:00" }
)

foreach ($t in $plan) {
    $ruta = Join-Path $PSScriptRoot $t.Script
    $linea = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ruta`" $($t.Argumentos)"
    if ($Quitar) {
        Unregister-ScheduledTask -TaskName $t.Nombre -Confirm:$false -ErrorAction SilentlyContinue
        Write-Output "Quitada: $($t.Nombre)"
    }
    elseif ($Registrar) {
        $accion = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $linea
        # Si el equipo estaba apagado a la hora prevista, corre al encender. Tope de 1 hora.
        $ajustes = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1)
        Register-ScheduledTask -TaskName $t.Nombre -Action $accion -Trigger (& $t.Disparador) `
            -Settings $ajustes -Description "Plan de mantenimiento Food Store (TPI Base de Datos II)" -Force | Out-Null
        Write-Output "Registrada: $($t.Nombre) ($($t.Cuando))"
    }
    else {
        Write-Output "[simulacion] $($t.Nombre) - $($t.Cuando)"
        Write-Output "             powershell.exe $linea"
    }
}
if (-not $Registrar -and -not $Quitar) {
    Write-Output "Nada fue modificado. Agregar -Registrar para crear las tareas."
}
