# =================================================================
# OSDCloud Deployment Script met GUI
# Versie: v2 (OSDCloud-module / Deploy-OSDCloud) - TEST
# Auteur: Connectium B.V. / E. Beverdam
# =================================================================

#################################################################
# Volledige GUI voor OSDCloud Keuzemenu
#################################################################
Write-Host -ForegroundColor Green "Version 2026.10.16.v2-test5"

# Workaround OSD 26.10.6.1: HP-driverpack catalogus datumparsing faalt onder nl-NL WinPE
# (opgelost in OSD 26.10.12 - verwijderen zodra die als stabiele versie beschikbaar is)
[System.Threading.Thread]::CurrentThread.CurrentCulture   = 'en-US'
[System.Threading.Thread]::CurrentThread.CurrentUICulture = 'en-US'
function Show-OSDCloudGUI_Dashboard {

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Connectium B.V. - OSDCloud Deployment'
    $form.Size = New-Object System.Drawing.Size(900, 610)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    # --- Logo sectie ---
    function Download-FileWithRetry {
        param(
            [string]$Url,
            [string]$DestinationPath,
            [int]$MaxRetries = 3,
            [int]$DelaySeconds = 2
        )

        $attempt = 0
        while ($attempt -lt $MaxRetries) {
            try {
                Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -UseBasicParsing
                if (Test-Path $DestinationPath) {
                    return $true
                }
            } catch {
                Write-Warning "Download poging $($attempt + 1) mislukt: $_"
            }
            Start-Sleep -Seconds $DelaySeconds
            $attempt++
        }
        return $false
    }

    $logoUrl = "https://raw.githubusercontent.com/ebeverdam/OSDCloud/refs/heads/main/images/Connectium.png"

    $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($logoUrl)
    $fileExtension = [System.IO.Path]::GetExtension($logoUrl)

    $randomSuffix = Get-Random -Minimum 10000 -Maximum 99999

    $tempLogoPath = Join-Path -Path $env:TEMP -ChildPath "$originalFileName-TEMP$randomSuffix$fileExtension"

    if (Download-FileWithRetry -Url $logoUrl -DestinationPath $tempLogoPath) {
        $pictureBox = New-Object System.Windows.Forms.PictureBox
        $pictureBox.Image = [System.Drawing.Image]::FromFile($tempLogoPath)
        $pictureBox.Location = New-Object System.Drawing.Point(130, 20)
        $pictureBox.Size = New-Object System.Drawing.Size(632, 162)
        $pictureBox.SizeMode = 'StretchImage'
        $form.Controls.Add($pictureBox)
    } else {
        Write-Warning "Kon het logo niet downloaden na meerdere pogingen."
    }

    
    $font = New-Object System.Drawing.Font('Segoe UI', 10)
    $fontGroupBox = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $fontInfo = New-Object System.Drawing.Font('Segoe UI', 9)

    $yPositionGroupBoxes = 200
    $groupBoxNL = New-Object System.Windows.Forms.GroupBox
    $groupBoxNL.Text = "ZERO-TOUCH Nederlands"
    $groupBoxNL.Font = $fontGroupBox
    $groupBoxNL.Location = New-Object System.Drawing.Point(15, $yPositionGroupBoxes)
    $groupBoxNL.Size = New-Object System.Drawing.Size(270, 260)

    $groupBoxEN = New-Object System.Windows.Forms.GroupBox
    $groupBoxEN.Text = "ZERO-TOUCH Engels"
    $groupBoxEN.Font = $fontGroupBox
    $groupBoxEN.Location = New-Object System.Drawing.Point(305, $yPositionGroupBoxes)
    $groupBoxEN.Size = New-Object System.Drawing.Size(270, 260)

    $groupBoxOther = New-Object System.Windows.Forms.GroupBox
    $groupBoxOther.Text = "Andere Opties"
    $groupBoxOther.Font = $fontGroupBox
    $groupBoxOther.Location = New-Object System.Drawing.Point(595, $yPositionGroupBoxes)
    $groupBoxOther.Size = New-Object System.Drawing.Size(270, 260)

    function New-DashboardButton {
        param($Text, $Y_Position, $DialogResult)
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $Text
        $button.Font = $font
        $button.Size = New-Object System.Drawing.Size(240, 50)
        $button.Location = New-Object System.Drawing.Point(15, $Y_Position)
        $button.DialogResult = $DialogResult
        $button.FlatStyle = 'System'
        return $button
    }

    $button1 = New-DashboardButton -Text "Windows 11 26H2 Professional" -Y_Position 60 -DialogResult Yes
    $button2 = New-DashboardButton -Text "Windows 11 25H2 Professional" -Y_Position 130 -DialogResult No
    $button3 = New-DashboardButton -Text "Windows 11 26H2 Professional" -Y_Position 60 -DialogResult Abort
    $button4 = New-DashboardButton -Text "Handmatige configuratie (GUI)" -Y_Position 60 -DialogResult Retry
    $button5 = New-DashboardButton -Text "Afsluiten en Herstarten" -Y_Position 130 -DialogResult Ignore
    $button6 = New-DashboardButton -Text "Alleen Afsluiten (Exit)" -Y_Position 200 -DialogResult Cancel

    $groupBoxNL.Controls.AddRange(@($button1, $button2))
    $groupBoxEN.Controls.Add($button3)
    $groupBoxOther.Controls.AddRange(@($button4, $button5, $button6))
    
    $fontInfo = New-Object System.Drawing.Font('Segoe UI', 9)
    $fontInfoBold = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    
    $infoTitleText = "Belangrijke informatie over Zero-Touch:"
    
    $infoPoint1 = "* De installatie wist de volledige harde schijf zonder extra bevestiging."
    $infoPoint2 = "* Windows wordt direct voorzien van de laatste cumulatieve updates en drivers."
    $infoPoint3 = "* Het volledige proces kan tot zeker 60 minuten duren."
    $infoManual = "`nVoor een handmatige installatie kiest u de optie 'Handmatige configuratie (GUI)' in de rechterkolom."
    $infoBodyText = "$infoPoint1`n$infoPoint2`n$infoPoint3`n$infoManual"

    $infoTitleLabel = New-Object System.Windows.Forms.Label
    $infoTitleLabel.Text = $infoTitleText
    $infoTitleLabel.Font = $fontInfoBold
    $infoTitleLabel.AutoSize = $true 
    $infoTitleLabel.Location = New-Object System.Drawing.Point(15, 480)
    
    $infoBodyLabel = New-Object System.Windows.Forms.Label
    $infoBodyLabel.Text = $infoBodyText
    $infoBodyLabel.Font = $fontInfo
    $infoBodyLabel.Location = New-Object System.Drawing.Point(15, 505) 
    $infoBodyLabel.Size = New-Object System.Drawing.Size(850, 80)

    $form.Controls.AddRange(@($groupBoxNL, $groupBoxEN, $groupBoxOther, $infoTitleLabel, $infoBodyLabel))

    $form.Controls.AddRange(@($groupBoxNL, $groupBoxEN, $groupBoxOther, $infoLabel))
 
    $result = $form.ShowDialog()
    
    if ($memoryStream) { $memoryStream.Dispose() }
    if (Test-Path $tempLogoPath) { Remove-Item $tempLogoPath -Force -ErrorAction SilentlyContinue }

    $selection = switch ($result) {
        'Yes'    { '1' }
        'No'     { '2' }
        'Abort'  { '3' }
        'Retry'  { '4' }
        'Ignore' { '5' }
        'Cancel' { '6' }
        Default  { '6' }
    }
    return $selection
}

