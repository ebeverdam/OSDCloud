# =================================================================
# OSDCloud Deployment Script met GUI
# Versie: v2 (OSDCloud-module / Deploy-OSDCloud) - TEST
# Auteur: Connectium B.V. / E. Beverdam
# =================================================================

#################################################################
# Volledige GUI voor OSDCloud Keuzemenu
#################################################################
Write-Host -ForegroundColor Green "Version 2026.10.16.v2-test9"

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
# Gegevens van het apparaat invullen (C-label, klant)
# =================================================================
$CLabelPattern = '^C\d{4,6}$'   # bijvoorbeeld C01234

function Show-DeploymentInfoForm {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $font      = New-Object System.Drawing.Font('Segoe UI', 10)
    $fontBold  = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $fontTitle = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = 'Connectium B.V. - Gegevens apparaat'
    $form.Size            = New-Object System.Drawing.Size(520, 400)
    $form.StartPosition   = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.TopMost         = $true

    $title = New-Object System.Windows.Forms.Label
    $title.Text     = 'Gegevens van dit apparaat'
    $title.Font     = $fontTitle
    $title.Location = New-Object System.Drawing.Point(24, 20)
    $title.Size     = New-Object System.Drawing.Size(460, 26)

    $lblLabel = New-Object System.Windows.Forms.Label
    $lblLabel.Text     = 'C-label (sticker op het apparaat), bijv. C01234'
    $lblLabel.Font     = $fontBold
    $lblLabel.Location = New-Object System.Drawing.Point(24, 62)
    $lblLabel.Size     = New-Object System.Drawing.Size(460, 22)

    $txtLabel = New-Object System.Windows.Forms.TextBox
    $txtLabel.Font            = New-Object System.Drawing.Font('Consolas', 12)
    $txtLabel.Location        = New-Object System.Drawing.Point(24, 88)
    $txtLabel.Size            = New-Object System.Drawing.Size(200, 30)
    $txtLabel.MaxLength       = 7
    $txtLabel.CharacterCasing = 'Upper'

    $chkNone = New-Object System.Windows.Forms.CheckBox
    $chkNone.Text     = 'Geen C-label bekend'
    $chkNone.Font     = $font
    $chkNone.Location = New-Object System.Drawing.Point(240, 90)
    $chkNone.Size     = New-Object System.Drawing.Size(240, 26)
    $chkNone.Add_CheckedChanged({ $txtLabel.Enabled = -not $chkNone.Checked; if ($chkNone.Checked) { $txtLabel.Text = '' } })

    $lblCust = New-Object System.Windows.Forms.Label
    $lblCust.Text     = 'Klant / organisatie'
    $lblCust.Font     = $fontBold
    $lblCust.Location = New-Object System.Drawing.Point(24, 136)
    $lblCust.Size     = New-Object System.Drawing.Size(460, 22)

    $txtCust = New-Object System.Windows.Forms.TextBox
    $txtCust.Font      = $font
    $txtCust.Location  = New-Object System.Drawing.Point(24, 162)
    $txtCust.Size      = New-Object System.Drawing.Size(456, 28)
    $txtCust.MaxLength = 80

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text     = 'Het C-label wordt ook de computernaam.'
    $lblInfo.Font     = New-Object System.Drawing.Font('Segoe UI', 9)
    $lblInfo.ForeColor = [System.Drawing.Color]::FromArgb(90, 100, 117)
    $lblInfo.Location = New-Object System.Drawing.Point(24, 200)
    $lblInfo.Size     = New-Object System.Drawing.Size(460, 20)

    $lblError = New-Object System.Windows.Forms.Label
    $lblError.Font      = $fontBold
    $lblError.ForeColor = [System.Drawing.Color]::FromArgb(176, 40, 30)
    $lblError.Location  = New-Object System.Drawing.Point(24, 228)
    $lblError.Size      = New-Object System.Drawing.Size(460, 40)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text     = 'Doorgaan'
    $btnOk.Font     = $fontBold
    $btnOk.Size     = New-Object System.Drawing.Size(150, 44)
    $btnOk.Location = New-Object System.Drawing.Point(330, 290)
    $btnOk.FlatStyle = 'System'

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text         = 'Terug naar menu'
    $btnCancel.Font         = $font
    $btnCancel.Size         = New-Object System.Drawing.Size(150, 44)
    $btnCancel.Location     = New-Object System.Drawing.Point(166, 290)
    $btnCancel.DialogResult = 'Cancel'
    $btnCancel.FlatStyle    = 'System'

    $btnOk.Add_Click({
        $value = $txtLabel.Text.Trim().ToUpper()
        if (-not $chkNone.Checked -and $value -notmatch $CLabelPattern) {
            $lblError.Text = 'Vul een geldig C-label in (C gevolgd door 4 tot 6 cijfers), of vink "Geen C-label bekend" aan.'
            $txtLabel.Focus()
            return
        }
        $form.DialogResult = 'OK'
        $form.Close()
    })

    $form.Controls.AddRange(@($title, $lblLabel, $txtLabel, $chkNone, $lblCust, $txtCust, $lblInfo, $lblError, $btnOk, $btnCancel))
    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel
    $form.Add_Shown({ $txtLabel.Focus() })

    $result = $form.ShowDialog()
    $info = $null
    if ($result -eq 'OK') {
        $info = [pscustomobject]@{
            CLabel   = if ($chkNone.Checked) { '' } else { $txtLabel.Text.Trim().ToUpper() }
            Customer = $txtCust.Text.Trim()
        }
    }
    $form.Dispose()
    return $info
}

