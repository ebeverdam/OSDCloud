<#
.SYNOPSIS
    Connectium: eenmalige Windows Update-ronde met popup + opleverrapport bij de eerste aanmelding.

.DESCRIPTION
    -Register   Maakt de geplande taak aan (vanuit SetupComplete, of door Test-FirstLogonFlow.ps1).
                De taak start direct bij elke aanmelding (ook op accu). Updates starten meteen; de popup wacht tot Windows Hello/ESP klaar is.
    (geen)      Wordt door de taak gestart als SYSTEM:
                1. Wacht tot OOBE klaar is en een echte gebruiker een bureaublad heeft (max 30 min).
                2. Start de popup in de sessie van de gebruiker (Start-UpdatePopup.ps1 -Ui).
                3. Voert de updates uit als SYSTEM (Start-UpdatePopup.ps1 -Worker).
                4. Verwijdert de taak en het gasten-WiFi-profiel.
                Valt terug op Install-OSUpdates.ps1 + New-InstallReport.ps1 als de popup ontbreekt.

.NOTES
    Auteur: Connectium B.V. / E. Beverdam
    Versie: 2026.10.19.05
#>

param(
    [switch]$Register,
    [string]$GuestSSID = 'Connectium Gasten'
)

$TaskName  = 'Connectium\FirstLogonWindowsUpdates'
$UiTaskName = 'UpdatePopupUI'
$UiTaskPath = '\Connectium\'
$Dir       = 'C:\ProgramData\Scripts\WindowsUpdates'
$PopupDir  = 'C:\ProgramData\Connectium\Popup'
$LogFile   = Join-Path $Dir 'FirstLogon.log'
$PsExe     = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$ThisFile  = Join-Path $Dir 'FirstLogon.ps1'

function Log([string]$m) {
    if (-not (Test-Path $Dir)) { New-Item -Path $Dir -ItemType Directory -Force | Out-Null }
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" | Out-File $LogFile -Append -Encoding utf8
}

# =================================================================
#  Taak aanmaken
# =================================================================
if ($Register) {
    $Xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Connectium: eenmalige Windows Update-ronde en opleverrapport bij de eerste aanmelding</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <ExecutionTimeLimit>PT3H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$PsExe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$ThisFile" -GuestSSID "$GuestSSID"</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    $XmlFile = Join-Path $Dir 'FirstLogonTask.xml'
    [IO.File]::WriteAllText($XmlFile, $Xml, [Text.Encoding]::Unicode)
    $out = schtasks.exe /Create /TN $TaskName /XML $XmlFile /F 2>&1
    Log "Taak aangemaakt: $TaskName ($out)"
    exit 0
}

# =================================================================
#  Uitvoeren (door de taak, als SYSTEM)
# =================================================================
function Get-DesktopUser {
    # Eigenaar van explorer.exe = gebruiker met een bureaublad; defaultuser0 (OOBE) telt niet
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue)) {
        $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction SilentlyContinue
        if ($o.User -and $o.User -notmatch '^defaultuser\d*$') { return "$($o.Domain)\$($o.User)" }
    }
    return $null
}

Log '--- Taak gestart ---'
$Setup = Get-ItemProperty 'HKLM:\SYSTEM\Setup' -ErrorAction SilentlyContinue
if ($Setup.OOBEInProgress -eq 1 -or $Setup.SystemSetupInProgress -eq 1) {
    Log 'OOBE is nog bezig: overslaan, de taak blijft staan voor de volgende aanmelding.'
    exit 0
}

$User = $null
for ($i = 0; $i -lt 600; $i++) {   # max 30 minuten, elke 3 seconden kijken
    $User = Get-DesktopUser
    if ($User) { break }
    Start-Sleep -Seconds 3
}
if (-not $User) {
    Log 'Geen bureaublad van een gebruiker gevonden: de taak blijft staan voor de volgende aanmelding.'
    exit 0
}
Log "Gebruiker met bureaublad: $User"
Start-Sleep -Seconds 5    # bureaublad laten opbouwen

