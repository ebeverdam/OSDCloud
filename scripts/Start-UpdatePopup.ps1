<#
.SYNOPSIS
    Connectium update-popup: tweede Windows Update-ronde bij de eerste aanmelding,
    met een nette popup voor de gebruiker en daarna het opleverrapport.

.DESCRIPTION
    Twee rollen in een script, die via bestanden in C:\ProgramData\Connectium\Popup samenwerken:

    -Worker  (draait als SYSTEM, gestart door FirstLogon.ps1)
             Zoekt updates, deelt ze in 4 categorieen in en installeert ze in vaste volgorde:
               1. Beveiligingsupdates   2. Defender-updates   3. Stuurprogramma-updates   4. Overige Windows-updates
             Schrijft de voortgang naar status.json, stopt netjes als de gebruiker afbreekt,
             maakt daarna het opleverrapport klaar.

    -Ui      (draait als de aangemelde gebruiker)
             Toont de popup rechtsonder (WPF), leest status.json, schrijft cancel.flag bij afbreken,
             opent het opleverrapport in Edge.

.NOTES
    Auteur: Connectium B.V. / E. Beverdam
    Versie: 2026.10.19.10
    Bestand is bewust ASCII: niet-ASCII tekst staat als HTML-entity en wordt via T() omgezet.
#>

param(
    [switch]$Worker,
    [switch]$Ui
)

# === Gedeelde instellingen ======================================
$Script:PopupDir   = 'C:\ProgramData\Connectium\Popup'
$Script:StatusFile = Join-Path $Script:PopupDir 'status.json'
$Script:CancelFlag = Join-Path $Script:PopupDir 'cancel.flag'
$Script:ClosedFlag = Join-Path $Script:PopupDir 'uiclosed.flag'
$Script:OpenedFlag = Join-Path $Script:PopupDir 'reportopened.flag'
$Script:ScriptDir  = 'C:\ProgramData\Scripts\WindowsUpdates'
$Script:LogFile    = Join-Path $Script:ScriptDir 'Popup.log'
$Script:LogoPath   = Join-Path $Script:ScriptDir 'Connectium.png'
$Script:ReportPs1  = Join-Path $Script:ScriptDir 'New-InstallReport.ps1'
$Script:ReportHtml = 'C:\ProgramData\Connectium\Installatierapport.html'
$Script:EdgeProfile = 'C:\ProgramData\Connectium\RapportBrowser'
$Script:HelpPhone  = '0548 722 045'

function T([string]$s) { [System.Net.WebUtility]::HtmlDecode($s) }

function Write-PopupLog([string]$Msg, [string]$Level = 'INFO') {
    try {
        if (-not (Test-Path $Script:ScriptDir)) { New-Item -Path $Script:ScriptDir -ItemType Directory -Force | Out-Null }
        "[{0}] [{1}] [{2}] {3}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $(if ($Worker) { 'Worker' } else { 'UI' }), $Msg |
            Out-File -FilePath $Script:LogFile -Append -Encoding utf8
    } catch {}
}

# =================================================================
#  WORKER (SYSTEM)
# =================================================================

# Microsoft update-classificaties (vaste ID's, ook op een Nederlandse Windows)
$Script:CatSecurity   = '0fa1201d-4330-4fa8-8ae9-b877473b6441'   # Security Updates
$Script:CatCritical   = 'e6cf1350-c01b-414d-a61f-263d14d133b4'   # Critical Updates
$Script:CatDefinition = 'e0789628-ce08-4437-be74-2495b842f43b'   # Definition Updates
$Script:CatDrivers    = 'ebfc1fc5-71a4-4f7b-9aca-3b9a503104a0'   # Drivers

$Script:Groups = @(
    @{ Key = 'security'; Label = 'Beveiligingsupdates' }
    @{ Key = 'defender'; Label = 'Defender-updates' }
    @{ Key = 'driver';   Label = 'Stuurprogramma-updates' }
    @{ Key = 'other';    Label = 'Overige Windows-updates' }
)

function Get-UpdateGroup($Update) {
    $ids = @()
    try { for ($j = 0; $j -lt $Update.Categories.Count; $j++) { $ids += [string]$Update.Categories.Item($j).CategoryID } } catch {}
    $title = [string]$Update.Title

    if ($Update.Type -eq 2 -or $ids -contains $Script:CatDrivers) { return 'driver' }
    if ($ids -contains $Script:CatDefinition -or $title -match 'Defender|Security platform|Windows Security|KB4052623|KB5007651|KB2267602') { return 'defender' }
    if ($ids -contains $Script:CatSecurity -or $ids -contains $Script:CatCritical) { return 'security' }
    return 'other'
}

