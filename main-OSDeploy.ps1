# =================================================================
# OSDCloud Deployment Script met GUI
# Versie: Definitief
# Auteur: Connectium B.V. / E. Beverdam
# =================================================================

#################################################################
# Volledige GUI voor OSDCloud Keuzemenu
#################################################################
Write-Host -ForegroundColor Green "Version 2026.10.16.03"

# Workaround OSD 26.10.6.1: HP-driverpack catalogus datumparsing faalt onder nl-NL WinPE
# (opgelost in OSD 26.10.12 - verwijderen zodra die als stabiele versie beschikbaar is)
[System.Threading.Thread]::CurrentThread.CurrentCulture   = 'en-US'
[System.Threading.Thread]::CurrentThread.CurrentUICulture = 'en-US'

#################################################################
# Keuze v1 (OSD / Start-OSDCloud) of v2 (OSDCloud / Deploy-OSDCloud)
# Geen keuze binnen de tijd = v1, zodat zero-touch ongewijzigd blijft.
#################################################################
$V2ScriptUrl = 'https://raw.githubusercontent.com/ebeverdam/OSDCloud/refs/heads/main/main-OSDeploy-v2.ps1'

function Show-OSDCloudVersionChoice {
    param([int]$TimeoutSeconds = 15)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $Script:ChoiceRemaining = $TimeoutSeconds

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = 'Connectium B.V. - OSDCloud Deployment'
    $form.Size            = New-Object System.Drawing.Size(560, 290)
    $form.StartPosition   = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.TopMost         = $true

    $title = New-Object System.Windows.Forms.Label
    $title.Text     = 'Welke deployment-versie wil je gebruiken?'
    $title.Font     = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $title.Location = New-Object System.Drawing.Point(20, 20)
    $title.Size     = New-Object System.Drawing.Size(510, 28)

    $body = New-Object System.Windows.Forms.Label
    $body.Text     = "v1 - Huidige productieversie (OSD / Start-OSDCloud).`n`n" +
                     "v2 - Nieuwe versie (OSDCloud / Deploy-OSDCloud), TEST.`n" +
                     "      Installeert na de herstart Windows Updates en drivers."
    $body.Font     = New-Object System.Drawing.Font('Segoe UI', 10)
    $body.Location = New-Object System.Drawing.Point(20, 60)
    $body.Size     = New-Object System.Drawing.Size(510, 90)

    $btnV1 = New-Object System.Windows.Forms.Button
    $btnV1.Text         = "v1 - Productie ($Script:ChoiceRemaining)"
    $btnV1.Font         = New-Object System.Drawing.Font('Segoe UI', 10)
    $btnV1.Size         = New-Object System.Drawing.Size(240, 50)
    $btnV1.Location     = New-Object System.Drawing.Point(20, 170)
    $btnV1.DialogResult = 'Yes'
    $btnV1.FlatStyle    = 'System'

    $btnV2 = New-Object System.Windows.Forms.Button
    $btnV2.Text         = 'v2 - Nieuw (test)'
    $btnV2.Font         = New-Object System.Drawing.Font('Segoe UI', 10)
    $btnV2.Size         = New-Object System.Drawing.Size(240, 50)
    $btnV2.Location     = New-Object System.Drawing.Point(285, 170)
    $btnV2.DialogResult = 'No'
    $btnV2.FlatStyle    = 'System'

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick({
        $Script:ChoiceRemaining--
        $btnV1.Text = "v1 - Productie ($Script:ChoiceRemaining)"
        if ($Script:ChoiceRemaining -le 0) {
            $timer.Stop()
            $form.DialogResult = 'Yes'
            $form.Close()
        }
    })
    # Bij klikken of muisbeweging over het venster: aftellen stoppen, gebruiker kiest zelf
    $form.Add_MouseEnter({ if ($timer.Enabled) { $timer.Stop(); $btnV1.Text = 'v1 - Productie' } })

    $form.Controls.AddRange(@($title, $body, $btnV1, $btnV2))
    $form.AcceptButton = $btnV1
    $form.Add_Shown({ $timer.Start() })

    $result = $form.ShowDialog()
    $timer.Dispose()
    $form.Dispose()

    if ($result -eq 'No') { return 'v2' }
    return 'v1'
}