# =================================================================
# HOOFDSCRIPT LOGICA
# =================================================================

# --- Stap 1: Keuze in het menu, daarna gegevens van het apparaat ---
# "Terug naar menu" in het gegevensvenster toont het keuzemenu opnieuw.
$DeployInfo = $null
do {
    $userChoice = Show-OSDCloudGUI_Dashboard
    if ($userChoice -notin ('1', '2', '3', '4')) { break }
    $DeployInfo = Show-DeploymentInfoForm
} while (-not $DeployInfo)

if ($DeployInfo) {
    $shown = if ($DeployInfo.CLabel) { $DeployInfo.CLabel } else { '(geen)' }
    Write-Host -ForegroundColor Cyan "C-label: $shown - Klant: $($DeployInfo.Customer)"
}

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
$ReportUrl    = 'https://raw.githubusercontent.com/ebeverdam/OSDCloud/refs/heads/main/scripts/New-InstallReport.ps1'
$LogoUrl      = 'https://raw.githubusercontent.com/ebeverdam/OSDCloud/refs/heads/main/images/Connectium.png'
$WUScriptArgs = '-Silent'                # alle updates: cumulatieve updates (CU), Defender, .NET en drivers
$OSDrive      = 'C:'
$GuestSSID    = 'Connectium Gasten'      # open WiFi: verbinden in SetupComplete als er geen kabel is