function Get-FriendlyName($Update, [string]$Group) {
    switch ($Group) {
        'driver' {
            $map = @{
                'MEDIA' = 'geluid'; 'AudioEndpoint' = 'geluid'; 'Camera' = 'camera'; 'Image' = 'camera'
                'Net' = 'netwerk'; 'Display' = 'beeldscherm'; 'Bluetooth' = 'bluetooth'; 'Sensor' = 'sensoren'
                'HIDClass' = 'invoerapparaten'; 'Keyboard' = 'toetsenbord'; 'Mouse' = 'muis / touchpad'
                'USB' = 'USB'; 'System' = 'systeem'; 'Firmware' = 'firmware'; 'Biometric' = 'vingerafdruk / gezicht'
                'SoftwareComponent' = 'softwareonderdeel'; 'Extension' = 'uitbreiding'; 'SecurityDevices' = 'beveiligingschip'
                'Printer' = 'printer'; 'DiskDrive' = 'opslag'; 'SCSIAdapter' = 'opslag'; 'Battery' = 'accu'
            }
            $cls = ''; $mfr = ''
            try { $cls = [string]$Update.DriverClass } catch {}
            try { $mfr = [string]$Update.DriverManufacturer } catch {}
            $name = if ($cls -and $map.ContainsKey($cls)) { $map[$cls] } elseif ($cls) { $cls.ToLower() } else { 'apparaat' }
            if ($mfr) { $mfr = (($mfr -replace '\((R|TM)\)', '') -replace '\s+(Inc\.?|Corp\.?|Corporation|Co\.,? Ltd\.?|Semiconductor|GmbH)\b.*$', '').Trim() }
            if ($mfr) { return "stuurprogramma voor $name ($mfr)" } else { return "stuurprogramma voor $name" }
        }
        'defender' { return 'Microsoft Defender' }
        'security' {
            if ($Update.Title -match 'Cumulati') { return 'maandelijkse beveiligingsupdate voor Windows' }
            return 'beveiligingsupdate voor Windows'
        }
        default { return 'Windows-update' }
    }
}

function Write-Status([hashtable]$Status) {
    $Status.updated = (Get-Date).ToString('s')
    $tmp = "$Script:StatusFile.tmp"
    try {
        ($Status | ConvertTo-Json -Depth 5) | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $Script:StatusFile -Force
    } catch { Write-PopupLog "Status schrijven mislukt: $($_.Exception.Message)" 'WARN' }
}

function Set-EdgeFirstRunPolicy([bool]$Enable) {
    # Edge-welkomstwizard tijdelijk uit, alleen als wij het beleid zelf zetten
    $key = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    if ($Enable) {
        $existing = (Get-ItemProperty -Path $key -Name HideFirstRunExperience -ErrorAction SilentlyContinue).HideFirstRunExperience
        if ($null -eq $existing) {
            New-Item -Path $key -Force | Out-Null
            New-ItemProperty -Path $key -Name HideFirstRunExperience -Value 1 -PropertyType DWord -Force | Out-Null
            return $true
        }
        return $false
    }
    Remove-ItemProperty -Path $key -Name HideFirstRunExperience -ErrorAction SilentlyContinue
    $k = Get-Item -Path $key -ErrorAction SilentlyContinue
    if ($k -and $k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0) { Remove-Item -Path $key -Force -ErrorAction SilentlyContinue }
}

