# =================================================================
# OSDCloud Deployment Script met GUI
# Versie: Definitief
# Auteur: Connectium B.V. / E. Beverdam
# =================================================================

# Eerst wordt de volledige functie voor de GUI gedefinieerd.
# Het script voert deze code nog niet uit, maar leest het in het geheugen.

#################################################################
# Volledige GUI voor OSDCloud Keuzemenu
#################################################################
function Show-OSDCloudGUI_Dashboard {
    # 1. Assemblies laden
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # 2. Hoofdvenster aanmaken
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Connectium B.V. - OSDCloud Deployment'
    
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    # --- Logo sectie ---
    # Functie om het logo te downloaden met meerdere pogingen
    function Download-FileWithRetry {
        param([string]$Url, [string]$DestinationPath, [int]$MaxRetries = 3, [int]$DelaySeconds = 2)
        $attempt = 0
        while ($attempt -lt $MaxRetries) {
            try {
                Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -UseBasicParsing
                if (Test-Path $DestinationPath) { return $true }
            } catch {
                Write-Warning "Download poging $($attempt + 1) mislukt: $_"
            }
            Start-Sleep -Seconds $DelaySeconds
            $attempt++
        }
        return $false
    }

    # URL en unieke bestandsnaam voor het logo
    $logoUrl = "https://raw.githubusercontent.com/ebeverdam/OSDCloud/refs/heads/main/images/Connectium.png"
    $tempLogoPath = Join-Path -Path $env:TEMP -ChildPath ("Connectium-TEMP" + (Get-Random -Minimum 10000 -Maximum 99999) + ".png")

    # Download en toon het logo
    if (Download-FileWithRetry -Url $logoUrl -DestinationPath $tempLogoPath) {
        $pictureBox = New-Object System.Windows.Forms.PictureBox
        # Gebruik de memory stream methode om file locks te voorkomen
        $fileBytes = [System.IO.File]::ReadAllBytes($tempLogoPath)
        $memoryStream = New-Object System.IO.MemoryStream($fileBytes)
        $pictureBox.Image = [System.Drawing.Image]::FromStream($memoryStream)
        
        $pictureBox.Location = New-Object System.Drawing.Point(130, 20)
        $pictureBox.Size = New-Object System.Drawing.Size(632, 162)
        $pictureBox.SizeMode = 'StretchImage'
        $form.Controls.Add($pictureBox)
    } else {
        Write-Warning "Kon het logo niet downloaden na meerdere pogingen."
    }
    
    # 3. Lettertypes
    $font = New-Object System.Drawing.Font('Segoe UI', 10)
    $fontGroupBox = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $fontInfo = New-Object System.Drawing.Font('Segoe UI', 9)

    # 4. GroupBoxes aanmaken
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

    # 5. Functie voor knoppen
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

    # 6. Knoppen aanmaken
    $button1 = New-DashboardButton -Text "Windows 11 24H2 Professional" -Y_Position 60 -DialogResult Yes
    $button2 = New-DashboardButton -Text "Windows 11 24H2 Home" -Y_Position 130 -DialogResult No
    $button3 = New-DashboardButton -Text "Windows 11 24H2 Professional" -Y_Position 60 -DialogResult Abort
    $button4 = New-DashboardButton -Text "Handmatige configuratie (GUI)" -Y_Position 60 -DialogResult Retry
    $button5 = New-DashboardButton -Text "Afsluiten en Herstarten" -Y_Position 130 -DialogResult Ignore
    $button6 = New-DashboardButton -Text "Alleen Afsluiten (Exit)" -Y_Position 200 -DialogResult Cancel

    # 7. Knoppen toevoegen aan de JUISTE GroupBox
    $groupBoxNL.Controls.AddRange(@($button1, $button2))
    $groupBoxEN.Controls.Add($button3)
    $groupBoxOther.Controls.AddRange(@($button4, $button5, $button6))
    
    # Info balk onderaan de boxen
    $infoTitle = "Belangrijke informatie over Zero-Touch:"
    $infoPoint1 = "• De installatie wist de volledige harde schijf zonder extra bevestiging."
    $infoPoint2 = "• Windows wordt direct voorzien van de laatste cumulatieve updates en drivers."
    $infoPoint3 = "• Het volledige proces duurt circa 30 tot 60 minuten."
    $infoManual = "`nVoor een handmatige installatie kiest u de optie 'Handmatige configuratie (GUI)' in de rechterkolom."
    $fullInfoText = "$infoTitle`n`n$infoPoint1`n$infoPoint2`n$infoPoint3`n$infoManual"

    $infoLabel = New-Object System.Windows.Forms.Label
    $infoLabel.Text = $fullInfoText
    $infoLabel.Font = $fontInfo
    $infoLabel.Location = New-Object System.Drawing.Point(15, 480) 
    $infoLabel.Size = New-Object System.Drawing.Size(850, 100)

    # 8. De GroupBoxes en het info label toevoegen aan het hoofdvenster
    $form.Controls.AddRange(@($groupBoxNL, $groupBoxEN, $groupBoxOther, $infoLabel))
    
    # 9. GUI tonen en wachten op een keuze
    $result = $form.ShowDialog()
    
    # Ruim de memory stream op, indien aangemaakt
    if ($memoryStream) { $memoryStream.Dispose() }
    # Ruim het tijdelijke bestand op
    if (Test-Path $tempLogoPath) { Remove-Item $tempLogoPath -Force -ErrorAction SilentlyContinue }

    # 10. Keuze "vertalen" naar een waarde
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
        Restart               = [bool]$False
        RecoveryPartition     = [bool]$true
        OEMActivation         = [bool]$True
        TimeZone              = 'W. Europe Standard Time' # Belangrijke toevoeging
        WindowsUpdate         = [bool]$true
        WindowsUpdateDrivers  = [bool]$true
        WindowsDefenderUpdate = [bool]$true
        SetTimeZone           = [bool]$true
        ClearDiskConfirm      = [bool]$False
        ShutdownSetupComplete = [bool]$false
        SyncMSUpCatDriverUSB  = [bool]$true
        CheckSHA1             = [bool]$true
    }
}

# --- Stap 3: Voer de actie uit die overeenkomt met de gemaakte keuze ---
# De switch reageert op de variabele $userChoice uit de GUI.
switch ($userChoice) {
    '1' { Start-OSDCloud -OSName 'Windows 11 24H2 x64' -OSLanguage 'nl-nl' -OSEdition 'Professional' -OSActivation 'Volume' }
    '2' { Start-OSDCloud -OSName 'Windows 11 24H2 x64' -OSLanguage 'nl-nl' -OSEdition 'Home' -OSActivation 'Volume' }
    '3' { Start-OSDCloud -OSName 'Windows 11 24H2 x64' -OSLanguage 'en-us' -OSEdition 'Professional' -OSActivation 'Volume' }
    '4' { Start-OSDCloudGui -v2 }
    '5' { # Doe niets, de reboot aan het einde wordt vanzelf uitgevoerd }
    '6' { 
        Write-Host -ForegroundColor Yellow "Script wordt afgesloten. De computer wordt NIET herstart."
        Start-Sleep -Seconds 3
        exit # Stop het script hier volledig
    }
}
}
# --- Stap 4: Herstart de computer na afloop ---
# Deze laatste stap wordt overgeslagen als de gebruiker voor optie '6' heeft gekozen.
Write-Host -ForegroundColor Green "Actie voltooid. De computer wordt nu opnieuw opgestart..."
Start-Sleep -Seconds 5
wpeutil reboot