if (Test-Path "$OSDrive\Windows\System32\config\SOFTWARE") {
    # --- Gegevens van het apparaat vastleggen + C-label als computernaam ---
    if ($DeployInfo) {
        try {
            $DeployData = [ordered]@{
                CLabel        = $DeployInfo.CLabel
                Customer      = $DeployInfo.Customer
                DeployDate    = (Get-Date).ToString('s')
                DeployVersion = 'v2'
                Choice        = $userChoice
            }

            # 1. JSON-bestand op C:
            $DataDir = "$OSDrive\ProgramData\Connectium"
            New-Item -Path $DataDir -ItemType Directory -Force | Out-Null
            $DeployData | ConvertTo-Json | Set-Content -Path (Join-Path $DataDir 'Deployment.json') -Encoding UTF8

            # 2. Register (offline SOFTWARE-hive): HKLM\SOFTWARE\Connectium\Deployment
            $null = reg.exe load 'HKLM\OSD_SOFTWARE' "$OSDrive\Windows\System32\config\SOFTWARE"
            try {
                foreach ($k in $DeployData.Keys) {
                    $null = reg.exe add 'HKLM\OSD_SOFTWARE\Connectium\Deployment' /v $k /t REG_SZ /d "$($DeployData[$k])" /f
                }
            }
            finally {
                [gc]::Collect(); Start-Sleep -Seconds 1
                $null = reg.exe unload 'HKLM\OSD_SOFTWARE'
            }
            Write-Host -ForegroundColor Green "Gegevens vastgelegd (C-label: $($DeployData.CLabel), klant: $($DeployData.Customer))."

            # 3. C-label als computernaam via unattend.xml (specialize-fase)
            if ($DeployInfo.CLabel) {
                $Arch      = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
                $Panther   = "$OSDrive\Windows\Panther"
                $Unattend  = Join-Path $Panther 'unattend.xml'
                $UnNs      = 'urn:schemas-microsoft-com:unattend'
                New-Item -Path $Panther -ItemType Directory -Force | Out-Null

                if (Test-Path $Unattend) {
                    [xml]$Xml = Get-Content -Path $Unattend -Raw
                } else {
                    [xml]$Xml = "<?xml version=`"1.0`" encoding=`"utf-8`"?><unattend xmlns=`"$UnNs`"></unattend>"
                }
                $Ns = New-Object System.Xml.XmlNamespaceManager($Xml.NameTable)
                $Ns.AddNamespace('u', $UnNs)

                $Settings = $Xml.SelectSingleNode("//u:settings[@pass='specialize']", $Ns)
                if (-not $Settings) {
                    $Settings = $Xml.CreateElement('settings', $UnNs)
                    $Settings.SetAttribute('pass', 'specialize')
                    [void]$Xml.DocumentElement.AppendChild($Settings)
                }
                $Shell = $Settings.SelectSingleNode("u:component[@name='Microsoft-Windows-Shell-Setup']", $Ns)
                if (-not $Shell) {
                    $Shell = $Xml.CreateElement('component', $UnNs)
                    $Shell.SetAttribute('name', 'Microsoft-Windows-Shell-Setup')
                    $Shell.SetAttribute('processorArchitecture', $Arch)
                    $Shell.SetAttribute('publicKeyToken', '31bf3856ad364e35')
                    $Shell.SetAttribute('language', 'neutral')
                    $Shell.SetAttribute('versionScope', 'nonSxS')
                    [void]$Settings.AppendChild($Shell)
                }
                $NameNode = $Shell.SelectSingleNode('u:ComputerName', $Ns)
                if (-not $NameNode) {
                    $NameNode = $Xml.CreateElement('ComputerName', $UnNs)
                    [void]$Shell.PrependChild($NameNode)
                }
                $NameNode.InnerText = $DeployInfo.CLabel
                $Xml.Save($Unattend)
                Write-Host -ForegroundColor Green "Computernaam wordt bij de eerste start: $($DeployInfo.CLabel)"
            }
        }
        catch {
            Write-Warning "Gegevens apparaat konden niet volledig worden vastgelegd: $($_.Exception.Message)"
        }
    }
    Write-Host -ForegroundColor Cyan "Windows Update-stap voorbereiden in SetupComplete..."

    $WUDir    = "$OSDrive\ProgramData\Scripts\WindowsUpdates"
    $WUScript = Join-Path $WUDir 'Install-OSUpdates.ps1'
    New-Item -Path $WUDir -ItemType Directory -Force | Out-Null

    try {
        Invoke-WebRequest -Uri $WUScriptUrl -OutFile $WUScript -UseBasicParsing
        Write-Host -ForegroundColor Green "Windows Update-script gedownload naar $WUScript"

        # Installatierapport (na ronde 2 bij eerste aanmelding); mislukt de download, dan gaat de rest door
        try {
            Invoke-WebRequest -Uri $ReportUrl -OutFile (Join-Path $WUDir 'New-InstallReport.ps1') -UseBasicParsing
            Invoke-WebRequest -Uri $LogoUrl   -OutFile (Join-Path $WUDir 'Connectium.png')        -UseBasicParsing
            Write-Host -ForegroundColor Green "Installatierapport-script gedownload."
        }
        catch { Write-Warning "Installatierapport-script niet gedownload: $($_.Exception.Message)" }

        $SetupScripts  = "$OSDrive\Windows\Setup\Scripts"
        $SetupComplete = Join-Path $SetupScripts 'SetupComplete.cmd'
        New-Item -Path $SetupScripts -ItemType Directory -Force | Out-Null

        # --- Netwerk in SetupComplete: zonder kabel verbinden met het gasten-WiFi ---
        $WlanXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$GuestSSID</name>
    <SSIDConfig>
        <SSID>
            <name>$GuestSSID</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>open</authentication>
                <encryption>none</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
        </security>
    </MSM>
</WLANProfile>
"@
        Set-Content -Path (Join-Path $WUDir 'GuestWiFi.xml') -Value $WlanXml -Encoding UTF8

        $ConnectScript = @'
# Connectium: netwerk regelen voor de Windows Update-ronde in SetupComplete
$SSID        = '__SSID__'
$ProfilePath = 'C:\ProgramData\Scripts\WindowsUpdates\GuestWiFi.xml'
$LogFile     = 'C:\ProgramData\Scripts\WindowsUpdates\Network.log'
$TestUrl     = 'http://www.msftconnecttest.com/connecttest.txt'

function Log($m) { "[$(Get-Date -Format 'HH:mm:ss')] $m" | Out-File $LogFile -Append -Encoding utf8 }
function Test-Internet {
    try { (Invoke-WebRequest -Uri $TestUrl -UseBasicParsing -TimeoutSec 5).Content -match 'Microsoft Connect Test' }
    catch { $false }
}

Log 'Netwerk controleren...'
# Eerste start: bekabeld netwerk heeft soms even nodig voor DHCP
for ($i = 1; $i -le 6; $i++) {
    if (Test-Internet) { Log 'Internet aanwezig, WiFi niet nodig.'; exit 0 }
    Start-Sleep -Seconds 5
}

$Interfaces = netsh wlan show interfaces 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $Interfaces -notmatch '(?i)(Name|Naam)\s*:') {
    Log 'Geen WiFi-adapter of driver gevonden. Windows Update wordt overgeslagen of faalt zonder netwerk.'
    exit 0
}

Log "Verbinden met '$SSID'..."
$null = netsh wlan delete profile name="$SSID" 2>&1
$null = netsh wlan add profile filename="$ProfilePath" user=all 2>&1
$null = netsh wlan connect name="$SSID" ssid="$SSID" 2>&1

for ($i = 1; $i -le 20; $i++) {
    Start-Sleep -Seconds 3
    if (Test-Internet) { Log "Verbonden met '$SSID', internet bereikbaar."; exit 0 }
}
Log "Geen internet via '$SSID' (buiten bereik of captive portal?)."
exit 0
'@
        $ConnectScript = $ConnectScript.Replace('__SSID__', $GuestSSID)
        Set-Content -Path (Join-Path $WUDir 'Connect-Network.ps1') -Value $ConnectScript -Encoding UTF8

        # Toevoegen (niet overschrijven): OSDCloud kan hier zelf al driverpack-stappen in zetten
        $Lines = @(
            ''
            'REM === Connectium: netwerk (kabel of gasten-WiFi) ==='
            '%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\Scripts\WindowsUpdates\Connect-Network.ps1"'
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
        # FirstLogon.ps1 controleert of de ECHTE gebruiker is aangemeld (niet OOBE/defaultuser0)
        # en wacht tot het bureaublad er is (na Autopilot-ESP). Pas dan: ronde 2, rapport, opruimen.
        $FirstLogonPs1 = @'
# Connectium: eenmalige Windows Update-ronde + installatierapport bij de eerste echte aanmelding
$TaskName = '__TASK__'
$SSID     = '__SSID__'
$Dir      = 'C:\ProgramData\Scripts\WindowsUpdates'
$LogFile  = Join-Path $Dir 'FirstLogon.log'
$PsExe    = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

function Log($m) { "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" | Out-File $LogFile -Append -Encoding utf8 }

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

# Wachten (max 30 min) tot het bureaublad van de gebruiker er is; tijdens de Autopilot-ESP is dat nog niet zo
$User = $null
for ($i = 0; $i -lt 180; $i++) {
    $User = Get-DesktopUser
    if ($User) { break }
    Start-Sleep -Seconds 10
}
if (-not $User) {
    Log 'Geen bureaublad van een gebruiker gevonden: de taak blijft staan voor de volgende aanmelding.'
    exit 0
}
Log "Gebruiker met bureaublad: $User"
Start-Sleep -Seconds 20   # bureaublad laten opbouwen

& $PsExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir 'Install-OSUpdates.ps1') -IgnoreOOBECheck
Log "Windows Update ronde 2 klaar (exitcode $LASTEXITCODE)."

$Report = Join-Path $Dir 'New-InstallReport.ps1'
if (Test-Path $Report) {
    & $PsExe -NoProfile -ExecutionPolicy Bypass -File $Report
    Log "Installatierapport gemaakt (exitcode $LASTEXITCODE)."
}

schtasks.exe /Delete /TN "$TaskName" /F | Out-Null
netsh.exe wlan delete profile name="$SSID" | Out-Null   # gasten-WiFi niet meenemen naar de klant
Log 'Taak en gasten-WiFi-profiel opgeruimd. Klaar.'
'@
        $FirstLogonPs1 = $FirstLogonPs1.Replace('__TASK__', $TaskName).Replace('__SSID__', $GuestSSID)
        Set-Content -Path (Join-Path $WUDir 'FirstLogon.ps1') -Value $FirstLogonPs1 -Encoding UTF8

        $FirstLogonContent = @(
            '@echo off'
            'REM Connectium: start FirstLogon.ps1 (controleert zelf of de echte gebruiker is aangemeld)'
            '"%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\Scripts\WindowsUpdates\FirstLogon.ps1"'
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
