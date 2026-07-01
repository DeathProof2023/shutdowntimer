# SHUTDOWN TIMER v1.3
# Beide Dateien im selben Ordner lassen, dann BAT per Doppelklick starten.

# ===========================================================================
# LIVE-STATS RUNSPACE  (laeuft im Hintergrund waehrend manueller Eingabe)
# ===========================================================================
function Start-LiveStats {
    param([int]$Row)
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript({
        param($Row)
        while ($true) {
            try {
                $s1   = (Get-NetAdapterStatistics -EA SilentlyContinue | Measure-Object ReceivedBytes -Sum).Sum
                Start-Sleep -Milliseconds 1500
                $s2   = (Get-NetAdapterStatistics -EA SilentlyContinue | Measure-Object ReceivedBytes -Sum).Sum
                $dl   = [math]::Round([math]::Max(0, ($s2 - $s1) / 1.5 / 1KB), 1)
                $cpu  = [math]::Round((Get-CimInstance Win32_Processor -EA SilentlyContinue |
                         Measure-Object LoadPercentage -Average).Average, 1)
                $dObj = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk `
                        -Filter "Name='_Total'" -EA SilentlyContinue
                $disk = if ($dObj) { [math]::Round($dObj.DiskBytesPersec / 1KB, 1) } else { 0.0 }
                $cL = [Console]::CursorLeft
                $cT = [Console]::CursorTop
                [Console]::SetCursorPosition(0, $Row)
                $line = "  >> Live:   DL = {0,8:F1} KB/s   |   CPU = {1,5:F1} %   |   Disk = {2,8:F1} KB/s  " `
                        -f $dl, $cpu, $disk
                [Console]::Write($line.PadRight([math]::Max(0, [Console]::WindowWidth - 1)))
                [Console]::SetCursorPosition($cL, $cT)
            } catch { Start-Sleep -Milliseconds 500 }
        }
    }) | Out-Null
    $ps.AddArgument($Row) | Out-Null
    $ps.BeginInvoke() | Out-Null
    return [PSCustomObject]@{ PS = $ps; RS = $rs }
}

function Stop-LiveStats {
    param($Job)
    try { $Job.PS.Stop()    } catch {}
    try { $Job.PS.Dispose() } catch {}
    try { $Job.RS.Dispose() } catch {}
}

# ---------------------------------------------------------------------------
# Eingabe-Header (manueller Modus): gibt Zeilennummer der Live-Zeile zurueck
# ---------------------------------------------------------------------------
function Show-InputHeader {
    param([string]$Title, [string[]]$InfoLines = @())
    Clear-Host
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "  $Title"                                   -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""
    foreach ($l in $InfoLines) { Write-Host "  $l" -ForegroundColor DarkGray }
    if ($InfoLines.Count -gt 0) { Write-Host "" }
    [int]$statsRow = [Console]::CursorTop
    $ph = "  >> Live:   DL = --- KB/s   |   CPU = --- %   |   Disk = --- KB/s  "
    Write-Host $ph.PadRight([math]::Max(0, [Console]::WindowWidth - 1)) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Werte eingeben  (Komma oder Punkt als Dezimaltrennzeichen)" -ForegroundColor White
    Write-Host ""
    return $statsRow
}