function Start-Worker {
    Write-PopupLog '--- Worker gestart ---'
    $status = @{
        stage = 'search'; total = 0; installed = 0; failed = 0; current = ''
        rebootRequired = $false; skipped = $false; reportReady = $false; message = ''; rescan = $false; ok = 0
        groups = @($Script:Groups | ForEach-Object { @{ key = $_.Key; label = $_.Label; total = 0; done = 0; state = 'pending' } })
    }
    Write-Status $status

    # --- Zoeken + installeren, in rondes ---
    # Na het installeren van een basisdriver biedt Windows Update vaak nog extensies of
    # onderdelen aan, en een eerste mislukte driver lukt bij een tweede poging meestal wel.
    # Daarom opnieuw zoeken tot er niets nieuws meer is (max $MaxPasses rondes).
    $MaxPasses = 3
    $order     = @{ security = 0; defender = 1; driver = 2; other = 3 }
    $Attempts  = @{}   # UpdateID -> aantal pogingen
    $Final     = @{}   # UpdateID -> $true (gelukt) / $false (mislukt)
    $session   = $null; $searcher = $null

    for ($pass = 1; $pass -le $MaxPasses; $pass++) {
        if (Test-Path $Script:CancelFlag) { break }

        # Zoeken
        $updates = @()
        try {
            if (-not $session) {
                $session = New-Object -ComObject Microsoft.Update.Session
                try {
                    $svc = New-Object -ComObject Microsoft.Update.ServiceManager
                    $svc.AddService2('7971f918-a847-4430-9279-4a52d1efe18d', 7, '') | Out-Null
                } catch {}
            }
            $searcher = $session.CreateUpdateSearcher()
            try { $searcher.ServiceID = '7971f918-a847-4430-9279-4a52d1efe18d'; $searcher.ServerSelection = 3 } catch {}
            if ($pass -gt 1) { $status.rescan = $true; $status.current = ''; Write-Status $status }
            Write-PopupLog "Ronde ${pass}: zoeken naar updates..."
            $result = $searcher.Search('IsInstalled=0 and IsHidden=0 and BrowseOnly=0')
            for ($i = 0; $i -lt $result.Updates.Count; $i++) { $updates += $result.Updates.Item($i) }
            Write-PopupLog "Ronde ${pass}: $($updates.Count) update(s) gevonden."
        }
        catch {
            Write-PopupLog "Zoeken mislukt (ronde $pass): $($_.Exception.Message)" 'ERROR'
            if ($pass -eq 1) {
                $status.stage = 'error'
                $status.message = T 'Er kon niet naar updates worden gezocht. Windows probeert het later vanzelf opnieuw.'
            }
            break
        }
        $status.rescan = $false

        # Alleen nieuwe updates, of eerder mislukte voor een tweede poging
        $updates = @($updates | Where-Object { -not $Attempts.ContainsKey($_.Identity.UpdateID) -or ($Final[$_.Identity.UpdateID] -eq $false -and $Attempts[$_.Identity.UpdateID] -lt 2) })
        if ($updates.Count -eq 0) { Write-PopupLog "Ronde ${pass}: niets nieuws, klaar."; break }

        # Indelen en sorteren
        $plan = @($updates | ForEach-Object {
            $g = Get-UpdateGroup $_
            # Binnen Defender: platform voor definities
            $sub = if ($g -eq 'defender' -and $_.Title -match 'beveiligingsinformatie|Security Intelligence|KB2267602') { 1 } else { 0 }
            [pscustomobject]@{ Update = $_; Group = $g; Order = $order[$g]; Sub = $sub; Name = (Get-FriendlyName $_ $g) }
        } | Sort-Object Order, Sub)

        foreach ($grp in $status.groups) {
            $k = $grp.key; $extra = @($plan | Where-Object { $_.Group -eq $k }).Count
            $grp.total += $extra
            if ($grp.total -eq 0) { $grp.state = 'none' }          # niets nodig = in orde (groen vinkje)
            elseif ($extra -gt 0) { $grp.state = 'pending' }
        }
        $status.total += $plan.Count
        foreach ($p in $plan) { Write-PopupLog (" - [{0}] {1}" -f $p.Group, $p.Update.Title) }

        # Installeren
        $status.stage = 'install'
        foreach ($p in $plan) {
            if (Test-Path $Script:CancelFlag) { $status.skipped = $true; Write-PopupLog 'Afgebroken door gebruiker.'; break }

            $grp = $status.groups | Where-Object { $_.key -eq $p.Group } | Select-Object -First 1
            foreach ($g in $status.groups) { if ($g.state -eq 'active') { $g.state = if ($g.done -ge $g.total) { 'done' } else { 'pending' } } }
            $grp.state = 'active'
            $status.current = $p.Name
            Write-Status $status

            $u  = $p.Update
            $id = $u.Identity.UpdateID
            $Attempts[$id] = 1 + [int]$Attempts[$id]
            try {
                if (-not $u.EulaAccepted) { $u.AcceptEula() }
                $coll = New-Object -ComObject Microsoft.Update.UpdateColl
                $coll.Add($u) | Out-Null
                if (-not $u.IsDownloaded) {
                    $dl = $session.CreateUpdateDownloader(); $dl.Updates = $coll; $dl.Download() | Out-Null
                }
                $inst = $session.CreateUpdateInstaller(); $inst.Updates = $coll
                $res = $inst.Install()
                if ($res.ResultCode -in 2, 3) {
                    $Final[$id] = $true
                    Write-PopupLog "OK: $($u.Title)"
                    if ($res.RebootRequired) { $status.rebootRequired = $true }
                } else {
                    $Final[$id] = $false
                    Write-PopupLog "MISLUKT ($($res.ResultCode)), poging $($Attempts[$id]): $($u.Title)" 'WARN'
                }
            }
            catch {
                $Final[$id] = $false
                Write-PopupLog "MISLUKT, poging $($Attempts[$id]): $($u.Title) - $($_.Exception.Message)" 'WARN'
            }

            $status.installed++
            $grp.done++
            if ($grp.done -ge $grp.total) { $grp.state = 'done' }
            Write-Status $status
        }
        if ($status.skipped) { break }
    }

    # Telling: een update die bij de tweede poging lukte telt als gelukt
    $status.failed = @($Final.Values | Where-Object { $_ -eq $false }).Count
    $status.ok     = @($Final.Values | Where-Object { $_ -eq $true }).Count
    foreach ($g in $status.groups) { if ($g.total -eq 0) { $g.state = 'none' } elseif ($g.done -ge $g.total) { $g.state = 'done' } elseif ($g.state -eq 'active') { $g.state = 'pending' } }
    if ((Test-Path $Script:CancelFlag) -and $status.installed -lt $status.total) { $status.skipped = $true }

    # Eindstand (volle balk, alle vinkjes) even zichtbaar laten voordat de popup verder gaat
    # (ook als er niets nodig was: dan staan alle vier de categorieen op groen)
    if ($status.stage -ne 'error') {
        $status.stage = 'finishing'
        $status.current = ''
        Write-Status $status
        Start-Sleep -Seconds 4
    }

    # --- Afronden: rapport klaarzetten ---
    if ($status.stage -ne 'error') { $status.stage = 'finishing' }
    $status.current = ''
    Write-Status $status

    $ok = $status.ok
    if ($status.stage -ne 'error') {
        if ($status.total -eq 0) {
            $status.message = T 'Je computer is helemaal bijgewerkt. Er waren geen extra updates nodig.'
        } elseif ($status.skipped) {
            $status.message = T ("$ok van $($status.total) updates ge&iuml;nstalleerd. De rest installeert Windows later vanzelf.")
        } else {
            $woord = if ($ok -eq 1) { 'update' } else { 'updates' }
            $status.message = T ("$ok $woord ge&iuml;nstalleerd.")
        }
        if ($status.failed -gt 0) { $status.message += T (" $($status.failed) konden niet worden ge&iuml;nstalleerd; Windows probeert het later opnieuw.") }
        if ($status.rebootRequired) { $status.message += T ' Start je computer &eacute;&eacute;n keer opnieuw op om alles af te ronden.' }
    }

    $policyAdded = $false
    if (Test-Path $Script:ReportPs1) {
        try {
            & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $Script:ReportPs1 -NoOpen | Out-Null
            if (Test-Path $Script:ReportHtml) {
                New-Item -Path $Script:EdgeProfile -ItemType Directory -Force | Out-Null
                $null = icacls.exe $Script:EdgeProfile /grant '*S-1-5-32-545:(OI)(CI)M' /T /Q
                $policyAdded = Set-EdgeFirstRunPolicy $true
                $status.reportReady = $true
                Write-PopupLog 'Opleverrapport klaargezet.'
            }
        } catch { Write-PopupLog "Rapport maken mislukt: $($_.Exception.Message)" 'ERROR' }
    }

    if ($status.stage -ne 'error') { $status.stage = 'done' }
    Write-Status $status
    Write-PopupLog "Klaar: $($status.message)"

    # --- Wachten tot het rapport geopend of de popup gesloten is (max 30 min), dan Edge-beleid opruimen ---
    if ($policyAdded) {
        $deadline = (Get-Date).AddMinutes(30)
        while ((Get-Date) -lt $deadline) {
            if (Test-Path $Script:OpenedFlag) { Start-Sleep -Seconds 20; break }
            if (Test-Path $Script:ClosedFlag) { break }
            Start-Sleep -Seconds 2
        }
        Set-EdgeFirstRunPolicy $false
        Write-PopupLog 'Tijdelijk Edge-beleid verwijderd.'
    }
    Write-PopupLog '--- Worker klaar ---'
}