$Popup = Join-Path $Dir 'Start-UpdatePopup.ps1'
if (Test-Path $Popup) {
    # Uitwisselmap: SYSTEM schrijft de status, de gebruiker mag vlaggen (afbreken/gesloten) schrijven
    if (Test-Path $PopupDir) { Remove-Item -Path "$PopupDir\*" -Force -ErrorAction SilentlyContinue }
    New-Item -Path $PopupDir -ItemType Directory -Force | Out-Null
    $null = icacls.exe $PopupDir /grant '*S-1-5-32-545:(OI)(CI)M' /Q

    # Updates direct starten als SYSTEM (achtergrond), zodat er geen tijd verloren gaat
    $Worker = Start-Process -FilePath $PsExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Popup`" -Worker" -WindowStyle Hidden -PassThru
    $null = $Worker.Handle   # nodig om straks de exitcode te kunnen lezen
    Log "Worker gestart op de achtergrond (PID $($Worker.Id))."

    # Popup pas tonen als Windows Hello / ESP (CloudExperienceHost) klaar is,
    # anders verschijnt hij achter of tijdens de Hello-setup. Max 20 minuten wachten.
    $CxhNames = 'CloudExperienceHostBroker', 'CloudExperienceHost', 'WWAHost'
    $Waited = 0
    while ((Get-Process -Name $CxhNames -ErrorAction SilentlyContinue) -and $Waited -lt 1200 -and -not $Worker.HasExited) {
        if ($Waited -eq 0) { Log 'Windows Hello / account-setup is nog bezig: popup wacht.' }
        Start-Sleep -Seconds 3; $Waited += 3
    }
    if ($Waited -gt 0) { Log "Setup-scherm weg na $Waited s."; Start-Sleep -Seconds 3 }

    # Popup starten in de sessie van de gebruiker (groep Users), ook op accu
    if (-not $Worker.HasExited) { try {
        # Via conhost --headless: geen (leeg) consolevenster. Windows Terminal negeert -WindowStyle Hidden.
        $Conhost   = "$env:WINDIR\System32\conhost.exe"
        $PsArgs    = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$Popup`" -Ui"
        $Action    = if (Test-Path $Conhost) { New-ScheduledTaskAction -Execute $Conhost -Argument "--headless `"$PsExe`" $PsArgs" }
                     else { New-ScheduledTaskAction -Execute $PsExe -Argument $PsArgs }
        $Principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
        $Settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
        Register-ScheduledTask -TaskName $UiTaskName -TaskPath $UiTaskPath -Action $Action -Principal $Principal -Settings $Settings -Force | Out-Null
        Start-ScheduledTask -TaskName $UiTaskName -TaskPath $UiTaskPath
        Log 'Popup gestart in de sessie van de gebruiker.'
    }
    catch { Log "Popup starten mislukt: $($_.Exception.Message) - updates gaan wel door." } }
    else { Log 'Worker was al klaar voordat het setup-scherm weg was: geen popup nodig.' }

    # Wachten tot de updates klaar zijn
    $Worker.WaitForExit()
    Log "Worker klaar (exitcode $($Worker.ExitCode))."

    Unregister-ScheduledTask -TaskName $UiTaskName -TaskPath $UiTaskPath -Confirm:$false -ErrorAction SilentlyContinue
}
else {
    # Terugval: oude manier
    Log 'Start-UpdatePopup.ps1 niet gevonden: terugval op Install-OSUpdates + rapport.'
    & $PsExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir 'Install-OSUpdates.ps1') -IgnoreOOBECheck
    $Report = Join-Path $Dir 'New-InstallReport.ps1'
    if (Test-Path $Report) { & $PsExe -NoProfile -ExecutionPolicy Bypass -File $Report }
}

# Opruimen: taak en gasten-WiFi (niet meenemen naar de klant)
schtasks.exe /Delete /TN $TaskName /F | Out-Null
netsh.exe wlan delete profile name="$GuestSSID" | Out-Null
Log 'Taak en gasten-WiFi-profiel opgeruimd. Klaar.'