# ===========================================================================
# KALIBRIERUNG
# ===========================================================================
function Start-Calibration {
    param(
        [bool]   $NeedDL   = $true,
        [bool]   $NeedCPU  = $true,
        [bool]   $NeedDisk = $true,
        [int]    $Sekunden = 60,
        [double] $Prozent  = 0.15   # Schwellwert = 15% des gemessenen Durchschnitts
    )

    Clear-Host
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "  Automatische Kalibrierung              " -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Stelle sicher, dass der Download / die Installation bereits laeuft." -ForegroundColor White
    Write-Host "  Das Skript misst dann $Sekunden Sekunden lang die Auslastung des PCs" -ForegroundColor White
    Write-Host "  und berechnet daraus passende Schwellwerte." -ForegroundColor White
    Write-Host ""
    Write-Host "  Messdauer anpassen  (Backspace zum Aendern):" -ForegroundColor DarkGray
    Add-Type -AssemblyName System.Windows.Forms -EA SilentlyContinue
    [System.Windows.Forms.SendKeys]::SendWait("$Sekunden")
    $eingabe = Read-Host "  Sekunden"
    if ($eingabe -match '^\d+$' -and [int]$eingabe -ge 10) { $Sekunden = [int]$eingabe }
    Write-Host ""
    Write-Host "  [ENTER] druecken wenn der Download/die Installation laeuft..." -ForegroundColor Yellow
    Read-Host | Out-Null

    $dlSamples   = [System.Collections.Generic.List[double]]::new()
    $cpuSamples  = [System.Collections.Generic.List[double]]::new()
    $diskSamples = [System.Collections.Generic.List[double]]::new()

    $ende      = (Get-Date).AddSeconds($Sekunden)
    $sampleNum = 0

    # 4 Zeilen reservieren und Startposition merken
    Write-Host ""
    $topRow = [Console]::CursorTop
    Write-Host "  Fortschritt : wird gemessen...".PadRight(78)
    Write-Host "  Aktuell     : ---".PadRight(78)
    Write-Host "  Ø bisher    : ---".PadRight(78)
    Write-Host ""

    while ((Get-Date) -lt $ende) {
        $sampleNum++
        $verbleibend = [int]($ende - (Get-Date)).TotalSeconds

        # --- Messung ---
        $dl   = $null
        $cpu  = $null
        $disk = $null

        if ($NeedDL) {
            $s1  = (Get-NetAdapterStatistics -EA SilentlyContinue | Measure-Object ReceivedBytes -Sum).Sum
            Start-Sleep -Milliseconds 2000
            $s2  = (Get-NetAdapterStatistics -EA SilentlyContinue | Measure-Object ReceivedBytes -Sum).Sum
            $dl  = [math]::Round([math]::Max(0, ($s2 - $s1) / 2.0 / 1KB), 1)
            $dlSamples.Add($dl)
        } else {
            Start-Sleep -Milliseconds 2000
        }
        if ($NeedCPU) {
            $cpu = [math]::Round((Get-CimInstance Win32_Processor -EA SilentlyContinue |
                   Measure-Object LoadPercentage -Average).Average, 1)
            $cpuSamples.Add($cpu)
        }
        if ($NeedDisk) {
            $dObj = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk `
                    -Filter "Name='_Total'" -EA SilentlyContinue
            $disk = if ($dObj) { [math]::Round($dObj.DiskBytesPersec / 1KB, 1) } else { 0.0 }
            $diskSamples.Add($disk)
        }

        # --- Durchschnitte ---
        $avgDL   = if ($dlSamples.Count   -gt 0) { [math]::Round(($dlSamples   | Measure-Object -Average).Average, 1) } else { $null }
        $avgCPU  = if ($cpuSamples.Count  -gt 0) { [math]::Round(($cpuSamples  | Measure-Object -Average).Average, 1) } else { $null }
        $avgDisk = if ($diskSamples.Count -gt 0) { [math]::Round(($diskSamples | Measure-Object -Average).Average, 1) } else { $null }

        # --- Fortschrittsbalken ---
        $done    = $Sekunden - $verbleibend
        $pct     = [math]::Min(100, [int]($done * 100 / $Sekunden))
        $filled  = [int]($pct / 5)
        $bar     = ([string][char]9608 * $filled).PadRight(20, [char]9617)

        # --- Anzeigezeilen aktualisieren ---
        $saved = [Console]::CursorTop
        [Console]::SetCursorPosition(0, $topRow)

        # Zeile 1: Fortschritt
        $z1 = "  Fortschritt : [$bar] $pct%   noch ${verbleibend}s   Sample #$sampleNum"
        [Console]::WriteLine($z1.PadRight(78))

        # Zeile 2: Aktuell
        $z2 = "  Aktuell     :"
        if ($null -ne $dl)   { $z2 += "  DL = {0,8:F1} KB/s" -f $dl }
        if ($null -ne $cpu)  { $z2 += "   CPU = {0,5:F1} %" -f $cpu }
        if ($null -ne $disk) { $z2 += "   Disk = {0,8:F1} KB/s" -f $disk }
        [Console]::WriteLine($z2.PadRight(78))

        # Zeile 3: Durchschnitt
        $z3 = "  Ø bisher    :"
        if ($null -ne $avgDL)   { $z3 += "  DL = {0,8:F1} KB/s" -f $avgDL }
        if ($null -ne $avgCPU)  { $z3 += "   CPU = {0,5:F1} %" -f $avgCPU }
        if ($null -ne $avgDisk) { $z3 += "   Disk = {0,8:F1} KB/s" -f $avgDisk }
        [Console]::WriteLine($z3.PadRight(78))

        [Console]::SetCursorPosition(0, $saved)
    }

    # Abschlusswerte berechnen
    $result = [ordered]@{}
    if ($NeedDL -and $dlSamples.Count -gt 0) {
        $avg = ($dlSamples | Measure-Object -Average).Average
        $result['DL'] = [PSCustomObject]@{
            Avg       = [math]::Round($avg, 1)
            Suggested = [math]::Max(10, [math]::Round($avg * $Prozent, 0))
            Unit      = 'KB/s'
            Min       = 1
            Max       = 999999
        }
    }
    if ($NeedCPU -and $cpuSamples.Count -gt 0) {
        $avg = ($cpuSamples | Measure-Object -Average).Average
        # CPU schwankt im Ruhezustand staerker als DL/Disk (kurze Spitzen 6-15 %)
        # daher 50 % des Durchschnitts, Minimum 15 % damit Idle-Spitzen den Timer nicht unterbrechen
        $result['CPU'] = [PSCustomObject]@{
            Avg       = [math]::Round($avg, 1)
            Suggested = [math]::Max(15, [math]::Round($avg * 0.50, 1))
            Unit      = '%'
            Min       = 1
            Max       = 99
        }
    }
    if ($NeedDisk -and $diskSamples.Count -gt 0) {
        $avg = ($diskSamples | Measure-Object -Average).Average
        $result['Disk'] = [PSCustomObject]@{
            Avg       = [math]::Round($avg, 1)
            Suggested = [math]::Max(50, [math]::Round($avg * $Prozent, 0))
            Unit      = 'KB/s'
            Min       = 1
            Max       = 999999
        }
    }
    return $result
}

# ---------------------------------------------------------------------------
# Schwellwerte bestaetigen / anpassen (nach Kalibrierung)
# ---------------------------------------------------------------------------
function Confirm-Thresholds {
    param([System.Collections.Specialized.OrderedDictionary]$Results)

    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "  Kalibrierung abgeschlossen              " -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Gemessene Durchschnittswerte und vorgeschlagene Schwellwerte (15%):" -ForegroundColor White
    Write-Host ""

    $final = [ordered]@{}
    foreach ($key in $Results.Keys) {
        $r    = $Results[$key]
        $unit = $r.Unit
        Write-Host ("  {0,-4}  Durchschnitt = {1,9:F1} {2}   ->   Schwellwert = " -f $key, $r.Avg, $unit) `
                   -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0:F1} {1}" -f $r.Suggested, $unit) -ForegroundColor Cyan
        $eingabe = Read-Host "        [ENTER] uebernehmen  oder  eigenen Wert eingeben"
        if ($eingabe -eq '') {
            $final[$key] = $r.Suggested
        } else {
            $eingabe = $eingabe -replace ',', '.'
            if ($eingabe -match '^\d+(\.\d+)?$') {
                $val = [double]$eingabe
                if ($val -ge $r.Min -and $val -le $r.Max) {
                    $final[$key] = $val
                } else {
                    Write-Host "  Ungueltig, Vorschlag wird verwendet." -ForegroundColor DarkYellow
                    $final[$key] = $r.Suggested
                }
            } else {
                Write-Host "  Eingabe nicht erkannt, Vorschlag wird verwendet." -ForegroundColor DarkYellow
                $final[$key] = $r.Suggested
            }
        }
        Write-Host ""
    }
    return $final
}