# =================================================================
#  UI (gebruiker)
# =================================================================
function Start-Ui {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

    # Eigen taakbalk-ID: niet groeperen onder PowerShell, zodat ons eigen pictogram getoond wordt
    try {
        Add-Type -Namespace Cx -Name App -MemberDefinition '[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);'
        [void][Cx.App]::SetCurrentProcessExplicitAppUserModelID('Connectium.UpdatePopup')
    } catch {}

    # Voornaam voor een persoonlijke aanhef ("Elco Kuipers | Videra B.V." -> "Elco").
    # Geen naam bekend, of alleen de accountnaam (lokaal account zonder volledige naam)? Dan zonder naam.
    $FirstName = ''
    try {
        $lui = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI' -ErrorAction Stop
        if ($lui.LastLoggedOnDisplayName -and ([string]$lui.LastLoggedOnSAMUser -split '\\')[-1] -eq $env:USERNAME) {
            $fn = (([string]$lui.LastLoggedOnDisplayName -split '\|')[0].Trim() -split '\s+')[0]
            if ($fn -and $fn -ne $env:USERNAME -and $fn.Length -le 20) { $FirstName = $fn }
        }
    } catch {}

    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Connectium - Updates" Width="492" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" Topmost="True" ShowInTaskbar="True"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="14" Foreground="#26324A">
  <Window.Resources>
    <Style x:Key="BtnBase" TargetType="Button">
      <Setter Property="MinHeight" Value="36"/>
      <Setter Property="Padding" Value="16,0"/>
      <Setter Property="Margin" Value="8,0,0,0"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" CornerRadius="6" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderThickness" Value="2"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="BtnSec" TargetType="Button" BasedOn="{StaticResource BtnBase}">
      <Setter Property="Background" Value="#FFFFFF"/><Setter Property="BorderBrush" Value="#C9CED6"/><Setter Property="Foreground" Value="#26324A"/>
    </Style>
    <Style x:Key="BtnPri" TargetType="Button" BasedOn="{StaticResource BtnBase}">
      <Setter Property="Background" Value="#26324A"/><Setter Property="BorderBrush" Value="#26324A"/><Setter Property="Foreground" Value="#FFFFFF"/>
    </Style>
  </Window.Resources>

  <Grid Margin="16">
    <Border x:Name="Card" Background="#FFFFFF" CornerRadius="12" BorderBrush="#DDE1E7" BorderThickness="1">
      <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="6" Direction="270" Opacity="0.22" Color="#101828"/></Border.Effect>
      <StackPanel>

        <Grid Margin="20,12,12,12">
          <Image x:Name="Logo" Height="22" HorizontalAlignment="Left" VerticalAlignment="Center"/>
          <TextBlock x:Name="LogoText" Text="CONNECTIUM" FontWeight="SemiBold" VerticalAlignment="Center" Visibility="Collapsed"/>
          <Button x:Name="BtnHide" HorizontalAlignment="Right" Width="40" Height="32" Background="Transparent" BorderThickness="0" Cursor="Hand"
                  ToolTip="Verbergen. De updates gaan op de achtergrond door." AutomationProperties.Name="Verbergen">
            <TextBlock Text="&#xE921;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Foreground="#4A5568"/>
          </Button>
        </Grid>
        <Border Height="1" Background="#EEF0F3"/>

        <StackPanel Margin="24,22,24,8">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border x:Name="IconBg" Width="40" Height="40" CornerRadius="20" Background="#EAF0F8" VerticalAlignment="Top">
              <TextBlock x:Name="IconGlyph" Text="&#xE721;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="18" Foreground="#24508A" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <StackPanel Grid.Column="1" Margin="14,0,0,0">
              <TextBlock x:Name="TxtTitle" FontFamily="Segoe UI Variable Display, Segoe UI" FontSize="18" FontWeight="SemiBold" TextWrapping="Wrap"/>
              <TextBlock x:Name="TxtBody" Margin="0,4,0,0" Foreground="#4A5568" TextWrapping="Wrap"/>
            </StackPanel>
          </Grid>

          <StackPanel x:Name="ProgressArea" Margin="0,14,0,0">
            <Border x:Name="Track" Height="6" CornerRadius="3" Background="#E8EBF0" ClipToBounds="True">
              <Border x:Name="Fill" Height="6" CornerRadius="3" Background="#26324A" HorizontalAlignment="Left" Width="0"/>
            </Border>
            <Grid Margin="0,6,0,0">
              <TextBlock x:Name="TxtCurrent" FontSize="13" Foreground="#4A5568" TextTrimming="CharacterEllipsis" Margin="0,0,48,0"/>
              <TextBlock x:Name="TxtPercent" FontSize="13" Foreground="#4A5568" HorizontalAlignment="Right"/>
            </Grid>
          </StackPanel>

          <Border x:Name="DetailsBox" Margin="0,14,0,0" BorderBrush="#EEF0F3" BorderThickness="1" CornerRadius="10">
            <StackPanel>
              <Button x:Name="BtnDetails" Background="Transparent" BorderThickness="0" Padding="14,0" MinHeight="44" HorizontalContentAlignment="Stretch" Cursor="Hand">
                <Grid>
                  <TextBlock Text="Updates per onderdeel" FontWeight="SemiBold"/>
                  <TextBlock x:Name="Chevron" Text="&#xE70E;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="11" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                </Grid>
              </Button>
              <StackPanel x:Name="DetailsList" Margin="14,0,14,10"/>
            </StackPanel>
          </Border>

          <Border x:Name="InfoBox" Margin="0,14,0,0" Padding="14,12" CornerRadius="10" Background="#F4F5F7" Visibility="Collapsed">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <TextBlock Text="&#xE8A5;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="16" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="1" Margin="12,0,0,0" FontSize="13" Foreground="#3E4859" TextWrapping="Wrap"
                         Text="In het opleverrapport zie je wat er is ingesteld en hoe je ons bereikt."/>
            </Grid>
          </Border>
        </StackPanel>

        <Grid Margin="24,16,24,20">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <TextBlock x:Name="TxtHelp" Grid.Column="0" Margin="0,0,12,0" FontSize="12" Foreground="#5A6475" VerticalAlignment="Center" TextWrapping="Wrap"/>
          <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
            <Button x:Name="BtnSecondary" Style="{StaticResource BtnSec}"/>
            <Button x:Name="BtnPrimary" Style="{StaticResource BtnPri}"/>
          </StackPanel>
        </Grid>

      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $win = [Windows.Markup.XamlReader]::Load($reader)
    $c = @{}
    foreach ($n in 'Logo','LogoText','BtnHide','IconBg','IconGlyph','TxtTitle','TxtBody','ProgressArea','Track','Fill','TxtCurrent','TxtPercent',
                   'DetailsBox','BtnDetails','Chevron','DetailsList','InfoBox','TxtHelp','BtnSecondary','BtnPrimary') {
        $c[$n] = $win.FindName($n)
    }

    $conv = New-Object System.Windows.Media.BrushConverter
    function B([string]$hex) { $conv.ConvertFromString($hex) }

    # Logo
    if (Test-Path $Script:LogoPath) {
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit(); $bmp.UriSource = New-Object System.Uri($Script:LogoPath); $bmp.CacheOption = 'OnLoad'; $bmp.EndInit()
        $c.Logo.Source = $bmp
        # Taakbalkpictogram: het C-beeldmerk (linkerdeel van het logo) i.p.v. het PowerShell-pictogram
        try {
            $side = [Math]::Min($bmp.PixelWidth, [int]($bmp.PixelHeight * 1.04))
            $win.Icon = New-Object System.Windows.Media.Imaging.CroppedBitmap($bmp, (New-Object System.Windows.Int32Rect(0, 0, $side, $bmp.PixelHeight)))
        } catch {}
    } else { $c.Logo.Visibility = 'Collapsed'; $c.LogoText.Visibility = 'Visible' }
    $c.TxtHelp.Text = "Hulp nodig?`n$Script:HelpPhone"

    # Detailregels (4 vaste categorieen)
    $rows = @{}
    foreach ($g in $Script:Groups) {
        $grid = New-Object System.Windows.Controls.Grid
        foreach ($w in 'Auto', '*', 'Auto') {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            $cd.Width = if ($w -eq '*') { New-Object System.Windows.GridLength(1, 'Star') } else { [System.Windows.GridLength]::Auto }
            $grid.ColumnDefinitions.Add($cd)
        }
        $sep = New-Object System.Windows.Controls.Border
        $sep.Height = 1; $sep.Background = (B '#F1F3F6'); $sep.VerticalAlignment = 'Top'; [System.Windows.Controls.Grid]::SetColumnSpan($sep, 3)
        $ic = New-Object System.Windows.Controls.Border
        $ic.Width = 20; $ic.Height = 20; $ic.CornerRadius = (New-Object System.Windows.CornerRadius(10)); $ic.BorderThickness = (New-Object System.Windows.Thickness(2)); $ic.Margin = (New-Object System.Windows.Thickness(0, 8, 10, 8))
        $gl = New-Object System.Windows.Controls.TextBlock
        $gl.FontFamily = (New-Object System.Windows.Media.FontFamily('Segoe Fluent Icons, Segoe MDL2 Assets')); $gl.FontSize = 10; $gl.HorizontalAlignment = 'Center'; $gl.VerticalAlignment = 'Center'
        $ic.Child = $gl
        $lb = New-Object System.Windows.Controls.TextBlock
        $lb.Text = $g.Label; $lb.VerticalAlignment = 'Center'; [System.Windows.Controls.Grid]::SetColumn($lb, 1)
        $mt = New-Object System.Windows.Controls.TextBlock
        $mt.FontSize = 13; $mt.Foreground = (B '#5A6475'); $mt.VerticalAlignment = 'Center'; [System.Windows.Controls.Grid]::SetColumn($mt, 2)
        [void]$grid.Children.Add($sep); [void]$grid.Children.Add($ic); [void]$grid.Children.Add($lb); [void]$grid.Children.Add($mt)
        [void]$c.DetailsList.Children.Add($grid)
        $rows[$g.Key] = @{ Icon = $ic; Glyph = $gl; Meta = $mt; Label = $lb }
    }

    $ui = @{ local = $null; status = $null; indet = 0.0; detailsOpen = $true; allowClose = $false; started = (Get-Date) }

    function Set-RowState($row, [string]$state, [int]$done, [int]$total) {
        switch ($state) {
            { $_ -in 'done', 'none' } { $row.Icon.Background = (B '#E6F3EB'); $row.Icon.BorderBrush = (B '#E6F3EB'); $row.Glyph.Text = [string][char]0xE73E; $row.Glyph.Foreground = (B '#17643B') }
            'active'  { $row.Icon.Background = (B '#FFFFFF'); $row.Icon.BorderBrush = (B '#26324A'); $row.Glyph.Text = [string][char]0xE895; $row.Glyph.Foreground = (B '#26324A') }
            default   { $row.Icon.Background = (B '#FFFFFF'); $row.Icon.BorderBrush = (B '#D5DAE1'); $row.Glyph.Text = '' }
        }
        $row.Label.Foreground = (B '#26324A')
        $row.Meta.Text = if ($state -eq 'pending' -and $total -eq 0) { '' }   # nog aan het zoeken
                         elseif ($total -eq 0) { 'Up-to-date' }
                         elseif ($state -eq 'active') { "$done van $total" }
                         elseif ($total -eq 1) { '1 update' } else { "$total updates" }
    }

    function Set-Icon([int]$glyph, [string]$bg, [string]$fg) {
        $c.IconGlyph.Text = [string][char]$glyph; $c.IconBg.Background = (B $bg); $c.IconGlyph.Foreground = (B $fg)
    }

    function Show-Buttons($sec, $pri) {
        foreach ($p in @(@($c.BtnSecondary, $sec), @($c.BtnPrimary, $pri))) {
            if ($p[1]) { $p[0].Content = $p[1]; $p[0].Visibility = 'Visible' } else { $p[0].Visibility = 'Collapsed' }
        }
    }

    function Update-View {
        $s = $ui.status
        $stage = if ($ui.local) { $ui.local } elseif ($s) { $s.stage } else { 'search' }
        $c.InfoBox.Visibility = 'Collapsed'
        $c.DetailsBox.Visibility = 'Collapsed'
        $c.ProgressArea.Visibility = 'Visible'

        switch ($stage) {
            'search' {
                Set-Icon 0xE721 '#EAF0F8' '#24508A'
                $c.TxtTitle.Text = if ($FirstName) { "Hoi $FirstName, je computer wordt bijgewerkt" } else { 'Je computer wordt bijgewerkt' }
                $c.TxtBody.Text = T 'We kijken nog &eacute;&eacute;n keer of er updates zijn. Je kunt gewoon verder werken.'
                $c.TxtCurrent.Text = T 'Zoeken naar updates&hellip;'; $c.TxtPercent.Text = ''
                if ($s -and $s.groups) {
                    $c.DetailsBox.Visibility = 'Visible'
                    foreach ($g in $s.groups) { Set-RowState $rows[$g.key] $g.state $g.done $g.total }
                }
                Show-Buttons 'Overslaan' $null
            }
            'install' {
                Set-Icon 0xE896 '#EAF0F8' '#24508A'
                $n = [Math]::Min($s.installed + 1, $s.total)
                $c.TxtTitle.Text = 'Updates installeren'
                $c.TxtBody.Text = "$n van $($s.total) updates. Je kunt gewoon verder werken."
                $pct = if ($s.total) { [int]([Math]::Round($s.installed / $s.total * 100)) } else { 0 }
                $c.TxtCurrent.Text = if ($s.rescan) { T 'Controleren op extra updates&hellip;' } elseif ($s.current) { "Nu bezig: $($s.current)" } else { '' }; $c.TxtPercent.Text = "$pct%"
                $c.Fill.Margin = (New-Object System.Windows.Thickness(0)); $c.Fill.Width = [Math]::Max(0, $c.Track.ActualWidth * $pct / 100)
                $c.DetailsBox.Visibility = 'Visible'
                foreach ($g in $s.groups) { Set-RowState $rows[$g.key] $g.state $g.done $g.total }
                Show-Buttons 'Afbreken' $null
            }
            'confirm' {
                Set-Icon 0xE7BA '#FBF0DE' '#7F4A00'
                $c.TxtTitle.Text = 'Updates overslaan?'
                $c.TxtBody.Text = 'De overige updates installeert Windows later vanzelf. Het opleverrapport kun je daarna gewoon bekijken.'
                $c.ProgressArea.Visibility = 'Collapsed'
                Show-Buttons 'Overslaan' 'Doorgaan met updates'
            }
            { $_ -in 'skipping', 'finishing' } {
                Set-Icon 0xE895 '#EAF0F8' '#24508A'
                $c.TxtTitle.Text = 'Bijna klaar'
                $c.TxtBody.Text = 'We ronden af en zetten je opleverrapport klaar.'
                $c.TxtCurrent.Text = T 'Afronden&hellip;'; $c.TxtPercent.Text = ''
                if ($s -and $s.groups) {
                    $c.DetailsBox.Visibility = 'Visible'
                    foreach ($g in $s.groups) { Set-RowState $rows[$g.key] $g.state $g.done $g.total }
                }
                Show-Buttons $null $null
            }
            { $_ -in 'done', 'error' } {
                if ($stage -eq 'error') { Set-Icon 0xE7BA '#FBF0DE' '#7F4A00'; $c.TxtTitle.Text = 'Updates later' }
                else { Set-Icon 0xE73E '#E6F3EB' '#17643B'; $c.TxtTitle.Text = if ($FirstName) { "Je computer is klaar, $FirstName" } else { 'Je computer is klaar' } }
                $c.TxtBody.Text = [string]$s.message
                $c.ProgressArea.Visibility = 'Collapsed'
                $ui.allowClose = $true
                if ($s.reportReady) { Show-Buttons 'Sluiten' 'Opleverrapport bekijken' }
                else { Show-Buttons 'Sluiten' $null }
            }
        }
        $c.DetailsList.Visibility = if ($ui.detailsOpen) { 'Visible' } else { 'Collapsed' }
        $c.Chevron.Text = if ($ui.detailsOpen) { [string][char]0xE70E } else { [string][char]0xE70D }
    }

    function Open-Report {
        $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
            Where-Object { Test-Path $_ } | Select-Object -First 1
        try {
            if ($edge) {
                Start-Process -FilePath $edge -ArgumentList "--user-data-dir=`"$Script:EdgeProfile`" --inprivate --no-first-run --no-default-browser-check --start-maximized `"$Script:ReportHtml`""
            } else {
                Start-Process -FilePath $Script:ReportHtml
            }
            New-Item -Path $Script:OpenedFlag -ItemType File -Force | Out-Null
            Write-PopupLog 'Opleverrapport geopend.'
        } catch { Write-PopupLog "Rapport openen mislukt: $($_.Exception.Message)" 'ERROR' }
    }

    # --- Knoppen ---
    $c.BtnHide.Add_Click({ $win.WindowState = 'Minimized' })
    $c.BtnDetails.Add_Click({ $ui.detailsOpen = -not $ui.detailsOpen; Update-View })
    $c.BtnSecondary.Add_Click({
        $stage = if ($ui.local) { $ui.local } elseif ($ui.status) { $ui.status.stage } else { 'search' }
        switch ($stage) {
            { $_ -in 'search', 'install' } { $ui.local = 'confirm' }
            'confirm' {
                New-Item -Path $Script:CancelFlag -ItemType File -Force | Out-Null
                Write-PopupLog 'Gebruiker heeft updates overgeslagen.'
                $ui.local = 'skipping'
            }
            { $_ -in 'done', 'error' } {
                New-Item -Path $Script:ClosedFlag -ItemType File -Force | Out-Null
                $ui.allowClose = $true; $win.Close(); return
            }
        }
        Update-View
    })
    $c.BtnPrimary.Add_Click({
        $stage = if ($ui.local) { $ui.local } elseif ($ui.status) { $ui.status.stage } else { 'search' }
        if ($stage -eq 'confirm') { $ui.local = $null; Update-View }
        elseif ($stage -eq 'done') { Open-Report; $ui.allowClose = $true; $win.Close() }   # rapport open = popup klaar
    })

    # Sluiten tijdens updates = verbergen (updates gaan door)
    $win.Add_Closing({
        param($sender, $e)
        if (-not $ui.allowClose) { $e.Cancel = $true; $win.WindowState = 'Minimized' }
        else { New-Item -Path $Script:ClosedFlag -ItemType File -Force -ErrorAction SilentlyContinue | Out-Null }
    })

    # Rechtsonder op het scherm houden
    $place = {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $win.Left = $wa.Right - $win.ActualWidth
        $win.Top  = $wa.Bottom - $win.ActualHeight
    }
    $win.Add_SizeChanged($place)
    $win.Add_Loaded($place)

    # --- Status lezen (elke 0,5 s) ---
    $poll = New-Object System.Windows.Threading.DispatcherTimer
    $poll.Interval = [TimeSpan]::FromMilliseconds(500)
    $poll.Add_Tick({
        try {
            if (Test-Path $Script:StatusFile) {
                $ui.status = Get-Content -Path $Script:StatusFile -Raw -ErrorAction Stop | ConvertFrom-Json
                # Lokale tussenstand loslaten zodra de worker verder is
                if ($ui.local -eq 'skipping' -and $ui.status.stage -in 'done', 'error') { $ui.local = $null }
                if ($ui.local -eq 'confirm' -and $ui.status.stage -in 'finishing', 'done', 'error') { $ui.local = $null }
            }
            elseif (((Get-Date) - $ui.started).TotalMinutes -gt 10) {
                # Geen worker-status na 10 minuten: netjes afsluiten in plaats van eindeloos zoeken
                $ui.status = [pscustomobject]@{ stage = 'error'; reportReady = $false
                    message = 'Er kon niet naar updates worden gezocht. Windows probeert het later vanzelf opnieuw.' }
            }
        } catch {}
        Update-View
    })

    # --- Bewegende balk tijdens zoeken/afronden ---
    $anim = New-Object System.Windows.Threading.DispatcherTimer
    $anim.Interval = [TimeSpan]::FromMilliseconds(30)
    $anim.Add_Tick({
        $stage = if ($ui.local) { $ui.local } elseif ($ui.status) { $ui.status.stage } else { 'search' }
        if ($stage -in 'search', 'skipping', 'finishing') {
            $w = $c.Track.ActualWidth
            if ($w -gt 0) {
                $ui.indet = ($ui.indet + 0.012) % 1.3
                $c.Fill.Width = $w * 0.3
                $c.Fill.Margin = New-Object System.Windows.Thickness((($ui.indet - 0.3) * $w), 0, 0, 0)
            }
        }
    })

    Update-View
    $poll.Start(); $anim.Start()
    Write-PopupLog 'Popup getoond.'
    # Niet tonen zolang Windows Hello / ESP (CloudExperienceHost) op de voorgrond staat.
    # Gemeten vanuit de sessie van de gebruiker; achtergrondprocessen tellen niet mee. Max 20 min.
    try {
        Add-Type -Namespace Cx -Name Fg -MemberDefinition @'
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
'@
        $cxh = 'CloudExperienceHost', 'CloudExperienceHostBroker', 'WWAHost'
        for ($w = 0; $w -lt 400; $w++) {
            $fgPid = [uint32]0
            [void][Cx.Fg]::GetWindowThreadProcessId([Cx.Fg]::GetForegroundWindow(), [ref]$fgPid)
            $fgName = (Get-Process -Id $fgPid -ErrorAction SilentlyContinue).ProcessName
            if ($fgName -notin $cxh) { break }
            if ($w -eq 0) { Write-PopupLog "Setup-scherm ($fgName) op de voorgrond: popup wacht." }
            Start-Sleep -Seconds 3
        }
    } catch {}

    [void]$win.ShowDialog()
    $poll.Stop(); $anim.Stop()
    Write-PopupLog 'Popup gesloten.'
}

# =================================================================
if ($Worker) { Start-Worker }
elseif ($Ui) { Start-Ui }
else { Write-Host 'Gebruik: Start-UpdatePopup.ps1 -Worker (als SYSTEM) of -Ui (als gebruiker).' }