# =================================================================
# HOOFDSCRIPT LOGICA
# =================================================================

# --- Stap 1: Roep de GUI aan en wacht op de keuze van de gebruiker ---
# Het script pauzeert hier totdat er een knop is ingedrukt.
$userChoice = Show-OSDCloudGUI_Dashboard

# --- Stap 2: Nieuwe OSDCloud-module (v2) laden ---
if ($userChoice -in ('1', '2', '3', '4')) {
    Write-Host -ForegroundColor Yellow "Keuze '$userChoice' ontvangen. OSDCloud (v2) wordt voorbereid..."
    Import-Module OSDCloud -Force
    Write-Host -ForegroundColor Green "OSDCloud module versie: $((Get-Module OSDCloud).Version)"
}

# Gedeelde instellingen voor de zero-touch opties
# -CLI   : geen OSDCloud-GUI, direct starten
# -Force : schijf wissen zonder bevestiging (zero-touch)
# -PostAction Quit : niet zelf herstarten; eerst SetupComplete voorbereiden (Stap 4)
$DeployCommon = @{
    CLI          = $true
    Force        = $true
    PostAction   = 'Quit'
    OSEdition    = 'Pro'
    OSActivation = 'Volume'
}

# --- Stap 3: Voer de actie uit die overeenkomt met de gemaakte keuze ---
switch ($userChoice) {
    '1' { Deploy-OSDCloud @DeployCommon -OperatingSystem 'Windows 11 26H2' -OSLanguageCode 'nl-nl' }
    '2' { Deploy-OSDCloud @DeployCommon -OperatingSystem 'Windows 11 25H2' -OSLanguageCode 'nl-nl' }
    '3' { Deploy-OSDCloud @DeployCommon -OperatingSystem 'Windows 11 26H2' -OSLanguageCode 'en-us' }
    '4' { Deploy-OSDCloud -PostAction Quit }      # OSDCloud v2 GUI
    '5' {
        Write-Host -ForegroundColor Yellow "Script wordt afgesloten. De computer wordt nu opnieuw opgestart..."
        Start-Sleep -Seconds 3
        wpeutil reboot
    }
    '6' {
        Write-Host -ForegroundColor Yellow "Script wordt afgesloten."
        Start-Sleep -Seconds 3
        exit
    }
}