# ---------------------------------------------------------------------------
# Moduswahl: Manuell oder Kalibrieren  (nicht fuer Option 8)
# ---------------------------------------------------------------------------
function Get-InputMode {
    Write-Host "  Wie sollen die Schwellwerte ermittelt werden?" -ForegroundColor White
    Write-Host ""
    Write-Host "  [M]  Manuell eingeben" -ForegroundColor Yellow
    Write-Host "  [K]  Automatisch kalibrieren  (empfohlen)" -ForegroundColor Yellow
    Write-Host ""
    do {
        $c = (Read-Host "  Auswahl [M/K]").ToUpper().Trim()
    } while ($c -notin @('M','K'))
    return $c
}

# ===========================================================================
# MENUE
# ===========================================================================
function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "       SHUTDOWN TIMER  v1.3              " -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Wann soll der PC heruntergefahren werden?" -ForegroundColor White
    Write-Host ""
    Write-Host "  --- Zeit-basiert ---"                                                   -ForegroundColor DarkCyan
    Write-Host "  [1]  In X Sekunden"                                                     -ForegroundColor Yellow
    Write-Host "  [2]  In X Minuten"                                                      -ForegroundColor Yellow
    Write-Host "  [3]  In X Stunden"                                                      -ForegroundColor Yellow
    Write-Host "  [4]  In X Tagen"                                                        -ForegroundColor Yellow
    Write-Host "  [5]  Zu einer bestimmten Uhrzeit (HH:MM)"                              -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  --- Aktivitaets-basiert (Live: DL | CPU | Disk | auto-kalibrierbar) ---" -ForegroundColor DarkCyan
    Write-Host "  [7]  Downloadrate unter X KB/s fuer Y Minuten"                         -ForegroundColor Yellow
    Write-Host "  [8]  Keine Netzwerkaktivitaet fuer Y Minuten"                          -ForegroundColor Yellow
    Write-Host "  [9]  CPU-Auslastung unter X % fuer Y Minuten"                          -ForegroundColor Yellow
    Write-Host "  [10] Download + CPU niedrig fuer Y Minuten"                            -ForegroundColor Yellow
    Write-Host "  [11] Intelligentes Download-Ende  (DL + CPU + Disk + Timer-Reset)"     -ForegroundColor Yellow
    Write-Host "  [12] Laufwerkauslastung unter X KB/s fuer Y Minuten"                  -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [6]  Geplanten Shutdown ABBRECHEN"                                     -ForegroundColor Red
    Write-Host "  [0]  Beenden"                                                           -ForegroundColor DarkGray
    Write-Host ""
}