$DeployVersion = Show-OSDCloudVersionChoice -TimeoutSeconds 15

if ($DeployVersion -eq 'v2') {
    Write-Host -ForegroundColor Cyan "Keuze: v2. Script wordt geladen van $V2ScriptUrl"
    $V2Script = $null
    try {
        $V2Script = Invoke-RestMethod -Uri $V2ScriptUrl -UseBasicParsing
    }
    catch {
        Write-Warning "v2 kon niet worden gedownload: $($_.Exception.Message)"
        Write-Warning "Terugvallen op v1."
    }

    if ($V2Script) {
        # Alleen de download valt terug op v1. Gaat er tijdens v2 iets mis, dan NIET
        # alsnog v1 starten (de schijf kan al gewist zijn): venster openhouden voor de fout.
        Invoke-Expression $V2Script
        Write-Warning "v2 is beeindigd zonder herstart. Lees de meldingen hierboven."
        Read-Host 'Druk op Enter om af te sluiten'
        exit
    }
}
Write-Host -ForegroundColor Cyan "Keuze: v1 (productie)."
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

# --- Stap 2: Bereid de installatie voor als er een installatie-optie is gekozen ---
# Deze code wordt alleen uitgevoerd als de gebruiker NIET op afsluiten heeft geklikt.
if ($userChoice -in ('1', '2', '3', '4')) {
    Write-Host -ForegroundColor Yellow "Keuze '$userChoice' ontvangen. OSDCloud wordt voorbereid..."

    # Definieer de OSDCloud variabelen. Deze worden alleen ingesteld als het nodig is.
    $Global:MyOSDCloud = [ordered]@{
        Restart               = [bool]$true
        RecoveryPartition     = [bool]$true
        OEMActivation         = [bool]$true
        WindowsUpdate         = [bool]$true
        WindowsUpdateDrivers  = [bool]$true
        WindowsDefenderUpdate = [bool]$true
        SetTimeZone           = [bool]$true
        ClearDiskConfirm      = [bool]$false
        ShutdownSetupComplete = [bool]$false
        SyncMSUpCatDriverUSB  = [bool]$false
        CheckSHA1             = [bool]$false
    }
}

# --- Stap 3: Voer de actie uit die overeenkomt met de gemaakte keuze ---
# De switch reageert op de variabele $userChoice uit de GUI.
switch ($userChoice) {
    '1' { Start-OSDCloud -OSName 'Windows 11 26H2 x64' -OSLanguage 'nl-nl' -OSEdition 'Pro' -OSActivation 'Volume' }
    '2' { Start-OSDCloud -OSName 'Windows 11 25H2 x64' -OSLanguage 'nl-nl' -OSEdition 'Pro' -OSActivation 'Volume' }
    '3' { Start-OSDCloud -OSName 'Windows 11 26H2 x64' -OSLanguage 'en-us' -OSEdition 'Pro' -OSActivation 'Volume' }
    '4' { Start-OSDCloudGui }
    '5' { 
        Write-Host -ForegroundColor Yellow "Script wordt afgesloten. De computer wordt nu opnieuw opgestart..."
        Start-Sleep -Seconds 3
        wpeutil reboot 
        }
    '6' { 
        Write-Host -ForegroundColor Yellow "Script wordt afgesloten."
        Start-Sleep -Seconds 3
        exit # Stop het script hier volledig
    }
}

# --- Stap 4: Herstart de computer na afloop ---
# Deze laatste stap wordt overgeslagen als de gebruiker voor optie '6' heeft gekozen.
Write-Host -ForegroundColor Green "Actie voltooid. De computer wordt nu opnieuw opgestart..."
Start-Sleep -Seconds 5
wpeutil reboot