# --- Stap 4: Windows Updates (CU + drivers) na installatie via SetupComplete ---
# OSDCloud v2 heeft (nog) geen werkende Microsoft Update Catalog-driverstap.
# Daarom draait na de setup, als SYSTEM en voor OOBE, ons eigen Windows Update-script.
$WUScriptUrl  = 'https://raw.githubusercontent.com/ebeverdam/OSDCloud/refs/heads/main/scripts/Install-OSUpdates.ps1'
$WUScriptArgs = '-Silent'                # alle updates: cumulatieve updates (CU), Defender, .NET en drivers
$OSDrive      = 'C:'

if (Test-Path "$OSDrive\Windows\System32\config\SOFTWARE") {
    Write-Host -ForegroundColor Cyan "Windows Update-stap voorbereiden in SetupComplete..."

    $WUDir    = "$OSDrive\ProgramData\Scripts\WindowsUpdates"
    $WUScript = Join-Path $WUDir 'Install-OSUpdates.ps1'
    New-Item -Path $WUDir -ItemType Directory -Force | Out-Null

    try {
        Invoke-WebRequest -Uri $WUScriptUrl -OutFile $WUScript -UseBasicParsing
        Write-Host -ForegroundColor Green "Windows Update-script gedownload naar $WUScript"

        $SetupScripts  = "$OSDrive\Windows\Setup\Scripts"
        $SetupComplete = Join-Path $SetupScripts 'SetupComplete.cmd'
        New-Item -Path $SetupScripts -ItemType Directory -Force | Out-Null

        # Toevoegen (niet overschrijven): OSDCloud kan hier zelf al driverpack-stappen in zetten
        $Lines = @(
            ''
            'REM === Connectium: Windows Updates (CU + drivers) ==='
            "%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"C:\ProgramData\Scripts\WindowsUpdates\Install-OSUpdates.ps1`" $WUScriptArgs"
        )
        Add-Content -Path $SetupComplete -Value $Lines -Encoding Ascii
        Write-Host -ForegroundColor Green "SetupComplete.cmd bijgewerkt."

        # --- Tweede, zichtbare Windows Update-ronde bij de eerste aanmelding ---
        # Na de herstart (CU afgerond) komen vervolg-updates beschikbaar.
        # Eenmalige taak als SYSTEM; het script toont via ServiceUI de GUI in de gebruikerssessie.
        $TaskName     = 'Connectium\FirstLogonWindowsUpdates'
        $FirstLogonCmd = Join-Path $WUDir 'FirstLogonUpdates.cmd'
        $FirstLogonContent = @(
            '@echo off'
            'REM Connectium: eenmalige Windows Update-ronde met GUI bij eerste aanmelding'
            '"%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\Scripts\WindowsUpdates\Install-OSUpdates.ps1" -IgnoreOOBECheck'
            "schtasks /Delete /TN `"$TaskName`" /F"
        )
        Set-Content -Path $FirstLogonCmd -Value $FirstLogonContent -Encoding Ascii

        $TaskLines = @(
            ''
            'REM === Connectium: eenmalige Windows Update-ronde met GUI bij eerste aanmelding ==='
            "schtasks /Create /TN `"$TaskName`" /TR `"C:\ProgramData\Scripts\WindowsUpdates\FirstLogonUpdates.cmd`" /SC ONLOGON /DELAY 0002:00 /RU SYSTEM /RL HIGHEST /F"
        )
        Add-Content -Path $SetupComplete -Value $TaskLines -Encoding Ascii
        Write-Host -ForegroundColor Green "Eenmalige Windows Update-taak voor eerste aanmelding toegevoegd."
    }
    catch {
        Write-Warning "Windows Update-stap kon niet worden voorbereid: $($_.Exception.Message)"
        Write-Warning "De installatie gaat door zonder Windows Update-drivers."
    }

    # Melding vooraf: tijdens SetupComplete kan Windows geen vensters tonen
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $Script:Remaining = 30
        $NoticeForm = New-Object System.Windows.Forms.Form
        $NoticeForm.Text            = 'Connectium B.V. - OSDCloud Deployment'
        $NoticeForm.Size            = New-Object System.Drawing.Size(560, 260)
        $NoticeForm.StartPosition   = 'CenterScreen'
        $NoticeForm.FormBorderStyle = 'FixedDialog'
        $NoticeForm.MaximizeBox     = $false
        $NoticeForm.MinimizeBox     = $false
        $NoticeForm.TopMost         = $true

        $NoticeTitle = New-Object System.Windows.Forms.Label
        $NoticeTitle.Text     = 'Let op: na de herstart worden updates en drivers geinstalleerd'
        $NoticeTitle.Font     = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
        $NoticeTitle.Location = New-Object System.Drawing.Point(20, 20)
        $NoticeTitle.Size     = New-Object System.Drawing.Size(510, 25)

        $NoticeBody = New-Object System.Windows.Forms.Label
        $NoticeBody.Text     = "Windows installeert na de herstart automatisch Windows Updates en driver-updates.`n`n" +
                               "Het scherm 'Even geduld' kan daardoor aanzienlijk langer zichtbaar blijven.`n" +
                               "Zet de computer niet uit en houd de netwerkkabel aangesloten."
        $NoticeBody.Font     = New-Object System.Drawing.Font('Segoe UI', 10)
        $NoticeBody.Location = New-Object System.Drawing.Point(20, 55)
        $NoticeBody.Size     = New-Object System.Drawing.Size(510, 90)

        $NoticeButton = New-Object System.Windows.Forms.Button
        $NoticeButton.Text         = "Nu herstarten ($Script:Remaining)"
        $NoticeButton.Font         = New-Object System.Drawing.Font('Segoe UI', 10)
        $NoticeButton.Size         = New-Object System.Drawing.Size(200, 40)
        $NoticeButton.Location     = New-Object System.Drawing.Point(330, 160)
        $NoticeButton.DialogResult = 'OK'

        $NoticeTimer = New-Object System.Windows.Forms.Timer
        $NoticeTimer.Interval = 1000
        $NoticeTimer.Add_Tick({
            $Script:Remaining--
            $NoticeButton.Text = "Nu herstarten ($Script:Remaining)"
            if ($Script:Remaining -le 0) { $NoticeTimer.Stop(); $NoticeForm.Close() }
        })

        $NoticeForm.Controls.AddRange(@($NoticeTitle, $NoticeBody, $NoticeButton))
        $NoticeForm.AcceptButton = $NoticeButton
        $NoticeForm.Add_Shown({ $NoticeTimer.Start() })
        [void]$NoticeForm.ShowDialog()
        $NoticeTimer.Dispose()
        $NoticeForm.Dispose()
    }
    catch {
        Write-Warning "Melding kon niet worden getoond: $($_.Exception.Message)"
    }

    Write-Host -ForegroundColor Green "Installatie voltooid. De computer wordt nu opnieuw opgestart..."
    Start-Sleep -Seconds 3
    wpeutil reboot
}
else {
    # Geen Windows op C: -> deployment is gestopt of mislukt. Niet herstarten, zodat je de fout kunt lezen.
    Write-Warning "Geen Windows-installatie gevonden op $OSDrive. Controleer de meldingen hierboven."
    Write-Host "Logs: X:\Windows\Temp\osdcloud-logs"
}