# ===========================================================================
# SHUTDOWN PLANEN
# ===========================================================================
function Set-Shutdown {
    param([int]$Sekunden)
    shutdown /a 2>$null | Out-Null
    if ($Sekunden -lt 1)       { Write-Host "  FEHLER: Zeitpunkt liegt in der Vergangenheit!" -ForegroundColor Red; return }
    if ($Sekunden -gt 2592000) { Write-Host "  FEHLER: Maximal 30 Tage moeglich."             -ForegroundColor Red; return }
    shutdown /s /f /t $Sekunden | Out-Null
    $ziel = (Get-Date).AddSeconds($Sekunden)
    $h = [math]::Floor($Sekunden / 3600)
    $m = [math]::Floor(($Sekunden % 3600) / 60)
    $s = $Sekunden % 60
    Write-Host ""
    Write-Host "  >> Shutdown geplant fuer: $($ziel.ToString('dd.MM.yyyy HH:mm:ss'))" -ForegroundColor Green
    Write-Host "  >> Verbleibend: ${h}h ${m}m ${s}s"                                   -ForegroundColor Green
    Write-Host "  >> Zum Abbrechen: Option [6] waehlen."                                -ForegroundColor DarkGray
}

# ===========================================================================
# AKTIVITAETS-MONITOR
# ===========================================================================
function Start-ActivityMonitor {
    param(
        [ValidateSet("download","nonet","cpu","both","smart","disk")]
        [string]$Mode,
        [double]$DLLimit   = 100,
        [double]$CPULimit  = 10,
        [double]$DiskLimit = 100,
        [int]   $DurMin    = 10,
        [int]   $Interval  = 10
    )
    $durSec     = $DurMin * 60
    $condSec    = 0
    $needNet    = $Mode -in @("download","nonet","both","smart")
    $needCPU    = $Mode -in @("cpu","both","smart")
    $needDisk   = $Mode -in @("disk","smart")
    $sleepAfter = if ($needNet) { [math]::Max(0, $Interval - 2) } else { $Interval }

    Clear-Host
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "  Ueberwachung aktiv: $Mode"                -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""
    switch ($Mode) {
        "download" { Write-Host "  Ziel: DL < $DLLimit KB/s  fuer  $DurMin Min"                                                       -ForegroundColor White }
        "nonet"    { Write-Host "  Ziel: Keine Netzwerkaktivitaet  fuer  $DurMin Min"                                                  -ForegroundColor White }
        "cpu"      { Write-Host "  Ziel: CPU < $CPULimit %  fuer  $DurMin Min"                                                         -ForegroundColor White }
        "disk"     { Write-Host "  Ziel: Disk < $DiskLimit KB/s  fuer  $DurMin Min"                                                    -ForegroundColor White }
        "both"     { Write-Host "  Ziel: DL < $DLLimit KB/s  UND  CPU < $CPULimit %  fuer  $DurMin Min"                               -ForegroundColor White }
        "smart"    { Write-Host "  Ziel: DL < $DLLimit KB/s  UND  CPU < $CPULimit %  UND  Disk < $DiskLimit KB/s  fuer  $DurMin Min"  -ForegroundColor White
                     Write-Host "  Hinweis: Timer-Reset wenn ein Wert wieder steigt."                                                  -ForegroundColor DarkGray }
    }
    Write-Host "  STRG+C zum Abbrechen." -ForegroundColor DarkGray
    Write-Host ""

    while ($true) {
        $dlRate = $cpuLoad = $diskRate = $null

        if ($needNet) {
            $n1     = (Get-NetAdapterStatistics -EA SilentlyContinue | Measure-Object ReceivedBytes -Sum).Sum
            Start-Sleep -Milliseconds 2000
            $n2     = (Get-NetAdapterStatistics -EA SilentlyContinue | Measure-Object ReceivedBytes -Sum).Sum
            $dlRate = [math]::Round([math]::Max(0, ($n2 - $n1) / 2.0 / 1KB), 1)
        }
        if ($needCPU) {
            $cpuLoad = [math]::Round((Get-CimInstance Win32_Processor -EA SilentlyContinue |
                       Measure-Object LoadPercentage -Average).Average, 1)
        }
        if ($needDisk) {
            $dObj    = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk `
                       -Filter "Name='_Total'" -EA SilentlyContinue
            $diskRate = if ($dObj) { [math]::Round($dObj.DiskBytesPersec / 1KB, 1) } else { 0.0 }
        }

        $cond = switch ($Mode) {
            "download" { $dlRate   -lt $DLLimit }
            "nonet"    { $dlRate   -lt 1 }
            "cpu"      { $cpuLoad  -lt $CPULimit }
            "disk"     { $diskRate -lt $DiskLimit }
            "both"     { $dlRate   -lt $DLLimit -and $cpuLoad -lt $CPULimit }
            "smart"    { $dlRate   -lt $DLLimit -and $cpuLoad -lt $CPULimit -and $diskRate -lt $DiskLimit }
        }

        if ($cond) {
            $condSec += $Interval
        } else {
            if ($condSec -gt 0 -and $Mode -in @("smart","both")) {
                Write-Host "  [!] Bedingung unterbrochen - Timer zurueckgesetzt." -ForegroundColor DarkYellow
            }
            $condSec = 0
        }

        $elapsed  = [TimeSpan]::FromSeconds($condSec)
        $target   = [TimeSpan]::FromSeconds($durSec)
        $progress = if ($durSec -gt 0) { [math]::Min(100, [int]($condSec * 100 / $durSec)) } else { 0 }
        $bar      = ("#" * [int]($progress / 5)).PadRight(20)

        if ($null -ne $dlRate) {
            $dlCol = if (($Mode -eq "nonet" -and $dlRate -lt 1) -or ($Mode -ne "nonet" -and $dlRate -lt $DLLimit)) { "Green" } else { "Red" }
            Write-Host -NoNewline "  DL: "                          -ForegroundColor DarkGray
            Write-Host -NoNewline ("{0,8:F1} KB/s  " -f $dlRate)   -ForegroundColor $dlCol
        }
        if ($null -ne $cpuLoad) {
            $cpCol = if ($cpuLoad -lt $CPULimit) { "Green" } else { "Red" }
            Write-Host -NoNewline "CPU: "                           -ForegroundColor DarkGray
            Write-Host -NoNewline ("{0,5:F1} %  " -f $cpuLoad)     -ForegroundColor $cpCol
        }
        if ($null -ne $diskRate) {
            $dkCol = if ($diskRate -lt $DiskLimit) { "Green" } else { "Red" }
            Write-Host -NoNewline "Disk: "                          -ForegroundColor DarkGray
            Write-Host -NoNewline ("{0,8:F1} KB/s  " -f $diskRate) -ForegroundColor $dkCol
        }
        $tCol = if ($cond) { "Cyan" } else { "DarkGray" }
        Write-Host -NoNewline "Timer: "                             -ForegroundColor DarkGray
        Write-Host -NoNewline "$($elapsed.ToString('mm\:ss')) / $($target.ToString('mm\:ss'))  " -ForegroundColor $tCol
        Write-Host -NoNewline "[$bar] $progress%"                   -ForegroundColor $tCol
        Write-Host ""

        if ($condSec -ge $durSec) {
            Write-Host ""
            Write-Host "  ====================================================" -ForegroundColor Red
            Write-Host "  >> BEDINGUNG ERFUELLT! Shutdown in 60 Sekunden..."    -ForegroundColor Red
            Write-Host "  >> Zum Abbrechen jetzt:  shutdown /a"                  -ForegroundColor DarkYellow
            Write-Host "  ====================================================" -ForegroundColor Red
            shutdown /s /f /t 60 | Out-Null
            return
        }
        Start-Sleep -Seconds $sleepAfter
    }
}

# ===========================================================================
# HILFSFUNKTION: Zahl einlesen
# ===========================================================================
function Read-Number {
    param([string]$Prompt, [double]$Min, [double]$Max)
    do {
        $raw = (Read-Host $Prompt) -replace ',', '.'
        if ($raw -match '^\d+(\.\d+)?$') {
            $val = [double]$raw
            if ($val -ge $Min -and $val -le $Max) { return $val }
            Write-Host "  Wert muss zwischen $Min und $Max liegen." -ForegroundColor Red
        } else { Write-Host "  Ungueltige Eingabe!" -ForegroundColor Red }
    } while ($true)
}

# ===========================================================================
# HAUPTSCHLEIFE
# ===========================================================================
do {
    Show-Menu
    $wahl = Read-Host "  Auswahl"

    switch ($wahl) {

        "1" {
            $ein = Read-Host "  Sekunden (z.B. 300)"
            if ($ein -match '^\d+$') { Set-Shutdown([int]$ein) }
            else { Write-Host "  Ungueltige Eingabe!" -ForegroundColor Red }
        }
        "2" {
            $ein = Read-Host "  Minuten (z.B. 30)"
            if ($ein -match '^\d+$') { Set-Shutdown([int]$ein * 60) }
            else { Write-Host "  Ungueltige Eingabe!" -ForegroundColor Red }
        }
        "3" {
            $ein = Read-Host "  Stunden (z.B. 2 oder 1.5)"
            if ($ein -match '^\d+([.,]\d+)?$') {
                $ein = $ein -replace ',', '.'
                Set-Shutdown([int]([double]$ein * 3600))
            } else { Write-Host "  Ungueltige Eingabe!" -ForegroundColor Red }
        }
        "4" {
            $ein = Read-Host "  Tage (z.B. 1)"
            if ($ein -match '^\d+$') { Set-Shutdown([int]$ein * 86400) }
            else { Write-Host "  Ungueltige Eingabe!" -ForegroundColor Red }
        }
        "5" {
            $ein = Read-Host "  Uhrzeit (HH:MM, z.B. 23:30)"
            if ($ein -match '^\d{1,2}:\d{2}$') {
                try {
                    $jetzt = Get-Date
                    $ziel  = Get-Date "$($jetzt.ToString('yyyy-MM-dd')) $ein"
                    if ($ziel -le $jetzt) { $ziel = $ziel.AddDays(1) }
                    Set-Shutdown([int]($ziel - $jetzt).TotalSeconds)
                } catch { Write-Host "  Ungueltige Uhrzeit!" -ForegroundColor Red }
            } else { Write-Host "  Format muss HH:MM sein!" -ForegroundColor Red }
        }

        "6" {
            shutdown /a 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Host "  >> Shutdown ABGEBROCHEN." -ForegroundColor Green }
            else                     { Write-Host "  Kein aktiver Timer."       -ForegroundColor Yellow }
        }

        # ------------------------------------------------------------------
        "7" {
            Clear-Host
            Write-Host ""
            Write-Host "  ========================================" -ForegroundColor Cyan
            Write-Host "  [7] Downloadrate-Monitor               " -ForegroundColor Cyan
            Write-Host "  ========================================" -ForegroundColor Cyan
            Write-Host ""
            $mode = Get-InputMode
            if ($mode -eq 'K') {
                $cal = Start-Calibration -NeedDL $true -NeedCPU $false -NeedDisk $false
                $thr = Confirm-Thresholds -Results $cal
                $dl  = $thr['DL']
            } else {
                $row  = Show-InputHeader -Title "[7] Downloadrate-Monitor"
                $live = Start-LiveStats -Row $row
                $dl   = Read-Number "  Downloadrate-Schwellwert in KB/s (z.B. 100)" 1 999999
                Stop-LiveStats $live
            }
            $dur = Read-Number "  Dauer in Minuten (z.B. 10)" 1 1440
            Start-ActivityMonitor -Mode "download" -DLLimit $dl -DurMin ([int]$dur)
        }

        "8" {
            $row  = Show-InputHeader -Title "[8] Keine Netzwerkaktivitaet"
            $live = Start-LiveStats -Row $row
            $dur  = Read-Number "  Dauer in Minuten ohne Aktivitaet (z.B. 5)" 1 1440
            Stop-LiveStats $live
            Start-ActivityMonitor -Mode "nonet" -DurMin ([int]$dur)
        }

        "9" {
            Clear-Host
            Write-Host ""
            Write-Host "  ========================================" -ForegroundColor Cyan
            Write-Host "  [9] CPU-Auslastungs-Monitor            " -ForegroundColor Cyan
            Write-Host "  ========================================" -ForegroundColor Cyan
            Write-Host ""
            $mode = Get-InputMode
            if ($mode -eq 'K') {
                $cal = Start-Calibration -NeedDL $false -NeedCPU $true -NeedDisk $false
                $thr = Confirm-Thresholds -Results $cal
                $cpu = $thr['CPU']
            } else {
                $row  = Show-InputHeader -Title "[9] CPU-Auslastungs-Monitor"
                $live = Start-LiveStats -Row $row
                $cpu  = Read-Number "  CPU-Schwellwert in % (z.B. 10)" 1 99
                Stop-LiveStats $live
            }
            $dur = Read-Number "  Dauer in Minuten (z.B. 10)" 1 1440
            Start-ActivityMonitor -Mode "cpu" -CPULimit $cpu -DurMin ([int]$dur)
        }

        "10" {
            Clear-Host
            Write-Host ""
            Write-Host "  ========================================" -ForegroundColor Cyan
            Write-Host "  [10] Download + CPU niedrig            " -ForegroundColor Cyan
            Write-Host "  ========================================" -ForegroundColor Cyan
            Write-Host ""
            $mode = Get-InputMode
            if ($mode -eq 'K') {
                $cal = Start-Calibration -NeedDL $true -NeedCPU $true -NeedDisk $false
                $thr = Confirm-Thresholds -Results $cal
                $dl  = $thr['DL']
                $cpu = $thr['CPU']
            } else {
                $row  = Show-InputHeader -Title "[10] Download + CPU niedrig"
                $live = Start-LiveStats -Row $row
                $dl   = Read-Number "  Downloadrate-Schwellwert in KB/s (z.B. 100)" 1 999999
                $cpu  = Read-Number "  CPU-Schwellwert in % (z.B. 15)" 1 99
                Stop-LiveStats $live
            }
            $dur = Read-Number "  Dauer in Minuten (z.B. 10)" 1 1440
            Start-ActivityMonitor -Mode "both" -DLLimit $dl -CPULimit $cpu -DurMin ([int]$dur)
        }

        "11" {
            Clear-Host
            Write-Host ""
            Write-Host "  ========================================" -ForegroundColor Cyan
            Write-Host "  [11] Intelligentes Download-Ende       " -ForegroundColor Cyan
            Write-Host "  ========================================" -ForegroundColor Cyan
            Write-Host "  Alle drei Werte muessen gleichzeitig niedrig sein." -ForegroundColor DarkGray
            Write-Host "  Steigt einer an, wird der Timer zurueckgesetzt."    -ForegroundColor DarkGray
            Write-Host ""
            $mode = Get-InputMode
            if ($mode -eq 'K') {
                $cal  = Start-Calibration -NeedDL $true -NeedCPU $true -NeedDisk $true
                $thr  = Confirm-Thresholds -Results $cal
                $dl   = $thr['DL']
                $cpu  = $thr['CPU']
                $disk = $thr['Disk']
            } else {
                $infoLines = @(
                    "Alle drei Werte muessen gleichzeitig unter dem Schwellwert liegen.",
                    "Steigt einer wieder an, wird der Timer zurueckgesetzt."
                )
                $row  = Show-InputHeader -Title "[11] Intelligentes Download-Ende" -InfoLines $infoLines
                $live = Start-LiveStats -Row $row
                $dl   = Read-Number "  Downloadrate-Schwellwert in KB/s  (z.B.  50)" 1 999999
                $cpu  = Read-Number "  CPU-Schwellwert in %              (z.B.  10)" 1 99
                $disk = Read-Number "  Laufwerk-Schwellwert in KB/s      (z.B. 500)" 1 999999
                Stop-LiveStats $live
            }
            $dur = Read-Number "  Beobachtungsdauer in Minuten (z.B. 10)" 1 1440
            Start-ActivityMonitor -Mode "smart" -DLLimit $dl -CPULimit $cpu -DiskLimit $disk -DurMin ([int]$dur)
        }

        "12" {
            Clear-Host
            Write-Host ""
            Write-Host "  ========================================" -ForegroundColor Cyan
            Write-Host "  [12] Laufwerkauslastungs-Monitor       " -ForegroundColor Cyan
            Write-Host "  ========================================" -ForegroundColor Cyan
            Write-Host ""
            $mode = Get-InputMode
            if ($mode -eq 'K') {
                $cal  = Start-Calibration -NeedDL $false -NeedCPU $false -NeedDisk $true
                $thr  = Confirm-Thresholds -Results $cal
                $disk = $thr['Disk']
            } else {
                $row  = Show-InputHeader -Title "[12] Laufwerkauslastungs-Monitor"
                $live = Start-LiveStats -Row $row
                $disk = Read-Number "  Laufwerk-Schwellwert in KB/s (z.B. 500)" 1 999999
                Stop-LiveStats $live
            }
            $dur = Read-Number "  Dauer in Minuten (z.B. 10)" 1 1440
            Start-ActivityMonitor -Mode "disk" -DiskLimit $disk -DurMin ([int]$dur)
        }

        "0" { exit }

        default { Write-Host "  Bitte 0-12 eingeben." -ForegroundColor Red }
    }

    Write-Host ""
    Write-Host "  [ENTER] zurueck ins Menue..." -ForegroundColor DarkGray
    Read-Host | Out-Null

} while ($true)
